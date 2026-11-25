import AppKit
import Carbon
import CoreGraphics
import os
import SwisswitchCore

/// Global keyboard tap that reports Right ⌘ + letter or digit (swallowing those
/// events; digits only when some app is assigned that digit)
/// and Right ⌘ held on its own for `holdDelay` (never swallowed).
///
/// The tap is an active filter, so every key event system-wide waits for its
/// callback. The callback therefore runs on a dedicated high-priority thread and
/// only classifies the event; all real work is handed to the main actor
/// asynchronously, so a busy main thread can never stall typing.
@MainActor
final class KeyTap {
    private let onLetter: (Character) -> Void
    private let onHold: (Bool) -> Void
    private var context: TapContext?
    private var layoutMap: KeyboardLayoutMap?
    private var holdTimer: Task<Void, Never>?
    private var holding = false
    private let assignedDigits: OSAllocatedUnfairLock<Set<Character>>
    /// How long Right ⌘ must be held alone to show the preview; read each time.
    private let holdDelay: () -> Duration

    init(assignedDigits: OSAllocatedUnfairLock<Set<Character>>,
         holdDelay: @escaping () -> Duration,
         onLetter: @escaping (Character) -> Void, onHold: @escaping (Bool) -> Void) {
        self.assignedDigits = assignedDigits
        self.holdDelay = holdDelay
        self.onLetter = onLetter
        self.onHold = onHold
    }

    /// Installs the tap. Fails when the process lacks Accessibility access.
    func start() -> Bool {
        guard context == nil else { return true }
        let layoutMap = KeyboardLayoutMap()
        let context = TapContext(assignedDigits: assignedDigits,
                                 layout: layoutMap.table) { [weak self] signal in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.receive(signal) }
            }
        }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
            | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: keyTapCallback,
            userInfo: Unmanaged.passUnretained(context).toOpaque()
        ) else { return false }
        context.port = port
        let thread = TapThread(port: port)
        thread.name = "swisswitch.keytap"
        thread.qualityOfService = .userInteractive
        thread.start()
        self.context = context
        self.layoutMap = layoutMap
        return true
    }

    private func receive(_ signal: TapSignal) {
        switch signal {
        case .keyDown(let letter):
            cancelHoldTimer()
            if let letter {
                onLetter(letter)
                endHold()
            }
        case .flags(let rightDown, let alone):
            flagsChanged(rightDown: rightDown, alone: alone)
        case .reenabled(let timeout):
            Log.warning("event tap was disabled by \(timeout ? "timeout" : "user input"); re-enabled")
        }
    }

    /// Arms the hold timer when Right ⌘ goes down alone; any other modifier
    /// change cancels it, and releasing Right ⌘ ends a hold in progress.
    private func flagsChanged(rightDown: Bool, alone: Bool) {
        if alone && !holding {
            guard holdTimer == nil else { return }
            let delay = holdDelay()
            holdTimer = Task { [weak self] in
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled, let self else { return }
                self.holdTimer = nil
                self.holding = true
                self.onHold(true)
            }
        } else {
            cancelHoldTimer()
            if !rightDown { endHold() }
        }
    }

    private func cancelHoldTimer() {
        holdTimer?.cancel()
        holdTimer = nil
    }

    private func endHold() {
        guard holding else { return }
        holding = false
        onHold(false)
    }
}

/// What the tap thread tells the main actor.
private enum TapSignal: Sendable {
    /// A key went down; `letter` is set for a (non-repeat) Right ⌘ + key trigger.
    case keyDown(letter: Character?)
    case flags(rightDown: Bool, alone: Bool)
    case reenabled(timeout: Bool)
}

/// State shared with the C callback on the tap thread.
private final class TapContext: @unchecked Sendable {
    /// Set once before the tap thread starts, read only afterwards.
    var port: CFMachPort?
    let assignedDigits: OSAllocatedUnfairLock<Set<Character>>
    let layout: OSAllocatedUnfairLock<[UInt16: Character]>
    let deliver: @Sendable (TapSignal) -> Void

    init(assignedDigits: OSAllocatedUnfairLock<Set<Character>>,
         layout: OSAllocatedUnfairLock<[UInt16: Character]>,
         deliver: @escaping @Sendable (TapSignal) -> Void) {
        self.assignedDigits = assignedDigits
        self.layout = layout
        self.deliver = deliver
    }
}

/// Runs the tap's run loop off the main thread.
private final class TapThread: Thread, @unchecked Sendable {
    private let port: CFMachPort

    init(port: CFMachPort) {
        self.port = port
        super.init()
    }

    override func main() {
        let source = CFMachPortCreateRunLoopSource(nil, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)
        CFRunLoopRun()
    }
}

