import AppKit
import SwiftUI

/// Asks for Accessibility access and closes itself once it's granted.
@MainActor
final class OnboardingWindow {
    private let model = OnboardingModel()
    private let window: NSWindow
    private var poll: Timer?

    init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 380),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "swisswitch"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: OnboardingView(model: model))
    }

    func show(onGranted: @escaping @MainActor () -> Void) {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
        poll = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, AXIsProcessTrusted() else { return }
                self.poll?.invalidate()
                withAnimation(.spring(duration: 0.4)) { self.model.granted = true }
                onGranted()
                Task {
                    try? await Task.sleep(for: .milliseconds(900))
                    self.window.close()
                }
            }
        }
    }
}

@Observable
@MainActor
private final class OnboardingModel {
    var granted = false
}

private struct OnboardingView: View {
    let model: OnboardingModel

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "command")
                .font(.system(size: 34, weight: .semibold))
                .frame(width: 76, height: 76)
                .glassEffect(.regular.tint(.accentColor.opacity(0.35)), in: .circle)

            VStack(spacing: 6) {
                Text("Allow Accessibility")
                    .font(.title2.weight(.bold))
                Text("swisswitch needs Accessibility access to listen for Right ⌘ and bring apps to the front.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Label(model.granted ? "Access granted" : "Waiting for access…",
                  systemImage: model.granted ? "checkmark.circle.fill" : "hourglass")
                .font(.callout.weight(.medium))
                .foregroundStyle(model.granted ? Color.green : Color.secondary)
                .contentTransition(.symbolEffect(.replace))
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .glassEffect(.regular.tint(model.granted ? .green.opacity(0.2) : .clear), in: .capsule)

            GlassEffectContainer(spacing: 10) {
                HStack(spacing: 10) {
                    Button("Quit") { NSApp.terminate(nil) }
                        .buttonStyle(.glass)
                    Button("Open System Settings") {
                        NSWorkspace.shared.open(URL(string:
                            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                    }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
            }
        }
        .padding(.horizontal, 36)
        .padding(.top, 44)
        .padding(.bottom, 32)
        .frame(width: 440)
    }
}
