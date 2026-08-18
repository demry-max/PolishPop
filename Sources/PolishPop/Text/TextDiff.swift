import Foundation

/// One run of text in a rendered diff.
struct DiffSegment: Equatable, Sendable {
    enum Kind: Sendable {
        case unchanged
        case inserted
        case removed
    }

    let kind: Kind
    let text: String
}

/// The result of comparing the original selection with the polished draft.
struct DiffResult: Equatable, Sendable {
    /// Segments for rendering the draft: unchanged and inserted runs only.
    let draftSegments: [DiffSegment]
    /// Segments for rendering the original: unchanged and removed runs only.
    let originalSegments: [DiffSegment]
    let insertedWordCount: Int
    let removedWordCount: Int
    /// True when the texts were too large to compare and highlighting was skipped.
    let truncated: Bool

    var hasChanges: Bool { insertedWordCount > 0 || removedWordCount > 0 }

    static func unchanged(_ text: String) -> DiffResult {
        DiffResult(
            draftSegments: [DiffSegment(kind: .unchanged, text: text)],
            originalSegments: [DiffSegment(kind: .unchanged, text: text)],
            insertedWordCount: 0,
            removedWordCount: 0,
            truncated: false
        )
    }
}

/// Word-level diff used to highlight what the rewrite actually changed.
///
/// Uses Myers' greedy algorithm, whose cost scales with the number of *edits* rather than the
/// product of the two lengths. That matters because a polished draft is usually a long text with
/// scattered small changes: a quadratic pass either times out or has to give up on exactly the
/// documents where seeing the changes is most valuable.
enum TextDiff {
    /// Upper bound on tokens per side. Above this the texts are longer than any selection the app
    /// accepts, and comparison is skipped rather than risking a slow pass.
    static let maximumComparedTokens = 20_000

    /// Upper bound on the number of edits the diff will trace. Past this the draft is a rewrite
    /// rather than a revision, and highlighting every word adds nothing a reader can use.
    static let maximumEdits = 800

    static func compare(original: String, draft: String) -> DiffResult {
        guard original != draft else { return .unchanged(draft) }

        let originalTokens = tokenize(original)
        let draftTokens = tokenize(draft)

        var prefix = 0
        let maximumPrefix = min(originalTokens.count, draftTokens.count)
        while prefix < maximumPrefix, originalTokens[prefix] == draftTokens[prefix] {
            prefix += 1
        }

        var suffix = 0
        let maximumSuffix = maximumPrefix - prefix
        while suffix < maximumSuffix,
              originalTokens[originalTokens.count - 1 - suffix] == draftTokens[draftTokens.count - 1 - suffix] {
            suffix += 1
        }

        let originalMiddle = Array(originalTokens[prefix..<(originalTokens.count - suffix)])
        let draftMiddle = Array(draftTokens[prefix..<(draftTokens.count - suffix)])

        guard originalMiddle.count <= maximumComparedTokens,
              draftMiddle.count <= maximumComparedTokens,
              let script = myersScript(originalMiddle, draftMiddle) else {
            return DiffResult(
                draftSegments: [DiffSegment(kind: .unchanged, text: draft)],
                originalSegments: [DiffSegment(kind: .unchanged, text: original)],
                insertedWordCount: 0,
                removedWordCount: 0,
                truncated: true
            )
        }

        let head = originalTokens[0..<prefix].joined()
        let tail = originalTokens[(originalTokens.count - suffix)...].joined()

        var draftSegments: [DiffSegment] = []
        var originalSegments: [DiffSegment] = []
        var insertedWords = 0
        var removedWords = 0

        appendSegment(&draftSegments, kind: .unchanged, text: head)
        appendSegment(&originalSegments, kind: .unchanged, text: head)

        for entry in script {
            switch entry.kind {
            case .unchanged:
                appendSegment(&draftSegments, kind: .unchanged, text: entry.text)
                appendSegment(&originalSegments, kind: .unchanged, text: entry.text)
            case .inserted:
                appendSegment(&draftSegments, kind: .inserted, text: entry.text)
                insertedWords += entry.wordCount
            case .removed:
                appendSegment(&originalSegments, kind: .removed, text: entry.text)
                removedWords += entry.wordCount
            }
        }

        appendSegment(&draftSegments, kind: .unchanged, text: tail)
        appendSegment(&originalSegments, kind: .unchanged, text: tail)

        return DiffResult(
            draftSegments: draftSegments,
            originalSegments: originalSegments,
            insertedWordCount: insertedWords,
            removedWordCount: removedWords,
            truncated: false
        )
    }

    // MARK: - Internals

    private struct ScriptEntry {
        let kind: DiffSegment.Kind
        let text: String
        let wordCount: Int
    }

