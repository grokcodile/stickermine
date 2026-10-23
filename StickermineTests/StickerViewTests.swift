import AppKit
import Testing
@testable import Stickermine

@MainActor
struct StickerViewTests {
    private let shadow = LayerShadow(radius: 4, opacity: 0.35, offset: 2)
    private let pointSize = CGSize(width: 100, height: 50)

    private func makeView() -> StickerView {
        StickerView(frame: NSRect(origin: .zero, size: StickerView.frameSize(pointSize: pointSize, shadow: shadow)))
    }

    @Test func isLayerHostingWithItsThreeLayersInOrder() {
        let view = makeView()
        #expect(view.wantsLayer)
        let sublayers = view.layer?.sublayers ?? []
        #expect(sublayers.count == 3)
        #expect(sublayers.first === view.hitPadLayer)
        #expect(sublayers.dropFirst().first === view.contentLayer)
        #expect(sublayers.last === view.outlineLayer)
    }

    @Test func frameSizeAddsTheShadowMarginOnEverySide() {
        #expect(StickerView.frameSize(pointSize: pointSize, shadow: shadow) == CGSize(width: 128, height: 78))
        #expect(StickerView.frameSize(pointSize: pointSize, shadow: nil) == pointSize)
    }

    @Test func showContentsCentresTheBitmapAndAppliesTheLayerShadow() throws {
        let view = makeView()
        let image = TestImages.bands(width: 200, height: 100, top: (255, 0, 0), bottom: (0, 0, 255))
        view.showContents(image, pointSize: pointSize, shadow: shadow)
        #expect(view.contentLayer.bounds.size == pointSize)
        #expect(view.contentLayer.position == CGPoint(x: 64, y: 39))
        let contents = try #require(view.contentLayer.contents)
        #expect((contents as AnyObject) === image)
        #expect(view.contentLayer.shadowRadius == 4)
        #expect(view.contentLayer.shadowOpacity == 0.35)
        #expect(view.contentLayer.shadowOffset == CGSize(width: 0, height: -2))
        #expect(view.hitPadLayer.frame == view.bounds)
    }

    @Test func noShadowMeansAZeroShadowOpacity() {
        let view = StickerView(frame: NSRect(origin: .zero, size: pointSize))
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: pointSize, shadow: nil)
        #expect(view.contentLayer.shadowOpacity == 0)
        #expect(view.contentLayer.position == CGPoint(x: 50, y: 25))
    }

    @Test func clearContentsDropsTheBitmap() {
        let view = makeView()
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: pointSize, shadow: shadow)
        view.clearContents()
        #expect(view.contentLayer.contents == nil)
    }

    @Test func editingChromeIsAHitPadOfAlphaOneOver255() {
        let view = makeView()
        #expect(view.hitPadLayer.isHidden)
        #expect(view.outlineLayer.isHidden)
        view.setEditingChrome(true)
        #expect(view.isShowingEditingChrome)
        #expect(!view.hitPadLayer.isHidden)
        #expect(!view.outlineLayer.isHidden)
        let alpha = view.hitPadLayer.backgroundColor?.alpha ?? 0
        #expect(abs(alpha - 1.0 / 255.0) < 1e-6)
        view.setEditingChrome(false)
        #expect(view.hitPadLayer.isHidden)
        #expect(view.outlineLayer.isHidden)
    }

    @Test func outlineIsDrawnAtTheWindowsBackingScale() {
        let view = makeView()
        #expect(view.outlineLayer.contentsScale == 1)
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(origin: .zero, size: view.frame.size))
        defer { panel.close() }
        panel.contentView = view
        // A layer-hosting view's sublayers stay at 1× unless the view sets them,
        // which leaves the dashed outline blurry on a Retina display.
        #expect(view.outlineLayer.contentsScale == panel.backingScaleFactor)
    }

    @Test func acceptsTheFirstMouseClick() {
        #expect(makeView().acceptsFirstMouse(for: nil))
    }

    @Test func boundingSizeOfAScaledRotatedSticker() {
        let quarter = StickerView.boundingSize(of: pointSize, scale: 2, rotation: .pi / 2)
        #expect(abs(quarter.width - 100) < 1e-9)
        #expect(abs(quarter.height - 200) < 1e-9)
        let eighth = StickerView.boundingSize(of: CGSize(width: 100, height: 100), scale: 1, rotation: .pi / 4)
        #expect(abs(eighth.width - 100 * 2.0.squareRoot()) < 1e-9)
    }

    @Test func contentTransformScalesAndRotatesAroundTheCentre() {
        let view = makeView()
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: pointSize, shadow: shadow)
        view.setContentTransform(scale: 2, rotation: .pi / 2)
        let t = view.contentLayer.transform
        #expect(abs(t.m11) < 1e-9)
        #expect(abs(t.m12 - 2) < 1e-9)
        #expect(abs(t.m21 + 2) < 1e-9)
        #expect(abs(t.m22) < 1e-9)
        #expect(view.contentLayer.position == CGPoint(x: 64, y: 39))
        #expect(view.contentScale == 2)
    }
}
