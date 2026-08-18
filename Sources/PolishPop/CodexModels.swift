import Foundation

struct CodexAccount: Sendable, Equatable {
    let email: String?
    let planType: String

    var displayName: String {
        email?.isEmpty == false ? email! : "ChatGPT account"
    }

    var planDisplayName: String {
        planType.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct CodexLoginSession: Sendable, Equatable {
    let loginId: String
    let authorizationURL: URL
}

enum CodexClientError: LocalizedError, Equatable {
    case cliNotFound
    case cliIntegrityFailed
    case cliVersionUnsupported(String)
    case defaultKeychainUnavailable
    case processLaunchFailed(String)
    case processTerminated
    case malformedResponse
    case rpc(code: Int?, message: String)
    case requestTimedOut
    case notAuthenticated
    case loginFailed(String)
    case generationFailed(String)
    case emptyOutput
    case cancelled

    var message: LocalizedText {
        switch self {
        case .cliNotFound: ErrorStrings.cliNotFound
        case .cliIntegrityFailed: ErrorStrings.cliIntegrityFailed
        case .cliVersionUnsupported(let version): ErrorStrings.cliVersionUnsupported(version)
        case .defaultKeychainUnavailable: ErrorStrings.defaultKeychainUnavailable
        case .processLaunchFailed: ErrorStrings.processLaunchFailed
        case .processTerminated: ErrorStrings.processTerminated
        case .malformedResponse: ErrorStrings.malformedResponse
        case .rpc(_, let message): ErrorStrings.rpc(message)
        case .requestTimedOut: ErrorStrings.requestTimedOut
        case .notAuthenticated: ErrorStrings.notAuthenticated
        case .loginFailed(let message): ErrorStrings.loginFailed(message)
        case .generationFailed(let message): ErrorStrings.generationFailed(message)
        case .emptyOutput: ErrorStrings.emptyOutput
        case .cancelled: ErrorStrings.cancelled
        }
    }

    var errorDescription: String? { message.en }

    /// True when the fix is something the user does in Settings rather than by retrying.
    var isSetupProblem: Bool {
        switch self {
        case .cliNotFound, .cliIntegrityFailed, .cliVersionUnsupported,
             .defaultKeychainUnavailable, .notAuthenticated, .loginFailed:
            true
        default:
            false
        }
    }
}
