import AppKit
import SwisswitchCore

/// A running app paired with its matcher candidate.
struct SwitchableApp {
    let app: NSRunningApplication
    let candidate: AppCandidate
}

/// Finds the running app for a key and brings it to the front. Never launches apps.
@MainActor
enum AppActivator {
    /// Regular running apps, scored by learned preference, with their key assignments.
    static func switchableApps(usage: UsageStore, keys: KeyAssignmentStore) -> [SwitchableApp] {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.localizedName != nil && !$0.isTerminated }
            .map { app in
                SwitchableApp(app: app, candidate: AppCandidate(
                    name: app.localizedName!, id: UsageStore.id(of: app), aliases: aliases(of: app),
                    pid: app.processIdentifier, isFrontmost: app.processIdentifier == frontPID,
                    score: usage.score(of: app),
                    assignment: keys.assignment(for: UsageStore.id(of: app))))
            }
    }

    static func activate(key: Character, usage: UsageStore, keys: KeyAssignmentStore) -> NSRunningApplication? {
        let apps = switchableApps(usage: usage, keys: keys)
        guard let pick = pickApp(for: key, among: apps.map(\.candidate)),
              let app = apps.first(where: { $0.candidate.pid == pick.pid })?.app
        else { return nil }

        usage.noteSwitch(to: app)
        if app.isHidden { app.unhide() }
        if !app.activate(options: .activateAllWindows) {
            // Cooperative activation can refuse a background app's request.
            // Opening an already-running app's bundle just brings it forward.
            let name = app.localizedName ?? "?"
            guard let url = app.bundleURL else {
                Log.warning("activating \(name) was refused and it has no bundle to open")
                return app
            }
            Log.info("activating \(name) was refused; opening its bundle instead")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: config) { _, error in
                if let error { Log.error("could not open \(url.path): \(error)") }
            }
        }
        return app
    }

    /// The non-localized name, so "访达" is still reachable as Finder. Only one,
    /// so an app gets a single letter: CFBundleName ("Feishu") wins over the
    /// bundle file name ("Lark.app").
    private static func aliases(of app: NSRunningApplication) -> [String] {
        app.bundleURL.map(aliases(ofBundleAt:)) ?? []
    }

    static func aliases(ofBundleAt url: URL) -> [String] {
        let bundleName = Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String
        return [bundleName ?? url.deletingPathExtension().lastPathComponent]
    }
}
