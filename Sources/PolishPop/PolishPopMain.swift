import AppKit
import Darwin
import Dispatch

@main
enum PolishPopMain {
    static func main() {
        // A write to a Codex subprocess that has already exited must surface as an error, not as
        // a signal that terminates PolishPop.
        signal(SIGPIPE, SIG_IGN)

        if CommandLine.arguments.contains("--self-test") {
            exit(SelfTest.run() ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        if CommandLine.arguments.contains("--codex-smoke-test") {
            Task.detached {
                let client = CodexAppServerClient()
                do {
                    let account = try await client.account()
                    if let account {
                        print("Codex app-server smoke test: initialized; ChatGPT plan = \(account.planType)")
                    } else {
                        print("Codex app-server smoke test: initialized; OAuth account not connected")
                    }
                    await client.stop()
                    exit(EXIT_SUCCESS)
                } catch {
                    fputs("Codex app-server smoke test failed: \(error.localizedDescription)\n", stderr)
                    await client.stop()
                    exit(EXIT_FAILURE)
                }
            }
            dispatchMain()
        }
        if CommandLine.arguments.contains("--polish-smoke-test") {
            Task.detached {
                let client = CodexAppServerClient()
                do {
                    let result = try await client.polish(
                        text: "pls review the attached report and send feedback by friday",
                        tone: .professional,
                        purpose: .email,
                        model: "gpt-5.6-luna"
                    )
                    guard !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw CodexClientError.emptyOutput
                    }
                    print("PolishPop generation smoke test passed")
                    await client.stop()
                    exit(EXIT_SUCCESS)
                } catch {
                    fputs("PolishPop generation smoke test failed: \(error.localizedDescription)\n", stderr)
                    await client.stop()
                    exit(EXIT_FAILURE)
                }
            }
            dispatchMain()
        }

        if CommandLine.arguments.contains("--diagnose") {
            // Must be run from inside the installed bundle: Accessibility trust is granted to a
            // specific binary at a specific path, so asking a different copy proves nothing.
            let accessibility = MainActor.assumeIsolated { AccessibilityService() }
            let trusted = MainActor.assumeIsolated { accessibility.isTrusted }
            print("bundle path:        \(Bundle.main.bundlePath)")
            print("bundle identifier:  \(Bundle.main.bundleIdentifier ?? "(none)")")
            print("version:            \(AppInfo.version)")
            print("accessibility:      \(trusted ? "GRANTED" : "NOT GRANTED")")
            print("sparkle button:     \(Preferences.showSelectionButton ? "on" : "off")")
            print("polish shortcut:    \(Preferences.polishShortcut?.displayString ?? "(cleared)")")
            print("instant replace:    \(Preferences.quickReplaceEnabled ? Preferences.quickShortcut?.displayString ?? "(cleared)" : "off")")
            print("language:           \(AppLanguage.resolve(Preferences.language).rawValue)")
            print("codex cli:          \(CodexAppServerClient.findCodexExecutable()?.path ?? "NOT FOUND")")
            exit(trusted ? EXIT_SUCCESS : EXIT_FAILURE)
        }

        if CommandLine.arguments.contains("--window-probe") {
            let application = NSApplication.shared
            application.setActivationPolicy(.accessory)
            let frames = MainActor.assumeIsolated { UIRenderer.probeWindowFrames() }
            for line in frames {
                print(line)
            }
            exit(EXIT_SUCCESS)
        }

        if let index = CommandLine.arguments.firstIndex(of: "--render-ui"),
           index + 1 < CommandLine.arguments.count {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1])
            let application = NSApplication.shared
            application.setActivationPolicy(.prohibited)
            do {
                let written = try MainActor.assumeIsolated { try UIRenderer.renderAll(to: directory) }
                print("Rendered \(written.count) screens: \(written.joined(separator: ", "))")
                exit(EXIT_SUCCESS)
            } catch {
                fputs("UI render failed: \(error)\n", stderr)
                exit(EXIT_FAILURE)
            }
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
