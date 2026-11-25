import AppKit
import Carbon
import os
import SwisswitchCore

/// Keycode → trigger character table, shared between the main actor (writer)
/// and the event-tap thread (reader).
typealias KeyTable = OSAllocatedUnfairLock<[UInt16: Character]>

/// Keycode → lowercase ASCII letter/digit for the current keyboard layout:
/// the character each key types with no modifiers. Built on the main thread
/// (TIS requires it) and rebuilt whenever the input source changes; the tap
/// thread only reads `table`.
@MainActor
final class KeyboardLayoutMap {
    nonisolated let table = KeyTable(initialState: [:])
    private var observer: NSObjectProtocol?
    private var currentLayoutID: String?

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
        let (id, data) = Self.currentLayout()
        // The notification fires on every input-source switch and on app
        // focus changes; input methods resolve to the same ASCII layout, so
        // usually the layout is unchanged and there is nothing to rebuild.
        guard id != currentLayoutID else { return }
        currentLayoutID = id
        let map = data.map(Self.translate) ?? [:]
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

    /// The ID and key layout data of the layout the current input source types through.
    private static func currentLayout() -> (layoutID: String, data: CFData?) {
        // Input methods (e.g. Chinese) have no layout data; fall back to the
        // ASCII-capable layout they type through.
        for copySource in [TISCopyCurrentKeyboardLayoutInputSource,
                           TISCopyCurrentASCIICapableKeyboardLayoutInputSource] {
            guard let source = copySource()?.takeRetainedValue(),
                  let data = layoutData(source)
            else { continue }
            return (inputSourceID(source), data)
        }
        return ("none", nil)
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
                let typed = String(utf16CodeUnits: chars, count: length)
                if let char = triggerKey(typed: typed) { map[code] = char }
            }
        }
        return map
    }
}