    /// Splits text into alternating word and separator tokens so the pieces rejoin losslessly.
    ///
    /// CJK has no spaces between words, so each ideograph is its own token; that gives
    /// character-level highlighting for Chinese and word-level highlighting for Latin scripts.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentIsSeparator: Bool?

        func flush() {
            if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }

        for character in text {
            if isIdeograph(character) {
                flush()
                currentIsSeparator = nil
                tokens.append(String(character))
                continue
            }
            let isSeparator = character.isWhitespace || character.isNewline
            if currentIsSeparator != isSeparator {
                flush()
                currentIsSeparator = isSeparator
            }
            current.append(character)
        }
        flush()
        return tokens
    }

    static func isIdeograph(_ character: Character) -> Bool {
        guard let scalar = character.unicodeScalars.first, character.unicodeScalars.count == 1 else {
            return false
        }
        switch scalar.value {
        case 0x3040...0x30FF,     // Hiragana and Katakana
             0x3400...0x4DBF,     // CJK Extension A
             0x4E00...0x9FFF,     // CJK Unified Ideographs
             0xF900...0xFAFF,     // CJK Compatibility Ideographs
             0xAC00...0xD7AF,     // Hangul syllables
             0x3000...0x303F,     // CJK punctuation
             0xFF00...0xFF60:     // Fullwidth forms
            return true
        default:
            return false
        }
    }

    private static func isWordToken(_ token: String) -> Bool {
        guard let first = token.first else { return false }
        return !(first.isWhitespace || first.isNewline)
    }

    private static func appendSegment(_ segments: inout [DiffSegment], kind: DiffSegment.Kind, text: String) {
        guard !text.isEmpty else { return }
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1] = DiffSegment(kind: kind, text: last.text + text)
            return
        }
        segments.append(DiffSegment(kind: kind, text: text))
    }

    /// Myers' greedy diff with a bounded edit distance.
    ///
    /// Returns `nil` when the two sides differ by more than `maximumEdits`, which the caller
    /// reports as an un-highlighted diff instead of a slow one.
    private static func myersScript(_ left: [String], _ right: [String]) -> [ScriptEntry]? {
        let n = left.count
        let m = right.count
        guard n > 0 else {
            return right.isEmpty ? [] : [entry(.inserted, right)]
        }
        guard m > 0 else {
            return [entry(.removed, left)]
        }

        let maximum = min(maximumEdits, n + m)
        let offset = maximum
        var furthest = [Int](repeating: 0, count: 2 * maximum + 1)
        var trace: [[Int]] = []
        trace.reserveCapacity(maximum + 1)

        for d in 0...maximum {
            trace.append(furthest)
            var k = -d
            while k <= d {
                let index = k + offset
                var x: Int
                if k == -d || (k != d && furthest[index - 1] < furthest[index + 1]) {
                    x = furthest[index + 1]
                } else {
                    x = furthest[index - 1] + 1
                }
                var y = x - k
                while x < n, y < m, left[x] == right[y] {
                    x += 1
                    y += 1
                }
                furthest[index] = x
                if x >= n, y >= m {
                    return backtrack(trace: trace, left: left, right: right, offset: offset)
                }
                k += 2
            }
        }
        return nil
    }

    /// Walks the recorded frontiers backwards to turn the edit distance into an actual script.
    private static func backtrack(
        trace: [[Int]],
        left: [String],
        right: [String],
        offset: Int
    ) -> [ScriptEntry] {
        var reversed: [ScriptEntry] = []
        var x = left.count
        var y = right.count

        for d in stride(from: trace.count - 1, through: 0, by: -1) {
            let furthest = trace[d]
            let k = x - y
            let index = k + offset

            let previousK: Int
            if k == -d || (k != d && furthest[index - 1] < furthest[index + 1]) {
                previousK = k + 1
            } else {
                previousK = k - 1
            }
            let previousX = furthest[previousK + offset]
            let previousY = previousX - previousK

            while x > previousX, y > previousY {
                x -= 1
                y -= 1
                reversed.append(single(.unchanged, left[x]))
            }
            guard d > 0 else { break }
            if x == previousX {
                y -= 1
                reversed.append(single(.inserted, right[y]))
            } else {
                x -= 1
                reversed.append(single(.removed, left[x]))
            }
        }
        return reversed.reversed()
    }

    private static func single(_ kind: DiffSegment.Kind, _ token: String) -> ScriptEntry {
        ScriptEntry(kind: kind, text: token, wordCount: isWordToken(token) ? 1 : 0)
    }

    private static func entry(_ kind: DiffSegment.Kind, _ tokens: [String]) -> ScriptEntry {
        ScriptEntry(kind: kind, text: tokens.joined(), wordCount: tokens.filter(isWordToken).count)
    }
}
