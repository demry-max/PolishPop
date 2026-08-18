import AppKit
import SwiftUI

/// Renders the app's screens to PNG files without showing anything on the user's display.
///
/// Used by `--render-ui` to review the interface during development, and to check that both
/// language variants lay out without clipping.
@MainActor
enum UIRenderer {
    struct Screen {
        let name: String
        let size: NSSize
        let makeView: () -> AnyView
    }

    static func renderAll(to directory: URL) throws -> [String] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var written: [String] = []
        for screen in screens() {
            let url = directory.appendingPathComponent("\(screen.name).png")
            try render(screen, to: url)
            written.append(url.lastPathComponent)
        }
        return written
    }

    private static func screens() -> [Screen] {
        var result: [Screen] = []
        for language in [AppLanguage.english, .chineseSimplified] {
            let suffix = language == .english ? "en" : "zh"
            result.append(
                Screen(name: "review-ready-\(suffix)", size: NSSize(width: 760, height: 520)) {
                    AnyView(reviewView(language: language, phase: .ready))
                }
            )
            result.append(
                Screen(name: "review-generating-\(suffix)", size: NSSize(width: 760, height: 520)) {
                    AnyView(reviewView(language: language, phase: .generating))
                }
            )
            for tab in ["general", "writing", "account"] {
                result.append(
                    Screen(name: "settings-\(tab)-\(suffix)", size: NSSize(width: 600, height: 680)) {
                        AnyView(settingsView(language: language, tab: tab))
                    }
                )
            }
        }
        return result
    }

    private static func reviewView(language: AppLanguage, phase: ReviewPhase) -> some View {
        Localization.shared.update(to: language)
        let model = ReviewViewModel()
        let isChinese = language == .chineseSimplified
        model.original = isChinese ? UISamples.originalTextChinese : UISamples.originalText
        model.draft = phase == .generating ? "" : (isChinese ? UISamples.draftTextChinese : UISamples.draftText)
        model.tone = .professional
        model.purpose = .email
        model.generatedTone = .professional
        model.generatedPurpose = .email
        model.targetApplicationName = "Mail"
        model.canReplace = true
        model.showDiff = true
        model.phase = phase
        model.status = phase == .generating ? ReviewStrings.generating : ReviewStrings.reviewFirst
        model.recomputeDiff()

        return ReviewView(
            model: model,
            apply: {},
            copy: {},
            cancel: {},
            regenerate: {},
            stop: {}
        )
    }

    private static func settingsView(language: AppLanguage, tab: String) -> some View {
        Localization.shared.update(to: language)
        let viewModel = SettingsViewModel(
            client: CodexAppServerClient(),
            accessibility: AccessibilityService()
        )
        viewModel.accountState = .signedIn(CodexAccount(email: "you@example.com", planType: "plus"))
        // Pre-populated so the picker renders without the live model/list request firing.
        viewModel.availableModels = ["gpt-5.6-luna", "gpt-5.6-codex"]
        viewModel.defaultModelName = "gpt-5.6-luna"
        viewModel.accessibilityGranted = true
        viewModel.codexAvailable = true
        viewModel.quickReplaceEnabled = true
        viewModel.polishShortcut = .polishDefault
        viewModel.quickShortcut = .quickDefault
        return SettingsView(viewModel: viewModel, initialTab: tab)
    }

    /// Draws into an offscreen window, so no Screen Recording permission and no visible flicker.
    private static func render(_ screen: Screen, to url: URL) throws {
        let hosting = NSHostingView(rootView: screen.makeView())
        hosting.frame = NSRect(origin: .zero, size: screen.size)

        let window = NSWindow(
            contentRect: hosting.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = hosting
        window.layoutIfNeeded()

        // SwiftUI needs a few run-loop turns to size text and instantiate NSTextView children.
        for _ in 0..<40 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        window.layoutIfNeeded()
        hosting.displayIfNeeded()

        guard let representation = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw RenderError.bitmapUnavailable
        }
        hosting.cacheDisplay(in: hosting.bounds, to: representation)
        guard let data = representation.representation(using: .png, properties: [:]) else {
            throw RenderError.encodingFailed
        }
        try data.write(to: url)
    }

    /// Opens the real windows briefly and reports the frames macOS actually gave them.
    ///
    /// Offscreen rendering cannot catch a window that AppKit sizes differently from the view, so
    /// this is the check that the panels come up at usable dimensions.
    static func probeWindowFrames() -> [String] {
        let settings = SettingsWindowController(
            client: CodexAppServerClient(),
            accessibility: AccessibilityService()
        )
        let review = ReviewWindowController()
        settings.show()
        _ = review.showGenerating(
            original: UISamples.originalText,
            tone: .professional,
            purpose: .email,
            targetApplicationName: "Mail",
            canReplace: true,
            near: NSPoint(x: 600, y: 500)
        )

        for _ in 0..<60 {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        return NSApplication.shared.windows.map { window in
            let size = window.frame.size
            let content = window.contentLayoutRect.size
            return "\(window.title.isEmpty ? "(untitled)" : window.title): frame \(Int(size.width))x\(Int(size.height)) content \(Int(content.width))x\(Int(content.height))"
        }
    }

    enum RenderError: Error {
        case bitmapUnavailable
        case encodingFailed
    }
}
