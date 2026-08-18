import SwiftUI

/// Settings, split into the three things a user comes here for: getting set up, choosing how the
/// rewrite should read, and managing the ChatGPT connection.
///
/// Every control writes its preference immediately — the old Save button meant a user could
/// change a tone, close the window, and silently lose it.
struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel
    @ObservedObject private var localization = Localization.shared

    private enum Tab: String, Hashable {
        case general
        case writing
        case account
    }

    @State private var selectedTab: Tab

    init(viewModel: SettingsViewModel, initialTab: String = Tab.general.rawValue) {
        self.viewModel = viewModel
        _selectedTab = State(initialValue: Tab(rawValue: initialTab) ?? .general)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if viewModel.setupStepsRemaining > 0 {
                setupBanner
            }
            Picker("", selection: $selectedTab) {
                Text(SettingsStrings.generalTab.current).tag(Tab.general)
                Text(SettingsStrings.writingTab.current).tag(Tab.writing)
                Text(SettingsStrings.accountTab.current).tag(Tab.account)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)

            Group {
                switch selectedTab {
                case .general: generalTab
                case .writing: writingTab
                case .account: accountTab
                }
            }
            .frame(maxHeight: .infinity)

            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 560)
    }

    // MARK: - Chrome

    private var header: some View {
        HStack(spacing: 11) {
            Image(systemName: "sparkles")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.purple)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(ShellStrings.appName.current)
                    .font(.title3.bold())
                Text(SettingsStrings.tagline.current)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 12)
    }

    private var setupBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text(
                SettingsStrings.setupProgress(
                    done: 3 - viewModel.setupStepsRemaining,
                    total: 3
                ).current
            )
            .font(.callout)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(.orange.opacity(0.12))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let statusMessage = viewModel.statusMessage {
                Text(statusMessage.current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(SettingsStrings.settingsSavedAutomatically.current)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 12)
            Text(SettingsStrings.version(AppInfo.version).current)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Button(SettingsStrings.quitApp.current) {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - General

    private var generalTab: some View {
        Form {
            accessibilitySection
            shortcutsSection
            behaviourSection
        }
        .formStyle(.grouped)
    }

    private var accessibilitySection: some View {
        Section {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: viewModel.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                    .foregroundStyle(viewModel.accessibilityGranted ? .green : .orange)
                Text(
                    viewModel.accessibilityGranted
                        ? SettingsStrings.accessibilityGranted.current
                        : SettingsStrings.accessibilityMissing.current
                )
                .fixedSize(horizontal: false, vertical: true)
            }

            if !viewModel.accessibilityGranted {
                Text(SettingsStrings.accessibilityInstructions.current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button(SettingsStrings.requestAccessibility.current) {
                        viewModel.requestAccessibility()
                    }
                    .buttonStyle(.borderedProminent)
                    Button(SettingsStrings.openAccessibilitySettings.current) {
                        viewModel.openAccessibilitySettings()
                    }
                }
            }
        } header: {
            Text(SettingsStrings.accessibilityHeading.current)
        }
    }

    private var shortcutsSection: some View {
        Section {
            LabeledContent(SettingsStrings.polishShortcut.current) {
                ShortcutRecorderField(
                    shortcut: Binding(
                        get: { viewModel.polishShortcut },
                        set: { viewModel.updatePolishShortcut($0) }
                    ),
                    placeholder: SettingsStrings.recordShortcut.current,
                    recordingPlaceholder: SettingsStrings.recordingShortcut.current
                )
                .frame(width: 132, height: 22)
            }

            Toggle(SettingsStrings.quickShortcut.current, isOn: Binding(
                get: { viewModel.quickReplaceEnabled },
                set: { viewModel.updateQuickReplaceEnabled($0) }
            ))

            if viewModel.quickReplaceEnabled {
                LabeledContent(SettingsStrings.quickShortcutKey.current) {
                    ShortcutRecorderField(
                        shortcut: Binding(
                            get: { viewModel.quickShortcut },
                            set: { viewModel.updateQuickShortcut($0) }
                        ),
                        placeholder: SettingsStrings.recordShortcut.current,
                        recordingPlaceholder: SettingsStrings.recordingShortcut.current
                    )
                    .frame(width: 132, height: 22)
                }
                Text(SettingsStrings.quickModeWarning.current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } header: {
            Text(SettingsStrings.shortcutsHeading.current)
        }
    }

    private var behaviourSection: some View {
        Section {
            Toggle(isOn: Binding(
                get: { viewModel.showSelectionButton },
                set: { viewModel.updateShowSelectionButton($0) }
            )) {
                Text(SettingsStrings.autoButton.current)
                Text(SettingsStrings.autoButtonNote.current)
            }

            Toggle(SettingsStrings.launchAtLogin.current, isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { viewModel.updateLaunchAtLogin($0) }
            ))

            Toggle(SettingsStrings.hideDockIcon.current, isOn: Binding(
                get: { viewModel.hideDockIcon },
                set: { viewModel.updateHideDockIcon($0) }
            ))

            Picker(SettingsStrings.language.current, selection: Binding(
                get: { viewModel.language },
                set: { viewModel.updateLanguage($0) }
            )) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.menuTitle).tag(language)
                }
            }
        } header: {
            Text(SettingsStrings.behaviourHeading.current)
        }
    }

    // MARK: - Writing

    private var writingTab: some View {
        Form {
            Section {
                Picker(SettingsStrings.useCase.current, selection: Binding(
                    get: { viewModel.purpose },
                    set: { viewModel.updatePurpose($0) }
                )) {
                    ForEach(PolishPurpose.allCases) { purpose in
                        Label(purpose.title.current, systemImage: purpose.symbolName).tag(purpose)
                    }
                }

                Picker(SettingsStrings.tone.current, selection: Binding(
                    get: { viewModel.tone },
                    set: { viewModel.updateTone($0) }
                )) {
                    ForEach(PolishTone.allCases) { tone in
                        Label(tone.title.current, systemImage: tone.symbolName).tag(tone)
                    }
                }

                LabeledContent(SettingsStrings.model.current) {
                    modelPicker
                }
            } header: {
                Text(SettingsStrings.writingHeading.current)
            } footer: {
                Text(SettingsStrings.modelUnavailableNote.current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section {
                Label(SettingsStrings.reviewAlwaysNote.current, systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SettingsStrings.pasteFallbackNote.current)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
    }

    /// A menu of the models the signed-in plan actually offers. The old free-text field asked
    /// users to know and correctly type an internal model identifier.
    @ViewBuilder
    private var modelPicker: some View {
        if viewModel.availableModels.isEmpty {
            HStack(spacing: 8) {
                if viewModel.isLoadingModels {
                    ProgressView().controlSize(.small)
                    Text(SettingsStrings.modelLoading.current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(SettingsStrings.modelPlanDefault.current)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 240, alignment: .leading)
            .task { viewModel.loadModels() }
        } else {
            Picker("", selection: Binding(
                get: { viewModel.model },
                set: { viewModel.updateModel($0) }
            )) {
                Text(SettingsStrings.modelPlanDefault.current).tag("")
                Divider()
                ForEach(viewModel.availableModels, id: \.self) { name in
                    Text(name == viewModel.defaultModelName ? "\(name) ·" : name).tag(name)
                }
            }
            .labelsHidden()
            .frame(width: 240)
        }
    }

    // MARK: - Account

    private var accountTab: some View {
        Form {
            codexSection
            accountSection
            Section { privacyNotice }
        }
        .formStyle(.grouped)
    }

    private var codexSection: some View {
        Section {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: viewModel.codexAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(viewModel.codexAvailable ? .green : .orange)
                Text(viewModel.codexAvailable ? SettingsStrings.codexFound.current : SettingsStrings.codexMissing.current)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !viewModel.codexAvailable {
                HStack {
                    Button(SettingsStrings.copyInstallCommand.current) {
                        viewModel.copyCodexInstallCommand()
                    }
                    Button(SettingsStrings.recheck.current) {
                        viewModel.recheckCodex()
                    }
                }
            }
        } header: {
            Text(SettingsStrings.codexHeading.current)
        }
    }

    private var accountSection: some View {
        Section {
            switch viewModel.accountState {
            case .starting:
                HStack {
                    ProgressView().controlSize(.small)
                    Text(SettingsStrings.checkingSignIn.current)
                }

            case .signedOut:
                Button(SettingsStrings.signIn.current) { viewModel.signIn() }
                    .buttonStyle(.borderedProminent)

            case .authenticating:
                HStack {
                    ProgressView().controlSize(.small)
                    Text(SettingsStrings.waitingForBrowser.current)
                    Spacer()
                    Button(SettingsStrings.cancel.current) { viewModel.cancelSignIn() }
                }

            case .signedIn(let account):
                HStack {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName).fontWeight(.medium)
                        Text(SettingsStrings.planLine(account.planDisplayName).current)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(SettingsStrings.signOut.current) { viewModel.signOut() }
                }

            case .unavailable(let message):
                VStack(alignment: .leading, spacing: 8) {
                    Label(message.current, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(SettingsStrings.tryAgain.current) { viewModel.refreshAccount() }
                        Button(SettingsStrings.signIn.current) { viewModel.signIn() }
                    }
                }
            }

            Text(SettingsStrings.accountNote.current)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(SettingsStrings.isolationNote.current)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } header: {
            Text(SettingsStrings.accountHeading.current)
        }
    }

    private var privacyNotice: some View {
        Label {
            Text(SettingsStrings.privacyNotice.current)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "hand.raised.fill").foregroundStyle(.blue)
        }
        .padding(12)
        .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
