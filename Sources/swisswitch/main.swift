import AppKit
import SwisswitchCore

@MainActor
final class AppController {
    private let hud = SwitchHUD()
    private let preview = AppPreview()
    private let usage = UsageStore()
    private let keys = KeyAssignmentStore()
    private let settings = AppSettings()
    private lazy var settingsWindow = SettingsWindow(
        keys: keys, settings: settings,
        onResetUsage: { [weak self] in
            self?.usage.reset()
            Log.info("learned preferences reset")
        })
    private var statusMenu: StatusMenu?
    private var tap: KeyTap?
    private var onboarding: OnboardingWindow?
    private var debugSignal: DispatchSourceSignal?
    /// Opts out of App Nap: a napped process answers the event tap late, and
    /// since the tap filters every keystroke, that stalls typing system-wide.
    private let activity = ProcessInfo.processInfo.beginActivity(
        options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
        reason: "Global keyboard shortcut tap")

    func start() {
        logSettings()
        statusMenu = StatusMenu(
            onShowApps: { [weak self] in self?.showPreview(autoHide: .seconds(3)) },
            onSettings: { [weak self] in self?.settingsWindow.show() },
            onShowLog: { NSWorkspace.shared.activateFileViewerSelecting([Log.file.fileURL]) })
        usage.start()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.usage.flush()
                Log.info("quitting")
            }
        }
        if AXIsProcessTrusted() {
            startTap()
        } else {
            Log.warning("Accessibility access not granted; showing onboarding")
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            let window = OnboardingWindow()
            onboarding = window
            window.show { [weak self] in
                Log.info("Accessibility access granted")
                self?.startTap()
            }
        }
        installDebugTrigger()
    }

    /// Debug only: with SWISSWITCH_DEBUG_LETTER_FILE set, `kill -USR1 <pid>` switches
    /// using the letter or digit in that file, or shows/hides the preview when the file
    /// says `preview`/`release`. Synthetic keys from automation tools are often
    /// posted straight to a process and never reach the session event tap.
    private func installDebugTrigger() {
        guard let path = ProcessInfo.processInfo.environment["SWISSWITCH_DEBUG_LETTER_FILE"] else { return }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return }
                switch text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
                case "preview": self?.showPreview(); return
                case "release": self?.preview.hide(); return
                default: break
                }
                guard let letter = text.lazy.compactMap(triggerKey(for:)).first else { return }
                self?.switchTo(letter)
            }
        }
        source.resume()
        debugSignal = source
        Log.info("debug trigger on SIGUSR1 (pid \(getpid()), letter file \(path))")
    }

    private func startTap() {
        let tap = KeyTap(
            assignedDigits: keys.assignedDigits,
            holdDelay: { [weak self] in self?.settings.holdDelay ?? .seconds(1) },
            onLetter: { [weak self] letter in self?.switchTo(letter) },
            onHold: { [weak self] down in
                guard let self else { return }
                if down { if self.settings.previewEnabled { self.showPreview() } }
                else { self.preview.hide() }
            })
        guard tap.start() else {
            Log.error("could not create the event tap (Accessibility trusted: \(AXIsProcessTrusted())); exiting")
            exit(1)
        }
        self.tap = tap
        Log.info("event tap running; press Right ⌘ + a letter or digit, hold Right ⌘ to preview")
    }

    private func showPreview(autoHide: Duration? = nil) {
        hud.hide()
        preview.show(AppActivator.switchableApps(usage: usage, keys: keys), autoHide: autoHide)
    }

    private func switchTo(_ letter: Character) {
        preview.hide()
        if let app = AppActivator.activate(key: letter, usage: usage, keys: keys) {
            Log.info("\(letter) → \(app.localizedName ?? "?") (\(UsageStore.id(of: app)))")
            if settings.showHUD {
                hud.show(.app(name: app.localizedName ?? "", icon: app.icon, letter: letter))
            }
        } else {
            Log.info("\(letter) → no running app")
            if settings.showHUD { hud.show(.noMatch(letter: letter)) }
        }
    }

    private func logSettings() {
        Log.info("settings: HUD \(settings.showHUD), preview \(settings.previewEnabled), "
            + "hold delay \(settings.holdDelay), launch at login \(settings.loginStatus.logDescription), "
            + "\(keys.entries.count) key assignment(s)")
    }
}

Log.installExceptionHandler()
Log.launched()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
controller.start()
app.run()
