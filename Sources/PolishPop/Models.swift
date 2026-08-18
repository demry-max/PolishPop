import AppKit
@preconcurrency import ApplicationServices

enum PolishTone: String, CaseIterable, Identifiable {
    case natural
    case professional
    case friendly
    case concise
    case executive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .natural: "Natural"
        case .professional: "Professional"
        case .friendly: "Friendly"
        case .concise: "Concise"
        case .executive: "Executive"
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

enum PolishPurpose: String, CaseIterable, Identifiable {
    case smart
    case email
    case chat
    case social
    case businessUpdate
    case announcement

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smart: "Smart / Auto"
        case .email: "Email"
        case .chat: "Chat message"
        case .social: "Social post / 朋友圈"
        case .businessUpdate: "Business update"
        case .announcement: "Announcement"
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

struct SelectionSnapshot {
    let text: String
    let element: AXUIElement
    let targetPID: pid_t
    let selectedRange: CFRange
    let targetApplication: NSRunningApplication?
    let capturedAt: Date

    init(
        text: String,
        element: AXUIElement,
        targetPID: pid_t,
        selectedRange: CFRange,
        targetApplication: NSRunningApplication?,
        capturedAt: Date = Date()
    ) {
        self.text = text
        self.element = element
        self.targetPID = targetPID
        self.selectedRange = selectedRange
        self.targetApplication = targetApplication
        self.capturedAt = capturedAt
    }
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

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionMissing:
            "Accessibility permission is required to read and replace selected text."
        case .noSelection:
            "Select some editable text first."
        case .protectedTextField:
            "PolishPop never reads passwords or other protected text fields."
        case .selectionChanged:
            "The selected text changed before the rewrite was ready. Please try again."
        case .selectionTooLong(let limit):
            "The selection is too long. Please select fewer than \(limit.formatted()) characters."
        case .replacementFailed:
            "PolishPop could not replace the selection. The polished text is available from the menu-bar item."
        }
    }
}
