import Foundation

/// Learned app preference as an exponentially decayed usage counter ("frecency").
///
/// Each use adds its weight; every `halfLife` without use halves the score, so the
/// number reflects both how often and how recently an app was chosen.
public struct UsageStats: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var score: Double
        public var updated: Date
    }

    public static let defaultHalfLife: TimeInterval = 7 * 24 * 3600

    public var halfLife: TimeInterval
    public private(set) var entries: [String: Entry]

    public init(halfLife: TimeInterval = UsageStats.defaultHalfLife, entries: [String: Entry] = [:]) {
        self.halfLife = halfLife
        self.entries = entries
    }

    /// The decayed score of `id` at `date` (0 for unknown apps).
    public func score(_ id: String, at date: Date = Date()) -> Double {
        guard let entry = entries[id] else { return 0 }
        return decayed(entry, to: date)
    }

    /// Records one use of `id`.
    public mutating func record(_ id: String, weight: Double = 1, at date: Date = Date()) {
        let current = score(id, at: date)
        entries[id] = Entry(score: current + weight, updated: date)
    }

    /// Drops entries whose decayed score has fallen below `threshold`.
    public mutating func prune(below threshold: Double = 0.01, at date: Date = Date()) {
        entries = entries.filter { decayed($0.value, to: date) >= threshold }
    }

    public mutating func reset() {
        entries.removeAll()
    }

    private func decayed(_ entry: Entry, to date: Date) -> Double {
        let elapsed = max(0, date.timeIntervalSince(entry.updated))
        return entry.score * pow(2, -elapsed / halfLife)
    }
}
