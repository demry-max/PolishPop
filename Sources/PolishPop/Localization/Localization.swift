import Foundation
import Combine

/// The user-selectable interface language.
///
/// `automatic` follows the macOS preferred-language list so a Chinese system gets a Chinese
/// interface with no configuration, while the explicit cases let a user override that.
enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case automatic
    case english
    case chineseSimplified

    var id: String { rawValue }

    /// The concrete languages name themselves so the option stays readable whatever the current
    /// interface language is; only "Automatic" follows the interface.
    @MainActor
    var menuTitle: String {
        switch self {
        case .automatic:
            Localization.shared.language == .chineseSimplified ? "跟随系统" : "Automatic"
        case .english:
            "English"
        case .chineseSimplified:
            "简体中文"
        }
    }

    /// The concrete language `automatic` resolves to for the current system settings.
    static func resolve(_ language: AppLanguage, preferred: [String] = Locale.preferredLanguages) -> AppLanguage {
        guard language == .automatic else { return language }
        let isChinese = preferred.first?.lowercased().hasPrefix("zh") == true
        return isChinese ? .chineseSimplified : .english
    }
}

/// A single user-visible string in every supported language.
///
/// Storing both variants in one value makes a missing translation a compile error rather than a
/// runtime fallback: there is no way to construct a `LocalizedText` with only one language.
struct LocalizedText: Sendable, Equatable {
    let en: String
    let zh: String

    init(_ en: String, _ zh: String) {
        self.en = en
        self.zh = zh
    }

    func text(in language: AppLanguage) -> String {
        AppLanguage.resolve(language) == .chineseSimplified ? zh : en
    }

    /// The string for the language currently in effect.
    @MainActor
    var current: String {
        text(in: Localization.shared.language)
    }
}

/// Holds the language in effect and republishes changes so SwiftUI views re-render and AppKit
/// menus can be rebuilt when the user switches languages.
@MainActor
final class Localization: ObservableObject {
    static let shared = Localization()

    static let didChangeNotification = Notification.Name("PolishPopLocalizationDidChange")

    @Published private(set) var language: AppLanguage

    private init() {
        language = AppLanguage.resolve(Preferences.language)
    }

    func update(to language: AppLanguage) {
        let resolved = AppLanguage.resolve(language)
        guard resolved != self.language else { return }
        self.language = resolved
        NotificationCenter.default.post(name: Self.didChangeNotification, object: nil)
    }
}
