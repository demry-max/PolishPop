import AppKit

@MainActor
final class SelectionMonitor {
    typealias SelectionHandler = (SelectionSnapshot, NSPoint) -> Void

    var onSelection: SelectionHandler?
    var onSelectionCleared: (() -> Void)?
    private let accessibility: AccessibilityService
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var pendingCapture: Task<Void, Never>?

    init(accessibility: AccessibilityService) {
        self.accessibility = accessibility
    }

    func start() {
        guard mouseMonitor == nil else { return }

        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseUp]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleCapture(anchor: NSEvent.mouseLocation)
            }
        }

        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.keyUp]) { [weak self] event in
            let isShiftSelection = event.modifierFlags.contains(.shift)
            let isSelectAll = event.modifierFlags.contains(.command)
                && event.charactersIgnoringModifiers?.lowercased() == "a"
            guard isShiftSelection || isSelectAll else { return }
            Task { @MainActor [weak self] in
                self?.scheduleCapture(anchor: NSEvent.mouseLocation)
            }
        }
    }

    func stop() {
        pendingCapture?.cancel()
        pendingCapture = nil
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    func captureNow(anchor: NSPoint = NSEvent.mouseLocation) {
        do {
            let snapshot = try accessibility.currentSelection()
            onSelection?(snapshot, anchor)
        } catch {
            onSelectionCleared?()
        }
    }

    private func scheduleCapture(anchor: NSPoint) {
        pendingCapture?.cancel()
        pendingCapture = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 140_000_000)
            guard !Task.isCancelled else { return }
            self?.captureNow(anchor: anchor)
        }
    }
}
