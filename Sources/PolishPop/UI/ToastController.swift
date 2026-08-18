import AppKit
import SwiftUI

/// What a toast is telling the user, which drives its icon, tint and how long it stays up.
enum ToastSeverity: Sendable {
    case info
    case success
    case warning
    case failure

    var symbolName: String {
        switch self {
        case .info: "sparkles"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .failure: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .info: .purple
        case .success: .green
        case .warning: .orange
        case .failure: .red
        }
    }

    var defaultDuration: TimeInterval {
        switch self {
        case .info, .success: 2.6
        case .warning, .failure: 5.5
        }
    }
}

/// A single transient message, optionally with one button.
struct Toast: Identifiable {
    struct Action {
        let title: LocalizedText
        let handler: @MainActor () -> Void
    }

    let id = UUID()
    let severity: ToastSeverity
    let message: LocalizedText
    var action: Action?
    var duration: TimeInterval?

    var resolvedDuration: TimeInterval {
        if let duration { return duration }
        return action == nil ? severity.defaultDuration : max(severity.defaultDuration, 7)
    }
}

@MainActor
private final class ToastModel: ObservableObject {
    @Published var toast: Toast?
}

private final class NonActivatingToastPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows short status messages without ever taking focus from whatever the user is typing in.
///
/// This replaces modal alerts: a rewrite utility that interrupts your typing with a dialog you
/// must dismiss is worse than one that quietly tells you what happened.
@MainActor
final class ToastController {
    private let model = ToastModel()
    private let panel: NonActivatingToastPanel
    private var dismissTask: Task<Void, Never>?
    /// Invalidates the completion handler of a fade-out that a newer toast has overtaken.
    private var generation = 0

    init() {
        panel = NonActivatingToastPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.animationBehavior = .utilityWindow

        let hosting = NSHostingView(
            rootView: ToastView(model: model) { [weak self] in
                self?.dismiss()
            }
        )
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
    }

    func show(_ toast: Toast, near anchor: NSPoint? = nil) {
        dismissTask?.cancel()
        generation += 1
        model.toast = toast

        let size = preferredSize(for: toast)
        panel.setContentSize(size)
        position(size: size, near: anchor)
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.14
            panel.animator().alphaValue = 1
        }

        let duration = toast.resolvedDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        guard panel.isVisible else { return }
        generation += 1
        let token = generation
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            panel.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor in
                // A toast shown during this fade owns the panel now; tearing it down here would
                // make the newer message vanish after 120 ms.
                guard let self, self.generation == token else { return }
                self.panel.orderOut(nil)
                self.model.toast = nil
            }
        }
    }

    /// Grows the panel for long messages instead of truncating the one thing the user needs to read.
    ///
    /// Measured rather than estimated from a character count: a Chinese ideograph is roughly twice
    /// as wide as a Latin letter, so a character-count heuristic clips every translated message.
    private func preferredSize(for toast: Toast) -> NSSize {
        let text = toast.message.current
        let width: CGFloat = text.count > 60 ? 420 : 360
        let textWidth = width - 78
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12.5)]
        let bounding = (text as NSString).boundingRect(
            with: NSSize(width: textWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
        let actionHeight: CGFloat = toast.action == nil ? 0 : 30
        return NSSize(width: width, height: max(56, ceil(bounding.height) + 30 + actionHeight))
    }

    private func position(size: NSSize, near anchor: NSPoint?) {
        let anchorPoint = anchor ?? NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(anchorPoint) } ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else { return }

        var origin: NSPoint
        if anchor == nil {
            origin = NSPoint(
                x: visibleFrame.maxX - size.width - 18,
                y: visibleFrame.maxY - size.height - 18
            )
        } else {
            origin = NSPoint(x: anchorPoint.x + 14, y: anchorPoint.y - size.height - 26)
            if origin.y < visibleFrame.minY + 12 {
                origin.y = anchorPoint.y + 26
            }
        }
        origin.x = min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
        origin.y = min(max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        panel.setFrameOrigin(origin)
    }
}

private struct ToastView: View {
    @ObservedObject var model: ToastModel
    @ObservedObject private var localization = Localization.shared
    let dismiss: () -> Void

    init(model: ToastModel, dismiss: @escaping () -> Void) {
        self.model = model
        self.dismiss = dismiss
    }

    var body: some View {
        if let toast = model.toast {
            HStack(alignment: .top, spacing: 11) {
                Image(systemName: toast.severity.symbolName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(toast.severity.tint)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 7) {
                    Text(toast.message.current)
                        .font(.system(size: 12.5))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if let action = toast.action {
                        Button(action.title.current) {
                            action.handler()
                            dismiss()
                        }
                        .controlSize(.small)
                    }
                }

                Button(action: dismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(ShellStrings.dismissButton.current)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
            .overlay(
                RoundedRectangle(cornerRadius: 13)
                    .strokeBorder(toast.severity.tint.opacity(0.35), lineWidth: 1)
            )
            .accessibilityElement(children: .contain)
        }
    }
}
