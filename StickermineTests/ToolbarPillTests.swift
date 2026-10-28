import AppKit
import Testing
@testable import Stickermine

/// The pill's placement, panel and model. No pill here is ordered in.
@MainActor
struct ToolbarPillTests {
    private let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private let size = CGSize(width: 120, height: 30)

    @Test func thePillSitsCentredUnderTheStickerWithAnEightPointGap() {
        let frame = ToolbarPill.frame(size: size, stickerRect: CGRect(x: 100, y: 300, width: 200, height: 100),
                                      visibleFrame: visible)
        #expect(frame == CGRect(x: 140, y: 262, width: 120, height: 30))
        #expect(ToolbarPill.gap == 8)
    }

    @Test func withoutRoomBelowThePillGoesAbove() {
        let frame = ToolbarPill.frame(size: size, stickerRect: CGRect(x: 100, y: 20, width: 200, height: 100),
                                      visibleFrame: visible)
        #expect(frame == CGRect(x: 140, y: 128, width: 120, height: 30))
    }

    @Test func thePillStaysOnTheStickersDisplay() {
        // Near the left edge: moved right, still under the sticker.
        let left = ToolbarPill.frame(size: size, stickerRect: CGRect(x: -40, y: 300, width: 100, height: 100),
                                     visibleFrame: visible)
        #expect(left == CGRect(x: 0, y: 262, width: 120, height: 30))
        // On another display (its own visible frame, here to the right of the first).
        let other = CGRect(x: 1000, y: 0, width: 800, height: 600)
        let right = ToolbarPill.frame(size: size, stickerRect: CGRect(x: 1700, y: 300, width: 100, height: 100),
                                      visibleFrame: other)
        #expect(right == CGRect(x: 1680, y: 262, width: 120, height: 30))
    }

    @Test func withRoomNeitherBelowNorAboveThePillOverlapsTheStickersLowerEdge() {
        let frame = ToolbarPill.frame(size: size, stickerRect: CGRect(x: 0, y: 0, width: 1000, height: 790),
                                      visibleFrame: visible)
        #expect(frame == CGRect(x: 440, y: 8, width: 120, height: 30))
    }

    @Test func aFractionalSizeLandsOnWholePoints() {
        let frame = ToolbarPill.frame(size: CGSize(width: 120.4, height: 30.2),
                                      stickerRect: CGRect(x: 100, y: 300, width: 200, height: 100), visibleFrame: visible)
        #expect(frame == CGRect(x: 140, y: 261, width: 121, height: 31))
    }

    @Test func thePanelNeverBecomesKeyAndFollowsThePanelPolicy() {
        let panel = ToolbarPill.makePanel()
        defer { panel.close() }
        #expect(!panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.canHide)
        #expect(!panel.isFloatingPanel)
        #expect(panel.hasShadow)
        #expect(!panel.isOpaque)
        #expect(panel.level == PanelPolicy.stickerLevel)
        #expect(panel.collectionBehavior == PanelPolicy.stickerBehavior)
        #expect(!panel.isVisible)
    }

    @Test func itsControlsTakeTheFirstClick() {
        let model = Self.model()
        let pill = ToolbarPill(model: model)
        defer { pill.close() }
        #expect(pill.panel.contentView?.acceptsFirstMouse(for: nil) == true)
        #expect(pill.size.width > 0 && pill.size.height > 0)
    }

    @Test func theStyleRowMakesThePillTaller() {
        let model = Self.model()
        let pill = ToolbarPill(model: model)
        defer { pill.close() }
        let closed = pill.size
        model.toggleStyles()
        #expect(model.showsStyles)
        #expect(pill.size.height > closed.height)
        model.toggleStyles()
        #expect(pill.size == closed)
    }

    /// A 200 × 100 pt Outline placement of a fixture master at 2×.
    static func model(flipped: Bool = false) -> ToolbarPillModel {
        let placement = Placement(sticker: UUID(), style: .outline, flipped: flipped,
                                  poses: ["1920x1080": Pose(x: 0.5, y: 0.5, scale: 1)])
        return ToolbarPillModel(placement: placement, natural: CGSize(width: 200, height: 100), sourceLongSide: 400,
                                renderer: StyleRenderer(masterProvider: { _ in Fixtures.image(width: 400, height: 200) }),
                                backingScale: 2)
    }

    @Test func theStyleRowRendersTheFourPreviewsInUIOrder() async {
        let model = Self.model(flipped: true)
        model.toggleStyles()
        #expect(await PickerModelTests.waitUntil { model.previews.count == 4 })
        #expect(model.renderOrder == StickerStyle.allCases)
        for style in StickerStyle.allCases {
            let request = model.previews[style]?.request
            #expect(request?.style == style)
            #expect(request?.flipped == true)
            #expect(request?.rotation == 0)
            // 200 × 100 fitted into the 40 × 40 preview box.
            #expect(request?.pointSize == CGSize(width: 40, height: 20))
        }
        model.cancel()
    }

    @Test func buttonsActAfterTheClickIsHandled() async {
        let model = Self.model()
        var actions: [String] = []
        model.onStyle = { actions.append("style \($0.rawValue)") }
        model.onFlip = { actions.append("flip") }
        model.onFloatOnTop = { actions.append("float") }
        model.onRemove = { actions.append("remove") }
        model.choose(.none)
        model.flip()
        model.floatOnTop()
        model.remove()
        #expect(actions.isEmpty)
        #expect(await PickerModelTests.waitUntil { actions.count == 4 })
        #expect(actions == ["style none", "flip", "float", "remove"])
    }

    @Test func updatesFromThePlacementShowInThePill() {
        let model = Self.model()
        model.update(style: .shadow, flipped: true, onTop: true)
        #expect(model.style == .shadow)
        #expect(model.flipped)
        #expect(model.onTop)
    }
}
