import Foundation

/// Opt-in launch-time logging, enabled with the `--debug-log` argument.
///
/// Exists because the state that matters cannot be observed from a terminal: macOS attributes
/// Accessibility permission to the process *responsible* for the launch, so a binary started from
/// a shell reports the shell's permission, not its own. Only an app started by LaunchServices can
/// answer the question honestly.
///
/// Never records selected text — only whether a selection was seen and how long it was.
enum Diagnostics {
    static let isEnabled = CommandLine.arguments.contains("--debug-log")

    private static let queue = DispatchQueue(label: "com.demry.polishpop.diagnostics")

    static var logURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else { return nil }
        let directory = base.appendingPathComponent("PolishPop", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("debug.log")
    }

    static func log(_ message: String) {
        guard isEnabled, let logURL else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        let line = "\(stamp)  \(message)\n"
        queue.async {
            guard let data = line.data(using: .utf8) else { return }
            if let handle = try? FileHandle(forWritingTo: logURL) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: logURL)
            }
        }
    }

    static func reset() {
        guard isEnabled, let logURL else { return }
        try? FileManager.default.removeItem(at: logURL)
    }
}
