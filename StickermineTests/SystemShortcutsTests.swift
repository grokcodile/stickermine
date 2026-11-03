import Carbon.HIToolbox
import Foundation
import Testing
@testable import Stickermine

/// An injected table stands in for `CopySymbolicHotKeys`, with rows shaped
/// like the real ones (NSNumber values under the kHISymbolicHotKey* keys).
struct SystemShortcutsTests {
    private func row(_ code: Int, _ modifiers: Int, enabled: Bool? = true) -> [String: Any] {
        var row: [String: Any] = [kHISymbolicHotKeyCode as String: NSNumber(value: code),
                                  kHISymbolicHotKeyModifiers as String: NSNumber(value: modifiers)]
        if let enabled { row[kHISymbolicHotKeyEnabled as String] = NSNumber(value: enabled) }
        return row
    }

    @Test func anEnabledRowWithTheSameKeyAndModifiersConflicts() {
        // ⌘⇧3 (key 20, 0x300): Save picture of screen as a file.
        let entries = SystemShortcuts.entries(from: [row(20, 0x300), row(49, 0x100)])
        #expect(SystemShortcuts.conflicts(with: Shortcut(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey)), in: entries))
        #expect(SystemShortcuts.conflicts(with: Shortcut(keyCode: 49, modifiers: UInt32(cmdKey)), in: entries))
    }

    @Test func aDisabledOrMissingEnabledFlagDoesNotConflict() {
        let entries = SystemShortcuts.entries(from: [row(1, 0x1900, enabled: false), row(2, 0x1100, enabled: nil)])
        #expect(!SystemShortcuts.conflicts(with: .defaultCapture, in: entries))
        #expect(!SystemShortcuts.conflicts(with: Shortcut(keyCode: 2, modifiers: UInt32(cmdKey | controlKey)), in: entries))
    }

    @Test func otherModifiersOrKeysDoNotConflict() {
        let entries = SystemShortcuts.entries(from: [row(20, 0x300)])
        #expect(!SystemShortcuts.conflicts(with: Shortcut(keyCode: 20, modifiers: UInt32(cmdKey)), in: entries))
        #expect(!SystemShortcuts.conflicts(with: Shortcut(keyCode: 21, modifiers: UInt32(cmdKey | shiftKey)), in: entries))
        #expect(!SystemShortcuts.conflicts(with: .defaultCapture, in: entries))
    }

    @Test func theFnBitOnFKeyRowsIsIgnored() {
        // F11 (103) with the fn bit 0x20000: Show Desktop.
        let entries = SystemShortcuts.entries(from: [row(103, 0x20000)])
        #expect(entries == [SystemShortcuts.Entry(keyCode: 103, modifiers: 0, enabled: true)])
        #expect(SystemShortcuts.conflicts(with: Shortcut(keyCode: 103, modifiers: 0), in: entries))
        #expect(!SystemShortcuts.conflicts(with: Shortcut(keyCode: 103, modifiers: UInt32(shiftKey)), in: entries))
    }

    @Test func malformedRowsAreSkipped() {
        let table: [[String: Any]] = [
            [kHISymbolicHotKeyCode as String: NSNumber(value: 1)],
            [kHISymbolicHotKeyModifiers as String: NSNumber(value: 0x100)],
            [kHISymbolicHotKeyCode as String: "S", kHISymbolicHotKeyModifiers as String: NSNumber(value: 0x100)],
            row(-1, 0x100),
            row(1, 0x1900),
        ]
        #expect(SystemShortcuts.entries(from: table) == [SystemShortcuts.Entry(keyCode: 1, modifiers: 0x1900, enabled: true)])
    }

    @Test func theLiveTableCanBeRead() {
        // Every Mac has system shortcuts (Spotlight, screenshots, Mission Control).
        #expect(!SystemShortcuts.entries(from: SystemShortcuts.liveTable()).isEmpty)
    }
}
