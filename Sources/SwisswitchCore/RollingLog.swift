import Foundation

public enum LogLevel: String, Sendable {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

/// An append-only text log that rolls over by size. When the next line would push
/// the file past `maxBytes`, `name.log` becomes `name.1.log`, older archives shift
/// up by one, and the one past `maxArchives` is deleted, so the logs never take more
/// than about `maxBytes * (maxArchives + 1)` on disk.
///
/// Thread-safe. Each line goes straight to disk, so it survives a crash.
public final class RollingLog: @unchecked Sendable {
    public let fileURL: URL
    public let maxBytes: Int
    public let maxArchives: Int

    private let lock = NSLock()
    private var handle: FileHandle?
    private var size = 0
    private let timestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = .current
        return formatter
    }()

    public init(fileURL: URL, maxBytes: Int = 1 << 20, maxArchives: Int = 3) {
        precondition(maxBytes > 0 && maxArchives >= 0)
        self.fileURL = fileURL
        self.maxBytes = maxBytes
        self.maxArchives = maxArchives
    }

    deinit { try? handle?.close() }

    /// `name.<index>.log` next to the live file.
    public func archiveURL(_ index: Int) -> URL {
        let ext = fileURL.pathExtension
        let base = fileURL.deletingPathExtension().lastPathComponent
        let name = ext.isEmpty ? "\(base).\(index)" : "\(base).\(index).\(ext)"
        return fileURL.deletingLastPathComponent().appending(path: name)
    }

    /// Appends one timestamped line.
    public func write(_ level: LogLevel, _ message: String, at date: Date = Date()) {
        lock.withLock {
            let line = "\(timestamp.string(from: date)) [\(level.rawValue)] \(message)\n"
            let data = Data(line.utf8)
            if handle == nil { open() }
            if size > 0 && size + data.count > maxBytes { rotate() }
            guard let handle else { return }
            do {
                try handle.write(contentsOf: data)
                size += data.count
            } catch {
                // Reopen on the next write, e.g. after the folder was deleted.
                try? handle.close()
                self.handle = nil
            }
        }
    }

    private func open() {
        let fm = FileManager.default
        try? fm.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if !fm.fileExists(atPath: fileURL.path) {
            fm.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        size = Int((try? handle.seekToEnd()) ?? 0)
        self.handle = handle
    }

    private func rotate() {
        try? handle?.close()
        handle = nil
        let fm = FileManager.default
        if maxArchives == 0 {
            try? fm.removeItem(at: fileURL)
        } else {
            try? fm.removeItem(at: archiveURL(maxArchives))
            for index in stride(from: maxArchives - 1, through: 1, by: -1) {
                try? fm.moveItem(at: archiveURL(index), to: archiveURL(index + 1))
            }
            try? fm.moveItem(at: fileURL, to: archiveURL(1))
        }
        open()
    }
}
