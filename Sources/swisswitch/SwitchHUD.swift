import AppKit
import SwiftUI

/// A transient Liquid Glass HUD confirming each switch.
@MainActor
final class SwitchHUD {
    enum Content {
        case app(name: String, icon: NSImage?, letter: Character)
        case noMatch(letter: Character)

        var letter: Character {
            switch self {
            case .app(_, _, let l), .noMatch(let l): l
            }
        }
    }

    private let model = HUDModel()
    private let panel: NSPanel
    private var hideTask: Task<Void, Never>?
    /// How long the HUD stays up; SWISSWITCH_HUD_HOLD_MS overrides it for debugging.
    private let holdTime: Duration = .milliseconds(
        ProcessInfo.processInfo.environment["SWISSWITCH_HUD_HOLD_MS"].flatMap(Int.init) ?? 450)

    init() {
        panel = HUDPanel.make(size: NSSize(width: 560, height: 140))
        let host = NSHostingView(rootView: HUDView(model: model))
        host.sizingOptions = []
        panel.contentView = host
    }

    func show(_ content: Content, trigger: TriggerKey) {
        position()
        panel.orderFrontRegardless()
        model.trigger = trigger
        withAnimation(.spring(duration: 0.35, bounce: 0.3)) {
            model.content = content
            model.serial += 1
        }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: self?.holdTime ?? .zero)
            guard !Task.isCancelled, let self else { return }
            withAnimation(.easeOut(duration: 0.25)) { self.model.content = nil }
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            self.panel.orderOut(nil)
        }
    }

    /// Hides the HUD right away (e.g. when the preview takes over).
    func hide() {
        hideTask?.cancel()
        model.content = nil
        panel.orderOut(nil)
    }

    /// Centers the panel a bit below the middle of the screen holding the pointer.
    private func position() {
        guard let frame = HUDPanel.pointerScreen()?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.midY - frame.height * 0.18 - size.height / 2))
    }
}

/// A transparent, click-through overlay panel that never takes focus.
final class HUDPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    static func make(size: NSSize) -> HUDPanel {
        let panel = HUDPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }

    static func pointerScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}

@Observable
@MainActor
private final class HUDModel {
    var content: SwitchHUD.Content?
    var trigger: TriggerKey = .default
    var serial = 0
}

private struct HUDView: View {
    let model: HUDModel
    @Namespace private var glass

    var body: some View {
        GlassEffectContainer(spacing: 14) {
            if let content = model.content {
                HStack(spacing: 10) {
                    KeyCap(symbol: model.trigger.symbol, letter: content.letter, matched: content.isMatch)
                        .glassEffectID("key", in: glass)
                    label(for: content)
                        .glassEffectID("label", in: glass)
                }
                .transition(.scale(scale: 0.85).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func label(for content: SwitchHUD.Content) -> some View {
        switch content {
        case .app(let name, let icon, _):
            HStack(spacing: 12) {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 40, height: 40)
                }
                Text(name)
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                    .lineLimit(1)
            }
            .padding(.leading, 14)
            .padding(.trailing, 22)
            .frame(height: 64)
            .glassEffect(.regular, in: .capsule)
            .contentTransition(.interpolate)
        case .noMatch:
            Text("No running app")
                .font(.system(size: 19, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 22)
                .frame(height: 64)
                .glassEffect(.regular.tint(.orange.opacity(0.18)), in: .capsule)
        }
    }
}

private struct KeyCap: View {
    let symbol: String
    let letter: Character
    let matched: Bool

    var body: some View {
        HStack(spacing: 2) {
            Text(symbol).font(.system(size: 15, weight: .semibold))
            Text(String(letter).uppercased())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .contentTransition(.numericText())
        }
        .frame(width: 64, height: 64)
        .glassEffect(.regular.tint(matched ? .accentColor.opacity(0.35) : .clear).interactive(false),
                     in: .circle)
    }
}

private extension SwitchHUD.Content {
    var isMatch: Bool {
        if case .app = self { true } else { false }
    }
}
