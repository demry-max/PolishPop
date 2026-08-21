import AppKit
@preconcurrency import ApplicationServices

/// Everything read from an element in a single visit, so one probe means one trip to the
/// target application instead of several.
struct AXSelectionReading: @unchecked Sendable {
    let element: AXUIElement
    let text: String
    let pid: pid_t
    let range: CFRange
    let isReplaceable: Bool
}

/// The blocking Accessibility calls, isolated from the rest of the app so they can only ever be
/// invoked through `AXQueue`.
///
/// Timeouts are passed in rather than hard-coded because the passive probe that runs after a
/// selection gesture must give up quickly, while the deliberate capture right before sending
/// text can afford to wait.
enum AXReader {
    enum ReadError: Error, Equatable {
        case noFocusedElement
        case noSelection
        /// The focused element exists but refuses to hand over its selection. Distinct from
        /// `noSelection`, which means the field answered and had nothing selected — telling
        /// somebody to "select some text first" when they demonstrably just did is worse than
        /// saying nothing.
        case selectionUnavailable
        case protectedField
        case tooLong
    }

    /// What asking an element for its selected text actually produced.
    enum SelectedTextOutcome: Equatable {
        /// The element answered. An empty string means there is genuinely no selection.
        case value(String)
        /// The element cannot or will not report a selection — typical of canvas-drawn web
        /// editors, Electron apps and custom text controls that implement no Accessibility text
        /// interface at all.
        case unavailable(AXError)
    }

    static func focusedElement(timeout: Float) -> AXElementBox? {
        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, timeout)
        var focusedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedValue
        )
        guard status == .success,
              let focusedValue,
              CFGetTypeID(focusedValue) == AXUIElementGetTypeID() else {
            return nil
        }
        return AXElementBox(unsafeDowncast(focusedValue, to: AXUIElement.self))
    }

    /// Reads the focused element's selection in one pass.
    ///
    /// - Parameter deepProtectedScan: walks ancestors looking for DRM-protected containers. Each
    ///   step is another blocking round trip, so it is reserved for the moment before text
    ///   actually leaves the machine.
    static func readSelection(
        timeout: Float,
        deepProtectedScan: Bool,
        maximumLength: Int
    ) throws -> AXSelectionReading {
        guard let box = focusedElement(timeout: timeout) else {
            throw ReadError.noFocusedElement
        }
        let element = box.element
        AXUIElementSetMessagingTimeout(element, timeout)

        guard !isSecureTextField(element) else { throw ReadError.protectedField }
        if deepProtectedScan, containsProtectedContent(element, timeout: timeout) {
            throw ReadError.protectedField
        }

        let text: String
        switch readSelectedText(in: element) {
        case .value(let value):
            guard !value.isEmpty else { throw ReadError.noSelection }
            text = value
        case .unavailable(let status):
            Diagnostics.log("selection unavailable: AXError \(status.rawValue)")
            throw ReadError.selectionUnavailable
        }
        guard text.count <= maximumLength else {
            throw ReadError.tooLong
        }

        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success,
              let range = selectedRange(in: element) else {
            throw ReadError.noSelection
        }

        var settable = DarwinBoolean(false)
        let settableStatus = AXUIElementIsAttributeSettable(
            element,
            kAXSelectedTextAttribute as CFString,
            &settable
        )

        return AXSelectionReading(
            element: element,
            text: text,
            pid: pid,
            range: range,
            isReplaceable: settableStatus == .success && settable.boolValue
        )
    }

    static func selectedText(in element: AXUIElement) -> String? {
        guard case .value(let text) = readSelectedText(in: element) else { return nil }
        return text
    }

    static func readSelectedText(in element: AXUIElement) -> SelectedTextOutcome {
        var selectedValue: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selectedValue
        )
        return classifySelectedText(status: status, text: selectedValue as? String)
    }

    /// Split out from the Accessibility call so the classification can be tested directly.
    ///
    /// `noValue` is deliberately treated as an empty selection rather than as a failure: the
    /// attribute exists, the field simply has nothing selected right now.
    nonisolated static func classifySelectedText(status: AXError, text: String?) -> SelectedTextOutcome {
        switch status {
        case .success:
            guard let text else { return .unavailable(.attributeUnsupported) }
            return .value(text)
        case .noValue:
            return .value("")
        default:
            return .unavailable(status)
        }
    }

    static func selectedRange(in element: AXUIElement) -> CFRange? {
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

    /// Screen rectangle of the current selection, used to park the sparkle button beside the
    /// text the user highlighted instead of wherever the pointer happened to stop.
    static func selectionBounds(for element: AXUIElement, timeout: Float) -> CGRect? {
        AXUIElementSetMessagingTimeout(element, timeout)
        var rangeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeValue
        ) == .success,
            let rangeValue,
            CFGetTypeID(rangeValue) == AXValueGetTypeID() else {
            return nil
        }

        var boundsValue: CFTypeRef?
        guard AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            rangeValue,
            &boundsValue
        ) == .success,
            let boundsValue,
            CFGetTypeID(boundsValue) == AXValueGetTypeID() else {
            return nil
        }

        let axValue = unsafeDowncast(boundsValue, to: AXValue.self)
        guard AXValueGetType(axValue) == .cgRect else { return nil }
        var rect = CGRect.zero
        guard AXValueGetValue(axValue, .cgRect, &rect), !rect.isEmpty else { return nil }
        return rect
    }

    static func isSecureTextField(_ element: AXUIElement) -> Bool {
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

    static func containsProtectedContent(_ element: AXUIElement, timeout: Float) -> Bool {
        var current: AXUIElement? = element

        for _ in 0..<8 {
            guard let candidate = current else { return false }
            AXUIElementSetMessagingTimeout(candidate, timeout)
            var protectedValue: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                candidate,
                "AXContainsProtectedContent" as CFString,
                &protectedValue
            ) == .success,
                let protectedFlag = protectedValue as? NSNumber,
                protectedFlag.boolValue {
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

    /// Selects an explicit character range, used to put the caret back around text PolishPop
    /// already wrote so it can be replaced again.
    static func setSelectedRange(element: AXUIElement, range: CFRange, timeout: Float) -> Bool {
        AXUIElementSetMessagingTimeout(element, timeout)
        var mutableRange = range
        guard let value = AXValueCreate(.cfRange, &mutableRange) else { return false }
        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }

    /// Writes the replacement directly, then reads the field back to confirm the change actually
    /// landed. Some applications report success for a write they silently ignore, and a silent
    /// no-op would look to the user like PolishPop lost their text.
    static func setSelectedTextVerified(
        element: AXUIElement,
        replacement: String,
        timeout: Float
    ) -> Bool {
        AXUIElementSetMessagingTimeout(element, timeout)
        let status = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            replacement as CFTypeRef
        )
        guard status == .success else { return false }

        guard let range = selectedRange(in: element) else {
            // No range to verify against; the write reported success, so trust it.
            return true
        }
        // A successful replacement leaves the caret collapsed after the inserted text, or the
        // inserted text selected. Either is proof the field accepted the write.
        if range.length == 0 { return true }
        return selectedText(in: element) == replacement
    }
}
