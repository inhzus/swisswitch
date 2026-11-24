import AppKit
import SwisswitchCore

/// Learns which app the user prefers per letter by watching app activations.
///
/// An activation counts only if the app is still frontmost after `dwell`, so apps
/// merely passed through while cycling don't gain score. Activations reached
/// through swisswitch weigh more than ones from ⌘-Tab, the Dock or clicks.
@MainActor
final class UsageStore {
    private static let dwell: Duration = .milliseconds(1500)
    private static let switchWeight = 1.0
    private static let otherWeight = 0.5

    private(set) var stats: UsageStats
    private let fileURL: URL
    private var observer: NSObjectProtocol?
    private var dwellTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    /// Bundle ID the next activation is expected to come from swisswitch for.
    private var pendingSwitch: String?

    init() {
        if let path = ProcessInfo.processInfo.environment["SWISSWITCH_USAGE_FILE"] {
            fileURL = URL(fileURLWithPath: path)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            fileURL = support.appending(path: "swisswitch/usage.json")
        }
        stats = (try? Data(contentsOf: fileURL))
            .flatMap { data in
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try? decoder.decode(UsageStats.self, from: data)
            } ?? UsageStats()
    }

    func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            let id = app.map(Self.id(of:))
            let pid = app?.processIdentifier
            MainActor.assumeIsolated { self?.activated(id: id, pid: pid) }
        }
    }

    nonisolated static func id(of app: NSRunningApplication) -> String {
        app.bundleIdentifier ?? app.localizedName ?? "pid:\(app.processIdentifier)"
    }

    func score(of app: NSRunningApplication) -> Double {
        stats.score(Self.id(of: app))
    }

    /// Marks that swisswitch is about to activate `app`, so it gets the higher weight.
    func noteSwitch(to app: NSRunningApplication) {
        pendingSwitch = Self.id(of: app)
        // Activating the already-frontmost app posts no notification; count it directly.
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            activated(id: pendingSwitch, pid: app.processIdentifier)
        }
    }

    func reset() {
        stats.reset()
        scheduleSave()
    }

    /// Writes pending changes immediately (used on quit).
    func flush() {
        saveTask?.cancel()
        save()
    }

    private func activated(id: String?, pid: pid_t?) {
        dwellTask?.cancel()
        guard let id, let pid else { return }
        let weight = pendingSwitch == id ? Self.switchWeight : Self.otherWeight
        pendingSwitch = nil
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: Self.dwell)
            guard !Task.isCancelled, let self,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
            self.stats.record(id, weight: weight)
            self.scheduleSave()
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    private func save() {
        var snapshot = stats
        snapshot.prune()
        stats = snapshot
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(snapshot).write(to: fileURL, options: .atomic)
        } catch {
            print("[swisswitch] could not save usage: \(error)")
        }
    }
}
