import Foundation

/// A running app that can be switched to.
public struct AppCandidate: Equatable, Sendable {
    /// Display name (usually localized), used for ordering.
    public let name: String
    /// Stable identity for usage stats (bundle ID, or the name as a fallback).
    public let id: String
    /// Fallback names for a non-Latin display name, e.g. "Finder" for "访达".
    /// Only the first is matched on.
    public let aliases: [String]
    public let pid: pid_t
    public let isFrontmost: Bool
    /// Learned preference; higher wins.
    public let score: Double

    public init(name: String, id: String? = nil, aliases: [String] = [], pid: pid_t,
                isFrontmost: Bool, score: Double = 0) {
        self.name = name
        self.id = id ?? name
        self.aliases = aliases
        self.pid = pid
        self.isFrontmost = isFrontmost
        self.score = score
    }

    /// Each app answers to exactly one letter: its name's initial if that is a–z,
    /// otherwise the first alias's (e.g. "访达" → Finder). So "Google Chrome" isn't
    /// also reachable through "Chrome", nor "飞书" through both Feishu and Lark.
    func matches(_ key: Character) -> Bool {
        guard let first = initial(of: name) else { return false }
        if first.isASCII && first.isLetter { return first == key }
        return aliases.first.flatMap(initial(of:)) == key
    }
}

/// Normalized (case- and diacritic-folded) first character of `name`.
func initial(of name: String) -> Character? {
    name.trimmingCharacters(in: .whitespaces)
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        .first
}

/// Orders apps the way presses visit them: highest score first, then by name.
func preferenceOrder(_ a: AppCandidate, _ b: AppCandidate) -> Bool {
    if a.score != b.score { return a.score > b.score }
    let order = a.name.localizedStandardCompare(b.name)
    return order == .orderedSame ? a.pid < b.pid : order == .orderedAscending
}

/// Apps matching `letter`, in press order.
public func matches(for letter: Character, among candidates: [AppCandidate]) -> [AppCandidate] {
    guard let key = initial(of: String(letter)) else { return [] }
    return candidates.filter { $0.matches(key) }.sorted(by: preferenceOrder)
}

/// Picks the app to switch to for `letter`.
///
/// Matches are ordered by learned preference (then name), so one press goes to
/// the app the user picks most. If the frontmost app is one of the matches, the
/// next match (wrapping around) is returned, so repeated presses cycle.
public func pickApp(for letter: Character, among candidates: [AppCandidate]) -> AppCandidate? {
    let matches = matches(for: letter, among: candidates)
    guard !matches.isEmpty else { return nil }
    if let current = matches.firstIndex(where: \.isFrontmost) {
        return matches[(current + 1) % matches.count]
    }
    return matches[0]
}

/// Every letter a–z that has apps, each with its apps in press order.
/// An app can appear under several letters through its aliases.
public func groupedApps(_ candidates: [AppCandidate]) -> [(letter: Character, apps: [AppCandidate])] {
    "abcdefghijklmnopqrstuvwxyz".compactMap { letter in
        let apps = matches(for: letter, among: candidates)
        return apps.isEmpty ? nil : (letter, apps)
    }
}
