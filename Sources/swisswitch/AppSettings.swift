import Foundation
import Observation
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

    @ObservationIgnored private let defaults = UserDefaults.swisswitch

    /// Show the switch HUD after each switch.
    var showHUD: Bool {
        didSet { defaults.set(showHUD, forKey: "showHUD"); Log.info("setting: HUD \(showHUD)") }
    }
    /// Show the app preview while Right ⌘ is held alone.
    var previewEnabled: Bool {
        didSet {
            defaults.set(previewEnabled, forKey: "previewEnabled")
            Log.info("setting: preview \(previewEnabled)")
        }
    }
    /// Seconds Right ⌘ must be held before the preview appears.
    var previewDelay: Double {
        didSet {
            defaults.set(previewDelay, forKey: "previewDelay")
            Log.info("setting: preview delay \(previewDelay)s")
        }
    }

    /// Login-item state, refreshed from the system.
    private(set) var loginStatus: SMAppService.Status = .notRegistered
    private(set) var loginError: String?

    init() {
        showHUD = defaults.object(forKey: "showHUD") as? Bool ?? true
        previewEnabled = defaults.object(forKey: "previewEnabled") as? Bool ?? true
        previewDelay = defaults.object(forKey: "previewDelay") as? Double ?? 1
        refreshLogin()
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
