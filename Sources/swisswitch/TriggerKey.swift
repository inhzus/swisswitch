import CoreGraphics

/// The right-hand modifier that, held with a letter or digit, switches apps.
/// Only the right key of each pair triggers; the left one keeps working as usual.
enum TriggerKey: String, CaseIterable, Identifiable, Sendable {
    case rightCommand, rightOption, rightControl, rightShift

    static let `default`: TriggerKey = .rightCommand

    var id: Self { self }

    /// The device-independent flag set while either key of the pair is down.
    var flag: CGEventFlags {
        switch self {
        case .rightCommand: .maskCommand
        case .rightOption: .maskAlternate
        case .rightControl: .maskControl
        case .rightShift: .maskShift
        }
    }

    /// `NX_DEVICER*KEYMASK` from IOKit's IOLLEvent.h: set only while the right key is down.
    var rightMask: UInt64 {
        switch self {
        case .rightCommand: 0x10   // NX_DEVICERCMDKEYMASK
        case .rightOption: 0x40    // NX_DEVICERALTKEYMASK
        case .rightControl: 0x2000 // NX_DEVICERCTLKEYMASK
        case .rightShift: 0x04     // NX_DEVICERSHIFTKEYMASK
        }
    }

    /// `NX_DEVICEL*KEYMASK` from IOKit's IOLLEvent.h: set only while the left key is down.
    var leftMask: UInt64 {
        switch self {
        case .rightCommand: 0x08   // NX_DEVICELCMDKEYMASK
        case .rightOption: 0x20    // NX_DEVICELALTKEYMASK
        case .rightControl: 0x01   // NX_DEVICELCTLKEYMASK
        case .rightShift: 0x02     // NX_DEVICELSHIFTKEYMASK
        }
    }

    /// The other modifiers, any of which disqualifies a trigger.
    var otherModifiers: CGEventFlags {
        CGEventFlags([.maskCommand, .maskAlternate, .maskControl, .maskShift]).subtracting(flag)
    }

    var symbol: String {
        switch self {
        case .rightCommand: "⌘"
        case .rightOption: "⌥"
        case .rightControl: "⌃"
        case .rightShift: "⇧"
        }
    }

    /// e.g. "Right ⌘".
    var name: String { "Right \(symbol)" }

    /// What the trigger takes away from normal typing, shown in Settings.
    var caveat: String? {
        switch self {
        case .rightCommand: nil
        case .rightOption: "Right ⌥ + letter no longer types special characters; use Left ⌥ for those."
        case .rightControl: "Right ⌃ + letter shortcuts (e.g. ⌃A, ⌃E) go to swisswitch; use Left ⌃ for those."
        case .rightShift: "Right ⇧ + letter no longer types capitals; use Left ⇧ for those."
        }
    }
}
