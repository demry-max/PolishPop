import AppKit

/// Builds the menu-bar menu and the sparkle's right-click menu.
///
/// The menu is rebuilt rather than mutated so shortcut labels, check marks and enablement always
/// reflect the live preferences — the old menu advertised a fixed ⌥⌘P even when registration had
/// failed, and its Pause item never changed its title.
@MainActor
final class StatusMenuController: NSObject, NSMenuDelegate {
    let menu = NSMenu()

    private let polish: () -> Void
    private let quickReplace: () -> Void
    private let undoReplacement: () -> Void
    private let copyLastResult: () -> Void
    private let toggleSelectionButton: () -> Void
    private let selectTone: (PolishTone) -> Void
    private let selectPurpose: (PolishPurpose) -> Void
    private let openSettings: () -> Void
    private let quit: () -> Void
    private let canUndo: () -> Bool?
    private let hasLastResult: () -> Bool?

    init(
        polish: @escaping () -> Void,
        quickReplace: @escaping () -> Void,
        undoReplacement: @escaping () -> Void,
        copyLastResult: @escaping () -> Void,
        toggleSelectionButton: @escaping () -> Void,
        selectTone: @escaping (PolishTone) -> Void,
        selectPurpose: @escaping (PolishPurpose) -> Void,
        openSettings: @escaping () -> Void,
        quit: @escaping () -> Void,
        canUndo: @escaping () -> Bool?,
        hasLastResult: @escaping () -> Bool?
    ) {
        self.polish = polish
        self.quickReplace = quickReplace
        self.undoReplacement = undoReplacement
        self.copyLastResult = copyLastResult
        self.toggleSelectionButton = toggleSelectionButton
        self.selectTone = selectTone
        self.selectPurpose = selectPurpose
        self.openSettings = openSettings
        self.quit = quit
        self.canUndo = canUndo
        self.hasLastResult = hasLastResult
        super.init()
        menu.delegate = self
        // Automatic enabling would recompute every item and discard the explicit isEnabled values
        // below, leaving Undo and Copy clickable with nothing to act on.
        menu.autoenablesItems = false
        rebuild()
    }

    /// Rebuilt right before display so state is never stale by the time the user reads it.
    func menuWillOpen(_ menu: NSMenu) {
        rebuild()
    }

    func rebuild() {
        menu.removeAllItems()

        menu.addItem(command(ShellStrings.polishSelection, shortcut: Preferences.polishShortcut) { [weak self] in
            self?.polish()
        })

        if Preferences.quickReplaceEnabled {
            menu.addItem(command(ShellStrings.polishAndReplace, shortcut: Preferences.quickShortcut) { [weak self] in
                self?.quickReplace()
            })
        }

        let undoItem = command(ShellStrings.undoLastReplacement) { [weak self] in
            self?.undoReplacement()
        }
        undoItem.isEnabled = canUndo() ?? false
        menu.addItem(undoItem)

        let copyItem = command(ShellStrings.copyLastResult) { [weak self] in
            self?.copyLastResult()
        }
        copyItem.isEnabled = hasLastResult() ?? false
        menu.addItem(copyItem)

        menu.addItem(.separator())
        menu.addItem(purposeMenuItem())
        menu.addItem(toneMenuItem())

        menu.addItem(.separator())
        let buttonItem = command(ShellStrings.showSelectionButton) { [weak self] in
            self?.toggleSelectionButton()
        }
        buttonItem.state = Preferences.showSelectionButton ? .on : .off
        menu.addItem(buttonItem)

        menu.addItem(command(ShellStrings.settingsMenuItem, keyEquivalent: ",") { [weak self] in
            self?.openSettings()
        })
        menu.addItem(.separator())
        menu.addItem(command(ShellStrings.quit, keyEquivalent: "q") { [weak self] in
            self?.quit()
        })
    }

    /// Compact menu shown when the sparkle button is right-clicked, so tone and use case can be
    /// changed without opening Settings.
    func makeQuickMenu() -> NSMenu {
        let quickMenu = NSMenu()
        quickMenu.autoenablesItems = false
        quickMenu.addItem(purposeMenuItem())
        quickMenu.addItem(toneMenuItem())
        if Preferences.quickReplaceEnabled {
            quickMenu.addItem(.separator())
            quickMenu.addItem(command(ShellStrings.polishAndReplace, shortcut: Preferences.quickShortcut) { [weak self] in
                self?.quickReplace()
            })
        }
        return quickMenu
    }

    // MARK: - Item construction

    private func toneMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: ShellStrings.toneMenu.current, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = Preferences.tone
        for tone in PolishTone.allCases {
            let toneItem = command(tone.title) { [weak self] in self?.selectTone(tone) }
            toneItem.state = tone == current ? .on : .off
            toneItem.image = NSImage(systemSymbolName: tone.symbolName, accessibilityDescription: nil)
            submenu.addItem(toneItem)
        }
        item.submenu = submenu
        return item
    }

    private func purposeMenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: ShellStrings.purposeMenu.current, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let current = Preferences.purpose
        for purpose in PolishPurpose.allCases {
            let purposeItem = command(purpose.title) { [weak self] in self?.selectPurpose(purpose) }
            purposeItem.state = purpose == current ? .on : .off
            purposeItem.image = NSImage(systemSymbolName: purpose.symbolName, accessibilityDescription: nil)
            submenu.addItem(purposeItem)
        }
        item.submenu = submenu
        return item
    }

    private func command(
        _ title: LocalizedText,
        shortcut: ShortcutDefinition? = nil,
        keyEquivalent: String = "",
        handler: @escaping () -> Void
    ) -> NSMenuItem {
        let item = ClosureMenuItem(title: title.current, handler: handler)
        if let shortcut {
            if let character = shortcut.menuKeyEquivalentCharacter {
                item.keyEquivalent = character
                item.keyEquivalentModifierMask = shortcut.cocoaModifiers
            } else {
                // No single-character equivalent exists, so the shortcut is spelled out instead of
                // silently rendering as an unmatchable string.
                item.title = "\(title.current)  (\(shortcut.displayString))"
            }
        } else if !keyEquivalent.isEmpty {
            item.keyEquivalent = keyEquivalent
        }
        return item
    }
}

/// An `NSMenuItem` that owns its action, so the menu can be rebuilt without a growing switch
/// statement of selectors in the delegate.
private final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    @objc private func invoke() {
        handler()
    }
}
