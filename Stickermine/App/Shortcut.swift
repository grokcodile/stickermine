import Carbon.HIToolbox
import Foundation

/// A global shortcut: a virtual key code and a Carbon modifier mask
/// (`cmdKey | shiftKey | optionKey | controlKey`), the form
/// `RegisterEventHotKey` takes. Ported from Pullcord's `Shortcut`. Stored as
/// `{k, m}` (spec section 12); M6 adds the storage, the recorder and the
/// system-shortcut check.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    private enum CodingKeys: String, CodingKey {
        case keyCode = "k"
        case modifiers = "m"
    }

    /// ⌃⌥⌘S: key code 1 (kVK_ANSI_S) with Control, Option and Command.
    static let defaultCapture = Shortcut(keyCode: UInt32(kVK_ANSI_S),
                                         modifiers: UInt32(controlKey | optionKey | cmdKey))

    /// Virtual key codes for F1–F20, the only keys that may be used without
    /// ⌘ or ⌃.
    static let fKeyCodes: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                      103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    /// "⌃⌥⌘S": the modifier glyphs in Apple's order ⌃ ⌥ ⇧ ⌘, then the key, with
    /// no spaces (spec section 13 writes the tutorial as "Press ⌃⌥⌘S").
    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// Every chord must include ⌘ or ⌃; an F-key may stand alone (spec section 13).
    var isAcceptable: Bool {
        modifiers & UInt32(cmdKey | controlKey) != 0 || Self.fKeyCodes.contains(keyCode)
    }

    /// The character a menu item shows for this key (lowercase for letters),
    /// or nil for a key a menu can't show.
    var menuKeyEquivalent: String? {
        if let index = Self.fKeyCodes.firstIndex(of: keyCode) {
            // NSF1FunctionKey is U+F704; F1–F20 follow it in order.
            return UnicodeScalar(0xF704 + index).map { String(Character($0)) }
        }
        switch keyCode {
        case UInt32(kVK_Space): return " "
        case UInt32(kVK_LeftArrow): return "\u{F702}"
        case UInt32(kVK_RightArrow): return "\u{F703}"
        case UInt32(kVK_DownArrow): return "\u{F701}"
        case UInt32(kVK_UpArrow): return "\u{F700}"
        default:
            // Letters, digits and punctuation; the glyph names (↩, ⌫, ⎋ …) aren't keys.
            let name = Self.keyName(keyCode)
            guard name.count == 1, name.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
            return name.lowercased()
        }
    }

    /// The name a label shows for a key code (Pullcord's table).
    static func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
            9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
            34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`", 49: "Space",
            36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 76: "⌤",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            116: "⇞", 121: "⇟", 115: "↖", 119: "↘", 117: "⌦",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20",
        ]
        return names[code] ?? "key\(code)"
    }
}
