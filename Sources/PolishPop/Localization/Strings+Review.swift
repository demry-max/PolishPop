import Foundation

/// Strings for the floating review panel.
enum ReviewStrings {
    static let windowTitle = LocalizedText("Review PolishPop Draft", "校对润色结果")
    static let heading = LocalizedText("Review polished draft", "校对润色结果")
    static let originalUnchanged = LocalizedText("Original unchanged", "原文未改动")
    static let original = LocalizedText("Original", "原文")
    static let draft = LocalizedText("Polished draft — editable", "润色结果 — 可编辑")
    static let showChanges = LocalizedText("Changes", "改动")
    static let showChangesHelp = LocalizedText("Highlight what changed", "高亮显示改动内容")
    static let useCase = LocalizedText("Use case", "用途")
    static let tone = LocalizedText("Tone", "语气")
    static let regenerate = LocalizedText("Regenerate", "重新生成")
    static let apply = LocalizedText("Replace Original", "替换原文")
    static let copyDraft = LocalizedText("Copy", "拷贝")
    static let cancel = LocalizedText("Cancel", "取消")
    static let generating = LocalizedText("Writing the polished draft…", "正在生成润色结果…")
    static let stopGenerating = LocalizedText("Stop", "停止")

    static func targetApp(_ name: String) -> LocalizedText {
        LocalizedText("Replaces the selection in \(name)", "将替换 \(name) 中选中的文字")
    }

    static let targetUnavailable = LocalizedText(
        "The original field is no longer available — use Copy instead.",
        "原文所在的输入框已不可用 — 请改用「拷贝」。"
    )

    static func characterDelta(from: Int, to: Int) -> LocalizedText {
        LocalizedText("\(from) → \(to)", "\(from) → \(to) 字")
    }

    static func changeSummary(added: Int, removed: Int) -> LocalizedText {
        LocalizedText("+\(added) −\(removed)", "增\(added) 删\(removed)")
    }

    static let noChanges = LocalizedText("No changes were needed", "无需改动")

    // Status line
    static let reviewFirst = LocalizedText(
        "Nothing is replaced until you choose Replace Original.",
        "在你点击「替换原文」之前，原文不会有任何改动。"
    )
    static let applying = LocalizedText("Replacing the original selection…", "正在替换原文…")
    static let draftReady = LocalizedText("New draft ready. Review it before replacing.", "新的润色结果已生成，请先校对。")
    static let draftCopied = LocalizedText("Draft copied to the clipboard.", "已复制到剪贴板。")
    static let regenerationCancelled = LocalizedText(
        "Regeneration stopped. The existing draft was kept.",
        "已停止重新生成，保留原有结果。"
    )
    static let applyCancelled = LocalizedText(
        "Replacement cancelled. The original text was not changed.",
        "已取消替换，原文未改动。"
    )
    static let staleDraft = LocalizedText(
        "Settings changed — choose Regenerate for a new draft.",
        "设置已更改 — 点击「重新生成」获取新结果。"
    )

    static func applyFailed(_ reason: String) -> LocalizedText {
        LocalizedText(
            "\(reason) You can use Copy and paste it manually.",
            "\(reason) 你可以先「拷贝」再手动粘贴。"
        )
    }

    // Keyboard hints
    static let applyShortcutHint = LocalizedText("⌘↩", "⌘↩")
    static let copyShortcutHint = LocalizedText("⇧⌘C", "⇧⌘C")
    static let regenerateShortcutHint = LocalizedText("⌘R", "⌘R")
}
