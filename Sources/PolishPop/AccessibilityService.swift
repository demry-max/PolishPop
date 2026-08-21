import AppKit
@preconcurrency import ApplicationServices

/// Reads the user's selection and writes the polished text back.
///
/// The blocking Accessibility calls all happen on `AXQueue`; this type only orchestrates them and
/// owns the clipboard-restoring paste fallback.
@MainActor
final class AccessibilityService {
    static let maximumSelectionLength = 30_000

    /// Short enough that an unresponsive application cannot make the sparkle button lag behind
    /// the user's selection.
    private static let probeTimeout: Float = 0.12
    /// The user has asked for a rewrite and is willing to wait a moment for it.
    private static let captureTimeout: Float = 0.4

    var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    @discardableResult
    func requestPermission() -> Bool {
        let options = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Cheap, best-effort read used to decide whether to offer the sparkle button.
    ///
    /// Returns `nil` rather than throwing because "there is no selection right now" is the normal
    /// case after most clicks, not an error worth reporting.
    func probeSelection() async -> SelectionSnapshot? {
        guard isTrusted else { return nil }
        let limit = Self.maximumSelectionLength
        let timeout = Self.probeTimeout
        let reading = await AXQueue.shared.run { () -> AXSelectionReading? in
            try? AXReader.readSelection(
                timeout: timeout,
                deepProtectedScan: false,
                maximumLength: limit
            )
        }
        guard let reading else { return nil }
        return snapshot(from: reading)
    }

    /// Full read performed immediately before text is sent, including the ancestor scan for
    /// DRM-protected containers.
    func currentSelection() async throws -> SelectionSnapshot {
        guard isTrusted else {
            throw PolishPopError.accessibilityPermissionMissing
        }
        let limit = Self.maximumSelectionLength
        let timeout = Self.captureTimeout

        let result = await AXQueue.shared.run { () -> Result<AXSelectionReading, AXReader.ReadError> in
            do {
                return .success(
                    try AXReader.readSelection(
                        timeout: timeout,
                        deepProtectedScan: true,
                        maximumLength: limit
                    )
                )
            } catch let error as AXReader.ReadError {
                return .failure(error)
            } catch {
                return .failure(.noSelection)
            }
        }

        switch result {
        case .success(let reading):
            return snapshot(from: reading)
        case .failure(.protectedField):
            throw PolishPopError.protectedTextField
        case .failure(.tooLong):
            throw PolishPopError.selectionTooLong(limit: Self.maximumSelectionLength)
        case .failure(.selectionUnavailable):
            throw PolishPopError.selectionUnavailable
        case .failure:
            throw PolishPopError.noSelection
        }
    }

    /// Screen rectangle of the selection, used to anchor the sparkle button to the text.
    func selectionBounds(for snapshot: SelectionSnapshot) async -> CGRect? {
        let box = AXElementBox(snapshot.element)
        let timeout = Self.probeTimeout
        return await AXQueue.shared.run {
            AXReader.selectionBounds(for: box.element, timeout: timeout)
        }
    }

    /// Reselects text PolishPop wrote and puts the user's original wording back.
    ///
    /// Undo cannot reuse the normal path: after a replacement the caret is collapsed, so there is
    /// no selection to validate against. The applied range is reselected first, and only if the
    /// field really contains what PolishPop wrote is anything changed.
    func restoreOriginal(_ record: ReplacementRecord) async throws {
        guard let targetApplication = record.snapshot.targetApplication,
              !targetApplication.isTerminated else {
            throw PolishPopError.selectionChanged
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != record.snapshot.targetPID {
            targetApplication.activate(options: [.activateIgnoringOtherApps])
            try await waitForFrontmost(pid: record.snapshot.targetPID)
        }

        let box = AXElementBox(record.snapshot.element)
        let appliedRange = CFRange(
            location: record.snapshot.selectedRange.location,
            length: record.applied.utf16.count
        )
        let applied = record.applied
        let timeout = Self.captureTimeout

        let reselected = await AXQueue.shared.run { () -> Bool in
            AXUIElementSetMessagingTimeout(box.element, timeout)
            _ = AXUIElementSetAttributeValue(box.element, kAXFocusedAttribute as CFString, kCFBooleanTrue)
            guard AXReader.setSelectedRange(element: box.element, range: appliedRange, timeout: timeout) else {
                return false
            }
            return AXReader.selectedText(in: box.element) == applied
        }
        guard reselected else {
            throw PolishPopError.selectionChanged
        }

        let restoredSnapshot = SelectionSnapshot(
            text: applied,
            element: record.snapshot.element,
            targetPID: record.snapshot.targetPID,
            selectedRange: appliedRange,
            targetApplication: targetApplication,
            isReplaceable: record.snapshot.isReplaceable
        )
        try await replace(restoredSnapshot, with: record.original, allowClipboardFallback: true)
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    // MARK: - Replacement

    /// Replaces the reviewed selection after bringing the source application back to the front.
    ///
    /// A direct Accessibility write is tried first because it never touches the clipboard; the
    /// paste fallback only runs when the target application refuses or silently ignores the write.
    func replaceFromReview(
        _ snapshot: SelectionSnapshot,
        with replacement: String,
        allowClipboardFallback: Bool
    ) async throws {
        guard let targetApplication = snapshot.targetApplication,
              !targetApplication.isTerminated else {
            throw PolishPopError.selectionChanged
        }

        if NSWorkspace.shared.frontmostApplication?.processIdentifier != snapshot.targetPID {
            targetApplication.activate(options: [.activateIgnoringOtherApps])
            try await waitForFrontmost(pid: snapshot.targetPID)
        }

        try await replace(
            snapshot,
            with: replacement,
            allowClipboardFallback: allowClipboardFallback
        )
    }

    func replace(
        _ snapshot: SelectionSnapshot,
        with replacement: String,
        allowClipboardFallback: Bool
    ) async throws {
        try await ensureSelectionReady(snapshot)

        let box = AXElementBox(snapshot.element)
        let timeout = Self.captureTimeout
        let directSucceeded = await AXQueue.shared.run {
            AXReader.setSelectedTextVerified(
                element: box.element,
                replacement: replacement,
                timeout: timeout
            )
        }
        if directSucceeded { return }

        guard allowClipboardFallback, snapshot.targetApplication != nil else {
            throw PolishPopError.replacementFailed
        }
        try await pasteReplacement(replacement, into: snapshot)
    }

    /// Puts the draft on the clipboard just long enough to synthesise one Command-V into the
    /// target process, then puts the user's own clipboard back.
    private func pasteReplacement(_ replacement: String, into snapshot: SelectionSnapshot) async throws {
        let savedItems = clonePasteboardItems(NSPasteboard.general.pasteboardItems)
        let savedString = NSPasteboard.general.string(forType: .string)
        let pasteboardWasEmpty = NSPasteboard.general.pasteboardItems?.isEmpty != false
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(replacement, forType: .string)
        let replacementChangeCount = NSPasteboard.general.changeCount
        var needsRestore = true
        defer {
            if needsRestore {
                restorePasteboard(
                    savedItems,
                    wasEmpty: pasteboardWasEmpty,
                    fallbackString: savedString,
                    expectedChangeCount: replacementChangeCount
                )
            }
        }

        try await ensureSelectionReady(snapshot)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            throw PolishPopError.replacementFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(snapshot.targetPID)
        keyUp.postToPid(snapshot.targetPID)

        let landed = await waitForPasteToLand(snapshot)

        // Deliberately not `try await`: a cancellation here must not restore the clipboard out
        // from under an application that has not finished reading the paste.
        restorePasteboard(
            savedItems,
            wasEmpty: pasteboardWasEmpty,
            fallbackString: savedString,
            expectedChangeCount: replacementChangeCount
        )
        needsRestore = false

        guard landed else { throw PolishPopError.replacementFailed }
    }

    /// Watches the target field until the paste visibly takes effect, instead of assuming it did
    /// after a fixed 500 ms. A fast application finishes in a fraction of that; a slow one used to
    /// have its clipboard pulled away mid-paste.
    ///
    /// `validateTarget` has just read this field's selected text successfully, so a read that now
    /// returns nothing means the selection collapsed — which is what a paste does.
    private func waitForPasteToLand(_ snapshot: SelectionSnapshot) async -> Bool {
        let box = AXElementBox(snapshot.element)
        let originalText = snapshot.text

        for _ in 0..<24 {
            await settle(40_000_000)
            let observed = await AXQueue.shared.run {
                AXReader.selectedText(in: box.element)
            }
            guard let text = observed else { return true }
            if text != originalText { return true }
        }
        return false
    }

    /// A delay that cancellation cannot skip.
    ///
    /// `Task.sleep` returns immediately once the surrounding task is cancelled, which would let
    /// the clipboard be restored out from under an application still processing the paste.
    private func settle(_ nanoseconds: UInt64) async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated)
                .asyncAfter(deadline: .now() + .nanoseconds(Int(nanoseconds))) {
                    continuation.resume()
                }
        }
    }

