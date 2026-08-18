import AppKit
import SwiftUI

private final class NonActivatingReviewPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// What the review panel is doing right now, so the status line never has to be reverse-engineered
/// from the wording of a message.
enum ReviewPhase: Equatable {
    case generating
    case ready
    case stale
    case applying
    case problem
}

@MainActor
final class ReviewViewModel: ObservableObject {
    @Published var original = ""
    @Published var draft = ""
    @Published var tone: PolishTone = .professional
    @Published var purpose: PolishPurpose = .smart
    @Published var phase: ReviewPhase = .generating
    @Published var status: LocalizedText = ReviewStrings.generating
    @Published var showDiff = Preferences.showDiff
    @Published var targetApplicationName: String?
    @Published var canReplace = true
    @Published var diff: DiffResult = .unchanged("")
    /// Changes only when the draft text or the highlighting mode is replaced from outside, so the
    /// editor knows when it may safely restyle its contents.
    @Published private(set) var draftRevision = 0

    /// The tone and use case the visible draft was generated with, so switching a picker can mark
    /// the draft stale without a second source of truth.
    var generatedTone: PolishTone = .professional
    var generatedPurpose: PolishPurpose = .smart

    var isBusy: Bool { phase == .generating || phase == .applying }

    var draftIsEmpty: Bool {
        draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func recomputeDiff() {
        diff = draftIsEmpty ? .unchanged(original) : TextDiff.compare(original: original, draft: draft)
    }

    /// Replaces the draft with text PolishPop produced, as opposed to text the user is typing.
    func setGeneratedDraft(_ value: String) {
        draft = value
        recomputeDiff()
        draftRevision += 1
    }

    func refreshHighlighting() {
        draftRevision += 1
    }

    func markStaleIfSettingsChanged() {
        guard phase == .ready || phase == .stale else { return }
        if tone != generatedTone || purpose != generatedPurpose {
            phase = .stale
            status = ReviewStrings.staleDraft
        } else {
            phase = .ready
            status = ReviewStrings.reviewFirst
        }
    }
}

@MainActor
final class ReviewWindowController: NSObject, NSWindowDelegate {
    private let model = ReviewViewModel()
    private let window: NonActivatingReviewPanel
    private var suppressCloseCallback = false
    /// Identifies the polish the panel is currently showing. A reply that belongs to a session the
    /// user has already closed or replaced must not overwrite what is on screen.
    private(set) var sessionID = UUID()

    var onApply: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    /// Carries the draft as it stands so a cancelled session's hand edits are not simply lost.
    var onCancel: ((String) -> Void)?
    var onRegenerate: ((PolishPurpose, PolishTone) -> Void)?
    var onStopGenerating: (() -> Void)?

    override init() {
        window = NonActivatingReviewPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 540),
            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = ReviewStrings.windowTitle.current
        window.minSize = NSSize(width: 560, height: 380)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = false
        window.level = .floating
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.animationBehavior = .utilityWindow
        window.delegate = self
        let hosting = NSHostingView(
            rootView: ReviewView(
                model: model,
                apply: { [weak self] in self?.beginApply() },
                copy: { [weak self] in self?.copyDraft() },
                cancel: { [weak self] in self?.close() },
                regenerate: { [weak self] in self?.beginRegenerate() },
                stop: { [weak self] in self?.stopGenerating() }
            )
        )
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
    }

    /// Called by the app delegate when the interface language changes; SwiftUI redraws itself, but
    /// the AppKit window title has to be rewritten by hand.
    func refreshLanguage() {
        window.title = ReviewStrings.windowTitle.current
    }

    /// Opens the panel before the draft exists so the user sees progress and a Stop button
    /// instead of waiting on a 38-point spinner in the corner of their screen.
    func showGenerating(
        original: String,
        tone: PolishTone,
        purpose: PolishPurpose,
        targetApplicationName: String?,
        canReplace: Bool,
        near anchor: NSPoint
    ) -> UUID {
        sessionID = UUID()
        model.original = original
        model.setGeneratedDraft("")
        model.tone = tone
        model.purpose = purpose
        model.generatedTone = tone
        model.generatedPurpose = purpose
        model.targetApplicationName = targetApplicationName
        model.canReplace = canReplace
        model.phase = .generating
        model.status = ReviewStrings.reviewFirst
        model.showDiff = Preferences.showDiff
        suppressCloseCallback = false

        resizeForContent(original)
        position(near: anchor)
        window.orderFrontRegardless()
        window.makeKey()
        return sessionID
    }

