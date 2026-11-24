import Foundation
import Testing
@testable import SwisswitchCore

private let t0 = Date(timeIntervalSinceReferenceDate: 0)

@Test func unknownAppScoresZero() {
    #expect(UsageStats().score("x", at: t0) == 0)
}

@Test func recordAddsWeight() {
    var stats = UsageStats()
    stats.record("a", at: t0)
    stats.record("a", weight: 0.5, at: t0)
    #expect(stats.score("a", at: t0) == 1.5)
}

@Test func scoreHalvesEachHalfLife() {
    var stats = UsageStats(halfLife: 100)
    stats.record("a", weight: 8, at: t0)
    #expect(abs(stats.score("a", at: t0 + 100) - 4) < 1e-9)
    #expect(abs(stats.score("a", at: t0 + 300) - 1) < 1e-9)
}

@Test func recentUseOutranksOldHabit() {
    var stats = UsageStats(halfLife: 100)
    for _ in 0..<4 { stats.record("old", at: t0) }
    stats.record("new", at: t0 + 250)
    stats.record("new", at: t0 + 250)
    #expect(stats.score("new", at: t0 + 250) > stats.score("old", at: t0 + 250))
}

@Test func pruneDropsFadedEntries() {
    var stats = UsageStats(halfLife: 1)
    stats.record("a", at: t0)
    stats.record("b", at: t0 + 100)
    stats.prune(at: t0 + 100)
    #expect(stats.entries.keys.sorted() == ["b"])
}

@Test func codableRoundTrip() throws {
    var stats = UsageStats(halfLife: 42)
    stats.record("com.apple.Safari", weight: 2, at: t0)
    let data = try JSONEncoder().encode(stats)
    #expect(try JSONDecoder().decode(UsageStats.self, from: data) == stats)
}
