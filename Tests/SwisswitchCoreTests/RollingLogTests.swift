import Foundation
import Testing
import SwisswitchCore

private func tempLog(maxBytes: Int, maxArchives: Int) -> RollingLog {
    let dir = FileManager.default.temporaryDirectory
        .appending(path: "RollingLogTests-\(UUID().uuidString)/nested")
    return RollingLog(fileURL: dir.appending(path: "app.log"), maxBytes: maxBytes, maxArchives: maxArchives)
}

/// Removes the `RollingLogTests-*` folder `tempLog` made.
private func removeTempFolder(of log: RollingLog) {
    try? FileManager.default.removeItem(at: log.fileURL.deletingLastPathComponent().deletingLastPathComponent())
}

private func contents(_ url: URL) -> String? {
    try? String(contentsOf: url, encoding: .utf8)
}

@Test func writesTimestampedLinesAndCreatesFolder() throws {
    let log = tempLog(maxBytes: 1000, maxArchives: 1)
    defer { removeTempFolder(of: log) }
    log.write(.info, "hello")
    log.write(.error, "boom")
    let lines = try #require(contents(log.fileURL)).split(separator: "\n")
    #expect(lines.count == 2)
    #expect(lines[0].hasSuffix(" [INFO] hello"))
    #expect(lines[1].hasSuffix(" [ERROR] boom"))
}

@Test func archiveNamesKeepTheExtension() {
    let log = RollingLog(fileURL: URL(fileURLWithPath: "/x/app.log"))
    #expect(log.archiveURL(2).path == "/x/app.2.log")
}

@Test func rollsOverAndKeepsAtMostMaxArchives() throws {
    let log = tempLog(maxBytes: 100, maxArchives: 2)
    defer { removeTempFolder(of: log) }
    let fm = FileManager.default
    for i in 0..<20 { log.write(.info, "line \(i) " + String(repeating: "x", count: 30)) }

    for url in [log.fileURL, log.archiveURL(1), log.archiveURL(2)] {
        let size = try #require(try fm.attributesOfItem(atPath: url.path)[.size] as? Int)
        #expect(size <= 100)
    }
    #expect(!fm.fileExists(atPath: log.archiveURL(3).path))
    // Each ~77-byte line fills a file, so the newest is live and older ones shift up.
    #expect(try #require(contents(log.fileURL)).contains("line 19 "))
    #expect(try #require(contents(log.archiveURL(1))).contains("line 18 "))
    #expect(try #require(contents(log.archiveURL(2))).contains("line 17 "))
}

@Test func appendsToExistingFileAcrossInstances() throws {
    let first = tempLog(maxBytes: 1000, maxArchives: 1)
    defer { removeTempFolder(of: first) }
    first.write(.info, "one")
    let second = RollingLog(fileURL: first.fileURL, maxBytes: 1000, maxArchives: 1)
    second.write(.warning, "two")
    let text = try #require(contents(first.fileURL))
    #expect(text.contains("[INFO] one") && text.contains("[WARN] two"))
}

@Test func rollsOverAnOversizedFileFromAPreviousRun() throws {
    let first = tempLog(maxBytes: 50, maxArchives: 1)
    defer { removeTempFolder(of: first) }
    first.write(.info, String(repeating: "y", count: 80))
    let second = RollingLog(fileURL: first.fileURL, maxBytes: 50, maxArchives: 1)
    second.write(.info, "fresh")
    #expect(try #require(contents(second.fileURL)).contains("fresh"))
    #expect(try #require(contents(second.archiveURL(1))).contains("yyyy"))
}

@Test func zeroArchivesTruncates() throws {
    let log = tempLog(maxBytes: 60, maxArchives: 0)
    defer { removeTempFolder(of: log) }
    log.write(.info, "first " + String(repeating: "a", count: 30))
    log.write(.info, "second " + String(repeating: "b", count: 30))
    let text = try #require(contents(log.fileURL))
    #expect(!text.contains("first") && text.contains("second"))
    #expect(!FileManager.default.fileExists(atPath: log.archiveURL(1).path))
}