    func showDraft(_ draft: String, tone: PolishTone, purpose: PolishPurpose, session: UUID) {
        guard session == sessionID else { return }
        model.setGeneratedDraft(draft)
        model.tone = tone
        model.purpose = purpose
        model.generatedTone = tone
        model.generatedPurpose = purpose
        model.phase = .ready
        model.status = ReviewStrings.reviewFirst
        window.orderFrontRegardless()
        window.makeKey()
    }

    func updateDraft(_ draft: String, session: UUID) {
        guard session == sessionID else { return }
        model.setGeneratedDraft(draft)
        model.generatedTone = model.tone
        model.generatedPurpose = model.purpose
        model.phase = .ready
        model.status = ReviewStrings.draftReady
    }

    /// Errors are only shown while the panel is still on screen. Re-ordering a panel the user
    /// just dismissed back to the front would take their keyboard focus a second time.
    func showApplyError(_ message: LocalizedText, session: UUID) {
        guard session == sessionID, window.isVisible else { return }
        model.phase = .problem
        model.status = ReviewStrings.applyFailed(message.current)
    }

    func showGenerationError(_ message: LocalizedText, session: UUID) {
        guard session == sessionID, window.isVisible else { return }
        model.phase = model.draftIsEmpty ? .problem : .ready
        model.status = message
    }

    /// The draft as the user has it right now, including any hand edits.
    var currentDraft: String { model.draft }

    /// Only the session that opened the panel may close it; an apply that finishes after the user
    /// has started a new polish must not dismiss the new draft.
    func closeAfterSuccess(session: UUID) {
        guard session == sessionID else { return }
        suppressCloseCallback = true
        window.orderOut(nil)
        suppressCloseCallback = false
    }

    func close() {
        window.performClose(nil)
    }

    var isVisible: Bool { window.isVisible }

    func windowWillClose(_ notification: Notification) {
        guard !suppressCloseCallback else { return }
        onCancel?(model.draft)
    }

    /// Remembers the size the user chose so the next review opens at the same proportions.
    func windowDidResize(_ notification: Notification) {
        guard window.isVisible else { return }
        Preferences.reviewPanelSize = window.frame.size
    }

    // MARK: - Actions

    private func beginApply() {
        guard !model.draftIsEmpty, !model.isBusy else { return }
        model.phase = .applying
        model.status = ReviewStrings.applying
        onApply?(model.draft)
    }

    private func copyDraft() {
        guard !model.draftIsEmpty else { return }
        onCopy?(model.draft)
        model.status = ReviewStrings.draftCopied
    }

    private func beginRegenerate() {
        guard !model.isBusy else { return }
        model.phase = .generating
        model.status = ReviewStrings.reviewFirst
        Preferences.tone = model.tone
        Preferences.purpose = model.purpose
        onRegenerate?(model.purpose, model.tone)
    }

    private func stopGenerating() {
        onStopGenerating?()
    }

    // MARK: - Geometry

    /// A two-line selection does not need a 540-point-tall window; a long email does.
    private func resizeForContent(_ original: String) {
        if let remembered = Preferences.reviewPanelSize {
            window.setContentSize(remembered)
            return
        }
        let characters = original.count
        let height: CGFloat
        switch characters {
        case ..<160: height = 380
        case ..<600: height = 460
        case ..<2_000: height = 540
        default: height = 620
        }
        let width: CGFloat = characters < 160 ? 620 : 760
        let clamped = NSSize(
            width: min(width, (NSScreen.main?.visibleFrame.width ?? width) - 40),
            height: min(height, (NSScreen.main?.visibleFrame.height ?? height) - 40)
        )
        window.setContentSize(clamped)
    }

    private func position(near anchor: NSPoint) {
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
