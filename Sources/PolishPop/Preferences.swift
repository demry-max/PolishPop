import CoreGraphics
import Foundation

/// Every persisted user setting, read and written through one namespace.
///
/// Settings apply the moment they are changed, so there is no "unsaved" state anywhere in the UI.
enum Preferences {
    private enum Key {
        static let model = "openAIModel"
        static let tone = "polishTone"
        static let purpose = "polishPurpose"
        static let language = "appLanguage"
        static let showSelectionButton = "showSelectionButton"
        static let hideDockIcon = "hideDockIcon"
        static let polishShortcut = "polishShortcut"
        static let quickShortcut = "quickShortcut"
        static let quickReplaceEnabled = "quickReplaceEnabled"
        static let showDiff = "showDiffHighlighting"
        static let hasCompletedSetup = "hasCompletedSetup"
        static let reviewPanelSize = "reviewPanelSize"
    }

    /// Empty means "let the plan pick", which is what most users want.
    static var model: String {
        get {
            UserDefaults.standard.string(forKey: Key.model)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
        set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Key.model) }
    }

    static var tone: PolishTone {
        get { decode(Key.tone) ?? .professional }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.tone) }
    }

    static var purpose: PolishPurpose {
        get { decode(Key.purpose) ?? .smart }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.purpose) }
    }

    static var language: AppLanguage {
        get { decode(Key.language) ?? .automatic }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.language) }
    }

    static var showSelectionButton: Bool {
        get { bool(Key.showSelectionButton, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showSelectionButton) }
    }

    static var hideDockIcon: Bool {
        get { bool(Key.hideDockIcon, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hideDockIcon) }
    }

    static var showDiff: Bool {
        get { bool(Key.showDiff, default: true) }
        set { UserDefaults.standard.set(newValue, forKey: Key.showDiff) }
    }

    /// Instant replace skips the review panel, so it stays off until the user opts in.
    static var quickReplaceEnabled: Bool {
        get { bool(Key.quickReplaceEnabled, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: Key.quickReplaceEnabled) }
    }

    static var hasCompletedSetup: Bool {
        get { bool(Key.hasCompletedSetup, default: false) }
        set { UserDefaults.standard.set(newValue, forKey: Key.hasCompletedSetup) }
    }

    static var polishShortcut: ShortcutDefinition? {
        get { shortcut(Key.polishShortcut, default: .polishDefault) }
        set { setShortcut(newValue, forKey: Key.polishShortcut) }
    }

    static var quickShortcut: ShortcutDefinition? {
        get { shortcut(Key.quickShortcut, default: .quickDefault) }
        set { setShortcut(newValue, forKey: Key.quickShortcut) }
    }

    /// `nil` until the user resizes the review panel, so first-run sizing can still adapt to the
    /// length of the selection.
    static var reviewPanelSize: CGSize? {
        get {
            guard let stored = UserDefaults.standard.string(forKey: Key.reviewPanelSize) else { return nil }
            let parts = stored.split(separator: "x").compactMap { Double($0) }
            guard parts.count == 2, parts[0] >= 400, parts[1] >= 300 else { return nil }
            return CGSize(width: parts[0], height: parts[1])
        }
        set {
            guard let newValue else {
                UserDefaults.standard.removeObject(forKey: Key.reviewPanelSize)
                return
            }
            UserDefaults.standard.set("\(newValue.width)x\(newValue.height)", forKey: Key.reviewPanelSize)
        }
    }

    // MARK: - Helpers

    private static func decode<Value: RawRepresentable>(_ key: String) -> Value? where Value.RawValue == String {
        guard let raw = UserDefaults.standard.string(forKey: key) else { return nil }
        return Value(rawValue: raw)
    }

    private static func bool(_ key: String, default fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    /// A stored empty string means the user deliberately cleared the shortcut, which is different
    /// from never having touched it.
    private static func shortcut(_ key: String, default fallback: ShortcutDefinition) -> ShortcutDefinition? {
        guard let stored = UserDefaults.standard.string(forKey: key) else { return fallback }
        guard !stored.isEmpty else { return nil }
        return ShortcutDefinition(storageValue: stored) ?? fallback
    }

    private static func setShortcut(_ shortcut: ShortcutDefinition?, forKey key: String) {
        UserDefaults.standard.set(shortcut?.storageValue ?? "", forKey: key)
    }
}
