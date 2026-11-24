import AppKit

/// The menu-bar item: preview, permission status, reset and Quit.
@MainActor
final class StatusMenu: NSObject, NSMenuDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let accessItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let onShowApps: () -> Void
    private let onReset: () -> Void

    init(onShowApps: @escaping () -> Void, onReset: @escaping () -> Void) {
        self.onShowApps = onShowApps
        self.onReset = onReset
        super.init()

        let image = NSImage(systemSymbolName: "command", accessibilityDescription: "swisswitch")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "swisswitch"

        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(withTitle: "Show Apps", action: #selector(showApps), keyEquivalent: "").target = self
        accessItem.isEnabled = false
        menu.addItem(accessItem)
        menu.addItem(withTitle: "Reset Learned Preferences", action: #selector(reset), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit swisswitch", action: #selector(quit), keyEquivalent: "q").target = self
        item.menu = menu
        updateAccess()
    }

    func menuWillOpen(_ menu: NSMenu) {
        updateAccess()
    }

    private func updateAccess() {
        accessItem.title = AXIsProcessTrusted() ? "Accessibility: Granted" : "Accessibility: Not granted"
    }

    @objc private func showApps() { onShowApps() }
    @objc private func reset() { onReset() }
    @objc private func quit() { NSApp.terminate(nil) }
}
