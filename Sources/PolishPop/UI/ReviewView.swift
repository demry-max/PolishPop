import SwiftUI

/// The side-by-side review panel: the untouched original on the left, the editable draft on the
/// right, and a status line that says exactly what will happen when a button is pressed.
struct ReviewView: View {
    @ObservedObject var model: ReviewViewModel
    @ObservedObject private var localization = Localization.shared

    let apply: () -> Void
    let copy: () -> Void
    let cancel: () -> Void
    let regenerate: () -> Void
    let stop: () -> Void

    init(
        model: ReviewViewModel,
        apply: @escaping () -> Void,
        copy: @escaping () -> Void,
        cancel: @escaping () -> Void,
        regenerate: @escaping () -> Void,
        stop: @escaping () -> Void
    ) {
        self.model = model
        self.apply = apply
        self.copy = copy
        self.cancel = cancel
        self.regenerate = regenerate
        self.stop = stop
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            controls
            panes
            Divider()
            footer
        }
        .padding(20)
        .frame(minWidth: 560, minHeight: 380)
        .onChange(of: model.tone) { _ in model.markStaleIfSettingsChanged() }
        .onChange(of: model.purpose) { _ in model.markStaleIfSettingsChanged() }
        .onChange(of: model.draft) { _ in model.recomputeDiff() }
        .onChange(of: model.showDiff) { newValue in
            Preferences.showDiff = newValue
            model.refreshHighlighting()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "sparkles")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ReviewStrings.heading.current)
                    .font(.title3.bold())
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
        }
    }

    private var subtitle: String {
        var parts = [model.purpose.title.current, model.tone.title.current]
        if !model.canReplace {
            parts.append(ReviewStrings.targetUnavailable.current)
        } else if let name = model.targetApplicationName {
            parts.append(ReviewStrings.targetApp(name).current)
        } else {
            parts.append(ReviewStrings.originalUnchanged.current)
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 12) {
            Picker(ReviewStrings.useCase.current, selection: $model.purpose) {
                ForEach(PolishPurpose.allCases) { purpose in
                    Label(purpose.title.current, systemImage: purpose.symbolName).tag(purpose)
                }
            }
            .frame(maxWidth: 240)
            .disabled(model.isBusy)

            Picker(ReviewStrings.tone.current, selection: $model.tone) {
                ForEach(PolishTone.allCases) { tone in
                    Label(tone.title.current, systemImage: tone.symbolName).tag(tone)
                }
            }
            .frame(maxWidth: 190)
            .disabled(model.isBusy)

            Spacer()

            Toggle(isOn: $model.showDiff) {
                Label(ReviewStrings.showChanges.current, systemImage: "plusminus")
            }
            .toggleStyle(.button)
            .help(ReviewStrings.showChangesHelp.current)
            .disabled(model.diff.truncated)

            if model.phase == .generating {
                Button(ReviewStrings.stopGenerating.current, action: stop)
                    .keyboardShortcut(".", modifiers: .command)
            } else {
                Button(action: regenerate) {
                    Label(ReviewStrings.regenerate.current, systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(model.phase == .stale ? AnyButtonStyle(.borderedProminent) : AnyButtonStyle(.bordered))
                .disabled(model.isBusy)
            }
        }
    }

    // MARK: - Panes

    private var panes: some View {
        HStack(alignment: .top, spacing: 14) {
            originalPane
            draftPane
        }
        .frame(maxHeight: .infinity)
    }

    private var originalPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            paneHeader(
                title: ReviewStrings.original.current,
                symbol: "doc.text",
                trailing: "\(TextStats.characterCount(model.original))"
            )
            ScrollView {
                DiffOriginalText(
                    segments: model.diff.originalSegments,
                    showHighlights: model.showDiff && !model.diff.truncated,
                    plainText: model.original
                )
            }
            .background(.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(.secondary.opacity(0.18)))
            .accessibilityLabel(ReviewStrings.original.current)
            .accessibilityValue(model.original)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var draftPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            paneHeader(
                title: ReviewStrings.draft.current,
                symbol: "pencil.and.outline",
                trailing: changeSummary
            )
            ZStack {
                RichTextEditor(
                    text: $model.draft,
                    highlights: model.showDiff && !model.diff.truncated ? model.diff.draftSegments : [],
                    revision: model.draftRevision,
                    isEditable: !model.isBusy,
                    focusOnAppear: false
                )
                .background(.purple.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(.purple.opacity(0.25)))
                .opacity(model.phase == .generating ? 0.35 : 1)

                if model.phase == .generating {
                    VStack(spacing: 9) {
                        ProgressView().controlSize(.small)
                        Text(ReviewStrings.generating.current)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(ReviewStrings.generating.current)
                }
            }
            .accessibilityLabel(ReviewStrings.draft.current)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func paneHeader(title: String, symbol: String, trailing: String) -> some View {
        HStack(spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
            Spacer()
            Text(trailing)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private var changeSummary: String {
        guard !model.draftIsEmpty else { return "" }
        let counts = ReviewStrings.characterDelta(
            from: TextStats.characterCount(model.original),
            to: TextStats.characterCount(model.draft)
        ).current
        guard model.showDiff, !model.diff.truncated else { return counts }
        guard model.diff.hasChanges else { return ReviewStrings.noChanges.current }
        let delta = ReviewStrings.changeSummary(
            added: model.diff.insertedWordCount,
            removed: model.diff.removedWordCount
        ).current
        return "\(counts)  ·  \(delta)"
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.caption)
                .foregroundStyle(statusColor)
                .accessibilityHidden(true)
            Text(model.status.current)
                .font(.caption)
                .foregroundStyle(statusColor)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)


            Spacer(minLength: 12)

            Button(ReviewStrings.cancel.current, action: cancel)
                .keyboardShortcut(.cancelAction)

            Button(action: copy) {
                Text(ReviewStrings.copyDraft.current)
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
            .disabled(model.draftIsEmpty || model.isBusy)
            .help(ReviewStrings.copyShortcutHint.current)

            Button(action: apply) {
                Text(ReviewStrings.apply.current)
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.draftIsEmpty || model.isBusy || !model.canReplace)
            .help(ReviewStrings.applyShortcutHint.current)
        }
    }

    private var statusSymbol: String {
        switch model.phase {
        case .generating, .applying: "hourglass"
        case .ready: "checkmark.seal"
        case .stale: "arrow.triangle.2.circlepath"
        case .problem: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch model.phase {
        case .problem: .red
        case .stale: .orange
        default: .secondary
        }
    }
}

/// Lets a conditional pick between two concrete button styles without the branches disagreeing
/// about their opaque return types.
private struct AnyButtonStyle: PrimitiveButtonStyle {
    private let makeBody: (Configuration) -> AnyView

    init<Style: PrimitiveButtonStyle>(_ style: Style) {
        makeBody = { configuration in
            AnyView(style.makeBody(configuration: configuration))
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        makeBody(configuration)
    }
}
