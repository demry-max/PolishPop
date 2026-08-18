import AppKit
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    enum AccountState: Equatable {
        case starting
        case signedOut
        case authenticating
        case signedIn(CodexAccount)
        case unavailable(LocalizedText)
    }

    @Published var accountState: AccountState = .starting
    @Published var model = Preferences.model
    @Published var availableModels: [String] = []
    @Published var defaultModelName: String?
    @Published var isLoadingModels = false
    @Published var tone = Preferences.tone
    @Published var purpose = Preferences.purpose
    @Published var language = Preferences.language
    @Published var showSelectionButton = Preferences.showSelectionButton
    @Published var hideDockIcon = Preferences.hideDockIcon
    @Published var quickReplaceEnabled = Preferences.quickReplaceEnabled
    @Published var polishShortcut = Preferences.polishShortcut
    @Published var quickShortcut = Preferences.quickShortcut
    @Published var launchAtLogin = LoginItem.isEnabled
    @Published var accessibilityGranted = false
    @Published var codexAvailable = CodexAppServerClient.findCodexExecutable() != nil
    @Published var statusMessage: LocalizedText?

    /// Applied the moment a control changes; there is no Save button to forget to press.
    var onPreferencesChanged: ((PreferenceChange) -> Void)?

    enum PreferenceChange {
        case selectionButton
        case dockIcon
        case shortcuts
        case language
    }

    private let client: CodexAppServerClient
    private let accessibility: AccessibilityService
    private var currentLoginId: String?
    private var accountTask: Task<Void, Never>?
    private var modelsTask: Task<Void, Never>?
    private var permissionPollTask: Task<Void, Never>?
    private var accountOperationGeneration = 0

    init(client: CodexAppServerClient, accessibility: AccessibilityService) {
        self.client = client
        self.accessibility = accessibility
        accessibilityGranted = accessibility.isTrusted
    }

    deinit {
        accountTask?.cancel()
        modelsTask?.cancel()
        permissionPollTask?.cancel()
    }

    var setupStepsRemaining: Int {
        var remaining = 0
        if !codexAvailable { remaining += 1 }
        if case .signedIn = accountState {} else { remaining += 1 }
        if !accessibilityGranted { remaining += 1 }
        return remaining
    }

    var isSignedIn: Bool {
        if case .signedIn = accountState { return true }
        return false
    }

    // MARK: - Lifecycle

    func windowDidAppear() {
        accessibilityGranted = accessibility.isTrusted
        codexAvailable = CodexAppServerClient.findCodexExecutable() != nil
        launchAtLogin = LoginItem.isEnabled
        refreshAccount()
        startPermissionPolling()
    }

    func windowDidDisappear() {
        permissionPollTask?.cancel()
        permissionPollTask = nil
        if setupStepsRemaining == 0 {
            Preferences.hasCompletedSetup = true
        }
    }

    /// Accessibility is granted in System Settings, not in PolishPop, so the app watches for the
    /// change instead of asking the user to relaunch.
    private func startPermissionPolling() {
        permissionPollTask?.cancel()
        permissionPollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                guard let self, !Task.isCancelled else { return }
                let granted = accessibility.isTrusted
                if granted != accessibilityGranted {
                    accessibilityGranted = granted
                }
                let codex = CodexAppServerClient.findCodexExecutable() != nil
                if codex != codexAvailable {
                    codexAvailable = codex
                }
            }
        }
    }

    // MARK: - Account

    func refreshAccount() {
        accountTask?.cancel()
        accountOperationGeneration += 1
        let generation = accountOperationGeneration
        accountTask = Task { [weak self] in
            guard let self else { return }
            accountState = .starting
            do {
                let account = try await client.account()
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                accountState = account.map { .signedIn($0) } ?? .signedOut
                if account != nil { loadModels() }
            } catch {
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                accountState = .unavailable(message(for: error))
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
            statusMessage = SettingsStrings.startingSignIn
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
                statusMessage = SettingsStrings.finishInBrowser
                let account = try await client.waitForLogin(session.loginId)
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                currentLoginId = nil
                accountState = .signedIn(account)
                statusMessage = SettingsStrings.connected
                loadModels()
            } catch is CancellationError {
                guard generation == accountOperationGeneration else { return }
                accountState = .signedOut
            } catch {
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                currentLoginId = nil
                accountState = .unavailable(message(for: error))
                statusMessage = message(for: error)
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
        statusMessage = SettingsStrings.signInCancelled
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
                availableModels = []
                statusMessage = SettingsStrings.signedOut
            } catch {
                guard generation == accountOperationGeneration, !Task.isCancelled else { return }
                statusMessage = message(for: error)
            }
        }
    }

    func loadModels() {
        guard availableModels.isEmpty, !isLoadingModels else { return }
        modelsTask?.cancel()
        isLoadingModels = true
        modelsTask = Task { [weak self] in
            guard let self else { return }
            defer { isLoadingModels = false }
            guard let result = try? await client.availableModels(), !Task.isCancelled else { return }
            availableModels = result.models
            defaultModelName = result.defaultModel
        }
    }

    // MARK: - Preference writes

    func updateModel(_ value: String) {
        model = value
        Preferences.model = value
    }

    func updateTone(_ value: PolishTone) {
        tone = value
        Preferences.tone = value
    }

    func updatePurpose(_ value: PolishPurpose) {
        purpose = value
        Preferences.purpose = value
    }

    func updateLanguage(_ value: AppLanguage) {
        language = value
        Preferences.language = value
        Localization.shared.update(to: value)
        onPreferencesChanged?(.language)
    }

    func updateShowSelectionButton(_ value: Bool) {
        showSelectionButton = value
        Preferences.showSelectionButton = value
        onPreferencesChanged?(.selectionButton)
    }

    func updateHideDockIcon(_ value: Bool) {
        hideDockIcon = value
        Preferences.hideDockIcon = value
        onPreferencesChanged?(.dockIcon)
    }

    func updateQuickReplaceEnabled(_ value: Bool) {
        quickReplaceEnabled = value
        Preferences.quickReplaceEnabled = value
        onPreferencesChanged?(.shortcuts)
    }

    func updatePolishShortcut(_ value: ShortcutDefinition?) {
        polishShortcut = value
        Preferences.polishShortcut = value
        onPreferencesChanged?(.shortcuts)
    }

    func updateQuickShortcut(_ value: ShortcutDefinition?) {
        quickShortcut = value
        Preferences.quickShortcut = value
        onPreferencesChanged?(.shortcuts)
    }

    func updateLaunchAtLogin(_ value: Bool) {
        do {
            try LoginItem.setEnabled(value)
            launchAtLogin = LoginItem.isEnabled
            if LoginItem.requiresApproval {
                statusMessage = SettingsStrings.launchAtLoginFailed
            }
        } catch {
            launchAtLogin = LoginItem.isEnabled
            statusMessage = SettingsStrings.launchAtLoginFailed
        }
    }

    func reportShortcutUnavailable() {
        statusMessage = SettingsStrings.shortcutUnavailable
    }

    // MARK: - Permissions and dependencies

    func requestAccessibility() {
        _ = accessibility.requestPermission()
        accessibilityGranted = accessibility.isTrusted
        if !accessibilityGranted {
            openAccessibilitySettings()
        }
    }

    func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    func copyCodexInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("npm install -g @openai/codex", forType: .string)
        statusMessage = SettingsStrings.installCommandCopied
    }

    func recheckCodex() {
        codexAvailable = CodexAppServerClient.findCodexExecutable() != nil
        if codexAvailable {
            refreshAccount()
        }
    }

    private func message(for error: Error) -> LocalizedText {
        if let error = error as? CodexClientError { return error.message }
        if let error = error as? PolishPopError { return error.message }
        return ErrorStrings.unknown
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    let viewModel: SettingsViewModel

    init(client: CodexAppServerClient, accessibility: AccessibilityService) {
        viewModel = SettingsViewModel(client: client, accessibility: accessibility)
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 680),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        window.title = SettingsStrings.windowTitle.current
        let hosting = NSHostingView(rootView: SettingsView(viewModel: viewModel))
        // Without this the hosting view publishes its own ideal size as the window's size
        // constraints, and the settings window collapses to a fraction of its content.
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        window.contentView = hosting
        window.setContentSize(NSSize(width: 600, height: 680))
        window.contentMinSize = NSSize(width: 560, height: 460)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
    }

    func refreshLanguage() {
        window.title = SettingsStrings.windowTitle.current
    }

    func show() {
        viewModel.windowDidAppear()
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        viewModel.windowDidDisappear()
    }
}
