import AppKit
import SwiftUI

private final class NonActivatingReviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var original = ""
    @Published var draft = ""
    @Published var tone: PolishTone = .professional
    @Published var purpose: PolishPurpose = .smart
    @Published var statusMessage = "Review the draft before applying it."
    @Published var isApplying = false
    @Published var isGenerating = false
}

@MainActor
final class ReviewWindowController: NSObject, NSWindowDelegate {
    private let model = ReviewViewModel()
    private let window: NonActivatingReviewPanel
    private var suppressCloseCallback = false

    var onApply: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onCancel: (() -> Void)?
    var onRegenerate: ((PolishPurpose, PolishTone) -> Void)?

    override init() {
        window = NonActivatingReviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = "Review PolishPop Draft"
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .utilityWindow
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: ReviewView(
                model: model,
                apply: { [weak self] in
                    guard let self else { return }
                    model.isApplying = true
                    model.statusMessage = "Applying to the original selection…"
                    onApply?(model.draft)
                },
                copy: { [weak self] in
                    guard let self else { return }
                    onCopy?(model.draft)
                    model.statusMessage = "Draft copied to the clipboard."
                },
                cancel: { [weak self] in
                    self?.close()
                },
                regenerate: { [weak self] in
                    guard let self else { return }
                    model.isGenerating = true
                    model.statusMessage = "Generating a new \(model.purpose.title) draft…"
                    onRegenerate?(model.purpose, model.tone)
                }
            )
        )
        window.center()
    }

    func show(
        original: String,
        draft: String,
        tone: PolishTone,
        purpose: PolishPurpose,
        near anchor: NSPoint
    ) {
        model.original = original
        model.draft = draft
        model.tone = tone
        model.purpose = purpose
        model.statusMessage = "Review first. Apply uses a temporary paste fallback only if direct replacement is unavailable."
        model.isApplying = false
        model.isGenerating = false
        suppressCloseCallback = false
        window.orderOut(nil)
        positionWindow(near: anchor)
        window.orderFrontRegardless()
        window.makeKey()
    }

    func showApplyError(_ message: String) {
        model.isApplying = false
        model.statusMessage = message
        window.orderFrontRegardless()
        window.makeKey()
    }

    func updateDraft(_ draft: String) {
        model.draft = draft
        model.isGenerating = false
        model.statusMessage = "New draft ready. Review it before applying."
    }

    func showGenerationError(_ message: String) {
        model.isGenerating = false
        model.statusMessage = message
        window.orderFrontRegardless()
        window.makeKey()
    }

    func closeAfterSuccess() {
        suppressCloseCallback = true
        window.orderOut(nil)
        suppressCloseCallback = false
    }

    func close() {
        window.performClose(nil)
    }

    func windowWillClose(_ notification: Notification) {
        guard !suppressCloseCallback else { return }
        onCancel?()
    }

    private func positionWindow(near anchor: NSPoint) {
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) }) ?? NSScreen.main
        guard let visibleFrame = screen?.visibleFrame else {
            window.center()
            return
        }

        let size = window.frame.size
        var x = anchor.x - size.width / 2
        var y = anchor.y - size.height - 24
        if y < visibleFrame.minY + 12 {
            y = anchor.y + 28
        }
        x = min(max(x, visibleFrame.minX + 12), visibleFrame.maxX - size.width - 12)
        y = min(max(y, visibleFrame.minY + 12), visibleFrame.maxY - size.height - 12)
        window.setFrameOrigin(NSPoint(x: x, y: y))
    }
}

private struct ReviewView: View {
    @ObservedObject var model: ReviewViewModel
    let apply: () -> Void
    let copy: () -> Void
    let cancel: () -> Void
    let regenerate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            controls

            HStack(alignment: .top, spacing: 16) {
                originalPanel
                draftPanel
            }
            .frame(maxHeight: .infinity)

            Divider()

            HStack(spacing: 12) {
                Text(model.statusMessage)
                    .font(.caption)
                    .foregroundStyle(statusColor)
                    .lineLimit(2)
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .disabled(model.isApplying || model.isGenerating)
                Button("Copy Draft", action: copy)
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isApplying || model.isGenerating)
                Button("Apply to Original", action: apply)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isApplying || model.isGenerating)
            }
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 480)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 2) {
                Text("Review polished draft")
                    .font(.title2.bold())
                Text("\(model.purpose.title) · \(model.tone.title) tone · Original unchanged")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 14) {
            Picker("Use case", selection: $model.purpose) {
                ForEach(PolishPurpose.allCases) { purpose in
                    Text(purpose.title).tag(purpose)
                }
            }
            .frame(maxWidth: 220)

            Picker("Tone", selection: $model.tone) {
                ForEach(PolishTone.allCases) { tone in
                    Text(tone.title).tag(tone)
                }
            }
            .frame(maxWidth: 170)

            Spacer()

            Button(action: regenerate) {
                if model.isGenerating {
                    ProgressView().controlSize(.small)
                } else {
                    Label("Regenerate", systemImage: "arrow.clockwise")
                }
            }
            .disabled(model.isApplying || model.isGenerating)
        }
    }

    private var originalPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Original", systemImage: "doc.text")
                .font(.headline)
            ScrollView {
                Text(model.original)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .textSelection(.enabled)
                    .padding(12)
            }
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.18)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var draftPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Polished draft — editable", systemImage: "pencil.and.outline")
                .font(.headline)
            TextEditor(text: $model.draft)
                .font(.body)
                .padding(8)
                .scrollContentBackground(.hidden)
                .background(.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.purple.opacity(0.25)))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statusColor: Color {
        model.statusMessage.lowercased().contains("could not")
            || model.statusMessage.lowercased().contains("changed")
            ? .red
            : .secondary
    }
}