/// `NX_DEVICERCMDKEYMASK` / `NX_DEVICELCMDKEYMASK` from IOKit's IOLLEvent.h:
/// set only while the right / left Command key is down.
private let rightCommandMask: UInt64 = 0x10
private let leftCommandMask: UInt64 = 0x08
private let otherModifiers: CGEventFlags = [.maskShift, .maskAlternate, .maskControl]

/// The lowercase a–z letter or 0–9 digit when `event` is Right ⌘ + that key
/// with no other modifiers.
///
/// Runs on the tap thread, so it must not touch AppKit or Text Input Sources
/// (`NSEvent.charactersIgnoringModifiers` asserts the main queue and traps);
/// the character comes from the table `KeyboardLayoutMap` builds on main.
private func triggerKey(of event: CGEvent,
                        layout: OSAllocatedUnfairLock<[UInt16: Character]>) -> Character? {
    let flags = event.flags
    guard flags.contains(.maskCommand),
          flags.rawValue & rightCommandMask != 0,
          flags.isDisjoint(with: otherModifiers)
    else { return nil }
    let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    return layout.withLock { $0[code] }
}

/// Keycode → lowercase ASCII letter/digit for the current keyboard layout:
/// the character each key types with no modifiers. Built on the main thread
/// (TIS requires it) and rebuilt whenever the input source changes; the tap
/// thread only reads `table`.
@MainActor
final class KeyboardLayoutMap {
    nonisolated let table = OSAllocatedUnfairLock<[UInt16: Character]>(initialState: [:])
    private var observer: NSObjectProtocol?

    init() {
        rebuild()
        observer = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(kTISNotifySelectedKeyboardInputSourceChanged as String),
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.rebuild() }
        }
    }

    func rebuild() {
        let (id, map) = Self.currentMap()
        table.withLock { $0 = map }
        if map.isEmpty {
            Log.error("keyboard layout \(id) maps no letters or digits; switching won't work")
        } else {
            Log.info("keyboard layout \(id): \(map.count) keys mapped")
        }
    }

    private static func layoutData(_ source: TISInputSource?) -> CFData? {
        guard let source,
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        return Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue()
    }

    private static func inputSourceID(_ source: TISInputSource) -> String {
        guard let ptr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) else { return "?" }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    /// The ID of the layout the table came from, and the table.
    private static func currentMap() -> (layoutID: String, map: [UInt16: Character]) {
        // Input methods (e.g. Chinese) have no layout data; fall back to the
        // ASCII-capable layout they type through.
        for copySource in [TISCopyCurrentKeyboardLayoutInputSource,
                           TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
            guard let source = copySource()?.takeRetainedValue(),
                  let data = layoutData(source)
            else { continue }
            return (inputSourceID(source), translate(data))
        }
        return ("none", [:])
    }

    /// The lowercase ASCII letter or digit each keycode types in `layoutData`.
    private static func translate(_ layoutData: CFData) -> [UInt16: Character] {
        guard let bytes = CFDataGetBytePtr(layoutData) else { return [:] }
        let keyboardType = UInt32(LMGetKbdType())
        var map: [UInt16: Character] = [:]
        bytes.withMemoryRebound(to: UCKeyboardLayout.self, capacity: 1) { layout in
            for code in UInt16(0)..<128 {
                var deadKeyState: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(
                    layout, code, UInt16(kUCKeyActionDown), 0, keyboardType,
                    OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState,
                    chars.count, &length, &chars)
                guard status == noErr, length > 0 else { continue }
                let string = String(utf16CodeUnits: chars, count: length).lowercased()
                guard string.count == 1, let char = string.first,
                      char.isASCII, char.isLetter || char.isNumber
                else { continue }
                map[code] = char
            }
        }
        return map
    }
}

/// Runs on the tap thread: classify, hand off, and return immediately.
private func keyTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    guard let refcon else { return pass }
    let context = Unmanaged<TapContext>.fromOpaque(refcon).takeUnretainedValue()
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        if let port = context.port { CGEvent.tapEnable(tap: port, enable: true) }
        context.deliver(.reenabled(timeout: type == .tapDisabledByTimeout))
        return pass
    case .flagsChanged:
        let raw = event.flags.rawValue
        let rightDown = raw & rightCommandMask != 0
        let alone = rightDown && raw & leftCommandMask == 0
            && event.flags.isDisjoint(with: otherModifiers)
        context.deliver(.flags(rightDown: rightDown, alone: alone))
        return pass
    case .keyDown:
        // Unassigned digits pass through, so apps keep their ⌘1…⌘9 shortcuts.
        guard let letter = triggerKey(of: event, layout: context.layout),
              letter.isLetter || context.assignedDigits.withLock({ $0.contains(letter) })
        else {
            context.deliver(.keyDown(letter: nil))
            return pass
        }
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        context.deliver(.keyDown(letter: isRepeat ? nil : letter))
        return nil
    default:
        return pass
    }
}
