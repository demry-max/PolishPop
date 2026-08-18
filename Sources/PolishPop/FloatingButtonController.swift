import AppKit
import SwiftUI

@MainActor
final class FloatingButtonModel: ObservableObject {
    @Published var phase: FloatingPhase = .ready
    @Published var tooltip = ShellStrings.buttonAccessibilityLabel
}

private final class NonActivatingButtonPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The sparkle button that appears beside a fresh selection.
@MainActor
final class FloatingButtonController {
    private static let diameter: CGFloat = 42

    let model = FloatingButtonModel()
    var onPrimaryAction: (() -> Void)?
    /// Right-click menu with the tone, use case and instant-replace commands.
    var onSecondaryAction: (() -> NSMenu?)?

    private let panel: NonActivatingButtonPanel
    private var autoHideTask: Task<Void, Never>?

    /// The button is an offer, not a permanent fixture. Without this it sat on top of every other
    /// app, on every Space, until the user happened to click somewhere with no selection.
    private static let autoHideAfter: UInt64 = 15_000_000_000
    init() {
        panel = NonActivatingButtonPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.animationBehavior = .none
        let hosting = NSHostingView(
            rootView: FloatingButtonView(
                model: model,
                action: { [weak self] in self?.onPrimaryAction?() }
            )
        )
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        let container = SecondaryClickView(frame: NSRect(x: 0, y: 0, width: Self.diameter, height: Self.diameter))
        container.addSubview(hosting)
        hosting.frame = container.bounds
        panel.contentView = container
        container.handler = { [weak self] in self?.presentMenu() }
    }

    /// Parks the button just past the end of the selection when the target application reports
    /// where the selection is, and beside the pointer when it does not.
    func show(selectionBounds: CGRect?, fallbackAnchor: NSPoint) {
        let origin = preferredOrigin(selectionBounds: selectionBounds, fallbackAnchor: fallbackAnchor)
        panel.setFrameOrigin(origin)
        model.phase = .ready
        model.tooltip = Self.readyTooltip()
        panel.orderFrontRegardless()
        scheduleAutoHide()
    }

    func hide() {
        autoHideTask?.cancel()
        autoHideTask = nil
        panel.orderOut(nil)
        model.phase = .ready
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.autoHideAfter)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    var isVisible: Bool { panel.isVisible }

    func showWorking() {
        autoHideTask?.cancel()
        autoHideTask = nil
        model.phase = .working
        model.tooltip = ShellStrings.workingTooltip
    }

    func showSuccess() {
        model.phase = .success
        model.tooltip = ShellStrings.successTooltip
    }

    func showFailure(_ message: LocalizedText) {
        model.phase = .failure
        model.tooltip = message
    }

    static func readyTooltip() -> LocalizedText {
        let shortcut = Preferences.polishShortcut?.displayString ?? ""
        return shortcut.isEmpty
            ? ShellStrings.buttonAccessibilityLabel
            : ShellStrings.polishTooltip(shortcut)
    }

    private func presentMenu() {
        guard let menu = onSecondaryAction?(), let contentView = panel.contentView else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: contentView.bounds.height), in: contentView)
    }

    private func preferredOrigin(selectionBounds: CGRect?, fallbackAnchor: NSPoint) -> NSPoint {
        let size = Self.diameter
        var origin: NSPoint
        var reference: NSPoint

        if let cocoaBounds = selectionBounds.flatMap(Self.convertFromAccessibility) {
            // Just past the end of the last line, so the button never covers the text itself.
            origin = NSPoint(x: cocoaBounds.maxX + 6, y: cocoaBounds.minY - size - 2)
            reference = NSPoint(x: cocoaBounds.maxX, y: cocoaBounds.minY)
        } else {
            origin = NSPoint(x: fallbackAnchor.x + 10, y: fallbackAnchor.y - size - 8)
            reference = fallbackAnchor
        }

        let screen = NSScreen.screens.first { $0.frame.contains(reference) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return origin }

        if origin.y < visibleFrame.minY + 6 {
            origin.y = reference.y + 8
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 6), visibleFrame.maxX - size - 6)
        origin.y = min(max(origin.y, visibleFrame.minY + 6), visibleFrame.maxY - size - 6)
        return origin
    }

    /// Accessibility reports rectangles in a top-left origin space measured from the primary
    /// display; AppKit windows use a bottom-left origin.
    static func convertFromAccessibility(_ rect: CGRect) -> CGRect? {
        guard !rect.isEmpty else { return nil }
        let primary = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.screens.first
        guard let primaryHeight = primary?.frame.height else { return nil }
        return CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }
}

private struct FloatingButtonView: View {
    @ObservedObject var model: FloatingButtonModel
    @ObservedObject private var localization = Localization.shared
    let action: () -> Void

    init(model: FloatingButtonModel, action: @escaping () -> Void) {
        self.model = model
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThickMaterial)
                    .overlay(Circle().strokeBorder(borderColor.opacity(0.55), lineWidth: 1))

                switch model.phase {
                case .ready:
                    Image(systemName: "sparkles")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.purple)
                case .working:
                    ProgressView()
                        .controlSize(.small)
                case .success:
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.green)
                case .failure:
                    Image(systemName: "exclamationmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.red)
                }
            }
            .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .help(model.tooltip.current)
        .accessibilityLabel(ShellStrings.buttonAccessibilityLabel.current)
        .padding(2)
    }

    private var borderColor: Color {
        switch model.phase {
        case .ready, .working: .purple
        case .success: .green
        case .failure: .red
        }
    }
}

/// SwiftUI offers no right-click hook that behaves inside a non-activating panel, so the hosting
/// view sits in a plain AppKit container that forwards secondary clicks to the options menu.
private final class SecondaryClickView: NSView {
    var handler: (() -> Void)?

    override func rightMouseDown(with event: NSEvent) {
        handler?()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
