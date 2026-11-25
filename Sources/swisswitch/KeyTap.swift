import AppKit
import CoreGraphics
import os
import SwisswitchCore

/// Global keyboard tap that reports trigger key + letter or digit (swallowing those
/// events; digits only when some app is assigned that digit)
/// and the trigger key held on its own for `holdDelay` (never swallowed).
/// The trigger is a right-hand modifier (`TriggerKey`); its left twin never triggers.
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
    private let trigger: OSAllocatedUnfairLock<TriggerKey>
    /// How long the trigger key must be held alone to show the preview; read each time.
    private let holdDelay: () -> Duration

    init(assignedDigits: OSAllocatedUnfairLock<Set<Character>>,
         trigger: OSAllocatedUnfairLock<TriggerKey>,
         holdDelay: @escaping () -> Duration,
         onLetter: @escaping (Character) -> Void, onHold: @escaping (Bool) -> Void) {
        self.assignedDigits = assignedDigits
        self.trigger = trigger
        self.holdDelay = holdDelay
        self.onLetter = onLetter
        self.onHold = onHold
    }

    /// Installs the tap. Fails when the process lacks Accessibility access.
    func start() -> Bool {
        guard context == nil else { return true }
        let layoutMap = KeyboardLayoutMap()
        let context = TapContext(assignedDigits: assignedDigits,
                                 trigger: trigger,
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

    /// Arms the hold timer when the trigger key goes down alone; any other modifier
    /// change cancels it, and releasing the trigger key ends a hold in progress.
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
    /// A key went down; `letter` is set for a (non-repeat) trigger key + key press.
    case keyDown(letter: Character?)
    case flags(rightDown: Bool, alone: Bool)
    case reenabled(timeout: Bool)
}

/// State shared with the C callback on the tap thread.
private final class TapContext: @unchecked Sendable {
    /// Set once before the tap thread starts, read only afterwards.
    var port: CFMachPort?
    let assignedDigits: OSAllocatedUnfairLock<Set<Character>>
    let trigger: OSAllocatedUnfairLock<TriggerKey>
    let layout: KeyTable
    let deliver: @Sendable (TapSignal) -> Void

    init(assignedDigits: OSAllocatedUnfairLock<Set<Character>>,
         trigger: OSAllocatedUnfairLock<TriggerKey>,
         layout: KeyTable,
         deliver: @escaping @Sendable (TapSignal) -> Void) {
        self.assignedDigits = assignedDigits
        self.trigger = trigger
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

/// The lowercase a–z letter or 0–9 digit when `event` is the (right) trigger key
/// + that key with no other modifiers.
///
/// Runs on the tap thread, so it must not touch AppKit or Text Input Sources
/// (`NSEvent.charactersIgnoringModifiers` asserts the main queue and traps);
/// the character comes from the table `KeyboardLayoutMap` builds on main.
private func triggerKey(of event: CGEvent, trigger: TriggerKey,
                        layout: KeyTable) -> Character? {
    let flags = event.flags
    guard flags.contains(trigger.flag),
          flags.rawValue & trigger.rightMask != 0,
          flags.isDisjoint(with: trigger.otherModifiers)
    else { return nil }
    let code = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
    return layout.withLock { $0[code] }
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
        let trigger = context.trigger.withLock { $0 }
        let raw = event.flags.rawValue
        let rightDown = raw & trigger.rightMask != 0
        let alone = rightDown && raw & trigger.leftMask == 0
            && event.flags.isDisjoint(with: trigger.otherModifiers)
        context.deliver(.flags(rightDown: rightDown, alone: alone))
        return pass
    case .keyDown:
        // Unassigned digits pass through, so apps keep their ⌘1…⌘9 shortcuts.
        let trigger = context.trigger.withLock { $0 }
        guard let letter = triggerKey(of: event, trigger: trigger, layout: context.layout),
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
