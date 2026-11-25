import AppKit
import ServiceManagement
import SwiftUI
import SwisswitchCore
import UniformTypeIdentifiers

/// The Settings window: General preferences and per-app trigger keys, as toolbar tabs.
@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private static let width: CGFloat = 500

    private let model: SettingsModel
    private let settings: AppSettings
    private var window: NSWindow?
    private var monitor: Any?
    private var observers: [NSObjectProtocol] = []

    init(keys: KeyAssignmentStore, settings: AppSettings, onResetUsage: @escaping () -> Void) {
        model = SettingsModel(keys: keys, onResetUsage: onResetUsage)
        self.settings = settings
        super.init()
    }

    func show() {
        // Wait for the status menu to stop tracking; activating mid-tracking is often ignored.
        DispatchQueue.main.async { [self] in
            let window = self.window ?? makeWindow()
            model.reload()
            model.accessibilityGranted = AXIsProcessTrusted()
            settings.refreshLogin()
            if !window.isVisible && !window.isMiniaturized { window.center() }
            if monitor == nil { startObserving() }
            if window.isMiniaturized { window.deminiaturize(nil) }
            // Cooperative `activate()` is often refused for an accessory app.
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        }
    }

    func windowWillClose(_ notification: Notification) {
        model.recording = nil
        stopObserving()
    }

    private func makeWindow() -> NSWindow {
        let panes = SettingsPanes(panes: [
            pane("General", symbol: "gearshape", height: 440, GeneralView(settings: settings, model: model)),
            pane("Keys", symbol: "keyboard", height: 560, KeysView(model: model, settings: settings)),
        ])
        let window = NSWindow(contentViewController: panes)
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = self
        panes.install(in: window)
        self.window = window
        return window
    }

    private func pane(_ title: String, symbol: String, height: CGFloat,
                      _ view: some View) -> SettingsPanes.Pane {
        let controller = NSHostingController(rootView: view
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
        controller.sizingOptions = []
        return SettingsPanes.Pane(
            id: NSToolbarItem.Identifier(title), title: title,
            image: NSImage(systemSymbolName: symbol, accessibilityDescription: title),
            size: NSSize(width: Self.width, height: height), controller: controller)
    }

    /// Keeps the app list in sync with launches and quits, and handles keys
    /// for the recorder (and ⌘W, since an accessory app has no main menu).
    private func startObserving() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.model.reload() }
            })
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let swallow = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return swallow ? nil : event
        }
    }

    private func stopObserving() {
        observers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
        observers.removeAll()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    /// Returns true when the event was consumed.
    private func handle(_ event: NSEvent) -> Bool {
        guard event.window === window else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if mods == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
            window?.performClose(nil)
            return true
        }
        return model.record(event)
    }
}

/// Toolbar-tabbed panes, switched the way classic preference windows do it: the old
/// pane leaves, the empty window animates to the new pane's size, then the new pane
/// fades in. No pane is ever laid out, clipped or cross-faded mid-resize.
@MainActor
private final class SettingsPanes: NSViewController, NSToolbarDelegate {
    struct Pane {
        let id: NSToolbarItem.Identifier
        let title: String
        let image: NSImage?
        let size: NSSize
        let controller: NSViewController
    }

    private let panes: [Pane]
    private var current: Pane?

    init(panes: [Pane]) {
        self.panes = panes
        super.init(nibName: nil, bundle: nil)
        panes.forEach { addChild($0.controller) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func loadView() {
        view = NSView(frame: NSRect(origin: .zero, size: panes[0].size))
    }

    func install(in window: NSWindow) {
        let toolbar = NSToolbar(identifier: "SettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        select(panes[0], animated: false)
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let pane = panes.first(where: { $0.id == sender.itemIdentifier }) else { return }
        select(pane, animated: true)
    }

    private func select(_ pane: Pane, animated: Bool) {
        guard let window = view.window, pane.id != current?.id else { return }
        current?.controller.view.removeFromSuperview()
        current = pane
        window.toolbar?.selectedItemIdentifier = pane.id
        window.title = pane.title

        // Grow or shrink from the top edge, keeping the title bar in place.
        let old = window.frame
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: pane.size))
        frame.origin = NSPoint(x: old.minX, y: old.maxY - frame.height)
        window.setFrame(frame, display: true, animate: animated && window.isVisible)

        let content = pane.controller.view
        content.frame = view.bounds
        content.autoresizingMask = [.width, .height]
        view.addSubview(content)
        if animated && window.isVisible {
            content.alphaValue = 0
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                content.animator().alphaValue = 1
            }
        } else {
            content.alphaValue = 1
        }
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.id)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.id)
    }

    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        panes.map(\.id)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let pane = panes.first(where: { $0.id == id }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = pane.title
        item.image = pane.image
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
}

