import Foundation
import Observation
import os
import ServiceManagement

extension UserDefaults {
    /// swisswitch's preferences domain. The bundled app uses its own; unbundled
    /// (`swift run`) shares the bundled app's plist. SWISSWITCH_DEFAULTS_SUITE overrides.
    nonisolated(unsafe) static let swisswitch: UserDefaults = {
        if let suite = ProcessInfo.processInfo.environment["SWISSWITCH_DEFAULTS_SUITE"] {
            return UserDefaults(suiteName: suite) ?? .standard
        }
        if Bundle.main.bundleIdentifier != nil { return .standard }
        return UserDefaults(suiteName: "io.zunish.Swisswitch") ?? .standard
    }()
}

/// General preferences shown in Settings → General.
@Observable
@MainActor
final class AppSettings {
    static let previewDelays: [Double] = [0.5, 0.75, 1, 1.5, 2]

    private enum Key {
        static let showHUD = "showHUD"
        static let previewEnabled = "previewEnabled"
        static let previewDelay = "previewDelay"
        static let triggerKey = "triggerKey"
    }

    @ObservationIgnored private let defaults = UserDefaults.swisswitch

    /// Show the switch HUD after each switch.
    var showHUD: Bool { didSet { persist(showHUD, Key.showHUD) } }
    /// Show the app preview while the trigger key is held alone.
    var previewEnabled: Bool { didSet { persist(previewEnabled, Key.previewEnabled) } }
    /// Seconds the trigger key must be held before the preview appears.
    var previewDelay: Double { didSet { persist(previewDelay, Key.previewDelay) } }
    /// The modifier that, with a letter or digit, switches apps.
    var triggerKey: TriggerKey {
        didSet {
            persist(triggerKey.rawValue, Key.triggerKey)
            let trigger = triggerKey
            triggerState.withLock { $0 = trigger }
        }
    }
    /// `triggerKey`, mirrored for the event tap thread.
    @ObservationIgnored let triggerState: OSAllocatedUnfairLock<TriggerKey>

    /// Login-item state, refreshed from the system.
    private(set) var loginStatus: SMAppService.Status = .notRegistered
    private(set) var loginError: String?

    init() {
        showHUD = defaults.object(forKey: Key.showHUD) as? Bool ?? true
        previewEnabled = defaults.object(forKey: Key.previewEnabled) as? Bool ?? true
        previewDelay = defaults.object(forKey: Key.previewDelay) as? Double ?? 1
        let trigger = defaults.string(forKey: Key.triggerKey).flatMap(TriggerKey.init) ?? .default
        triggerState = OSAllocatedUnfairLock(initialState: trigger)
        triggerKey = trigger
        refreshLogin()
    }

    private func persist(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
        Log.info("setting: \(key) = \(value)")
    }

    /// The hold delay, with SWISSWITCH_HOLD_MS winning for debugging.
    var holdDelay: Duration {
        if let ms = ProcessInfo.processInfo.environment["SWISSWITCH_HOLD_MS"].flatMap(Int.init) {
            return .milliseconds(ms)
        }
        return .milliseconds(Int(previewDelay * 1000))
    }

    /// Login items need a real app bundle.
    var canLaunchAtLogin: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    var launchAtLogin: Bool {
        get { loginStatus == .enabled || loginStatus == .requiresApproval }
        set {
            loginError = nil
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                loginError = error.localizedDescription
                Log.error("could not \(newValue ? "register" : "unregister") login item: \(error)")
            }
            refreshLogin()
            Log.info("launch at login: \(loginStatus.logDescription)")
        }
    }

    func refreshLogin() {
        loginStatus = SMAppService.mainApp.status
    }
}

extension SMAppService.Status {
    var logDescription: String {
        switch self {
        case .notRegistered: "not registered"
        case .enabled: "enabled"
        case .requiresApproval: "requires approval"
        case .notFound: "not found"
        @unknown default: "status \(rawValue)"
        }
    }
}
