import AppKit

/// The menu-bar item: preview, settings, log and Quit.
@MainActor
final class StatusMenu: NSObject {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let onShowApps: () -> Void
    private let onSettings: () -> Void
    private let onShowLog: () -> Void

    init(onShowApps: @escaping () -> Void, onSettings: @escaping () -> Void,
         onShowLog: @escaping () -> Void) {
        self.onShowApps = onShowApps
        self.onSettings = onSettings
        self.onShowLog = onShowLog
        super.init()

        item.button?.image = MenuBarIcon.image()
        item.button?.toolTip = "swisswitch"

        let menu = NSMenu()
        menu.addItem(withTitle: "Show Apps", action: #selector(showApps), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(settings), keyEquivalent: ",").target = self
        menu.addItem(withTitle: "Show Log in Finder", action: #selector(showLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit swisswitch", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
    }

    @objc private func showApps() { onShowApps() }
    @objc private func settings() { onSettings() }
    @objc private func showLog() { onShowLog() }
    @objc private func quit() { NSApp.terminate(nil) }
}
