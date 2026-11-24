import AppKit
import SwiftUI
import SwisswitchCore

/// Liquid Glass overlay listing every switchable app, grouped by key, in the
/// order Right ⌘ + key visits them. Shown while Right ⌘ is held.
@MainActor
final class AppPreview {
    struct Tile: Identifiable {
        struct App: Identifiable {
            let id: pid_t
            let name: String
            let icon: NSImage?
            let isFrontmost: Bool
        }
        var id: Character { letter }
        let letter: Character
        let apps: [App]
    }

    private static let maxIcons = 4

    private let model = PreviewModel()
    private let panel: HUDPanel
    private var hideTask: Task<Void, Never>?

    var isVisible: Bool { model.tiles != nil }

    init() {
        panel = HUDPanel.make(size: NSSize(width: 1200, height: 800))
        let host = NSHostingView(rootView: PreviewView(model: model))
        host.sizingOptions = []
        panel.contentView = host
    }

    /// Shows the preview; with `autoHide`, it fades out on its own after that long.
    func show(_ apps: [SwitchableApp], autoHide: Duration? = nil) {
        let byPID = Dictionary(apps.map { ($0.candidate.pid, $0.app) }, uniquingKeysWith: { a, _ in a })
        let tiles = groupedApps(apps.map(\.candidate)).map { group in
            Tile(letter: group.letter, apps: group.apps.prefix(Self.maxIcons + 1).map {
                Tile.App(id: $0.pid, name: $0.name, icon: byPID[$0.pid]?.icon, isFrontmost: $0.isFrontmost)
            })
        }
        if let frame = HUDPanel.pointerScreen()?.visibleFrame {
            let size = NSSize(width: min(1200, frame.width - 80), height: min(800, frame.height - 80))
            panel.setFrame(NSRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                  width: size.width, height: size.height), display: false)
        }
        hideTask?.cancel()
        panel.orderFrontRegardless()
        withAnimation(.spring(duration: 0.4, bounce: 0.25)) { model.tiles = tiles }
        if let autoHide {
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: autoHide)
                guard !Task.isCancelled else { return }
                self?.hide()
            }
        }
    }

    func hide() {
        hideTask?.cancel()
        guard model.tiles != nil else { return }
        withAnimation(.easeOut(duration: 0.2)) { model.tiles = nil }
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self?.panel.orderOut(nil)
        }
    }
}

@Observable
@MainActor
private final class PreviewModel {
    var tiles: [AppPreview.Tile]?
}

private struct PreviewView: View {
    let model: PreviewModel

    var body: some View {
        ZStack {
            if let tiles = model.tiles {
                GlassEffectContainer(spacing: 12) {
                    VStack(spacing: 18) {
                        Text(tiles.isEmpty ? "No running apps" : "Right ⌘ + key")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .frame(height: 32)
                            .glassEffect(.regular, in: .capsule)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 200), spacing: 12)],
                                  spacing: 12) {
                            ForEach(tiles) { TileView(tile: $0) }
                        }
                    }
                    .padding(24)
                }
                .transition(.scale(scale: 0.92).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct TileView: View {
    let tile: AppPreview.Tile
    private static let maxIcons = 4

    var body: some View {
        let shown = Array(tile.apps.prefix(Self.maxIcons))
        let extra = tile.apps.count - shown.count
        HStack(spacing: 10) {
            Text(String(tile.letter).uppercased())
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .frame(width: 40, height: 40)
                .glassEffect(.regular.tint(.accentColor.opacity(0.35)), in: .circle)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, app in
                        AppIcon(app: app, primary: index == 0)
                    }
                    if extra > 0 {
                        Text("+\(extra)")
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                }
                Text(shown.first?.name ?? "")
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(height: 76)
        .glassEffect(.regular, in: .rect(cornerRadius: 22))
    }
}

private struct AppIcon: View {
    let app: AppPreview.Tile.App
    let primary: Bool

    var body: some View {
        let size: CGFloat = primary ? 34 : 24
        Group {
            if let icon = app.icon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").resizable()
            }
        }
        .frame(width: size, height: size)
        .opacity(primary ? 1 : 0.75)
        .overlay(alignment: .bottom) {
            if app.isFrontmost {
                Circle().fill(.primary).frame(width: 4, height: 4).offset(y: 5)
            }
        }
        .help(app.name)
    }
}
