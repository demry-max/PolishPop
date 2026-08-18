import Foundation

/// Length measurements shown next to the draft so the user can see at a glance whether the
/// rewrite grew or shrank the text.
enum TextStats {
    /// Characters as a reader would count them, ignoring leading and trailing whitespace.
    static func characterCount(_ text: String) -> Int {
        text.trimmingCharacters(in: .whitespacesAndNewlines).count
    }

    /// Words for space-separated scripts, plus one unit per CJK ideograph so Chinese text
    /// produces a meaningful count instead of one giant "word".
    static func wordCount(_ text: String) -> Int {
        var words = 0
        var insideLatinWord = false
        for character in text {
            if TextDiff.isIdeograph(character) {
                if !character.isPunctuation, !character.isWhitespace {
                    words += 1
                }
                insideLatinWord = false
                continue
            }
            if character.isLetter || character.isNumber {
                if !insideLatinWord {
                    words += 1
                    insideLatinWord = true
                }
            } else {
                insideLatinWord = false
            }
        }
        return words
    }
}
