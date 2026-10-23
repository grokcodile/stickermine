import AppKit
import Carbon.HIToolbox
import Testing
@testable import Stickermine

/// No status item is created here (it would appear in the menu bar): the
/// glyph, the menu and the click rules are checked on their own.
@MainActor
struct StatusItemControllerTests {
    @Test func theGlyphIsAnEighteenPointTemplate() throws {
        let glyph = try #require(StatusItemController.glyph())
        #expect(glyph.size == NSSize(width: 18, height: 18))
        #expect(glyph.isTemplate)
        // The named asset itself is left at its own size.
        #expect(NSImage(named: StatusItemController.glyphName)?.size != NSSize(width: 18, height: 18))
    }

    @Test func theAssetIsTheDesignGlyphAsAVectorTemplate() throws {
        let folder = "Assets.xcassets/MenuBarGlyph.imageset/"
        let json = try SourceFiles.contents(of: folder + "Contents.json")
        #expect(json.contains(#""template-rendering-intent" : "template""#))
        #expect(json.contains(#""preserves-vector-representation" : true"#))
        #expect(json.contains(#""filename" : "MenuBarGlyph.svg""#))
        let asset = try Data(contentsOf: SourceFiles.appRoot.appendingPathComponent(folder + "MenuBarGlyph.svg"))
        let design = try Data(contentsOf: SourceFiles.repoRoot.appendingPathComponent("design/menubar-glyph.svg"))
        #expect(asset == design)
    }

    @Test func theMenuHasNewStickerWithTheShortcutAndQuit() {
        let built = StatusItemController.makeMenu(shortcut: .defaultCapture)
        #expect(built.menu.items.map(\.title) == ["New Sticker", "", "Quit Stickermine"])
        #expect(built.menu.items[1].isSeparatorItem)
        #expect(built.newSticker.keyEquivalent == "s")
        #expect(built.newSticker.keyEquivalentModifierMask == [.control, .option, .command])
        #expect(built.quit.keyEquivalent == "q")
        #expect(!built.menu.autoenablesItems)
        let none = StatusItemController.makeMenu(shortcut: nil)
        #expect(none.newSticker.keyEquivalent == "")
    }

    @Test func newStickerIsDisabledDuringASession() {
        let item = StatusItemController.makeMenu(shortcut: .defaultCapture).newSticker
        StatusItemController.applySessionState(true, to: item)
        #expect(!item.isEnabled)
        StatusItemController.applySessionState(false, to: item)
        #expect(item.isEnabled)
    }

    @Test func aRightClickOrControlClickOpensTheMenu() {
        #expect(StatusItemController.opensMenu(type: .rightMouseUp, modifiers: []))
        #expect(StatusItemController.opensMenu(type: .leftMouseUp, modifiers: [.control]))
        #expect(!StatusItemController.opensMenu(type: .leftMouseUp, modifiers: []))
        #expect(!StatusItemController.opensMenu(type: .leftMouseUp, modifiers: [.command]))
    }

    @Test func carbonModifiersMapToAppKitFlags() {
        #expect(StatusItemController.modifierFlags(carbon: UInt32(controlKey | optionKey | cmdKey))
                == [.control, .option, .command])
        #expect(StatusItemController.modifierFlags(carbon: UInt32(shiftKey)) == [.shift])
        #expect(StatusItemController.modifierFlags(carbon: 0) == [])
    }
}
