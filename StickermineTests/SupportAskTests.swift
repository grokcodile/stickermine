import AppKit
import Testing
@testable import Stickermine

/// The card is only ever shown far off every real screen (x ≥ 40 000) and
/// dismissed in the same synchronous stretch.
@MainActor
struct SupportAskTests {
    private func suite() -> (UserDefaults, String) {
        let name = "StickermineTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    private static let offscreen = CGRect(x: 40_000, y: 0, width: 1512, height: 949)

    @Test func theFifthOwnPlacementShowsItOnce() {
        var count = 0
        var shown = false
        var shows = 0
        for _ in 0..<12 {
            let result = SupportAskRule.afterPlacement(count: count, alreadyShown: shown, isTutorial: false)
            count = result.count
            if result.show {
                shows += 1
                shown = true
                #expect(count == 5)
            }
        }
        #expect(count == 12)
        #expect(shows == 1)
    }

    @Test func tutorialPlacementsDontCount() {
        let tutorial = SupportAskRule.afterPlacement(count: 4, alreadyShown: false, isTutorial: true)
        #expect(tutorial.count == 4)
        #expect(!tutorial.show)
        #expect(SupportAskRule.afterPlacement(count: 4, alreadyShown: false, isTutorial: false).show)
        #expect(!SupportAskRule.afterPlacement(count: 9, alreadyShown: true, isTutorial: false).show)
        // An existing count above the threshold still shows it once when it was never shown.
        #expect(SupportAskRule.afterPlacement(count: 9, alreadyShown: false, isTutorial: false).show)
    }

    @Test func clicksAreCountedInTheDefaultsAndTheCardAppearsWithoutTakingFocus() throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        var opened: [URL] = []
        let ask = SupportAsk(defaults: defaults, openURL: { opened.append($0) }, anchor: { nil },
                             fallbackArea: { Self.offscreen }, showDelay: 0)
        defer { ask.dismiss() }
        for _ in 0..<4 { ask.placementClicked(isTutorial: false) }
        ask.placementClicked(isTutorial: true)
        #expect(defaults.ownPlacementsCount == 4)
        #expect(!ask.isVisible)
        #expect(!defaults.supportAskShown)
        let wasActive = NSApp.isActive
        ask.placementClicked(isTutorial: false)
        #expect(defaults.ownPlacementsCount == 5)
        #expect(defaults.supportAskShown)
        #expect(ask.isVisible)
        let panel = try #require(ask.panel)
        #expect(!panel.isKeyWindow)
        #expect(NSApp.isActive == wasActive)
        // The card itself; its transparent shadow padding may overhang.
        let pad = SupportAsk.shadowPadding
        #expect(Self.offscreen.contains(panel.frame.insetBy(dx: pad, dy: pad)))
        ask.dismiss()
        #expect(!ask.isVisible)
        #expect(ask.panel == nil)
        // Declined for good.
        for _ in 0..<5 { ask.placementClicked(isTutorial: false) }
        #expect(!ask.isVisible)
        #expect(opened.isEmpty)
    }

    @Test func thePanelFollowsThePanelPolicy() {
        let panel = SupportAsk.makePanel()
        defer { panel.close() }
        #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.level == .statusBar)
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.isFloatingPanel)
        #expect(!panel.isVisible)
    }

    @Test func theCardHangsBelowTheMenuBarIconInsideTheScreen() {
        let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
        let size = CGSize(width: 352, height: 180)
        let pad = SupportAsk.shadowPadding
        let icon = CGRect(x: 1200, y: 952, width: 30, height: 24)
        let below = SupportAsk.frame(size: size, anchor: icon, visibleFrame: visible)
        #expect(below.size == size)
        #expect(below.maxX - pad == icon.maxX)
        #expect(below.maxY - pad == icon.minY - SupportAsk.gap)
        // An icon near the right edge: the card stays on screen.
        let edge = SupportAsk.frame(size: size, anchor: CGRect(x: 1500, y: 952, width: 30, height: 24), visibleFrame: visible)
        #expect(edge.maxX - pad == visible.maxX - SupportAsk.edgeInset)
        // No icon: the top-right corner of the main display.
        let corner = SupportAsk.frame(size: size, anchor: nil, visibleFrame: visible)
        #expect(corner.maxX - pad == visible.maxX - SupportAsk.edgeInset)
        #expect(corner.maxY - pad == visible.maxY - SupportAsk.edgeInset)
        // An icon on a short screen: the card never goes below the bottom.
        let low = SupportAsk.frame(size: size, anchor: CGRect(x: 1200, y: 100, width: 30, height: 24), visibleFrame: visible)
        #expect(low.minY + pad == visible.minY + SupportAsk.edgeInset)
    }

    @Test func theWordsAndTheLinkAreTheSpecs() {
        #expect(SupportAsk.message == "Enjoying Stickermine? It’s free and open source. If it made you smile, you can buy me a coffee.")
        #expect(SupportAsk.coffeeTitle == "☕️ Buy me a coffee")
        #expect(SupportAsk.laterTitle == "Maybe later")
        #expect(SupportAsk.kofiURL.absoluteString == "https://ko-fi.com/grokcodile")
    }
}
