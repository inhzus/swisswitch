import AppKit

@MainActor
final class AppController {
    private let hud = SwitchHUD()
    private var tap: KeyTap?
    private var onboarding: OnboardingWindow?
    private var debugSignal: DispatchSourceSignal?

    func start() {
        if AXIsProcessTrusted() {
            startTap()
        } else {
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            let window = OnboardingWindow()
            onboarding = window
            window.show { [weak self] in self?.startTap() }
        }
        installDebugTrigger()
    }

    /// Debug only: with SWISSWITCH_DEBUG_LETTER_FILE set, `kill -USR1 <pid>` switches
    /// using the letter in that file. Synthetic keys from automation tools are often
    /// posted straight to a process and never reach the session event tap.
    private func installDebugTrigger() {
        guard let path = ProcessInfo.processInfo.environment["SWISSWITCH_DEBUG_LETTER_FILE"] else { return }
        signal(SIGUSR1, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGUSR1, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let text = try? String(contentsOfFile: path, encoding: .utf8),
                      let letter = text.lowercased().first(where: { $0.isASCII && $0.isLetter })
                else { return }
                self?.switchTo(letter)
            }
        }
        source.resume()
        debugSignal = source
        log("debug trigger on SIGUSR1 (pid \(getpid()), letter file \(path))")
    }

    private func startTap() {
        let tap = KeyTap { [weak self] letter in self?.switchTo(letter) }
        guard tap.start() else {
            log("could not create the event tap; is Accessibility access granted?")
            exit(1)
        }
        self.tap = tap
        log("running; press Right ⌘ + a letter (Ctrl-C to quit)")
    }

    private func switchTo(_ letter: Character) {
        if let app = AppActivator.activate(letter: letter) {
            log("\(letter) → \(app.localizedName ?? "?")")
            hud.show(.app(name: app.localizedName ?? "", icon: app.icon, letter: letter))
        } else {
            log("\(letter) → no running app")
            hud.show(.noMatch(letter: letter))
        }
    }

    private func log(_ message: String) {
        print("[swisswitch] \(message)")
        fflush(stdout)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let controller = AppController()
controller.start()
app.run()