@Observable
@MainActor
final class SettingsModel {
    struct Row: Identifiable {
        let id: String
        let name: String
        let aliases: [String]
        let icon: NSImage?
        let isRunning: Bool
    }

    let keys: KeyAssignmentStore
    @ObservationIgnored let onResetUsage: () -> Void
    private(set) var rows: [Row] = []
    /// The row whose key is being recorded.
    var recording: String?
    var search = ""
    var confirmResetKeys = false
    var confirmResetUsage = false
    var accessibilityGranted = false
    /// Apps picked with "Add App…" that have no assignment yet.
    @ObservationIgnored private var added: [String: URL] = [:]

    init(keys: KeyAssignmentStore, onResetUsage: @escaping () -> Void) {
        self.keys = keys
        self.onResetUsage = onResetUsage
    }

    var filteredRows: [Row] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return rows }
        return rows.filter {
            $0.name.localizedStandardContains(query) || $0.id.localizedStandardContains(query)
                || $0.aliases.contains { $0.localizedStandardContains(query) }
        }
    }

    /// Running regular apps plus any app with a saved or pending assignment.
    func reload() {
        var byID: [String: Row] = [:]
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular && !app.isTerminated {
            guard let name = app.localizedName else { continue }
            let id = UsageStore.id(of: app)
            guard byID[id] == nil else { continue }
            byID[id] = Row(id: id, name: name,
                           aliases: app.bundleURL.map(AppActivator.aliases(ofBundleAt:)) ?? [],
                           icon: app.icon, isRunning: true)
        }
        for id in Set(keys.entries.keys).union(added.keys) where byID[id] == nil {
            if let url = added[id] ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                byID[id] = Row(id: id, name: FileManager.default.displayName(atPath: url.path)
                                   .replacing(/\.app$/, with: ""),
                               aliases: AppActivator.aliases(ofBundleAt: url),
                               icon: NSWorkspace.shared.icon(forFile: url.path), isRunning: false)
            } else {
                byID[id] = Row(id: id, name: id, aliases: [], icon: nil, isRunning: false)
            }
        }
        rows = byID.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func candidate(_ row: Row) -> AppCandidate {
        AppCandidate(name: row.name, id: row.id, aliases: row.aliases, pid: 0, isFrontmost: false,
                     assignment: keys.assignment(for: row.id))
    }

    func set(_ assignment: KeyAssignment, for row: Row) {
        keys.set(assignment, for: row.id)
        if recording == row.id { recording = nil }
    }

    func toggleRecording(_ row: Row) {
        recording = recording == row.id ? nil : row.id
    }

    /// Handles a key press while recording. Returns true when consumed.
    func record(_ event: NSEvent) -> Bool {
        guard let id = recording else { return false }
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        if !mods.isEmpty {
            recording = nil
            return false
        }
        switch event.keyCode {
        case 53: // Esc
            recording = nil
        case 51, 117: // Delete, Forward Delete
            keys.set(.none, for: id)
            recording = nil
        default:
            guard let char = event.charactersIgnoringModifiers?.lowercased().first, char.isASCII,
                  let key = triggerKey(for: char)
            else {
                NSSound.beep()
                return true
            }
            keys.set(.key(key), for: id)
            recording = nil
        }
        return true
    }

    func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let id = Bundle(url: url)?.bundleIdentifier
        else { return }
        added[id] = url
        search = ""
        reload()
        recording = id
    }

    func resetAllKeys() {
        recording = nil
        keys.reset()
        reload()
    }
}

// MARK: - General

private struct GeneralView: View {
    @Bindable var settings: AppSettings
    @Bindable var model: SettingsModel

    var body: some View {
        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
                    .disabled(!settings.canLaunchAtLogin)
            } footer: {
                loginFooter
            }

