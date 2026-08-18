import Foundation

/// User-facing wording for every error the app can surface.
///
/// Kept apart from the error types themselves so `PolishPopError` and `CodexClientError` stay
/// plain value types and every message has both languages in one place.
enum ErrorStrings {
    // PolishPopError
    static let accessibilityPermissionMissing = LocalizedText(
        "Accessibility permission is required to read and replace selected text.",
        "需要辅助功能权限才能读取和替换选中的文字。"
    )
    static let noSelection = LocalizedText(
        "Select some text first.",
        "请先选中一段文字。"
    )
    static let protectedTextField = LocalizedText(
        "PolishPop never reads passwords or other protected text fields.",
        "PolishPop 不会读取密码等受保护的输入框。"
    )
    static let selectionChanged = LocalizedText(
        "The selected text changed before the rewrite was ready. Please try again.",
        "润色完成前所选文字已发生变化，请重试。"
    )
    static let replacementFailed = LocalizedText(
        "PolishPop could not replace the selection.",
        "PolishPop 无法替换选中的文字。"
    )

    static func selectionTooLong(limit: Int) -> LocalizedText {
        LocalizedText(
            "The selection is too long. Please select fewer than \(limit.formatted()) characters.",
            "选中的文字太长，请少于 \(limit.formatted()) 个字符。"
        )
    }

    // CodexClientError
    static let cliNotFound = LocalizedText(
        "Codex CLI was not found. Install or update Codex before signing in.",
        "未找到 Codex 命令行工具，请先安装或更新 Codex。"
    )
    static let cliIntegrityFailed = LocalizedText(
        "The installed Codex CLI could not be verified as an OpenAI-signed application.",
        "已安装的 Codex 命令行工具未通过 OpenAI 签名校验。"
    )
    static let defaultKeychainUnavailable = LocalizedText(
        "Your macOS login keychain is unavailable, so Codex cannot save the OAuth credentials.",
        "macOS 登录钥匙串不可用，Codex 无法保存 OAuth 凭据。"
    )
    static let processLaunchFailed = LocalizedText(
        "PolishPop could not start the local Codex service.",
        "PolishPop 无法启动本地 Codex 服务。"
    )
    static let processTerminated = LocalizedText(
        "The local Codex service stopped unexpectedly.",
        "本地 Codex 服务意外停止。"
    )
    static let malformedResponse = LocalizedText(
        "The local Codex service returned an unreadable response.",
        "本地 Codex 服务返回了无法解析的响应。"
    )
    static let requestTimedOut = LocalizedText(
        "The local Codex service did not respond in time.",
        "本地 Codex 服务响应超时。"
    )
    static let notAuthenticated = LocalizedText(
        "Sign in with ChatGPT in PolishPop Settings first.",
        "请先在 PolishPop 设置中使用 ChatGPT 登录。"
    )
    static let emptyOutput = LocalizedText(
        "Codex completed without returning polished text.",
        "Codex 未返回润色结果。"
    )
    static let cancelled = LocalizedText(
        "The Codex rewrite was cancelled.",
        "已取消本次润色。"
    )
    static let unknown = LocalizedText(
        "PolishPop could not complete the rewrite. Please try again.",
        "润色未能完成，请重试。"
    )

    static func cliVersionUnsupported(_ version: String) -> LocalizedText {
        LocalizedText(
            "Codex CLI 0.147.0 or later is required. Installed version: \(version).",
            "需要 Codex CLI 0.147.0 或更高版本，当前版本：\(version)。"
        )
    }

    static func rpc(_ message: String) -> LocalizedText {
        LocalizedText(
            "Codex could not complete the request: \(message)",
            "Codex 无法完成请求：\(message)"
        )
    }

    static func loginFailed(_ message: String) -> LocalizedText {
        LocalizedText(
            "ChatGPT sign-in failed: \(message)",
            "ChatGPT 登录失败：\(message)"
        )
    }

    static func generationFailed(_ message: String) -> LocalizedText {
        LocalizedText(
            "Codex could not polish the text: \(message)",
            "Codex 无法润色这段文字：\(message)"
        )
    }
}
