import AppKit
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    enum AccountState: Equatable {
        case starting
        case signedOut
        case authenticating
        case signedIn(CodexAccount)
        case unavailable(String)
    }

    @Published var accountState: AccountState = .starting
    @Published var model = Preferences.model
    @Published var tone = Preferences.tone
    @Published var purpose = Preferences.purpose
    @Published var accessibilityGranted = false
    @Published var statusMessage = ""

    private let client: CodexAppServerClient
    private let accessibility: AccessibilityService
    private var currentLoginId: String?
    private var accountTask: Task<Void, Never>?
    private var accountOperationGeneration = 0

    init(client: CodexAppServerClient, accessibility: AccessibilityService) {
        self.client = client
        self.accessibility = accessibility
        accessibilityGranted = accessibility.isTrusted
        refreshAccount()
    }

    deinit {
        accountTask?.cancel()
    }

    func refreshAccount() {
        accountTask?.cancel()
        accountOperationGeneration += 1
        let generation = accountOperationGeneration
        accountTask = Task { [weak self] in
            guard let self else { return }
            accountState = .starting
            do {
                if let account = try await client.account() {
                    guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                    accountState = .signedIn(account)
                } else {
                    guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                    accountState = .signedOut
                }
            } catch {
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                accountState = .unavailable(safeMessage(for: error))
            }
        }
    }

    func signIn() {
        accountTask?.cancel()
        accountOperationGeneration += 1
        let generation = accountOperationGeneration
        accountTask = Task { [weak self] in
            guard let self else { return }
            accountState = .authenticating
            statusMessage = "Starting secure ChatGPT sign-in…"
            do {
                let session = try await client.beginChatGPTLogin()
                guard generation == accountOperationGeneration, !Task.isCancelled else {
                    await client.cancelLogin(session.loginId)
                    return
                }
                currentLoginId = session.loginId
                guard NSWorkspace.shared.open(session.authorizationURL) else {
                    await client.cancelLogin(session.loginId)
                    throw CodexClientError.loginFailed("The sign-in page could not be opened.")
                }
                statusMessage = "Complete sign-in in your browser. PolishPop will update automatically."
                let account = try await client.waitForLogin(session.loginId)
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                currentLoginId = nil
                accountState = .signedIn(account)
                statusMessage = "Connected through Codex-managed ChatGPT OAuth."
            } catch is CancellationError {
                guard generation == accountOperationGeneration else { return }
                accountState = .signedOut
            } catch {
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                currentLoginId = nil
                accountState = .unavailable(safeMessage(for: error))
                statusMessage = safeMessage(for: error)
            }
        }
    }

    func cancelSignIn() {
        accountOperationGeneration += 1
        accountTask?.cancel()
        if let loginId = currentLoginId {
            Task { await client.cancelLogin(loginId) }
        }
        currentLoginId = nil
        accountState = .signedOut
        statusMessage = "Sign-in cancelled."
    }

    func signOut() {
        accountTask?.cancel()
        accountOperationGeneration += 1
        let generation = accountOperationGeneration
        accountTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await client.logout()
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                accountState = .signedOut
                statusMessage = "PolishPop signed out of Codex. Your browser ChatGPT session was not changed."
            } catch {
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                statusMessage = safeMessage(for: error)
            }
        }
    }

    func save() {
        Preferences.model = model.trimmingCharacters(in: .whitespacesAndNewlines)
        Preferences.tone = tone
        Preferences.purpose = purpose
        statusMessage = "Writing settings saved."
    }

    func requestAccessibility() {
        _ = accessibility.requestPermission()
        accessibilityGranted = accessibility.isTrusted
        if !accessibilityGranted {
            statusMessage = "Enable PolishPop in System Settings → Privacy & Security → Accessibility, then reopen the app."
        }
    }

    func refreshAccessibility() {
        accessibilityGranted = accessibility.isTrusted
    }

    private func safeMessage(for error: Error) -> String {
        if let error = error as? CodexClientError {
            return error.localizedDescription
        }
        return "PolishPop could not communicate with the local Codex service."
    }
}

