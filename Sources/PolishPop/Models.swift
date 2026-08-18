import AppKit
@preconcurrency import ApplicationServices

enum PolishTone: String, CaseIterable, Identifiable, Sendable {
    case natural
    case professional
    case friendly
    case concise
    case executive

    var id: String { rawValue }

    var title: LocalizedText {
        switch self {
        case .natural: LocalizedText("Natural", "自然")
        case .professional: LocalizedText("Professional", "专业")
        case .friendly: LocalizedText("Friendly", "亲切")
        case .concise: LocalizedText("Concise", "精简")
        case .executive: LocalizedText("Executive", "决断")
        }
    }

    var symbolName: String {
        switch self {
        case .natural: "leaf"
        case .professional: "briefcase"
        case .friendly: "hand.wave"
        case .concise: "scissors"
        case .executive: "chart.line.uptrend.xyaxis"
        }
    }

    var instruction: String {
        switch self {
        case .natural:
            "Make it clear, natural, and grammatically correct."
        case .professional:
            "Use a polished, courteous, professional business tone."
        case .friendly:
            "Use a warm, approachable, and respectful tone."
        case .concise:
            "Make it concise and direct while retaining every important fact."
        case .executive:
            "Use a confident executive tone with crisp, decisive wording."
        }
    }
}

enum PolishPurpose: String, CaseIterable, Identifiable, Sendable {
    case smart
    case email
    case chat
    case social
    case businessUpdate
    case announcement

    var id: String { rawValue }

    var title: LocalizedText {
        switch self {
        case .smart: LocalizedText("Smart / Auto", "智能识别")
        case .email: LocalizedText("Email", "邮件")
        case .chat: LocalizedText("Chat message", "即时消息")
        case .social: LocalizedText("Social post", "朋友圈 / 社交动态")
        case .businessUpdate: LocalizedText("Business update", "工作汇报")
        case .announcement: LocalizedText("Announcement", "通知公告")
        }
    }

    var symbolName: String {
        switch self {
        case .smart: "wand.and.stars"
        case .email: "envelope"
        case .chat: "bubble.left.and.bubble.right"
        case .social: "person.2"
        case .businessUpdate: "chart.bar.doc.horizontal"
        case .announcement: "megaphone"
        }
    }

    var instruction: String {
        switch self {
        case .smart:
            "Infer the writing format from the source and preserve its intended channel."
        case .email:
            "Polish it as an email. Keep any existing greeting and signature, use clear paragraphs, and make requests and deadlines easy to understand. Do not invent a recipient, subject, or sign-off."
        case .chat:
            "Polish it as a natural chat message. Keep it conversational, compact, and easy to reply to. Avoid unnecessary email-style greetings and sign-offs."
        case .social:
            "Polish it as an engaging social post suitable for WeChat Moments. Use natural rhythm and readable paragraph breaks. Keep emoji and hashtags restrained, and do not add claims or personal details."
        case .businessUpdate:
            "Polish it as a concise business update. Make the status, key facts, owner, deadline, blocker, and next action clear when those details already exist."
        case .announcement:
            "Polish it as a clear announcement. Lead with the main point, organize practical details, and make any required action and deadline explicit without inventing information."
        }
    }
}

struct SelectionSnapshot: @unchecked Sendable {
    let text: String
    let element: AXUIElement
    let targetPID: pid_t
    let selectedRange: CFRange
    let targetApplication: NSRunningApplication?
    /// False for read-only text such as a rendered web page, where the draft can only be copied.
    let isReplaceable: Bool
    let capturedAt: Date

    init(
        text: String,
        element: AXUIElement,
        targetPID: pid_t,
        selectedRange: CFRange,
        targetApplication: NSRunningApplication?,
        isReplaceable: Bool,
        capturedAt: Date = Date()
    ) {
        self.text = text
        self.element = element
        self.targetPID = targetPID
        self.selectedRange = selectedRange
        self.targetApplication = targetApplication
        self.isReplaceable = isReplaceable
        self.capturedAt = capturedAt
    }

    var targetApplicationName: String? {
        targetApplication?.localizedName
    }

    /// Same field, same range, same text — used to tell a fresh probe from a repeat of one
    /// already on screen so the sparkle does not flicker.
    func matchesLocation(of other: SelectionSnapshot) -> Bool {
        targetPID == other.targetPID
            && CFEqual(element, other.element)
            && selectedRange.location == other.selectedRange.location
            && selectedRange.length == other.selectedRange.length
            && text == other.text
    }
}

/// What PolishPop wrote, where it wrote it, and what was there before — everything undo needs.
struct ReplacementRecord: @unchecked Sendable {
    let snapshot: SelectionSnapshot
    let original: String
    let applied: String
}

enum FloatingPhase: Equatable {
    case ready
    case working
    case success
    case failure
}

enum PolishPopError: LocalizedError, Equatable {
    case accessibilityPermissionMissing
    case noSelection
    case protectedTextField
    case selectionChanged
    case selectionTooLong(limit: Int)
    case replacementFailed

    var message: LocalizedText {
        switch self {
        case .accessibilityPermissionMissing: ErrorStrings.accessibilityPermissionMissing
        case .noSelection: ErrorStrings.noSelection
        case .protectedTextField: ErrorStrings.protectedTextField
        case .selectionChanged: ErrorStrings.selectionChanged
        case .selectionTooLong(let limit): ErrorStrings.selectionTooLong(limit: limit)
        case .replacementFailed: ErrorStrings.replacementFailed
        }
    }

    var errorDescription: String? { message.en }
}