            Section {
                Picker("Trigger key", selection: $settings.triggerKey) {
                    ForEach(TriggerKey.allCases) { Text($0.name).tag($0) }
                }
                Toggle("Show app name when switching", isOn: $settings.showHUD)
                Toggle("Hold \(settings.triggerKey.name) to preview apps", isOn: $settings.previewEnabled)
                Picker("Preview delay", selection: $settings.previewDelay) {
                    ForEach(AppSettings.previewDelays, id: \.self) { delay in
                        Text("\(delay.formatted()) s").tag(delay)
                    }
                }
                .disabled(!settings.previewEnabled)
            } header: {
                Text("Switching")
            } footer: {
                if let caveat = settings.triggerKey.caveat {
                    Text(caveat).foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent {
                    Button("Reset…") { model.confirmResetUsage = true }
                } label: {
                    Text("Learned preferences")
                    Text("Among apps sharing a key, the ones you use most come first.")
                }
                LabeledContent("Accessibility") {
                    if model.accessibilityGranted {
                        Label("Granted", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button("Open System Settings") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog("Reset learned preferences?", isPresented: $model.confirmResetUsage) {
            Button("Reset", role: .destructive) { model.onResetUsage() }
        } message: {
            Text("Apps sharing a key go back to alphabetical order until swisswitch relearns your habits.")
        }
    }

    @ViewBuilder
    private var loginFooter: some View {
        if !settings.canLaunchAtLogin {
            Text("Available when running Swisswitch.app.").foregroundStyle(.secondary)
        } else if let error = settings.loginError {
            Text(error).foregroundStyle(.red)
        } else if settings.loginStatus == .requiresApproval {
            HStack {
                Text("Approve Swisswitch in Login Items to finish.").foregroundStyle(.secondary)
                Spacer()
                Button("Open Login Items…") { SMAppService.openSystemSettingsLoginItems() }
                    .controlSize(.small)
            }
        }
    }
}

// MARK: - Keys

private struct KeysView: View {
    @Bindable var model: SettingsModel
    let settings: AppSettings

    var body: some View {
        let rows = model.filteredRows
        // The header sits above the scroll view (not as a safe-area inset), so the list
        // scrolls only beneath its own top edge and never shows through the header.
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    TextField("Search", text: $model.search, prompt: Text("Search apps"))
                        .textFieldStyle(.roundedBorder)
                    Button("Add App…", systemImage: "plus") { model.addApp() }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Add an app that isn't running")
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(model.recording != nil
                         ? "Press a letter or digit · ⌫ No key · esc Cancel"
                         : "\(settings.triggerKey.name) + key switches apps. Apps sharing a key take turns.")
                        .font(.callout)
                        .foregroundStyle(model.recording != nil ? Color.accentColor : .secondary)
                    Spacer()
                    Button("Reset All…") { model.confirmResetKeys = true }
                        .controlSize(.small)
                        .disabled(model.keys.entries.isEmpty)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Divider()

            Form {
                Section {
                    if rows.isEmpty {
                        Text(model.search.isEmpty ? "No apps" : "No matching apps")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(rows) { KeyRow(model: model, row: $0) }
                }
            }
            .formStyle(.grouped)
        }
        .confirmationDialog("Reset all trigger keys to their defaults?", isPresented: $model.confirmResetKeys) {
            Button("Reset All", role: .destructive) { model.resetAllKeys() }
        }
    }
}

private struct KeyRow: View {
    let model: SettingsModel
    let row: SettingsModel.Row

    var body: some View {
        let candidate = model.candidate(row)

        HStack(spacing: 10) {
            HStack(spacing: 10) {
                Group {
                    if let icon = row.icon {
                        Image(nsImage: icon).resizable().interpolation(.high)
                    } else {
                        Image(systemName: "app.dashed").resizable().foregroundStyle(.secondary)
                    }
                }
                .frame(width: 20, height: 20)
                Text(row.name).lineLimit(1).truncationMode(.tail)
                if let status = status(candidate) {
                    Text(status).font(.caption).foregroundStyle(.secondary)
                }
            }
            .opacity(row.isRunning ? 1 : 0.55)

            Spacer(minLength: 8)

            if candidate.assignment != .automatic {
                Button("Use Default", systemImage: "arrow.uturn.backward") {
                    model.set(.automatic, for: row)
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .controlSize(.small)
                .foregroundStyle(.secondary)
                .help(candidate.defaultKey.map { "Use default (\(String($0).uppercased()))" } ?? "Use default (none)")
            }

            KeyCap(candidate: candidate, isRecording: model.recording == row.id) {
                model.toggleRecording(row)
            }
        }
        .contextMenu {
            Button(candidate.defaultKey.map { "Use Default (\(String($0).uppercased()))" } ?? "Use Default (None)") {
                model.set(.automatic, for: row)
            }
            Button("No Key") { model.set(.none, for: row) }
        }
    }

    private func status(_ candidate: AppCandidate) -> String? {
        switch candidate.assignment {
        case .key: "Custom"
        case .none: "No key"
        case .automatic: row.isRunning ? nil : "Not running"
        }
    }
}

/// A small keyboard-key cap showing the app's key. Click to record a new one.
private struct KeyCap: View {
    let candidate: AppCandidate
    let isRecording: Bool
    let action: () -> Void

    var body: some View {
        let isCustom = candidate.assignment != .automatic
        let tint: Color = isRecording ? .accentColor : isCustom ? .accentColor.opacity(0.3) : .clear

        Button(action: action) {
            Group {
                if isRecording {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white)
                        .phaseAnimator([0.4, 1]) { content, phase in
                            content.opacity(phase)
                        } animation: { _ in .easeInOut(duration: 0.6) }
                } else if let key = candidate.triggerKey {
                    Text(String(key).uppercased())
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                } else {
                    Text("–")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 30, height: 22)
            .contentShape(.rect(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(tint).interactive(), in: .rect(cornerRadius: 6))
        .help("Click, then press a letter or digit")
    }
}
