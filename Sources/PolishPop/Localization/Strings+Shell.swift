import Foundation

/// Strings for the application shell: main menu, status-item menu, floating button and toasts.
enum ShellStrings {
    // Application and main menu
    static let appName = LocalizedText("PolishPop", "PolishPop")
    static let settingsMenuItem = LocalizedText("Settings…", "设置…")
    static let quit = LocalizedText("Quit PolishPop", "退出 PolishPop")
    static let about = LocalizedText("About PolishPop", "关于 PolishPop")
    static let hide = LocalizedText("Hide PolishPop", "隐藏 PolishPop")
    static let hideOthers = LocalizedText("Hide Others", "隐藏其他")
    static let editMenu = LocalizedText("Edit", "编辑")
    static let undo = LocalizedText("Undo", "撤销")
    static let redo = LocalizedText("Redo", "重做")
    static let cut = LocalizedText("Cut", "剪切")
    static let copy = LocalizedText("Copy", "拷贝")
    static let paste = LocalizedText("Paste", "粘贴")
    static let pasteAndMatchStyle = LocalizedText("Paste and Match Style", "粘贴并匹配样式")
    static let selectAll = LocalizedText("Select All", "全选")
    static let windowMenu = LocalizedText("Window", "窗口")
    static let minimize = LocalizedText("Minimize", "最小化")
    static let closeWindow = LocalizedText("Close", "关闭")

    // Status-item menu
    static let polishSelection = LocalizedText("Polish Selection…", "润色所选文字…")
    static let polishAndReplace = LocalizedText("Polish and Replace Now", "润色并直接替换")
    static let undoLastReplacement = LocalizedText("Undo Last Replacement", "撤销上次替换")
    static let copyLastResult = LocalizedText("Copy Last Polished Text", "拷贝上次润色结果")
    static let showSelectionButton = LocalizedText("Show Selection Button", "显示悬浮按钮")
    static let statusItemTooltip = LocalizedText("PolishPop — select text, then click the sparkle", "PolishPop — 选中文字后点击闪光按钮")

    static let toneMenu = LocalizedText("Tone", "语气")
    static let purposeMenu = LocalizedText("Use Case", "用途")

    // Floating button
    static func polishTooltip(_ shortcut: String) -> LocalizedText {
        LocalizedText("Polish selection (\(shortcut))", "润色所选文字（\(shortcut)）")
    }

    static let workingTooltip = LocalizedText("Polishing…", "正在润色…")
    static let successTooltip = LocalizedText("Draft ready", "润色完成")
    static let buttonAccessibilityLabel = LocalizedText("Polish the selected text", "润色选中的文字")
    static let dismissButton = LocalizedText("Dismiss", "关闭")

    // Toasts
    static let appliedToast = LocalizedText("Replaced the original text.", "已替换原文。")
    static let undoAvailableToast = LocalizedText("Undo", "撤销")
    static let undoneToast = LocalizedText("Restored the original text.", "已还原原文。")
    static let copiedToast = LocalizedText("Copied to the clipboard.", "已复制到剪贴板。")
    static let workingToast = LocalizedText("Polishing the selection…", "正在润色…")
    static let openSettings = LocalizedText("Open Settings", "打开设置")
    static let noUndoAvailable = LocalizedText("There is nothing to undo.", "没有可撤销的替换。")
    static let undoUnavailable = LocalizedText(
        "The text has changed since PolishPop replaced it. Your original wording is on the clipboard.",
        "替换之后文字已被改动。原文已复制到剪贴板。"
    )
    static let noResultYet = LocalizedText("No polished text is available yet.", "还没有润色结果。")
}
