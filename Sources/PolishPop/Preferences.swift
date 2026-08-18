import Foundation

enum Preferences {
    private enum Key {
        static let model = "openAIModel"
        static let tone = "polishTone"
        static let purpose = "polishPurpose"
    }

    static var model: String {
        get {
            let value = UserDefaults.standard.string(forKey: Key.model)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return value?.isEmpty == false ? value! : "gpt-5.6-luna"
        }
        set { UserDefaults.standard.set(newValue, forKey: Key.model) }
    }

    static var tone: PolishTone {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Key.tone),
                  let tone = PolishTone(rawValue: rawValue) else {
                return .professional
            }
            return tone
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.tone) }
    }

    static var purpose: PolishPurpose {
        get {
            guard let rawValue = UserDefaults.standard.string(forKey: Key.purpose),
                  let purpose = PolishPurpose(rawValue: rawValue) else {
                return .smart
            }
            return purpose
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: Key.purpose) }
    }

}
