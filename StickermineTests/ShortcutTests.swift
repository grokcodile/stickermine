import Carbon.HIToolbox
import Foundation
import Testing
@testable import Stickermine

struct ShortcutTests {
    @Test func theDefaultIsControlOptionCommandS() {
        #expect(Shortcut.defaultCapture.keyCode == 1)
        #expect(Shortcut.defaultCapture.modifiers == UInt32(controlKey | optionKey | cmdKey))
        #expect(Shortcut.defaultCapture.modifiers == 0x1900)
        #expect(Shortcut.defaultCapture.label == "⌃⌥⌘S")
    }

    @Test func labelsUseApplesModifierOrderWithoutSpaces() {
        let all = Shortcut(keyCode: 40, modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        #expect(all.label == "⌃⌥⇧⌘K")
        #expect(Shortcut(keyCode: 122, modifiers: 0).label == "F1")
        #expect(Shortcut(keyCode: 49, modifiers: UInt32(cmdKey)).label == "⌘Space")
        #expect(Shortcut(keyCode: 200, modifiers: UInt32(cmdKey)).label == "⌘key200")
    }

    @Test func aChordNeedsCommandOrControlUnlessItIsAnFKey() {
        #expect(Shortcut(keyCode: 1, modifiers: UInt32(cmdKey)).isAcceptable)
        #expect(Shortcut(keyCode: 1, modifiers: UInt32(controlKey)).isAcceptable)
        #expect(!Shortcut(keyCode: 1, modifiers: UInt32(optionKey)).isAcceptable)
        #expect(!Shortcut(keyCode: 1, modifiers: UInt32(optionKey | shiftKey)).isAcceptable)
        #expect(!Shortcut(keyCode: 1, modifiers: 0).isAcceptable)
        #expect(Shortcut(keyCode: 111, modifiers: 0).isAcceptable)     // F12 alone
        #expect(Shortcut(keyCode: 90, modifiers: UInt32(shiftKey)).isAcceptable)   // ⇧F20
    }

    @Test func storesAsKAndM() throws {
        let data = try JSONEncoder().encode(Shortcut.defaultCapture)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Int])
        #expect(object == ["k": 1, "m": 6400])
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == Shortcut.defaultCapture)
    }

    @Test func menusShowLowercaseCharactersAndFunctionKeys() {
        #expect(Shortcut.defaultCapture.menuKeyEquivalent == "s")
        #expect(Shortcut(keyCode: 29, modifiers: UInt32(cmdKey)).menuKeyEquivalent == "0")
        #expect(Shortcut(keyCode: 122, modifiers: 0).menuKeyEquivalent == "\u{F704}")   // F1
        #expect(Shortcut(keyCode: 90, modifiers: 0).menuKeyEquivalent == "\u{F717}")    // F20
        #expect(Shortcut(keyCode: 49, modifiers: UInt32(cmdKey)).menuKeyEquivalent == " ")
        #expect(Shortcut(keyCode: 36, modifiers: UInt32(cmdKey)).menuKeyEquivalent == nil)   // Return
    }
}
