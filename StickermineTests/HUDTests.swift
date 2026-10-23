import AppKit
import Testing
@testable import Stickermine

/// The HUD is never shown here: only its panel and geometry are checked.
@MainActor
struct HUDTests {
    @Test func theMessagesAreTheSpecs() {
        #expect(HUD.controlHeldMessage == "Let go of Control before releasing the mouse")
        #expect(HUD.couldNotStartMessage == "Couldn’t start a capture")
    }

    @Test func thePillSitsAtTheTopCentre() {
        let frame = HUD.frame(width: 300, in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == CGRect(x: 350, y: 742, width: 300, height: 42))
    }

    @Test func thePanelNeverTakesFocusOrClicks() {
        let panel = HUD.makePanel()
        defer { panel.close() }
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.isFloatingPanel)
        #expect(panel.level == .statusBar)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }
}
