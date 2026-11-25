import Foundation
import os
import SwisswitchCore

/// App-wide logging. Each message goes to
/// `~/Library/Application Support/swisswitch/logs/swisswitch.log` (1 MB per file,
/// 3 rolled-over archives kept), to the unified log (`log stream --predicate
/// 'subsystem == "io.zunish.Swisswitch"'`), and to stderr when run from a terminal.
/// SWISSWITCH_LOG_FILE points the file at another path.
enum Log {
    static let file: RollingLog = {
        let url: URL
        if let path = ProcessInfo.processInfo.environment["SWISSWITCH_LOG_FILE"] {
            url = URL(fileURLWithPath: path)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            url = support.appending(path: "swisswitch/logs/swisswitch.log")
        }
        return RollingLog(fileURL: url, maxBytes: 1 << 20, maxArchives: 3)
    }()

    private static let system = Logger(subsystem: "io.zunish.Swisswitch", category: "app")
    private static let toTerminal = isatty(STDERR_FILENO) != 0

    static func info(_ message: String) { write(.info, message) }
    static func warning(_ message: String) { write(.warning, message) }
    static func error(_ message: String) { write(.error, message) }

    private static func write(_ level: LogLevel, _ message: String) {
        file.write(level, message)
        switch level {
        case .info: system.info("\(message, privacy: .public)")
        case .warning: system.warning("\(message, privacy: .public)")
        case .error: system.error("\(message, privacy: .public)")
        }
        if toTerminal {
            FileHandle.standardError.write(Data("[swisswitch] \(level.rawValue) \(message)\n".utf8))
        }
    }

    /// Logs Objective-C exceptions that would otherwise only reach the crash report.
    static func installExceptionHandler() {
        NSSetUncaughtExceptionHandler { exception in
            Log.error("uncaught exception \(exception.name.rawValue): \(exception.reason ?? "")\n"
                + exception.callStackSymbols.joined(separator: "\n"))
        }
    }
}
