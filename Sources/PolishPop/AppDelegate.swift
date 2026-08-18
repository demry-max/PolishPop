import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let accessibility = AccessibilityService()
    private let client = CodexAppServerClient()

    private var statusItem: NSStatusItem?
    private var selectionMonitor: SelectionMonitor?
    private let globalHotKey = GlobalHotKey()
    private var floatingButton: FloatingButtonController?
    private var settingsWindow: SettingsWindowController?
    private var reviewWindow: ReviewWindowController?
    private var currentSelection: SelectionSnapshot?
    private var currentSelectionAnchor: NSPoint?
    private var polishTask: Task<Void, Never>?
    private var applyTask: Task<Void, Never>?
    private var reviewRegenerateTask: Task<Void, Never>?
    private var lastPolishedText: String?
    private var lastResultExpiryTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        configureMenuBar()
        configureSelectionExperience()
        globalHotKey.action = { [weak self] in
            self?.captureAndPolishCurrentSelection()
        }
        if !globalHotKey.register() {
            statusItem?.button?.toolTip = "PolishPop — ⌥⌘P is unavailable; use the selection button or menu."
        }

        if ProcessInfo.processInfo.arguments.contains("--review-preview") {
            showReviewPreview()
            return
        }

        Task { [weak self] in
            guard let self else { return }
            do {
                if try await client.account() == nil || !accessibility.isTrusted {
                    showSettings()
                }
            } catch {
                showSettings()
            }
        }
    }

    private func showReviewPreview() {
        let controller = ReviewWindowController()
        reviewWindow = controller
        controller.onApply = { [weak controller] _ in
            controller?.closeAfterSuccess()
        }
        controller.onCopy = { [weak self] draft in
            self?.accessibility.copyToPasteboard(draft)
        }
        controller.show(
            original: "pls review the attached report and send feedback by friday",
            draft: "Please review the attached report and send your feedback by Friday.",
            tone: .professional,
            purpose: .email,
            near: NSEvent.mouseLocation
        )
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let applicationMenuItem = NSMenuItem()
        mainMenu.addItem(applicationMenuItem)

        let applicationMenu = NSMenu(title: "PolishPop")
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        applicationMenu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit PolishPop",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        applicationMenu.addItem(quitItem)

        applicationMenuItem.submenu = applicationMenu
        NSApplication.shared.mainMenu = mainMenu
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        selectionMonitor?.stop()
        globalHotKey.unregister()
        polishTask?.cancel()
        applyTask?.cancel()
        reviewRegenerateTask?.cancel()
        lastResultExpiryTask?.cancel()
        Task {
            await client.stop()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    private func configureSelectionExperience() {
        let floatingButton = FloatingButtonController()
        floatingButton.onPrimaryAction = { [weak self] in
            self?.polishCapturedSelection()
        }
        self.floatingButton = floatingButton

        let monitor = SelectionMonitor(accessibility: accessibility)
        monitor.onSelection = { [weak self] selection, anchor in
            guard let self else { return }
            guard polishTask == nil else { return }
            currentSelection = selection
            currentSelectionAnchor = anchor
            floatingButton.show(near: anchor)
        }
        monitor.onSelectionCleared = { [weak self] in
            guard self?.polishTask == nil else { return }
            self?.currentSelection = nil
            self?.currentSelectionAnchor = nil
            self?.floatingButton?.hide()
        }
        monitor.start()
        selectionMonitor = monitor
    }

    private func configureMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "PolishPop")
        item.button?.toolTip = "PolishPop"

        let menu = NSMenu()
        let polishItem = NSMenuItem(
            title: "Polish Current Selection",
            action: #selector(polishFromMenu),
            keyEquivalent: "p"
        )
        polishItem.keyEquivalentModifierMask = [.option, .command]
        polishItem.target = self
        menu.addItem(polishItem)

        let copyItem = NSMenuItem(
            title: "Copy Last Polished Text",
            action: #selector(copyLastResult),
            keyEquivalent: ""
        )
        copyItem.target = self
        menu.addItem(copyItem)
        menu.addItem(.separator())

        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(showSettingsFromMenu),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)
        menu.addItem(.separator())

        let pauseItem = NSMenuItem(
            title: "Pause Selection Button",
            action: #selector(togglePause(_:)),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        let quitItem = NSMenuItem(
            title: "Quit PolishPop",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func polishFromMenu() {
        captureAndPolishCurrentSelection()
    }

    @objc private func copyLastResult() {
        guard let lastPolishedText else {
            showError("No polished text is available yet.")
            return
        }
        accessibility.copyToPasteboard(lastPolishedText)
    }

    @objc private func showSettingsFromMenu() {
        showSettings()
    }

    @objc private func togglePause(_ sender: NSMenuItem) {
        if sender.state == .on {
            sender.state = .off
            selectionMonitor?.start()
        } else {
            sender.state = .on
            selectionMonitor?.stop()
            floatingButton?.hide()
            currentSelection = nil
            currentSelectionAnchor = nil
            lastPolishedText = nil
            lastResultExpiryTask?.cancel()
        }
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func captureAndPolishCurrentSelection() {
        do {
            let selection = try accessibility.currentSelection()
            currentSelection = selection
            currentSelectionAnchor = NSEvent.mouseLocation
            floatingButton?.show(near: currentSelectionAnchor ?? NSEvent.mouseLocation)
            polishCapturedSelection()
        } catch {
            handle(error)
        }
    }

    private func polishCapturedSelection() {
        guard polishTask == nil else { return }
        guard let selection = currentSelection else {
            handle(PolishPopError.noSelection)
            return
        }
        floatingButton?.showWorking()
        let tone = Preferences.tone
        let purpose = Preferences.purpose
        let model = Preferences.model
        let reviewAnchor = currentSelectionAnchor ?? NSEvent.mouseLocation

        polishTask = Task { [weak self] in
            guard let self else { return }
            defer { polishTask = nil }

            do {
                let polished = try await client.polish(
                    text: selection.text,
                    tone: tone,
                    purpose: purpose,
                    model: model
                )
                try Task.checkCancellation()
                lastPolishedText = polished
                scheduleLastResultExpiry()

                floatingButton?.showSuccess()
                try? await Task.sleep(nanoseconds: 350_000_000)
                floatingButton?.hide()
                presentReview(
                    originalSelection: selection,
                    draft: polished,
                    tone: tone,
                    purpose: purpose,
                    near: reviewAnchor
                )
                currentSelection = nil
                currentSelectionAnchor = nil
            } catch is CancellationError {
                floatingButton?.hide()
                currentSelection = nil
                currentSelectionAnchor = nil
            } catch {
                handle(error)
                if (error as? CodexClientError) == .notAuthenticated {
                    showSettings()
                }
            }
        }
    }

    private func handle(_ error: Error) {
        let message = safeMessage(for: error)
        currentSelection = nil
        currentSelectionAnchor = nil
        floatingButton?.showFailure(message)
        statusItem?.button?.toolTip = message
        showError(message)

        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            self?.floatingButton?.hide()
            self?.statusItem?.button?.toolTip = "PolishPop"
        }
    }

    private func presentReview(
        originalSelection: SelectionSnapshot,
        draft: String,
        tone: PolishTone,
        purpose: PolishPurpose,
        near anchor: NSPoint
    ) {
        if reviewWindow == nil {
            reviewWindow = ReviewWindowController()
        }
        guard let reviewWindow else { return }

        reviewWindow.onApply = { [weak self] editedDraft in
            self?.applyReviewedDraft(editedDraft, to: originalSelection)
        }
        reviewWindow.onCopy = { [weak self] editedDraft in
            self?.accessibility.copyToPasteboard(editedDraft)
        }
        reviewWindow.onCancel = { [weak self] in
            self?.applyTask?.cancel()
            self?.applyTask = nil
            self?.reviewRegenerateTask?.cancel()
            self?.reviewRegenerateTask = nil
        }
        reviewWindow.onRegenerate = { [weak self] purpose, tone in
            self?.regenerateReview(
                originalSelection: originalSelection,
                purpose: purpose,
                tone: tone
            )
        }
        reviewWindow.show(
            original: originalSelection.text,
            draft: draft,
            tone: tone,
            purpose: purpose,
            near: anchor
        )
    }

    private func regenerateReview(
        originalSelection: SelectionSnapshot,
        purpose: PolishPurpose,
        tone: PolishTone
    ) {
        guard reviewRegenerateTask == nil else { return }
        reviewRegenerateTask = Task { [weak self] in
            guard let self else { return }
            defer { reviewRegenerateTask = nil }

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
                reviewWindow?.updateDraft(regenerated)
            } catch is CancellationError {
                reviewWindow?.showGenerationError("Regeneration was cancelled. The existing draft was kept.")
            } catch {
                reviewWindow?.showGenerationError(safeMessage(for: error))
            }
        }
    }

    private func applyReviewedDraft(_ draft: String, to selection: SelectionSnapshot) {
        guard applyTask == nil else { return }
        applyTask = Task { [weak self] in
            guard let self else { return }
            defer { applyTask = nil }

            do {
                try await accessibility.replaceFromReview(
                    selection,
                    with: draft,
                    allowClipboardFallback: true
                )
                lastPolishedText = draft
                scheduleLastResultExpiry()
                reviewWindow?.closeAfterSuccess()
            } catch is CancellationError {
                reviewWindow?.showApplyError("Apply was cancelled. The original text was not changed.")
            } catch {
                reviewWindow?.showApplyError(
                    "\(safeMessage(for: error)) You can use Copy Draft and paste it manually."
                )
            }
        }
    }

    private func scheduleLastResultExpiry() {
        lastResultExpiryTask?.cancel()
        lastResultExpiryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000_000)
            guard !Task.isCancelled else { return }
            self?.lastPolishedText = nil
        }
    }

    private func safeMessage(for error: Error) -> String {
        if let polishError = error as? PolishPopError {
            return polishError.localizedDescription
        }
        if let codexError = error as? CodexClientError {
            return codexError.localizedDescription
        }
        return "PolishPop could not complete the rewrite. Please try again."
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "PolishPop"
        alert.informativeText = message
        alert.alertStyle = .informational
        NSApplication.shared.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(
                client: client,
                accessibility: accessibility
            )
        }
        settingsWindow?.show()
    }
}
