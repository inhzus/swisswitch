import Foundation

/// How an app's trigger key is chosen.
public enum KeyAssignment: Equatable, Sendable {
    /// The name's initial (see `AppCandidate.defaultKey`).
    case automatic
    /// A user-chosen key, a–z or 0–9.
    case key(Character)
    /// Not reachable by any key.
    case none
}

/// Every key that can trigger a switch, in display order.
public let triggerKeys: [Character] = Array("abcdefghijklmnopqrstuvwxyz0123456789")

/// The normalized trigger key for `character`, or nil if it can't be one.
public func triggerKey(for character: Character) -> Character? {
    guard let key = initial(of: String(character)), key.isASCII, key.isLetter || key.isNumber
    else { return nil }
    return key
}

/// The trigger key a keyboard key types, given its unmodified output: only an
/// exact ASCII letter or digit (lowercased). Unlike `triggerKey(for:)`, accents
/// are not folded: on a layout with an é key, that key is not the E key.
public func triggerKey(typed: String) -> Character? {
    let lowered = typed.lowercased()
    guard lowered.count == 1, let key = lowered.first, key.isASCII, key.isLetter || key.isNumber
    else { return nil }
    return key
}

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
    public let assignment: KeyAssignment

    public init(name: String, id: String? = nil, aliases: [String] = [], pid: pid_t,
                isFrontmost: Bool, score: Double = 0, assignment: KeyAssignment = .automatic) {
        self.name = name
        self.id = id ?? name
        self.aliases = aliases
        self.pid = pid
        self.isFrontmost = isFrontmost
        self.score = score
        self.assignment = assignment
    }

    /// The automatic letter: the name's initial if that is a–z, otherwise the
    /// first alias's (e.g. "访达" → Finder). So "Google Chrome" isn't also
    /// reachable through "Chrome", nor "飞书" through both Feishu and Lark.
    public var defaultKey: Character? {
        Self.defaultKey(name: name, aliases: aliases)
    }

    public static func defaultKey(name: String, aliases: [String]) -> Character? {
        guard let first = initial(of: name) else { return nil }
        if first.isASCII && first.isLetter { return first }
        return aliases.first.flatMap(initial(of:)).flatMap { $0.isASCII && $0.isLetter ? $0 : nil }
    }

    /// The single key this app answers to, after any user assignment.
    public var triggerKey: Character? {
        switch assignment {
        case .automatic: defaultKey
        case .key(let key): SwisswitchCore.triggerKey(for: key)
        case .none: nil
        }
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

/// Apps triggered by `letter` (a letter or digit), in press order.
public func matches(for letter: Character, among candidates: [AppCandidate]) -> [AppCandidate] {
    guard let key = triggerKey(for: letter) else { return [] }
    return candidates.filter { $0.triggerKey == key }.sorted(by: preferenceOrder)
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

/// Every key (a–z, then 0–9) that has apps, each with its apps in press order.
public func groupedApps(_ candidates: [AppCandidate]) -> [(letter: Character, apps: [AppCandidate])] {
    triggerKeys.compactMap { letter in
        let apps = matches(for: letter, among: candidates)
        return apps.isEmpty ? nil : (letter, apps)
    }
}