    /// Runs the ancestor scan for DRM-protected containers on a snapshot that came from the cheap
    /// probe, so text captured by the sparkle button gets the same check as the shortcut path.
    func assertNotProtected(_ snapshot: SelectionSnapshot) async throws {
        let box = AXElementBox(snapshot.element)
        let timeout = Self.captureTimeout
        let isProtected = await AXQueue.shared.run {
            AXReader.isSecureTextField(box.element)
                || AXReader.containsProtectedContent(box.element, timeout: timeout)
        }
        if isProtected {
            throw PolishPopError.protectedTextField
        }
    }

    // MARK: - Internals

    private func snapshot(from reading: AXSelectionReading) -> SelectionSnapshot {
        SelectionSnapshot(
            text: reading.text,
            element: reading.element,
            targetPID: reading.pid,
            selectedRange: reading.range,
            targetApplication: NSRunningApplication(processIdentifier: reading.pid),
            isReplaceable: reading.isReplaceable
        )
    }

    /// Polls briefly instead of sleeping a fixed interval, so a fast application is not made to
    /// wait for a slow one's worst case.
    private func waitForFrontmost(pid: pid_t) async throws {
        for _ in 0..<60 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return }
            try await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    /// Makes sure the field is focused and holds exactly the text the user reviewed, restoring the
    /// selection if the application dropped it.
    ///
    /// Many editors — Electron and web-based ones especially — collapse their selection the moment
    /// they lose focus, which the review panel necessarily takes. Demanding an untouched selection
    /// therefore refused to apply in exactly the apps people use most. Re-selecting the recorded
    /// range keeps the safety property intact: nothing is written unless the text now selected is
    /// character-for-character the text the user approved.
    private func ensureSelectionReady(_ snapshot: SelectionSnapshot) async throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.targetPID else {
            Diagnostics.log("apply: wrong frontmost app")
            throw PolishPopError.selectionChanged
        }

