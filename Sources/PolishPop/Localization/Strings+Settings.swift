import Foundation

/// Strings for the settings window.
enum SettingsStrings {
    static let windowTitle = LocalizedText("PolishPop Settings", "PolishPop 设置")
    static let tagline = LocalizedText(
        "Select text anywhere, then click the sparkle or press the shortcut.",
        "在任何应用里选中文字，点击闪光按钮或按快捷键。"
    )

    static func version(_ value: String) -> LocalizedText {
        LocalizedText("Version \(value)", "版本 \(value)")
    }

    // Tabs
    static let generalTab = LocalizedText("General", "通用")
    static let writingTab = LocalizedText("Writing", "写作")
    static let accountTab = LocalizedText("Account", "账户")

    // Setup checklist
    static func setupProgress(done: Int, total: Int) -> LocalizedText {
        LocalizedText("Step \(done) of \(total) complete", "已完成 \(done)/\(total) 步")
    }

    // Account
    static let accountHeading = LocalizedText("ChatGPT subscription", "ChatGPT 订阅")
    static let checkingSignIn = LocalizedText("Checking Codex sign-in…", "正在检查 Codex 登录状态…")
    static let signIn = LocalizedText("Sign in with ChatGPT", "使用 ChatGPT 登录")
    static let waitingForBrowser = LocalizedText("Waiting for browser sign-in…", "等待浏览器完成登录…")
    static let cancel = LocalizedText("Cancel", "取消")
    static let signOut = LocalizedText("Sign Out", "退出登录")
    static let tryAgain = LocalizedText("Try Again", "重试")
    static let startingSignIn = LocalizedText("Starting secure ChatGPT sign-in…", "正在启动安全登录…")
    static let finishInBrowser = LocalizedText(
        "Complete sign-in in your browser. PolishPop will update automatically.",
        "请在浏览器中完成登录，PolishPop 会自动更新状态。"
    )
    static let signInCancelled = LocalizedText("Sign-in cancelled.", "已取消登录。")
    static let connected = LocalizedText("Connected through Codex-managed ChatGPT OAuth.", "已通过 Codex 官方 OAuth 连接。")
    static let signedOut = LocalizedText(
        "PolishPop signed out of Codex. Your browser ChatGPT session was not changed.",
        "PolishPop 已退出 Codex 登录，浏览器中的 ChatGPT 登录状态不受影响。"
    )

    static func planLine(_ plan: String) -> LocalizedText {
        LocalizedText("\(plan) plan · Codex allowance", "\(plan) 套餐 · Codex 额度")
    }

    static let accountNote = LocalizedText(
        "PolishPop uses the official Codex App Server OAuth flow and the Codex allowance or credits included with an eligible ChatGPT plan. It does not use API keys or separate API billing.",
        "PolishPop 使用 Codex App Server 官方 OAuth 流程，消耗符合条件的 ChatGPT 套餐所含的 Codex 额度，不使用 API Key，也不产生单独的 API 账单。"
    )
    static let isolationNote = LocalizedText(
        "PolishPop uses a dedicated Codex home for its configuration and ephemeral sessions. Codex manages OAuth credentials in the macOS keyring. It does not access custom GPTs, ChatGPT chats, history, or memory.",
        "PolishPop 使用独立的 Codex 配置目录与一次性会话；OAuth 凭据由 Codex 保存在 macOS 钥匙串中。它不会访问自定义 GPT、ChatGPT 对话、历史或记忆。"
    )

    // Codex CLI
    static let codexHeading = LocalizedText("Codex CLI", "Codex 命令行工具")
    static let codexFound = LocalizedText("Detected and signature-verified.", "已检测到并通过签名校验。")
    static let codexMissing = LocalizedText(
        "PolishPop needs the OpenAI Codex CLI 0.147.0 or later installed on this Mac.",
        "PolishPop 需要本机安装 OpenAI Codex CLI 0.147.0 或更高版本。"
    )
    static let copyInstallCommand = LocalizedText("Copy Install Command", "拷贝安装命令")
    static let recheck = LocalizedText("Check Again", "重新检测")
    static let installCommandCopied = LocalizedText("Install command copied.", "安装命令已复制。")

