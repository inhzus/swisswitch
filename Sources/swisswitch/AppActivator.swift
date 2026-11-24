import AppKit
import SwisswitchCore

/// A running app paired with its matcher candidate.
struct SwitchableApp {
    let app: NSRunningApplication
    let candidate: AppCandidate
}

/// Finds the running app for a letter and brings it to the front. Never launches apps.
@MainActor
enum AppActivator {
    /// Regular running apps, scored by learned preference.
    static func switchableApps(usage: UsageStore) -> [SwitchableApp] {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.localizedName != nil && !$0.isTerminated }
            .map { app in
                SwitchableApp(app: app, candidate: AppCandidate(
                    name: app.localizedName!, id: UsageStore.id(of: app), aliases: aliases(of: app),
                    pid: app.processIdentifier, isFrontmost: app.processIdentifier == frontPID,
                    score: usage.score(of: app)))
            }
    }

    static func activate(letter: Character, usage: UsageStore) -> NSRunningApplication? {
        let apps = switchableApps(usage: usage)
        guard let pick = pickApp(for: letter, among: apps.map(\.candidate)),
              let app = apps.first(where: { $0.candidate.pid == pick.pid })?.app
        else { return nil }

        usage.noteSwitch(to: app)
        if app.isHidden { app.unhide() }
        if !app.activate(options: .activateAllWindows) {
            // Cooperative activation can refuse a background app's request.
            // Opening an already-running app's bundle just brings it forward.
            if let url = app.bundleURL {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        }
        return app
    }

    /// Non-localized names, so "访达" is still reachable as Finder.
    private static func aliases(of app: NSRunningApplication) -> [String] {
        guard let url = app.bundleURL else { return [] }
        var names = [url.deletingPathExtension().lastPathComponent]
        if let name = Bundle(url: url)?.infoDictionary?["CFBundleName"] as? String {
            names.append(name)
        }
        return names
    }
}
