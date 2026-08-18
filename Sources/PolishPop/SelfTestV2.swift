import Foundation

/// Deterministic checks that run in the packaging script before an app bundle is produced.
enum SelfTest {
    /// Accumulates results so a run reports every failure at once rather than the first.
    struct Results {
        private(set) var total = 0
        private(set) var failures: [String] = []

        mutating func check(_ condition: Bool, _ name: String) {
            total += 1
            if !condition { failures.append(name) }
        }
    }

    static func run() -> Bool {
        var results = Results()

        checkProtocol(&results)
        checkPrompts(&results)
        checkDiff(&results)
        checkTextStats(&results)
        checkShortcuts(&results)
        checkLocalization(&results)
        checkSelectionGestures(&results)

        if results.failures.isEmpty {
            print("PolishPop self-test: \(results.total) checks passed")
            return true
        }
        for failure in results.failures {
            fputs("FAIL: \(failure)\n", stderr)
        }
        return false
    }

    // MARK: - Codex protocol

    private static func checkProtocol(_ results: inout Results) {
        let unicodeValue: JSONValue = .object([
            "id": .number(7),
            "text": .string("Hello 世界 👋"),
            "enabled": .bool(true)
        ])
        let roundTrip = try? JSONDecoder().decode(
            JSONValue.self,
            from: JSONEncoder().encode(unicodeValue)
        )
        results.check(roundTrip == unicodeValue, "JSONL value round trip")

        let accountPayload: JSONValue = .object([
            "account": .object([
                "type": .string("chatgpt"),
                "email": .string("person@example.com"),
                "planType": .string("plus")
            ]),
            "requiresOpenaiAuth": .bool(true)
        ])
        results.check(CodexAppServerClient.parseAccount(from: accountPayload)?.planType == "plus", "ChatGPT account parser")

        let apiAccountPayload: JSONValue = .object([
            "account": .object(["type": .string("apiKey")]),
            "requiresOpenaiAuth": .bool(true)
        ])
        results.check(CodexAppServerClient.parseAccount(from: apiAccountPayload) == nil, "API-key account rejection")

        let structured = try? CodexAppServerClient.extractAnswer(from: #"{"answer":"Polished message"}"#)
        results.check(structured == "Polished message", "structured output parser")

        let invalidPlain = try? CodexAppServerClient.extractAnswer(from: "Unstructured message")
        results.check(invalidPlain == nil, "unstructured output rejection")
    }

    private static func checkPrompts(_ results: inout Results) {
        results.check(CodexAppServerClient.baseInstructions.contains("Do not use tools"), "no-tools base instruction")

        let developer = CodexAppServerClient.developerInstructions(for: .professional, purpose: .email)
        results.check(developer.contains("names, dates, amounts") && developer.contains("Never invent missing facts"), "business-facts preservation prompt")
    }

    // MARK: - Diff

    private static func checkDiff(_ results: inout Results) {
        let identical = TextDiff.compare(original: "same text", draft: "same text")
        results.check(!identical.hasChanges, "identical text reports no changes")

        let edited = TextDiff.compare(
            original: "pls review the report by friday",
            draft: "Please review the report by Friday."
        )
        results.check(edited.insertedWordCount > 0, "diff detects insertions")
        results.check(edited.removedWordCount > 0, "diff detects removals")

        // The rendered segments must rebuild each side exactly, or the panel would show the user
        // text that differs from what Apply will write.
        let draftFromSegments = edited.draftSegments
            .filter { $0.kind != .removed }
            .map(\.text)
            .joined()
        results.check(draftFromSegments == "Please review the report by Friday.", "draft segments reconstruct the draft")
        let originalFromSegments = edited.originalSegments
            .filter { $0.kind != .inserted }
            .map(\.text)
            .joined()
        results.check(originalFromSegments == "pls review the report by friday", "original segments reconstruct the original")

        let shortChinese = TextDiff.compare(original: "我可能去不了", draft: "我可能无法出席")
        results.check(shortChinese.hasChanges, "diff handles CJK without spaces")
        results.check(shortChinese.draftSegments.filter { $0.kind != .removed }.map(\.text).joined() == "我可能无法出席", "CJK draft segments reconstruct the draft")

        // A long selection with a trailing edit: the prefix/suffix trim alone should handle it.
        let long = String(repeating: "word ", count: 3_000)
        let longEdited = TextDiff.compare(original: long, draft: long + "extra")
        results.check(!longEdited.truncated, "long text with a trailing edit still highlights")
        results.check(longEdited.insertedWordCount == 1, "trailing edit is isolated to the change")

        // The case a quadratic diff cannot serve: a long document whose changes are spread all the
        // way through it, which is exactly what a polished draft looks like.
        let paragraph = "the report shows steady growth and the team expects that to continue. "
        let scattered = String(repeating: paragraph, count: 40)
        let scatteredDraft = scattered
            .replacingOccurrences(of: "steady", with: "consistent")
            .replacingOccurrences(of: "expects", with: "anticipates")
        let scatteredStart = Date()
        let scatteredDiff = TextDiff.compare(original: scattered, draft: scatteredDraft)
        let scatteredMilliseconds = Date().timeIntervalSince(scatteredStart) * 1_000
        results.check(!scatteredDiff.truncated, "scattered edits across a long text still highlight")
        results.check(scatteredDiff.insertedWordCount == 80, "every scattered edit is found")
        results.check(scatteredMilliseconds < 100, "scattered-edit diff stays interactive")

        // CJK has no word separators, so every character is a token; this must stay fast enough to
        // run while the user types in the draft.
        let chinese = String(repeating: "下周三的评审会我可能去不了，有几个数据还没跑完。", count: 40)
        let chineseDraft = chinese.replacingOccurrences(of: "去不了", with: "无法出席")
        let chineseStart = Date()
        let chineseDiff = TextDiff.compare(original: chinese, draft: chineseDraft)
        let chineseMilliseconds = Date().timeIntervalSince(chineseStart) * 1_000
        results.check(!chineseDiff.truncated, "long CJK text still highlights")
        results.check(chineseMilliseconds < 100, "CJK diff stays interactive")

        // Two texts that share nothing exceed the edit budget and must degrade to plain text
        // rather than spending seconds tracing a rewrite word by word.
        let leftWords = (0..<1_200).map { "a\($0)" }.joined(separator: " ")
        let rightWords = (0..<1_200).map { "b\($0)" }.joined(separator: " ")
        let oversized = TextDiff.compare(original: leftWords, draft: rightWords)
        results.check(oversized.truncated, "wholesale rewrite degrades safely")
        results.check(
            oversized.draftSegments.map(\.text).joined() == rightWords,
            "truncated diff still renders the full draft"
        )
    }

    private static func checkTextStats(_ results: inout Results) {
        results.check(TextStats.wordCount("hello there friend") == 3, "latin word count")
        results.check(TextStats.wordCount("下周三的评审会") == 7, "CJK character count")
        results.check(TextStats.characterCount("  padded  ") == 6, "character count trims padding")
    }

    // MARK: - Shortcuts

    private static func checkShortcuts(_ results: inout Results) {
        let stored = ShortcutDefinition.polishDefault.storageValue
        results.check(ShortcutDefinition(storageValue: stored) == .polishDefault, "shortcut storage round trip")
        results.check(ShortcutDefinition(keyCode: 35, carbonModifiers: 0).isValid == false, "modifier-less shortcut rejected")
        results.check(ShortcutDefinition.polishDefault.displayString.hasSuffix("P"), "shortcut renders its key name")
        results.check(ShortcutDefinition.quickDefault != ShortcutDefinition.polishDefault, "instant-replace shortcut differs from the review shortcut")

        // NSMenuItem.keyEquivalent holds one character; anything longer renders literally and
        // never matches a key press, so those shortcuts must report no equivalent at all.
        results.check(ShortcutDefinition.polishDefault.menuKeyEquivalentCharacter == "p", "letter shortcut yields a menu key equivalent")
        let spaceShortcut = ShortcutDefinition(keyCode: 49, carbonModifiers: ShortcutDefinition.polishDefault.carbonModifiers)
        results.check(spaceShortcut.menuKeyEquivalentCharacter == " ", "Space maps to its own character")
        let unknownShortcut = ShortcutDefinition(keyCode: 9_999, carbonModifiers: ShortcutDefinition.polishDefault.carbonModifiers)
        results.check(unknownShortcut.menuKeyEquivalentCharacter == nil, "unnameable key reports no menu equivalent")
        results.check(unknownShortcut.displayString.contains("9999"), "unnameable key still renders in the shortcut label")
    }

    // MARK: - Selection gestures

    /// A mouse-up with no matching mouse-down is the normal case, not an edge case: a global
    /// monitor sees nothing while PolishPop itself is frontmost. Treating it as a sentinel
    /// distance once crashed the app on release builds, so the nil path is pinned here.
    private static func checkSelectionGestures(_ results: inout Results) {
        results.check(
            SelectionMonitor.isSelectionGesture(travelled: nil, clickCount: 1, isShiftHeld: false),
            "an unobserved mouse-down counts as a drag"
        )
        results.check(
            SelectionMonitor.describe(nil) == "unknown",
            "an unknown distance formats without a numeric conversion"
        )
        results.check(
            SelectionMonitor.describe(.infinity) == "unknown",
            "a non-finite distance formats without a numeric conversion"
        )
        results.check(SelectionMonitor.describe(12.4) == "12", "a real distance still formats")
        results.check(
            SelectionMonitor.isSelectionGesture(travelled: 40, clickCount: 1, isShiftHeld: false),
            "a drag is a selection gesture"
        )
        results.check(
            !SelectionMonitor.isSelectionGesture(travelled: 1, clickCount: 1, isShiftHeld: false),
            "a plain click is not a selection gesture"
        )
        results.check(
            SelectionMonitor.isSelectionGesture(travelled: 0, clickCount: 2, isShiftHeld: false),
            "a double-click is a selection gesture"
        )
        results.check(
            SelectionMonitor.isSelectionGesture(travelled: 0, clickCount: 1, isShiftHeld: true),
            "a shift-click extends a selection"
        )

        // The toast duration is scaled into UInt64 nanoseconds; nothing may reach that unclamped.
        let absurd = Toast(severity: .info, message: ShellStrings.copiedToast, action: nil, duration: .infinity)
        results.check(absurd.resolvedDuration.isFinite, "a non-finite toast duration is rejected")
        let negative = Toast(severity: .info, message: ShellStrings.copiedToast, action: nil, duration: -5)
        results.check(negative.resolvedDuration > 0, "a negative toast duration is clamped")
    }

    // MARK: - Localization

    /// Guards against a half-translated build: every string must differ between languages unless
    /// it is deliberately identical, and none may be empty.
    private static func checkLocalization(_ results: inout Results) {
        var texts: [(String, LocalizedText)] = [
            ("polishSelection", ShellStrings.polishSelection),
            ("polishAndReplace", ShellStrings.polishAndReplace),
            ("undoLastReplacement", ShellStrings.undoLastReplacement),
            ("appliedToast", ShellStrings.appliedToast),
            ("reviewHeading", ReviewStrings.heading),
            ("reviewApply", ReviewStrings.apply),
            ("reviewFirst", ReviewStrings.reviewFirst),
            ("settingsTagline", SettingsStrings.tagline),
            ("privacyNotice", SettingsStrings.privacyNotice),
            ("quickModeWarning", SettingsStrings.quickModeWarning),
            ("noSelection", ErrorStrings.noSelection),
            ("cliNotFound", ErrorStrings.cliNotFound)
        ]
        for tone in PolishTone.allCases {
            texts.append(("tone.\(tone.rawValue)", tone.title))
        }
        for purpose in PolishPurpose.allCases {
            texts.append(("purpose.\(purpose.rawValue)", purpose.title))
        }

        for (name, text) in texts {
            results.check(!text.en.isEmpty, "\(name) has English text")
            results.check(!text.zh.isEmpty, "\(name) has Chinese text")
            results.check(text.en != text.zh, "\(name) is actually translated")
        }

        results.check(AppLanguage.resolve(.automatic, preferred: ["zh-Hans-CN", "en-US"]) == .chineseSimplified, "automatic language follows a Chinese system")
        results.check(AppLanguage.resolve(.automatic, preferred: ["en-GB"]) == .english, "automatic language falls back to English")
        results.check(AppLanguage.resolve(.english, preferred: ["zh-Hans-CN"]) == .english, "explicit language overrides the system")
    }

}
