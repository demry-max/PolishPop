import AppKit
import SwiftUI

/// Carries an `NSEvent` into the main actor from a monitor callback that is already running there.
private struct EventBox: @unchecked Sendable {
    let event: NSEvent

    init(_ event: NSEvent) {
        self.event = event
    }
}

/// A click-to-record shortcut field.
///
/// Shortcuts were previously hard-coded, so a user whose ⌥⌘P was already taken by another app had
/// no keyboard path at all.
struct ShortcutRecorderField: NSViewRepresentable {
    @Binding var shortcut: ShortcutDefinition?
    var placeholder: String
    var recordingPlaceholder: String

    func makeCoordinator() -> Coordinator {
        Coordinator(shortcut: $shortcut)
    }

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.coordinator = context.coordinator
        context.coordinator.button = button
        button.bezelStyle = .rounded
        button.setButtonType(.momentaryPushIn)
        button.target = context.coordinator
        button.action = #selector(Coordinator.beginRecording)
        context.coordinator.refresh(placeholder: placeholder, recordingPlaceholder: recordingPlaceholder)
        return button
    }

    func updateNSView(_ nsView: RecorderButton, context: Context) {
        context.coordinator.shortcut = $shortcut
        context.coordinator.refresh(placeholder: placeholder, recordingPlaceholder: recordingPlaceholder)
    }

    /// SwiftUI tears the field down when its enclosing `if` collapses. Without this the recording
    /// monitor outlives the coordinator, and because it swallows every key event the app's entire
    /// keyboard stops working for the rest of the session.
    static func dismantleNSView(_ nsView: RecorderButton, coordinator: Coordinator) {
        coordinator.endRecording()
    }

    @MainActor
    final class Coordinator: NSObject {
        var shortcut: Binding<ShortcutDefinition?>
        weak var button: RecorderButton?
        var isRecording = false
        private var placeholder = ""
        private var recordingPlaceholder = ""
        private var monitor: Any?

        init(shortcut: Binding<ShortcutDefinition?>) {
            self.shortcut = shortcut
        }

        func refresh(placeholder: String, recordingPlaceholder: String) {
            self.placeholder = placeholder
            self.recordingPlaceholder = recordingPlaceholder
            guard let button else { return }
            if isRecording {
                button.title = recordingPlaceholder
            } else {
                button.title = shortcut.wrappedValue?.displayString ?? placeholder
            }
        }

        @objc func beginRecording() {
            guard !isRecording else {
                endRecording()
                return
            }
            isRecording = true
            refresh(placeholder: placeholder, recordingPlaceholder: recordingPlaceholder)
            // Every key event is swallowed while recording; the monitor exists only for the
            // moment between the click and the captured combination.
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
                let box = EventBox(event)
                // A monitor that outlives its coordinator must pass events through rather than eat
                // them, so a stale registration can never trap the app's keyboard.
                let consumed = MainActor.assumeIsolated { () -> Bool in
                    guard let self, self.isRecording else { return false }
                    self.handle(box.event)
                    return true
                }
                return consumed ? nil : event
            }
        }

        func endRecording() {
            isRecording = false
            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            refresh(placeholder: placeholder, recordingPlaceholder: recordingPlaceholder)
        }

        private func handle(_ event: NSEvent) {
            guard event.type == .keyDown else { return }
            if event.keyCode == 53 { // Escape cancels without changing the binding.
                endRecording()
                return
            }
            if event.keyCode == 51 { // Delete clears the binding.
                shortcut.wrappedValue = nil
                endRecording()
                return
            }
            guard let recorded = ShortcutDefinition(event: event) else { return }
            shortcut.wrappedValue = recorded
            endRecording()
        }
    }

    final class RecorderButton: NSButton {
        weak var coordinator: Coordinator?

        override func resignFirstResponder() -> Bool {
            MainActor.assumeIsolated { coordinator?.endRecording() }
            return super.resignFirstResponder()
        }
    }
}
