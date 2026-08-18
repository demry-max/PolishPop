import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let accessibility = AccessibilityService()
    private let client = CodexAppServerClient()
    private let toasts = ToastController()

    private var statusItem: NSStatusItem?
    private var selectionMonitor: SelectionMonitor?
    private let globalHotKey = GlobalHotKey()
    private var floatingButton: FloatingButtonController?
    private var settingsWindow: SettingsWindowController?
    private var reviewWindow: ReviewWindowController?
    private var menuController: StatusMenuController?

    private var currentSelection: SelectionSnapshot?
    private var currentSelectionAnchor: NSPoint?
    private var polishTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var reviewRegenerateTask: Task<Void, Never>?
    /// Tokens identify which task owns a handle. Cancelling `client.polish` is advisory — the
    /// Codex turn can take seconds to wind down — so a cancelled task may still be running when
    /// its replacement starts, and must not clear the newer task's handle on the way out.
    private var polishTaskToken: UUID?
    private var applyTaskToken: UUID?
    private var regenerateTaskToken: UUID?
    private var reviewSession: UUID?
    private var lastPolishedText: String?
    private var lastResultExpiryTask: Task<Void, Never>?
    /// Kept so a one-keystroke instant replacement is never a one-way door.
    private var lastReplacement: ReplacementRecord?

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        Diagnostics.reset()
        Diagnostics.log("launch: accessibilityTrusted=\(accessibility.isTrusted) showSelectionButton=\(Preferences.showSelectionButton) hasCompletedSetup=\(Preferences.hasCompletedSetup)")
        Localization.shared.update(to: Preferences.language)
        applyActivationPolicy()
        configureMainMenu()
        configureMenuBar()
        configureSelectionExperience()
        configureHotKeys()

        NotificationCenter.default.addObserver(
            forName: Localization.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.configureMainMenu()
                self.menuController?.rebuild()
                self.statusItem?.button?.toolTip = ShellStrings.statusItemTooltip.current
                self.reviewWindow?.refreshLanguage()
                self.settingsWindow?.refreshLanguage()
            }
        }

        if ProcessInfo.processInfo.arguments.contains("--review-preview") {
            showReviewPreview()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            if !accessibility.isTrusted || !Preferences.hasCompletedSetup {
                showSettings()
                return
            }
            // A Codex hiccup on a configured machine is reported quietly rather than by yanking
            // the user out of whatever they were doing to look at a settings window.
            do {
                if try await client.account() == nil {
                    showSettings()
                }
            } catch {
                toasts.show(
                    Toast(
                        severity: .warning,
                        message: message(for: error),
                        action: Toast.Action(title: ShellStrings.openSettings) { [weak self] in
                            self?.showSettings()
                        }
                    )
                )
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        selectionMonitor?.stop()
        globalHotKey.unregisterAll()
        polishTask?.cancel()
        applyTask?.cancel()
        reviewRegenerateTask?.cancel()
        lastResultExpiryTask?.cancel()
        Task {
            // Quit promptly even if the Codex subprocess is slow to die; the OS reaps it either way.
            _ = await withTaskGroup(of: Void.self) { group in
                group.addTask { await self.client.stop() }
                group.addTask { try? await Task.sleep(nanoseconds: 700_000_000) }
                await group.next()
                group.cancelAll()
            }
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Reopening from the Dock or Spotlight should show something, not appear to do nothing.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            showSettings()
        }
        return true
    }

    private func applyActivationPolicy() {
        NSApplication.shared.setActivationPolicy(Preferences.hideDockIcon ? .accessory : .regular)
    }

    // MARK: - Menus

    private func configureMainMenu() {
        let mainMenu = MainMenuBuilder.build(
            settingsTarget: self,
            settingsAction: #selector(showSettingsFromMenu),
            quitTarget: self,
            quitAction: #selector(quit)
        )
        NSApplication.shared.mainMenu = mainMenu
        NSApplication.shared.windowsMenu = MainMenuBuilder.windowsMenu(in: mainMenu)
    }

    private func configureMenuBar() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: ShellStrings.appName.current)
        statusItem.button?.toolTip = ShellStrings.statusItemTooltip.current

        let controller = StatusMenuController(
            polish: { [weak self] in self?.captureAndPolish(mode: .review) },
            quickReplace: { [weak self] in self?.captureAndPolish(mode: .instant) },
            undoReplacement: { [weak self] in self?.undoLastReplacement() },
            copyLastResult: { [weak self] in self?.copyLastResult() },
            toggleSelectionButton: { [weak self] in self?.toggleSelectionButton() },
            selectTone: { [weak self] tone in self?.selectTone(tone) },
            selectPurpose: { [weak self] purpose in self?.selectPurpose(purpose) },
            openSettings: { [weak self] in self?.showSettings() },
            quit: { [weak self] in self?.quit() },
            canUndo: { [weak self] in self?.lastReplacement != nil },
            hasLastResult: { [weak self] in self?.lastPolishedText != nil }
        )
        statusItem.menu = controller.menu
        menuController = controller
        self.statusItem = statusItem
    }

    private func configureSelectionExperience() {
        let floatingButton = FloatingButtonController()
        floatingButton.onPrimaryAction = { [weak self] in
            self?.polishCapturedSelection(mode: .review)
        }
        floatingButton.onSecondaryAction = { [weak self] in
            self?.menuController?.makeQuickMenu()
        }
        self.floatingButton = floatingButton

        let monitor = SelectionMonitor(accessibility: accessibility)
        monitor.onSelection = { [weak self] selection in
            Diagnostics.log("onSelection: length=\(selection.text.count) replaceable=\(selection.isReplaceable)")
            guard let self, polishTask == nil else { return }
            currentSelection = selection
            currentSelectionAnchor = NSEvent.mouseLocation
            Task { [weak self] in
                guard let self, let current = currentSelection,
                      current.matchesLocation(of: selection) else { return }
                let bounds = await accessibility.selectionBounds(for: selection)
                guard currentSelection?.matchesLocation(of: selection) == true else { return }
                floatingButton.show(
                    selectionBounds: bounds,
                    fallbackAnchor: currentSelectionAnchor ?? NSEvent.mouseLocation
                )
            }
        }
        monitor.onSelectionCleared = { [weak self] in
            guard let self, polishTask == nil else { return }
            currentSelection = nil
            currentSelectionAnchor = nil
            floatingButton.hide()
        }
        selectionMonitor = monitor
        if Preferences.showSelectionButton {
            monitor.start()
            Diagnostics.log("selection monitor started")
        } else {
            Diagnostics.log("selection monitor NOT started (preference off)")
        }
        observeApplicationSwitches()
    }

    /// Switching to a different application abandons the selection the sparkle was offered for,
    /// so the button goes with it instead of floating above the new app.
    private func observeApplicationSwitches() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let activated = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let activatedPID = activated?.processIdentifier
            MainActor.assumeIsolated {
                guard let self, self.polishTask == nil, self.applyTask == nil else { return }
                guard activatedPID != self.currentSelection?.targetPID,
                      activatedPID != ProcessInfo.processInfo.processIdentifier else {
                    return
                }
                self.floatingButton?.hide()
                self.currentSelection = nil
                self.currentSelectionAnchor = nil
                self.selectionMonitor?.invalidateDeliveredSelection()
            }
        }
    }

    private func configureHotKeys() {
        globalHotKey.action = { [weak self] command in
            switch command {
            case .polish:
                self?.captureAndPolish(mode: .review)
            case .quickReplace:
                self?.captureAndPolish(mode: .instant)
            }
        }
        registerHotKeys()
    }

    private func registerHotKeys() {
        let polishRegistered = globalHotKey.register(Preferences.polishShortcut, for: .polish)
        let quickShortcut = Preferences.quickReplaceEnabled ? Preferences.quickShortcut : nil
        let quickRegistered = globalHotKey.register(quickShortcut, for: .quickReplace)
        Diagnostics.log("hotkeys: polish=\(polishRegistered) quick=\(quickRegistered)")
        if !polishRegistered || !quickRegistered {
            settingsWindow?.viewModel.reportShortcutUnavailable()
        }
        menuController?.rebuild()
        if floatingButton?.isVisible == true {
            floatingButton?.model.tooltip = FloatingButtonController.readyTooltip()
        }
    }

    // MARK: - Menu actions

    private func copyLastResult() {
        guard let lastPolishedText else {
            toasts.show(Toast(severity: .warning, message: ShellStrings.noResultYet))
            return
        }
        accessibility.copyToPasteboard(lastPolishedText)
        toasts.show(Toast(severity: .success, message: ShellStrings.copiedToast))
    }

    private func toggleSelectionButton() {
        let enabled = !Preferences.showSelectionButton
        Preferences.showSelectionButton = enabled
        settingsWindow?.viewModel.showSelectionButton = enabled
        applySelectionButtonPreference()
    }

    private func applySelectionButtonPreference() {
        if Preferences.showSelectionButton {
            selectionMonitor?.start()
        } else {
            selectionMonitor?.stop()
            floatingButton?.hide()
            currentSelection = nil
            currentSelectionAnchor = nil
        }
        menuController?.rebuild()
    }

    private func selectTone(_ tone: PolishTone) {
        Preferences.tone = tone
        settingsWindow?.viewModel.tone = tone
        menuController?.rebuild()
    }

    private func selectPurpose(_ purpose: PolishPurpose) {
        Preferences.purpose = purpose
        settingsWindow?.viewModel.purpose = purpose
        menuController?.rebuild()
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: - Polishing

    private enum PolishMode {
        case review
        case instant
    }

    private func captureAndPolish(mode: PolishMode) {
        Task { [weak self] in
            guard let self else { return }
            guard polishTask == nil, applyTask == nil else { return }
            do {
                let selection = try await accessibility.currentSelection()
                guard polishTask == nil, applyTask == nil else { return }
                currentSelection = selection
                currentSelectionAnchor = NSEvent.mouseLocation
                selectionMonitor?.invalidateDeliveredSelection()
                polishCapturedSelection(mode: mode)
            } catch {
                present(error)
            }
        }
    }

    /// The menu-bar icon is the one piece of PolishPop that is always on screen, so it carries
    /// the busy state for people who dismissed or never saw the panel.
    private func updateStatusItemIcon(isBusy: Bool) {
        // A distinct symbol rather than a dimmed one: a greyed-out menu-bar icon reads as
        // "unavailable", not "working".
        let symbol = isBusy ? "sparkles.rectangle.stack.fill" : "sparkles"
        statusItem?.button?.image = NSImage(
            systemSymbolName: symbol,
            accessibilityDescription: ShellStrings.appName.current
        )
        statusItem?.button?.toolTip = isBusy
            ? ShellStrings.workingTooltip.current
            : ShellStrings.statusItemTooltip.current
    }

    /// Beyond this the snapshot is treated as stale: the user has moved on, and spending a Codex
    /// turn on text they selected minutes ago is worse than asking them to select it again.
    private static let selectionLifetime: TimeInterval = 120

    private func polishCapturedSelection(mode: PolishMode) {
        // An apply is not instantaneous, and its completion talks to the review panel; starting a
        // new polish underneath it would let the old apply close the new session's window.
        guard polishTask == nil, applyTask == nil else { return }
        guard let selection = currentSelection else {
            present(PolishPopError.noSelection)
            return
        }
        guard Date().timeIntervalSince(selection.capturedAt) < Self.selectionLifetime else {
            currentSelection = nil
            currentSelectionAnchor = nil
            selectionMonitor?.invalidateDeliveredSelection()
            present(PolishPopError.selectionChanged)
            return
        }

        let tone = Preferences.tone
        let purpose = Preferences.purpose
        let model = Preferences.model
        let anchor = currentSelectionAnchor ?? NSEvent.mouseLocation

        var session: UUID?
        switch mode {
        case .review:
            // Opening the panel first turns a blind wait into visible progress with a Stop button,
            // so the sparkle has nothing left to say.
            session = presentReviewShell(for: selection, tone: tone, purpose: purpose, near: anchor)
            floatingButton?.hide()
        case .instant:
            // Instant mode has no panel, so the button and a toast carry the progress.
            floatingButton?.showWorking()
            toasts.show(Toast(severity: .info, message: ShellStrings.workingToast), near: anchor)
        }

        updateStatusItemIcon(isBusy: true)
        let token = UUID()
        polishTaskToken = token
        polishTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if polishTaskToken == token {
                    polishTaskToken = nil
                    polishTask = nil
                    updateStatusItemIcon(isBusy: false)
                }
            }

            do {
                // The sparkle path reaches here with a snapshot from the cheap probe, which skips
                // the ancestor scan for DRM-protected containers. Run it before any text is sent.
                try await accessibility.assertNotProtected(selection)
                let polished = try await client.polish(
                    text: selection.text,
                    tone: tone,
                    purpose: purpose,
                    model: model
                )
                try Task.checkCancellation()
                lastPolishedText = polished
                scheduleLastResultExpiry()
                menuController?.rebuild()

                switch mode {
                case .review:
                    floatingButton?.hide()
                    if let session {
                        reviewWindow?.showDraft(polished, tone: tone, purpose: purpose, session: session)
                    }
                case .instant:
                    await applyInstantly(polished, to: selection, anchor: anchor)
                }
                currentSelection = nil
                currentSelectionAnchor = nil
            } catch is CancellationError {
                floatingButton?.hide()
                currentSelection = nil
                currentSelectionAnchor = nil
            } catch {
                switch mode {
                case .review:
                    floatingButton?.hide()
                    if let session {
                        reviewWindow?.showGenerationError(message(for: error), session: session)
                    }
                case .instant:
                    present(error, near: anchor)
                }
            }
        }
    }

    /// Instant mode: replace without a review panel, and immediately offer one-click undo.
    private func applyInstantly(_ draft: String, to selection: SelectionSnapshot, anchor: NSPoint) async {
        do {
            try await accessibility.replaceFromReview(
                selection,
                with: draft,
                allowClipboardFallback: true
            )
            lastReplacement = ReplacementRecord(snapshot: selection, original: selection.text, applied: draft)
            menuController?.rebuild()
            floatingButton?.hide()
            toasts.show(
                Toast(
                    severity: .success,
                    message: ShellStrings.appliedToast,
                    action: Toast.Action(title: ShellStrings.undoAvailableToast) { [weak self] in
                        self?.undoLastReplacement()
                    }
                ),
                near: anchor
            )
        } catch {
            accessibility.copyToPasteboard(draft)
            present(error, near: anchor)
        }
    }

    /// Puts the user's own words back by replacing the applied draft with the original text.
    private func undoLastReplacement() {
        guard let record = lastReplacement else {
            toasts.show(Toast(severity: .warning, message: ShellStrings.noUndoAvailable))
            return
        }
        lastReplacement = nil
        menuController?.rebuild()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await accessibility.restoreOriginal(record)
                toasts.show(Toast(severity: .success, message: ShellStrings.undoneToast))
            } catch {
                // The field moved on; hand the original back through the clipboard rather than
                // overwriting whatever is there now.
                accessibility.copyToPasteboard(record.original)
                toasts.show(Toast(severity: .warning, message: ShellStrings.undoUnavailable))
            }
        }
    }

    // MARK: - Review panel

    private func presentReviewShell(
        for selection: SelectionSnapshot,
        tone: PolishTone,
        purpose: PolishPurpose,
        near anchor: NSPoint
    ) -> UUID {
        let controller = reviewWindow ?? ReviewWindowController()
        // Starting a new polish over an open panel would otherwise throw away a draft the user may
        // have spent time editing; it is kept reachable from "Copy Last Polished Text".
        if controller.isVisible, !controller.currentDraft.isEmpty {
            lastPolishedText = controller.currentDraft
            scheduleLastResultExpiry()
        }
        reviewWindow = controller

        controller.onCopy = { [weak self] draft in
            self?.accessibility.copyToPasteboard(draft)
        }
        controller.onCancel = { [weak self] draft in
            guard let self else { return }
            if !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lastPolishedText = draft
                scheduleLastResultExpiry()
                menuController?.rebuild()
            }
            cancelReviewWork()
        }
        controller.onStopGenerating = { [weak self] in
            self?.polishTask?.cancel()
            self?.reviewRegenerateTask?.cancel()
        }
        controller.onRegenerate = { [weak self] purpose, tone in
            self?.regenerateReview(originalSelection: selection, purpose: purpose, tone: tone)
        }
        let session = controller.showGenerating(
            original: selection.text,
            tone: tone,
            purpose: purpose,
            targetApplicationName: selection.targetApplicationName,
            canReplace: selection.isReplaceable,
            near: anchor
        )
        reviewSession = session
        controller.onApply = { [weak self] draft in
            self?.applyReviewedDraft(draft, to: selection, session: session)
        }
        return session
    }

    private func cancelReviewWork() {
        polishTask?.cancel()
        polishTask = nil
        polishTaskToken = nil
        applyTask?.cancel()
        applyTask = nil
        applyTaskToken = nil
        reviewRegenerateTask?.cancel()
        reviewRegenerateTask = nil
        regenerateTaskToken = nil
        updateStatusItemIcon(isBusy: false)
        floatingButton?.hide()
    }

    private func regenerateReview(
        originalSelection: SelectionSnapshot,
        purpose: PolishPurpose,
        tone: PolishTone
    ) {
        guard reviewRegenerateTask == nil else { return }
        let session = reviewSession
        let token = UUID()
        regenerateTaskToken = token
        reviewRegenerateTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if regenerateTaskToken == token {
                    regenerateTaskToken = nil
                    reviewRegenerateTask = nil
                }
            }

            do {
                let regenerated = try await client.polish(
                    text: originalSelection.text,
                    tone: tone,
                    purpose: purpose,
                    model: Preferences.model
                )
                try Task.checkCancellation()
                lastPolishedText = regenerated
                scheduleLastResultExpiry()
                menuController?.rebuild()
                if let session {
                    reviewWindow?.updateDraft(regenerated, session: session)
                }
            } catch is CancellationError {
                if let session {
                    reviewWindow?.showGenerationError(ReviewStrings.regenerationCancelled, session: session)
                }
            } catch {
                if let session {
                    reviewWindow?.showGenerationError(message(for: error), session: session)
                }
            }
        }
    }

    private func applyReviewedDraft(_ draft: String, to selection: SelectionSnapshot, session: UUID) {
        guard applyTask == nil else { return }
        let token = UUID()
        applyTaskToken = token
        applyTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if applyTaskToken == token {
                    applyTaskToken = nil
                    applyTask = nil
                }
            }

            do {
                try await accessibility.replaceFromReview(
                    selection,
                    with: draft,
                    allowClipboardFallback: true
                )
                Diagnostics.log("apply: succeeded")
                lastPolishedText = draft
                lastReplacement = ReplacementRecord(snapshot: selection, original: selection.text, applied: draft)
                scheduleLastResultExpiry()
                menuController?.rebuild()
                reviewWindow?.closeAfterSuccess(session: session)
                toasts.show(
                    Toast(
                        severity: .success,
                        message: ShellStrings.appliedToast,
                        action: Toast.Action(title: ShellStrings.undoAvailableToast) { [weak self] in
                            self?.undoLastReplacement()
                        }
                    )
                )
            } catch is CancellationError {
                reviewWindow?.showApplyError(ReviewStrings.applyCancelled, session: session)
            } catch {
                reviewWindow?.showApplyError(message(for: error), session: session)
            }
        }
    }

    // MARK: - Feedback

    /// Errors appear as a dismissible toast beside the selection instead of a modal alert that
    /// yanks focus out of whatever the user was typing in.
    private func present(_ error: Error, near anchor: NSPoint? = nil) {
        // The selection is deliberately kept: a Codex timeout or a momentary auth blip should not
        // force the user to go back and highlight the same paragraph again.
        if let polishError = error as? PolishPopError,
           polishError == .noSelection || polishError == .protectedTextField {
            currentSelection = nil
            currentSelectionAnchor = nil
        }
        let text = message(for: error)
        floatingButton?.showFailure(text)
        statusItem?.button?.toolTip = text.current

        var toast = Toast(severity: .failure, message: text)
        if isSetupProblem(error) {
            toast.action = Toast.Action(title: ShellStrings.openSettings) { [weak self] in
                self?.showSettings()
            }
        }
        toasts.show(toast, near: anchor ?? NSEvent.mouseLocation)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard let self, !Task.isCancelled else { return }
            // Only clear the failure that armed this timer; by now the button may be offering a
            // brand-new selection that has nothing to do with the error.
            if floatingButton?.model.phase == .failure {
                floatingButton?.hide()
            }
            statusItem?.button?.toolTip = ShellStrings.statusItemTooltip.current
        }
    }

    private func isSetupProblem(_ error: Error) -> Bool {
        if let codexError = error as? CodexClientError { return codexError.isSetupProblem }
        if let polishError = error as? PolishPopError {
            return polishError == .accessibilityPermissionMissing
        }
        return false
    }

    private func message(for error: Error) -> LocalizedText {
        if let polishError = error as? PolishPopError { return polishError.message }
        if let codexError = error as? CodexClientError { return codexError.message }
        return ErrorStrings.unknown
    }

    private func scheduleLastResultExpiry() {
        lastResultExpiryTask?.cancel()
        lastResultExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lastPolishedText = nil
            self?.lastReplacement = nil
            self?.menuController?.rebuild()
        }
    }

    private func showSettings() {
        if settingsWindow == nil {
            let controller = SettingsWindowController(client: client, accessibility: accessibility)
            controller.viewModel.onPreferencesChanged = { [weak self] change in
                switch change {
                case .selectionButton: self?.applySelectionButtonPreference()
                case .dockIcon: self?.applyActivationPolicy()
                case .shortcuts: self?.registerHotKeys()
                case .language: break
                }
            }
            settingsWindow = controller
        }
        settingsWindow?.show()
    }

    private func showReviewPreview() {
        let controller = ReviewWindowController()
        reviewWindow = controller
        controller.onCopy = { [weak self] draft in
            self?.accessibility.copyToPasteboard(draft)
        }
        let session = controller.showGenerating(
            original: UISamples.originalText,
            tone: .professional,
            purpose: .email,
            targetApplicationName: "Mail",
            canReplace: true,
            near: NSEvent.mouseLocation
        )
        controller.showDraft(UISamples.draftText, tone: .professional, purpose: .email, session: session)
    }
}
