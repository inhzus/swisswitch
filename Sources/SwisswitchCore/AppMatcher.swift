import Foundation

/// A running app that can be switched to.
public struct AppCandidate: Equatable, Sendable {
    /// Display name (usually localized), used for ordering.
    public let name: String
    /// Extra names to match on, e.g. the non-localized "Finder" for "访达".
    public let aliases: [String]
    public let pid: pid_t
    public let isFrontmost: Bool

    public init(name: String, aliases: [String] = [], pid: pid_t, isFrontmost: Bool) {
        self.name = name
        self.aliases = aliases
        self.pid = pid
        self.isFrontmost = isFrontmost
    }

    func matches(_ key: Character) -> Bool {
        initial(of: name) == key || aliases.contains { initial(of: $0) == key }
    }
}

/// Normalized (case- and diacritic-folded) first character of `name`.
func initial(of name: String) -> Character? {
    name.trimmingCharacters(in: .whitespaces)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .first
}

/// Picks the app to switch to for `letter`.
///
/// Matches are ordered by name so repeated presses are predictable. If the
/// frontmost app is one of the matches, the next match (wrapping around) is
/// returned, so pressing the same letter cycles through apps sharing it.
public func pickApp(for letter: Character, among candidates: [AppCandidate]) -> AppCandidate? {
    guard let key = initial(of: String(letter)) else { return nil }
    let matches = candidates
        .filter { $0.matches(key) }
        .sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.pid < $1.pid : order == .orderedAscending
        }
    guard !matches.isEmpty else { return nil }
    if let current = matches.firstIndex(where: \.isFrontmost) {
        return matches[(current + 1) % matches.count]
    }
    return matches[0]
}
