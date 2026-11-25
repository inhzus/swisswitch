import Foundation
import Observation
import os
import SwisswitchCore

/// User-chosen trigger keys per app, kept in the app's defaults plist as
/// `keyAssignments: [bundleID: key]`, where "" means no key and a missing
/// entry means automatic.
@Observable
@MainActor
final class KeyAssignmentStore {
    private static let defaultsKey = "keyAssignments"

    /// Digits some app is assigned, readable from the event-tap thread.
    nonisolated let assignedDigits = OSAllocatedUnfairLock<Set<Character>>(initialState: [])

    private(set) var entries: [String: String]
    @ObservationIgnored private let defaults: UserDefaults

    init() {
        defaults = .swisswitch
        entries = defaults.dictionary(forKey: Self.defaultsKey) as? [String: String] ?? [:]
        publishDigits()
    }

    func assignment(for id: String) -> KeyAssignment {
        guard let value = entries[id] else { return .automatic }
        guard let char = value.first, let key = triggerKey(for: char) else { return .none }
        return .key(key)
    }

    func set(_ assignment: KeyAssignment, for id: String) {
        switch assignment {
        case .automatic: entries[id] = nil
        case .none: entries[id] = ""
        case .key(let key):
            guard let key = triggerKey(for: key) else { return }
            entries[id] = String(key)
        }
        Log.info("key assignment: \(id) → \(assignment.logDescription)")
        save()
    }

    func reset() {
        entries.removeAll()
        Log.info("key assignments reset")
        save()
    }

    private func save() {
        if entries.isEmpty {
            defaults.removeObject(forKey: Self.defaultsKey)
        } else {
            defaults.set(entries, forKey: Self.defaultsKey)
        }
        publishDigits()
    }

    private func publishDigits() {
        let digits = Set(entries.values.compactMap(\.first).filter(\.isNumber))
        assignedDigits.withLock { $0 = digits }
    }
}

extension KeyAssignment {
    var logDescription: String {
        switch self {
        case .automatic: "automatic"
        case .none: "none"
        case .key(let key): String(key)
        }
    }
}
