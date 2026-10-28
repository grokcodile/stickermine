import AppKit
import Testing
@testable import Stickermine

@MainActor
struct PickerPanelTests {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 400, height: 300)

    @Test func thePanelSitsBelowTheCursorWhenItFits() {
        let frame = PickerController.frame(size: size, near: CGPoint(x: 500, y: 600), visibleFrame: visible)
        #expect(frame == CGRect(x: 300, y: 284, width: 400, height: 300))
    }

    @Test func itGoesAboveWhenThereIsNoRoomBelow() {
        let frame = PickerController.frame(size: size, near: CGPoint(x: 500, y: 100), visibleFrame: visible)
        #expect(frame == CGRect(x: 300, y: 116, width: 400, height: 300))
    }

    @Test func itFallsBackToTheCentreOfTheDisplay() {
        let short = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let frame = PickerController.frame(size: size, near: CGPoint(x: 500, y: 200), visibleFrame: short)
        #expect(frame == CGRect(x: 300, y: 50, width: 400, height: 300))
    }

    @Test func itStaysInsideTheDisplaysSides() {
        let left = PickerController.frame(size: size, near: CGPoint(x: 40, y: 600), visibleFrame: visible)
        #expect(left.minX == 0)
        let right = PickerController.frame(size: size, near: CGPoint(x: 990, y: 600), visibleFrame: visible)
        #expect(right.maxX == 1000)
    }

    @Test func keysOneToFourPickTheStylesInOrder() {
        #expect(PickerController.style(forKey: "1") == .puffy)
        #expect(PickerController.style(forKey: "2") == .outline)
        #expect(PickerController.style(forKey: "3") == .shadow)
        #expect(PickerController.style(forKey: "4") == StickerStyle.none)
        #expect(PickerController.style(forKey: "5") == nil)
        #expect(PickerController.style(forKey: "0") == nil)
        #expect(PickerController.style(forKey: "a") == nil)
        #expect(PickerController.style(forKey: nil) == nil)
    }

    @Test func thePanelFollowsThePanelPolicyAndSurvivesLosingKey() {
        let panel = PickerController.makePanel()
        defer { panel.close() }
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isVisible)
    }

    /// The session ignores every trigger while the picker is up, so Hide (⌘H)
    /// and a Space switch must not take it out of sight.
    @Test func thePickerIsNeverHiddenAndJoinsEverySpace() {
        let panel = PickerController.makePanel()
        defer { panel.close() }
        #expect(!panel.canHide)
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(!panel.collectionBehavior.contains(.moveToActiveSpace))
    }
}
