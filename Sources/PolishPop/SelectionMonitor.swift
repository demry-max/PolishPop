import AppKit
import Carbon.HIToolbox

/// Watches for gestures that plausibly *create* a text selection and probes Accessibility only
/// then.
///
/// The previous version probed after every left-mouse-up anywhere on the system, which meant a
/// blocking Accessibility round trip for every click the user made all day. Now a plain click
/// simply hides the button — it collapses the selection anyway — and only drags, multi-clicks and
/// selection keystrokes pay for a probe.
@MainActor
final class SelectionMonitor {
    typealias SelectionHandler = (SelectionSnapshot) -> Void

    var onSelection: SelectionHandler?
    var onSelectionCleared: (() -> Void)?

    /// Pointer travel, in points, above which a mouse-up is treated as a drag-select.
    nonisolated private static let dragThreshold: CGFloat = 4
    private static let debounce: UInt64 = 110_000_000

    private let accessibility: AccessibilityService
    private var monitors: [Any] = []
    private var pendingCapture: Task<Void, Never>?
    private var mouseDownLocation: NSPoint?
    private var lastDelivered: SelectionSnapshot?

    init(accessibility: AccessibilityService) {
        self.accessibility = accessibility
    }

    func start() {
        guard monitors.isEmpty else { return }

        add(matching: .leftMouseDown) { [weak self] _ in
            // Screen coordinates, not `event.locationInWindow`: a global monitor's events have no
            // window, so window-relative coordinates are not comparable between the down and the
            // up — and an under-measured drag reads as a plain click, which hides the button
            // instead of offering it.
            self?.mouseDownLocation = NSEvent.mouseLocation
        }

        add(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return }
            let start = mouseDownLocation
            mouseDownLocation = nil
            let end = NSEvent.mouseLocation
            let travelled = start.map { hypot($0.x - end.x, $0.y - end.y) }

            if Self.isSelectionGesture(
                travelled: travelled,
                clickCount: event.clickCount,
                isShiftHeld: event.modifierFlags.contains(.shift)
            ) {
                Diagnostics.log("mouseUp: probing (travelled=\(Self.describe(travelled)) clicks=\(event.clickCount))")
                scheduleCapture()
            } else {
                Diagnostics.log("mouseUp: plain click, clearing")
                clear()
            }
        }

        add(matching: .keyUp) { [weak self] event in
            guard let self else { return }
            if Self.isSelectionKeystroke(event) {
                Diagnostics.log("keyUp: selection keystroke, probing")
                scheduleCapture()
            } else if Self.isDismissingKeystroke(event) {
                clear()
            }
        }
    }

    func stop() {
        pendingCapture?.cancel()
        pendingCapture = nil
        mouseDownLocation = nil
        lastDelivered = nil
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }

    /// Forgets the selection currently on screen so the next probe is delivered even if the user
    /// re-selects exactly the same text.
    func invalidateDeliveredSelection() {
        lastDelivered = nil
    }

    // MARK: - Internals

    private func add(matching mask: NSEvent.EventTypeMask, handler: @escaping @MainActor (NSEvent) -> Void) {
        guard let monitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { event in
            MainActor.assumeIsolated { handler(event) }
        }) else {
            return
        }
        monitors.append(monitor)
    }

    private func clear() {
        pendingCapture?.cancel()
        pendingCapture = nil
        guard lastDelivered != nil else { return }
        lastDelivered = nil
        onSelectionCleared?()
    }

    private func scheduleCapture() {
        pendingCapture?.cancel()
        pendingCapture = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: Self.debounce)
            guard !Task.isCancelled else { return }
            await self?.captureNow()
        }
    }

    private func captureNow() async {
        let snapshot = await accessibility.probeSelection()
        Diagnostics.log("probe result: \(snapshot == nil ? "nil" : "length=\(snapshot!.text.count)")")
        // The probe suspends; by the time it answers the monitor may have been stopped, and
        // delivering a selection then would put the button back on screen after the user turned
        // it off.
        guard !monitors.isEmpty, !Task.isCancelled else { return }
        guard let snapshot else {
            clear()
            return
        }
        // Re-showing an identical selection would make the button jump for no reason.
        if let lastDelivered, snapshot.matchesLocation(of: lastDelivered) { return }
        lastDelivered = snapshot
        onSelection?(snapshot)
    }

    /// Whether a mouse-up plausibly created a selection.
    ///
    /// - Parameter travelled: distance from the matching mouse-down, or `nil` when that
    ///   mouse-down was never observed — which happens routinely, because a global monitor
    ///   receives nothing while PolishPop itself is frontmost. An unknown distance counts as a
    ///   drag: offering the button needlessly is a smaller sin than hiding it after a real
    ///   selection.
    ///
    /// Pure and static so the decision can be tested directly; the crash this replaced lived in
    /// an event handler that no test could reach.
    nonisolated static func isSelectionGesture(travelled: CGFloat?, clickCount: Int, isShiftHeld: Bool) -> Bool {
        if clickCount >= 2 { return true }
        if isShiftHeld { return true }
        guard let travelled else { return true }
        return travelled > dragThreshold
    }

    /// Formats a distance for the debug log without ever converting a non-finite value.
    nonisolated static func describe(_ travelled: CGFloat?) -> String {
        guard let travelled, travelled.isFinite else { return "unknown" }
        return String(Int(travelled.rounded()))
    }

    private static func isSelectionKeystroke(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "a" {
            return true
        }
        guard flags.contains(.shift) else { return false }
        let navigationKeys: Set<UInt16> = [
            UInt16(kVK_LeftArrow), UInt16(kVK_RightArrow),
            UInt16(kVK_UpArrow), UInt16(kVK_DownArrow),
            UInt16(kVK_Home), UInt16(kVK_End),
            UInt16(kVK_PageUp), UInt16(kVK_PageDown)
        ]
        return navigationKeys.contains(event.keyCode)
    }

    /// Typing, deleting or moving the caret destroys the selection, so the button should go
    /// away. Command and Control shortcuts are excluded because Copy, Save and friends leave the
    /// selection exactly where it was.
    private static func isDismissingKeystroke(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags
        return !flags.contains(.shift) && !flags.contains(.command) && !flags.contains(.control)
    }
}
