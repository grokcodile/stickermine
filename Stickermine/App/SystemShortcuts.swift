import Carbon.HIToolbox
import Foundation

/// Whether a chord is one of macOS's own enabled keyboard shortcuts (System
/// Settings › Keyboard › Keyboard Shortcuts), read with `CopySymbolicHotKeys`
/// (spec section 13). The recorder warns about such a chord but still takes
/// it. Clashes with other apps can't be found: Carbon hotkeys aren't
/// exclusive, and registering one that another app uses succeeds anyway.
enum SystemShortcuts {
    /// One row of the symbolic hotkey table.
    struct Entry: Equatable {
        let keyCode: UInt32
        /// Only the four modifiers a `Shortcut` carries.
        let modifiers: UInt32
        let enabled: Bool
    }

    /// ⌘ ⇧ ⌥ ⌃. The table sets other bits too: F-key rows carry the fn bit
    /// (0x20000, `kEventKeyModifierFnMask`), which a `Shortcut` never has.
    static let modifierMask = UInt32(cmdKey | shiftKey | optionKey | controlKey)

    /// The table's rows; rows without a key code or modifiers are skipped.
    static func entries(from table: [[String: Any]]) -> [Entry] {
        table.compactMap { row in
            guard let code = (row[kHISymbolicHotKeyCode as String] as? NSNumber)?.intValue,
                  let modifiers = (row[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.intValue,
                  (0...0xFFFF).contains(code), modifiers >= 0
            else { return nil }
            let enabled = (row[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue ?? false
            return Entry(keyCode: UInt32(code), modifiers: UInt32(truncatingIfNeeded: modifiers) & modifierMask,
                         enabled: enabled)
        }
    }

    /// An enabled row with the same key and the same four modifiers.
    static func conflicts(with shortcut: Shortcut, in entries: [Entry]) -> Bool {
        let modifiers = shortcut.modifiers & modifierMask
        return entries.contains { $0.enabled && $0.keyCode == shortcut.keyCode && $0.modifiers == modifiers }
    }

    /// The live table (empty if the call fails).
    static func liveTable() -> [[String: Any]] {
        var table: Unmanaged<CFArray>?
        guard CopySymbolicHotKeys(&table) == noErr,
              let rows = table?.takeRetainedValue() as? [[String: Any]]
        else { return [] }
        return rows
    }

    /// The contract's check, against the live table.
    static func conflicts(with shortcut: Shortcut) -> Bool {
        conflicts(with: shortcut, in: entries(from: liveTable()))
    }
}