        let box = AXElementBox(snapshot.element)
        let expectedText = snapshot.text
        let expectedRange = snapshot.selectedRange
        let timeout = Self.captureTimeout

        let outcome = await AXQueue.shared.run { () -> SelectionReadiness in
            // The element may still carry the probe's short messaging timeout from when the
            // sparkle was offered; applying is deliberate work and gets the longer budget.
            AXUIElementSetMessagingTimeout(box.element, timeout)

            let focused = AXReader.focusedElement(timeout: timeout)
            let isFocused = focused.map { CFEqual($0.element, box.element) } ?? false

            if isFocused,
               AXReader.selectedText(in: box.element) == expectedText,
               let currentRange = AXReader.selectedRange(in: box.element),
               currentRange.location == expectedRange.location,
               currentRange.length == expectedRange.length {
                return .intact
            }

            if !isFocused {
                // Ask the field for focus back before touching its selection.
                _ = AXUIElementSetAttributeValue(
                    box.element,
                    kAXFocusedAttribute as CFString,
                    kCFBooleanTrue
                )
            }

            guard AXReader.setSelectedRange(element: box.element, range: expectedRange, timeout: timeout) else {
                return .unrecoverable
            }
            // The decisive check: only the exact reviewed text may be replaced.
            guard AXReader.selectedText(in: box.element) == expectedText else {
                return .textNoLongerMatches
            }
            return .restored
        }

        switch outcome {
        case .intact:
            return
        case .restored:
            Diagnostics.log("apply: selection was dropped by the app and re-selected")
            return
        case .textNoLongerMatches:
            Diagnostics.log("apply: text at the recorded range no longer matches")
            throw PolishPopError.selectionChanged
        case .unrecoverable:
            Diagnostics.log("apply: field would not accept a selection range")
            throw PolishPopError.selectionChanged
        }
    }

    private enum SelectionReadiness {
        case intact
        case restored
        case textNoLongerMatches
        case unrecoverable
    }

    private func clonePasteboardItems(_ items: [NSPasteboardItem]?) -> [NSPasteboardItem] {
        (items ?? []).map { original in
            let copy = NSPasteboardItem()
            for type in original.types {
                if let data = original.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }
    }

    private func restorePasteboard(
        _ items: [NSPasteboardItem],
        wasEmpty: Bool,
        fallbackString: String?,
        expectedChangeCount: Int
    ) {
        guard NSPasteboard.general.changeCount == expectedChangeCount else { return }
        NSPasteboard.general.clearContents()
        if !wasEmpty {
            let restored = NSPasteboard.general.writeObjects(items)
            if !restored, let fallbackString {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fallbackString, forType: .string)
            }
        }
    }
}
