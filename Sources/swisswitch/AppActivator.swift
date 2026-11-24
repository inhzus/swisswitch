import AppKit
import SwisswitchCore

/// Finds the running app for a letter and brings it to the front. Never launches apps.
@MainActor
enum AppActivator {
    static func activate(letter: Character) -> NSRunningApplication? {
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let running = NSWorkspace.shared.runningApplications.filter {
            $0.activationPolicy == .regular && $0.localizedName != nil && !$0.isTerminated
        }
        let candidates = running.map {
            AppCandidate(name: $0.localizedName!, aliases: aliases(of: $0),
                         pid: $0.processIdentifier,
                         isFrontmost: $0.processIdentifier == frontPID)
        }
        guard let pick = pickApp(for: letter, among: candidates),
              let app = running.first(where: { $0.processIdentifier == pick.pid })
        else { return nil }

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
