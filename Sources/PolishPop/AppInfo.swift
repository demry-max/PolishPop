import Foundation

/// Build identity, read from the bundle when the app runs packaged and falling back to a literal
/// for the unbundled binary used by the self-test and UI-render modes.
enum AppInfo {
    static let fallbackVersion = "0.5.0"

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? fallbackVersion
    }
}
