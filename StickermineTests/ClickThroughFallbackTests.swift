import AppKit
import Testing
@testable import Stickermine

@MainActor
struct ClickThroughFallbackTests {
    /// A 2 × 2 mask whose left column is opaque.
    private let leftHalf = AlphaMask(width: 2, height: 2, bytes: [255, 0, 255, 0])
    private let rect = CGRect(x: 40_000, y: 0, width: 200, height: 100)

    private func candidate(_ rect: CGRect, mask: AlphaMask?, editing: Bool = false) -> ClickThroughFallback.Candidate {
        ClickThroughFallback.Candidate(contentRect: rect, frame: rect.insetBy(dx: -20, dy: -20), mask: mask,
                                       wholeFrame: editing)
    }

    @Test func onlyOpaquePixelsTakeTheClick() {
        let candidates = [candidate(rect, mask: leftHalf)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: candidates) == 0)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_150, y: 50), in: candidates) == nil)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 39_990, y: 50), in: candidates) == nil)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: [candidate(rect, mask: nil)]) == nil)
    }

    @Test func theFrontMostStickerWins() {
        let candidates = [candidate(rect, mask: leftHalf), candidate(rect, mask: leftHalf)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: candidates) == 0)
        let behind = [candidate(rect, mask: AlphaMask(width: 1, height: 1, bytes: [0])), candidate(rect, mask: leftHalf)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: behind) == 1)
    }

    @Test func anEditingStickerTakesItsWholeFrame() {
        let candidates = [candidate(rect, mask: leftHalf, editing: true)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_150, y: 50), in: candidates) == 0)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 39_985, y: -15), in: candidates) == 0)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 39_970, y: 50), in: candidates) == nil)
    }

    @Test func theStickerUnderTheCursorIsTheOnlyOneTakingTheMouse() {
        let front = PanelPolicy.makeStickerPanel(contentRect: rect)
        let back = PanelPolicy.makeStickerPanel(contentRect: rect.offsetBy(dx: 100, dy: 0))
        defer { front.close(); back.close() }
        let fallback = ClickThroughFallback(targets: { [front, back, rect, leftHalf] in
            [ClickThroughFallback.Target(panel: front, contentRect: rect, mask: leftHalf, wholeFrame: false),
             ClickThroughFallback.Target(panel: back, contentRect: rect.offsetBy(dx: 100, dy: 0), mask: leftHalf,
                                         wholeFrame: false)]
        }, buttonsDown: { false })
        fallback.prepare(front)
        fallback.prepare(back)
        #expect(front.ignoresMouseEvents && back.ignoresMouseEvents)
        // Moves over a sticker that has taken the mouse reach the local monitor only through this.
        for panel in [front, back] {
            #expect(panel.contentView?.trackingAreas.contains { $0.options.contains([.mouseMoved, .activeAlways]) } == true)
        }
        fallback.update(at: CGPoint(x: 40_050, y: 50))
        #expect(!front.ignoresMouseEvents)
        #expect(back.ignoresMouseEvents)
        #expect(fallback.activePanel === front)
        // x = 40 150 is the front sticker's transparent half but the back one's opaque half.
        fallback.update(at: CGPoint(x: 40_150, y: 50))
        #expect(front.ignoresMouseEvents)
        #expect(!back.ignoresMouseEvents)
        fallback.update(at: CGPoint(x: 41_000, y: 50))
        #expect(front.ignoresMouseEvents && back.ignoresMouseEvents)
        #expect(fallback.activePanel == nil)
    }

    @Test func nothingSwitchesWhileAButtonIsHeld() {
        let panel = PanelPolicy.makeStickerPanel(contentRect: rect)
        defer { panel.close() }
        var held = false
        let fallback = ClickThroughFallback(targets: { [panel, rect, leftHalf] in
            [ClickThroughFallback.Target(panel: panel, contentRect: rect, mask: leftHalf, wholeFrame: false)]
        }, buttonsDown: { held })
        fallback.prepare(panel)
        fallback.update(at: CGPoint(x: 40_050, y: 50))
        #expect(!panel.ignoresMouseEvents)
        // A drag (the corner knob) leaves the sticker: it keeps the mouse until the button is up.
        held = true
        fallback.update(at: CGPoint(x: 41_000, y: 50))
        #expect(!panel.ignoresMouseEvents)
        #expect(fallback.activePanel === panel)
        held = false
        fallback.update(at: CGPoint(x: 41_000, y: 50))
        #expect(panel.ignoresMouseEvents)
    }
}
