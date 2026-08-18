import AppKit
import Darwin
import Dispatch

@main
enum PolishPopMain {
    static func main() {
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

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)

        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}
