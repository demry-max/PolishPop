import AppKit
import SwiftUI

@MainActor
final class FloatingButtonModel: ObservableObject {
    @Published var phase: FloatingPhase = .ready
    @Published var tooltip = "Polish selection"
}

@MainActor
final class FloatingButtonController {
    let model = FloatingButtonModel()
    var onPrimaryAction: (() -> Void)?

    private let panel: NSPanel

    init() {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 42, height: 42),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isMovable = false
        panel.contentView = NSHostingView(
            rootView: FloatingButtonView(model: model) { [weak self] in
                self?.onPrimaryAction?()
            }
        )
    }

    func show(near anchor: NSPoint) {
        let screen = NSScreen.screens.first { $0.frame.contains(anchor) } ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? .zero
        var origin = NSPoint(x: anchor.x + 8, y: anchor.y - 48)
        origin.x = min(max(origin.x, visibleFrame.minX + 6), visibleFrame.maxX - 48)
        origin.y = min(max(origin.y, visibleFrame.minY + 6), visibleFrame.maxY - 48)
        panel.setFrameOrigin(origin)
        model.phase = .ready
        model.tooltip = "Polish selection (⌥⌘P)"
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
        model.phase = .ready
    }

    func showWorking() {
        model.phase = .working
        model.tooltip = "Polishing…"
    }

    func showSuccess() {
        model.phase = .success
        model.tooltip = "Selection polished"
    }

    func showFailure(_ message: String) {
        model.phase = .failure
        model.tooltip = message
    }
}

private struct FloatingButtonView: View {
    @ObservedObject var model: FloatingButtonModel
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(.ultraThickMaterial)
                    .overlay(Circle().strokeBorder(borderColor.opacity(0.5), lineWidth: 1))

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
        .help(model.tooltip)
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
