import AppKit
import SwiftUI

/// An editable text view that can show which words the rewrite added.
///
/// SwiftUI's `TextEditor` cannot render per-range styling and gives up its own undo stack, so the
/// draft pane wraps `NSTextView` directly. That also restores the standard editing shortcuts and
/// proper input-method behaviour for Chinese and Japanese typing.
struct RichTextEditor: NSViewRepresentable {
    @Binding var text: String
    var highlights: [DiffSegment]
    /// Bumped by the model whenever the draft is replaced from outside or the user toggles the
    /// change highlighting. Re-styling on anything else would rewrite the text storage under the
    /// user's cursor on every keystroke, resetting the selection and breaking IME composition.
    var revision: Int
    var isEditable: Bool
    var focusOnAppear: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else { return scrollView }

        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.font = .systemFont(ofSize: NSFont.systemFontSize)
        textView.textContainerInset = NSSize(width: 8, height: 9)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder

        context.coordinator.apply(text: text, highlights: highlights, revision: revision, to: textView)
        if focusOnAppear {
            DispatchQueue.main.async {
                textView.window?.makeFirstResponder(textView)
                textView.setSelectedRange(NSRange(location: 0, length: 0))
            }
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        textView.isEditable = isEditable
        textView.isSelectable = true
        context.coordinator.text = $text

        guard textView.string != text || context.coordinator.appliedRevision != revision else { return }
        context.coordinator.apply(text: text, highlights: highlights, revision: revision, to: textView)
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        private(set) var appliedRevision = -1
        private var isApplyingProgrammatically = false

        init(text: Binding<String>) {
            self.text = text
        }

        func apply(text value: String, highlights: [DiffSegment], revision: Int, to textView: NSTextView) {
            isApplyingProgrammatically = true
            defer { isApplyingProgrammatically = false }

            let selected = textView.selectedRange()
            let attributed = Self.attributedString(for: value, highlights: highlights)
            textView.textStorage?.setAttributedString(attributed)
            textView.typingAttributes = Self.baseAttributes
            appliedRevision = revision

            let safeLocation = min(selected.location, (value as NSString).length)
            textView.setSelectedRange(NSRange(location: safeLocation, length: 0))
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingProgrammatically,
                  let textView = notification.object as? NSTextView else { return }
            text.wrappedValue = textView.string
        }

        static var baseAttributes: [NSAttributedString.Key: Any] {
            [
                .font: NSFont.systemFont(ofSize: NSFont.systemFontSize),
                .foregroundColor: NSColor.labelColor
            ]
        }

        static func attributedString(for value: String, highlights: [DiffSegment]) -> NSAttributedString {
            let result = NSMutableAttributedString()
            let insertionBackground = NSColor.systemGreen.withAlphaComponent(0.22)

            guard !highlights.isEmpty else {
                return NSAttributedString(string: value, attributes: baseAttributes)
            }

            for segment in highlights where segment.kind != .removed {
                var attributes = baseAttributes
                if segment.kind == .inserted {
                    attributes[.backgroundColor] = insertionBackground
                }
                result.append(NSAttributedString(string: segment.text, attributes: attributes))
            }

            // Fall back to the plain string if the segments do not reconstruct the text exactly,
            // so a diff bug can never corrupt what the user is about to apply.
            guard result.string == value else {
                return NSAttributedString(string: value, attributes: baseAttributes)
            }
            return result
        }
    }
}

/// Read-only rendering of the original with the removed words struck through.
struct DiffOriginalText: View {
    let segments: [DiffSegment]
    let showHighlights: Bool
    let plainText: String

    var body: some View {
        Text(attributed)
            .font(.body)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
    }

    private var attributed: AttributedString {
        guard showHighlights else { return AttributedString(plainText) }
        var result = AttributedString()
        for segment in segments where segment.kind != .inserted {
            var piece = AttributedString(segment.text)
            if segment.kind == .removed {
                piece.backgroundColor = Color.red.opacity(0.18)
                piece.strikethroughStyle = .single
            }
            result.append(piece)
        }
        return result.characters.isEmpty ? AttributedString(plainText) : result
    }
}