    // Accessibility
    static let accessibilityHeading = LocalizedText("Accessibility permission", "辅助功能权限")
    static let accessibilityGranted = LocalizedText(
        "Granted. PolishPop can read and replace only the text you explicitly select.",
        "已授权。PolishPop 只会读取和替换你主动选中的文字。"
    )
    static let accessibilityMissing = LocalizedText(
        "Required so PolishPop can see your selection and put the polished text back.",
        "需要此权限，PolishPop 才能读取选中文字并把润色结果写回。"
    )
    static let requestAccessibility = LocalizedText("Grant Permission…", "授予权限…")
    static let openAccessibilitySettings = LocalizedText("Open System Settings", "打开系统设置")
    static let accessibilityInstructions = LocalizedText(
        "Enable PolishPop under Privacy & Security → Accessibility. PolishPop detects the change automatically.",
        "请在「隐私与安全性 → 辅助功能」中开启 PolishPop，PolishPop 会自动检测到。"
    )

    // Shortcuts
    static let shortcutsHeading = LocalizedText("Shortcuts", "快捷键")
    static let polishShortcut = LocalizedText("Polish with review", "润色并校对")
    static let quickShortcut = LocalizedText("Polish and replace instantly", "润色并直接替换")
    static let recordShortcut = LocalizedText("Click to record", "点击录制")
    static let quickShortcutKey = LocalizedText("Instant-replace shortcut", "直接替换快捷键")
    static let recordingShortcut = LocalizedText("Press keys…", "请按快捷键…")
    static let clearShortcut = LocalizedText("Clear", "清除")
    static let shortcutUnavailable = LocalizedText(
        "That shortcut is already taken by another app.",
        "该快捷键已被其他应用占用。"
    )
    static let quickModeWarning = LocalizedText(
        "Instant replace skips the review panel. The original is kept so you can undo from the menu bar.",
        "「直接替换」会跳过校对面板。原文会被保留，可从菜单栏撤销。"
    )

    // Behaviour
    static let behaviourHeading = LocalizedText("Behaviour", "行为")
    static let autoButton = LocalizedText("Show the sparkle button when I select text", "选中文字时显示悬浮闪光按钮")
    static let autoButtonNote = LocalizedText(
        "Turn this off to use only the keyboard shortcut and the menu-bar item.",
        "关闭后只能通过快捷键和菜单栏使用。"
    )
    static let launchAtLogin = LocalizedText("Open PolishPop at login", "开机自动启动")
    static let hideDockIcon = LocalizedText("Hide the Dock icon (menu bar only)", "隐藏程序坞图标（仅菜单栏）")
    static let language = LocalizedText("Language", "界面语言")
    static let launchAtLoginFailed = LocalizedText(
        "macOS refused the login-item change. Approve PolishPop in System Settings → General → Login Items.",
        "macOS 拒绝了启动项更改，请在「系统设置 → 通用 → 登录项」中允许 PolishPop。"
    )

    // Writing
    static let writingHeading = LocalizedText("Writing defaults", "写作默认设置")
    static let useCase = LocalizedText("Use case", "用途")
    static let tone = LocalizedText("Tone", "语气")
    static let model = LocalizedText("Model", "模型")
    static let modelLoading = LocalizedText("Loading models…", "正在载入模型…")
    static let modelPlanDefault = LocalizedText("Plan default", "套餐默认")
    static let modelUnavailableNote = LocalizedText(
        "If the chosen model is unavailable on your plan, PolishPop uses the plan's default Codex model.",
        "若所选模型在你的套餐中不可用，PolishPop 会改用套餐默认的 Codex 模型。"
    )
    static let reviewAlwaysNote = LocalizedText(
        "A review panel is shown before anything is replaced, unless you use the instant-replace shortcut.",
        "除非使用「直接替换」快捷键，替换前都会先显示校对面板。"
    )
    static let pasteFallbackNote = LocalizedText(
        "When direct replacement is unavailable, PolishPop pastes the draft and then restores your previous clipboard.",
        "当无法直接写入时，PolishPop 会临时用粘贴方式替换，随后恢复你原本的剪贴板内容。"
    )

    // Privacy
    static let privacyNotice = LocalizedText(
        "Selected text is sent to OpenAI through Codex only after you click the sparkle or use a shortcut. Ephemeral threads and disabled transcript history are used; PolishPop does not add selections to its own storage. ChatGPT/Codex data controls and usage limits still apply. Never select passwords, banking details, or confidential records.",
        "只有在你点击闪光按钮或使用快捷键之后，选中的文字才会通过 Codex 发送给 OpenAI。全程使用一次性会话并关闭了记录留存；PolishPop 不会把选中内容存入自身存储。ChatGPT/Codex 的数据控制与用量限制依然适用。请勿选中密码、银行信息或机密资料。"
    )

    static let quitApp = LocalizedText("Quit PolishPop", "退出 PolishPop")
    static let settingsSavedAutomatically = LocalizedText("Changes are saved automatically.", "更改会自动保存。")
}
