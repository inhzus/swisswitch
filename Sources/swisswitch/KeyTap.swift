import AppKit
import CoreGraphics

/// Global keyboard tap that reports Right ⌘ + letter and swallows those events.
@MainActor
final class KeyTap {
    /// `NX_DEVICERCMDKEYMASK` from IOKit's IOLLEvent.h: set only while the
    /// *right* Command key is down.
    private static let rightCommandMask: UInt64 = 0x10
    private static let otherModifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskControl]

    private let onLetter: (Character) -> Void
    private var machPort: CFMachPort?

    init(onLetter: @escaping (Character) -> Void) {
        self.onLetter = onLetter
    }

    /// Installs the tap. Fails when the process lacks Accessibility access.
    func start() -> Bool {
        guard machPort == nil else { return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return false }
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        machPort = port
        return true
    }

    /// Returns true when the event should be swallowed.
    fileprivate func handle(type: CGEventType, event: CGEvent) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let machPort { CGEvent.tapEnable(tap: machPort, enable: true) }
            return false
        case .keyDown:
            guard let letter = Self.triggerLetter(of: event) else { return false }
            if event.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                onLetter(letter)
            }
            return true
        default:
            return false
        }
    }

    /// The lowercase a–z letter when `event` is Right ⌘ + letter with no other modifiers.
    private static func triggerLetter(of event: CGEvent) -> Character? {
        let flags = event.flags
        guard flags.contains(.maskCommand),
              flags.rawValue & rightCommandMask != 0,
              flags.isDisjoint(with: otherModifiers),
              // Layout-aware: the character this key types without modifiers.
              let chars = NSEvent(cgEvent: event)?.charactersIgnoringModifiers?.lowercased(),
              chars.count == 1,
              let letter = chars.first,
              letter.isASCII, letter.isLetter
        else { return nil }
        return letter
    }
}

private func keyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<KeyTap>.fromOpaque(refcon).takeUnretainedValue()
    // The tap's run-loop source is on the main run loop, so this is the main thread.
    nonisolated(unsafe) let event = event
    let swallow = MainActor.assumeIsolated { tap.handle(type: type, event: event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