@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let viewModel: SettingsViewModel

    init(client: CodexAppServerClient, accessibility: AccessibilityService) {
        viewModel = SettingsViewModel(client: client, accessibility: accessibility)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 570, height: 650),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PolishPop Settings"
        window.contentView = NSHostingView(rootView: SettingsView(viewModel: viewModel))
        window.isReleasedWhenClosed = false
        window.center()
    }

    func show() {
        viewModel.refreshAccessibility()
        viewModel.refreshAccount()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

private struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                Divider()
                accountSection
                Divider()
                writingSection
                Divider()
                permissionSection
                privacyNotice
                saveRow
            }
            .padding(28)
        }
        .frame(minWidth: 530, minHeight: 610)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 29, weight: .semibold))
                .foregroundStyle(.purple)
            VStack(alignment: .leading, spacing: 3) {
                Text("PolishPop")
                    .font(.title2.bold())
                Text("Select text anywhere, then click the sparkle or press ⌥⌘P.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("ChatGPT subscription", systemImage: "person.crop.circle.badge.checkmark")
                .font(.headline)

            switch viewModel.accountState {
            case .starting:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Checking Codex sign-in…")
                }

            case .signedOut:
                Button("Sign in with ChatGPT") {
                    viewModel.signIn()
                }
                .buttonStyle(.borderedProminent)

            case .authenticating:
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for browser sign-in…")
                    Spacer()
                    Button("Cancel") { viewModel.cancelSignIn() }
                }

            case .signedIn(let account):
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName).fontWeight(.medium)
                        Text("\(account.planDisplayName) plan · Codex allowance")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Sign Out") { viewModel.signOut() }
                }

            case .unavailable(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    HStack {
                        Button("Try Again") { viewModel.refreshAccount() }
                        Button("Sign in with ChatGPT") { viewModel.signIn() }
                    }
                }
            }

            Text("PolishPop uses the official Codex App Server OAuth flow and the Codex allowance or credits included with an eligible ChatGPT plan. It does not use API keys or separate API billing.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text("PolishPop uses a dedicated Codex home for its configuration and ephemeral sessions. Codex manages OAuth credentials in the macOS keyring. It does not access custom GPTs, ChatGPT chats, history, or memory.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var writingSection: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label("Writing defaults", systemImage: "text.badge.checkmark")
                .font(.headline)

            HStack {
                Text("Use case").frame(width: 110, alignment: .leading)
                Picker("Use case", selection: $viewModel.purpose) {
                    ForEach(PolishPurpose.allCases) { purpose in
                        Text(purpose.title).tag(purpose)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 250)
            }

            HStack {
                Text("Tone").frame(width: 110, alignment: .leading)
                Picker("Tone", selection: $viewModel.tone) {
                    ForEach(PolishTone.allCases) { tone in
                        Text(tone.title).tag(tone)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            HStack {
                Text("Preferred model").frame(width: 110, alignment: .leading)
                TextField("gpt-5.6-luna", text: $viewModel.model)
                    .textFieldStyle(.roundedBorder)
            }
            Text("If the preferred model is unavailable on your plan, PolishPop uses the plan's default Codex model.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Label("A review window is always shown before anything is replaced.", systemImage: "checkmark.seal.fill")
                .font(.caption)
                .foregroundStyle(.green)
            Text("When direct replacement is unavailable, Apply uses a temporary paste fallback and then restores your previous clipboard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("Accessibility", systemImage: viewModel.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                .font(.headline)
                .foregroundStyle(viewModel.accessibilityGranted ? .green : .orange)

            Text(viewModel.accessibilityGranted
                 ? "Permission granted. PolishPop can read and replace only the text you explicitly select."
                 : "Permission is required for the floating button and in-place replacement.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !viewModel.accessibilityGranted {
                Button("Request Accessibility Permission") {
                    viewModel.requestAccessibility()
                }
            }
        }
    }

    private var privacyNotice: some View {
        Label {
            Text("Selected text is sent to OpenAI through Codex only after you click the sparkle or use the shortcut. Ephemeral threads and disabled transcript history are used; PolishPop does not add selections to its own storage. ChatGPT/Codex data controls and usage limits still apply. Never select passwords, banking details, or confidential records.")
                .font(.caption)
        } icon: {
            Image(systemName: "hand.raised.fill").foregroundStyle(.blue)
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var saveRow: some View {
        HStack {
            Text(viewModel.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Quit PolishPop") {
                NSApplication.shared.terminate(nil)
            }
            Button("Save") { viewModel.save() }
                .keyboardShortcut(.defaultAction)
        }
    }
}
