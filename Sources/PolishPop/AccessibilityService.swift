import AppKit
@preconcurrency import ApplicationServices

@MainActor
final class AccessibilityService {
    static let maximumSelectionLength = 30_000

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

    func currentSelection() throws -> SelectionSnapshot {
        guard isTrusted else {
            throw PolishPopError.accessibilityPermissionMissing
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.4)
        var focusedValue: CFTypeRef?
        let focusedStatus = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard focusedStatus == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            throw PolishPopError.noSelection
        }

        let element = unsafeDowncast(focusedValue, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(element, 0.4)
        guard !isSecureTextField(element), !containsProtectedContent(element) else {
            throw PolishPopError.protectedTextField
        }
        guard let selectedText = selectedText(in: element), !selectedText.isEmpty else {
            throw PolishPopError.noSelection
        }
        guard selectedText.count <= Self.maximumSelectionLength else {
            throw PolishPopError.selectionTooLong(limit: Self.maximumSelectionLength)
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let selectedRange = selectedRange(in: element) else {
            throw PolishPopError.noSelection
        }

        return SelectionSnapshot(
            text: selectedText,
            element: element,
            targetPID: pid,
            selectedRange: selectedRange,
            targetApplication: NSWorkspace.shared.frontmostApplication
        )
    }

    func selectionBounds(for snapshot: SelectionSnapshot) -> CGRect? {
        var rangeValue: CFTypeRef?
        let rangeStatus = AXUIElementCopyAttributeValue(
            snapshot.element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard rangeStatus == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var boundsValue: CFTypeRef?
        let boundsStatus = AXUIElementCopyParameterizedAttributeValue(
            snapshot.element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        )
        guard boundsStatus == .success,
              let boundsValue,
              CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(boundsValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect) else { return nil }
        return rect
    }

    func replace(
        _ snapshot: SelectionSnapshot,
        with replacement: String,
        allowClipboardFallback: Bool,
        forcePaste: Bool = false
    ) async throws {
        try validateTarget(snapshot)

        if !forcePaste {
            let directStatus = AXUIElementSetAttributeValue(
                snapshot.element,
                kAXSelectedTextAttribute as CFString,
                replacement as CFTypeRef
            )
            if directStatus == .success {
                return
            }
        }

        guard allowClipboardFallback, snapshot.targetApplication != nil else {
            throw PolishPopError.replacementFailed
        }

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

        try validateTarget(snapshot)

        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            copyToPasteboard(replacement)
            throw PolishPopError.replacementFailed
        }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.postToPid(snapshot.targetPID)
        keyUp.postToPid(snapshot.targetPID)

        try await Task.sleep(nanoseconds: 500_000_000)
        restorePasteboard(
            savedItems,
            wasEmpty: pasteboardWasEmpty,
            fallbackString: savedString,
            expectedChangeCount: replacementChangeCount
        )
        needsRestore = false
    }

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
            try await Task.sleep(nanoseconds: 180_000_000)
        }

        try await replace(
            snapshot,
            with: replacement,
            allowClipboardFallback: allowClipboardFallback,
            forcePaste: true
        )
    }

    func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func selectedText(in element: AXUIElement) -> String? {
        var selectedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        guard status == .success else { return nil }
        return selectedValue as? String
    }

    private func selectedRange(in element: AXUIElement) -> CFRange? {
        var rangeValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        )
        guard status == .success,
              let rangeValue,
              CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }
        let axValue = unsafeDowncast(rangeValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cfRange else { return nil }
        var range = CFRange()
        return AXValueGetValue(axValue, .cfRange, &range) ? range : nil
    }

    private func isSecureTextField(_ element: AXUIElement) -> Bool {
        var subroleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleValue
        ) == .success,
              let subrole = subroleValue as? String else {
            return false
        }
        return subrole == (kAXSecureTextFieldSubrole as String)
    }

    private func containsProtectedContent(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element

        for _ in 0..<8 {
            guard let candidate = current else { return false }
            AXUIElementSetMessagingTimeout(candidate, 0.2)
            var protectedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                candidate,
                "AXContainsProtectedContent" as CFString,
                &protectedValue
            ) == .success,
               let protected = protectedValue as? NSNumber,
               protected.boolValue {
                return true
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                candidate,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
                  let parentValue,
                  CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                return false
            }
            current = unsafeDowncast(parentValue, to: AXUIElement.self)
        }
        return false
    }

    private func validateTarget(_ snapshot: SelectionSnapshot) throws {
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == snapshot.targetPID else {
            throw PolishPopError.selectionChanged
        }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, 0.4)
        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        ) == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID(),
              CFEqual(focusedValue, snapshot.element),
              selectedText(in: snapshot.element) == snapshot.text,
              let currentRange = selectedRange(in: snapshot.element),
              currentRange.location == snapshot.selectedRange.location,
              currentRange.length == snapshot.selectedRange.length else {
            throw PolishPopError.selectionChanged
        }
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
