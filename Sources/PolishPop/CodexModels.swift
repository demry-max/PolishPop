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

    var errorDescription: String? {
        switch self {
        case .cliNotFound:
            "Codex CLI was not found. Install or update Codex before signing in."
        case .cliIntegrityFailed:
            "The installed Codex CLI could not be verified as an OpenAI-signed application."
        case .cliVersionUnsupported(let version):
            "Codex CLI 0.147.0 or later is required. Installed version: \(version)."
        case .defaultKeychainUnavailable:
            "Your macOS login keychain is unavailable, so Codex cannot save the OAuth credentials."
        case .processLaunchFailed:
            "PolishPop could not start the local Codex service."
        case .processTerminated:
            "The local Codex service stopped unexpectedly."
        case .malformedResponse:
            "The local Codex service returned an unreadable response."
        case .rpc(_, let message):
            "Codex could not complete the request: \(message)"
        case .requestTimedOut:
            "The local Codex service did not respond in time."
        case .notAuthenticated:
            "Sign in with ChatGPT in PolishPop Settings first."
        case .loginFailed(let message):
            "ChatGPT sign-in failed: \(message)"
        case .generationFailed(let message):
            "Codex could not polish the text: \(message)"
        case .emptyOutput:
            "Codex completed without returning polished text."
        case .cancelled:
            "The Codex rewrite was cancelled."
        }
    }
}
