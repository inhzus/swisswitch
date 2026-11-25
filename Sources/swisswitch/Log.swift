import Foundation
import os
import SwisswitchCore

/// App-wide logging. Each message goes to
/// `~/Library/Application Support/swisswitch/logs/swisswitch.log` (1 MB per file,
/// 3 rolled-over archives kept), to the unified log (`log stream --predicate
/// 'subsystem == "io.zunish.Swisswitch"'`), and to stderr when run from a terminal.
/// SWISSWITCH_LOG_FILE points the file at another path.
enum Log {
    static let file = RollingLog(
        fileURL: .swisswitchSupportFile("logs/swisswitch.log", override: "SWISSWITCH_LOG_FILE"),
        maxBytes: 1 << 20, maxArchives: 3)

    private static let system = Logger(subsystem: "io.zunish.Swisswitch", category: "app")
    private static let toTerminal = isatty(STDERR_FILENO) != 0

    static func info(_ message: String) { write(.info, message) }
    static func warning(_ message: String) { write(.warning, message) }
    static func error(_ message: String) { write(.error, message) }

    private static func write(_ level: LogLevel, _ message: String) {
        file.write(level, message)
        switch level {
        // `.notice`, not `.info`: info messages aren't persisted and `log stream`
        // hides them by default.
        case .info: system.notice("\(message, privacy: .public)")
        case .warning: system.warning("\(message, privacy: .public)")
        case .error: system.error("\(message, privacy: .public)")
        }
        if toTerminal {
            FileHandle.standardError.write(Data("[swisswitch] \(level.rawValue) \(message)\n".utf8))
        }
    }

    /// Logs the version, process and OS this run started with.
    static func launched() {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "dev"
        let build = info["CFBundleVersion"] as? String ?? "-"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        Log.info("launched swisswitch \(version) (\(build)), pid \(getpid()), macOS \(os), "
            + "at \(Bundle.main.bundlePath)")
    }

    /// Logs Objective-C exceptions that would otherwise only reach the crash report.
    static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            Log.error("uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + exception.callStackSymbols.joined(separator: "\n"))
        }
    }
}
