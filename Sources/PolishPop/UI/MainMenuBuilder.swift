import AppKit

/// Builds the application menu bar.
///
/// A full Edit menu is what makes ⌘C, ⌘V, ⌘A and ⌘Z work inside the review panel's draft editor:
/// on macOS those commands reach a text view through main-menu key equivalents, and without them
/// the one editable field in the product had no working editing shortcuts at all.
@MainActor
enum MainMenuBuilder {
    static func build(
        settingsTarget: AnyObject,
        settingsAction: Selector,
        quitTarget: AnyObject,
        quitAction: Selector
    ) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(
            submenu(
                applicationMenu(
                    settingsTarget: settingsTarget,
                    settingsAction: settingsAction,
                    quitTarget: quitTarget,
                    quitAction: quitAction
                )
            )
        )
        mainMenu.addItem(submenu(editMenu()))
        mainMenu.addItem(submenu(windowMenu()))
        return mainMenu
    }

    /// The Window menu AppKit should manage, so it can track open panels.
    static func windowsMenu(in mainMenu: NSMenu) -> NSMenu? {
        mainMenu.items.last?.submenu
    }

    // MARK: - Sections

    private static func applicationMenu(
        settingsTarget: AnyObject,
        settingsAction: Selector,
        quitTarget: AnyObject,
        quitAction: Selector
    ) -> NSMenu {
        let menu = NSMenu(title: ShellStrings.appName.current)
        menu.addItem(
            responderItem(
                ShellStrings.about,
                #selector(NSApplication.orderFrontStandardAboutPanel(_:))
            )
        )
        menu.addItem(.separator())
        menu.addItem(
            targetedItem(
                ShellStrings.settingsMenuItem,
                action: settingsAction,
                target: settingsTarget,
                key: ","
            )
        )
        menu.addItem(.separator())
        menu.addItem(responderItem(ShellStrings.hide, #selector(NSApplication.hide(_:)), key: "h"))
        let hideOthers = responderItem(
            ShellStrings.hideOthers,
            #selector(NSApplication.hideOtherApplications(_:)),
            key: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(hideOthers)
        menu.addItem(.separator())
        menu.addItem(
            targetedItem(ShellStrings.quit, action: quitAction, target: quitTarget, key: "q")
        )
        return menu
    }

    /// Every item here keeps a nil target so the command travels the responder chain to whichever
    /// text view is focused.
    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: ShellStrings.editMenu.current)
        menu.addItem(responderItem(ShellStrings.undo, Selector(("undo:")), key: "z"))
        let redo = responderItem(ShellStrings.redo, Selector(("redo:")), key: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(responderItem(ShellStrings.cut, #selector(NSText.cut(_:)), key: "x"))
        menu.addItem(responderItem(ShellStrings.copy, #selector(NSText.copy(_:)), key: "c"))
        menu.addItem(responderItem(ShellStrings.paste, #selector(NSText.paste(_:)), key: "v"))
        let pastePlain = responderItem(
            ShellStrings.pasteAndMatchStyle,
            #selector(NSTextView.pasteAsPlainText(_:)),
            key: "v"
        )
        pastePlain.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(pastePlain)
        menu.addItem(responderItem(ShellStrings.selectAll, #selector(NSText.selectAll(_:)), key: "a"))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: ShellStrings.windowMenu.current)
        menu.addItem(responderItem(ShellStrings.minimize, #selector(NSWindow.miniaturize(_:)), key: "m"))
        menu.addItem(responderItem(ShellStrings.closeWindow, #selector(NSWindow.performClose(_:)), key: "w"))
        return menu
    }

    // MARK: - Item helpers

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem()
        item.submenu = menu
        return item
    }

    private static func responderItem(
        _ title: LocalizedText,
        _ action: Selector,
        key: String = ""
    ) -> NSMenuItem {
        NSMenuItem(title: title.current, action: action, keyEquivalent: key)
    }

    private static func targetedItem(
        _ title: LocalizedText,
        action: Selector,
        target: AnyObject,
        key: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title.current, action: action, keyEquivalent: key)
        item.target = target
        return item
    }
}
