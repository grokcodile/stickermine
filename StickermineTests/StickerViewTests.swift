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

    private func rendered(_ image: CGImage, points: CGSize, scale: CGFloat) -> RenderedSticker {
        RenderedSticker(contents: image, pixelSize: CGSize(width: image.width, height: image.height),
                        pointBounds: points, alphaMask: AlphaMask(width: 1, height: 1, bytes: [255]),
                        backingScale: scale)
    }

    @Test func showingARenderedStickerUsesItsPointBounds() {
        let view = makeView()
        let image = TestImages.bands(width: 300, height: 120, top: (0, 255, 0), bottom: (0, 0, 255))
        view.show(rendered(image, points: CGSize(width: 150, height: 60), scale: 2), shadow: nil, style: .outline)
        #expect(view.contentPointSize == CGSize(width: 150, height: 60))
        #expect((view.contentLayer.contents as AnyObject?) === image)
        // Without parameters there is no shadow and no margin.
        #expect(view.layerShadow == nil)
        #expect(view.contentLayer.shadowOpacity == 0)
        #expect(view.frameMargin == 0)
    }

    @Test func theLayerShadowIsThePixelParametersInPoints() {
        let view = makeView()
        let image = TestImages.bands(width: 800, height: 400, top: (0, 255, 0), bottom: (0, 0, 255))
        // 400 × 200 pt at 2×: 800 px long, so radius 10 px and offset 6 px.
        let parameters = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 800)
        for style in [StickerStyle.puffy, .outline, .shadow] {
            view.show(rendered(image, points: CGSize(width: 400, height: 200), scale: 2), shadow: parameters, style: style)
            #expect(view.layerShadow == LayerShadow(radius: 5, opacity: 0.35, offset: 3), "\(style)")
            #expect(view.contentLayer.shadowRadius == 5)
            #expect(view.contentLayer.shadowOpacity == 0.35)
            #expect(view.contentLayer.shadowOffset == CGSize(width: 0, height: -3))
            // StyleParameters.shadowMargin (36 px) in points.
            #expect(view.frameMargin == 18)
        }
        // A fractional margin is rounded up to whole device pixels: 466.74 px long
        // gives ceil(17.50) + 3.50 = 21.50 px, shown as 22 px = 11 pt.
        let odd = StyleParameters.forStickerPixels(longSide: 466.74, sourceLongSide: 910)
        view.show(rendered(image, points: CGSize(width: 233.37, height: 116.69), scale: 2), shadow: odd, style: .shadow)
        #expect(view.frameMargin == 11)
    }

    @Test func noneHasNoShadowAndNoMargin() {
        let view = makeView()
        let image = TestImages.bands(width: 8, height: 8, top: (0, 0, 0), bottom: (0, 0, 0))
        let parameters = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 800)
        view.show(rendered(image, points: CGSize(width: 4, height: 4), scale: 2), shadow: parameters, style: .outline)
        #expect(view.frameMargin > 0)
        view.show(rendered(image, points: CGSize(width: 4, height: 4), scale: 2), shadow: parameters, style: .none)
        #expect(view.layerShadow == nil)
        #expect(view.contentLayer.shadowOpacity == 0)
        #expect(view.frameMargin == 0)
    }

    @Test func rawContentsUseTheLayerShadowsOwnMargin() {
        let view = makeView()
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: pointSize, shadow: shadow)
        #expect(view.frameMargin == shadow.margin)
    }

    @Test func aBackingScaleChangeIsReportedWithTheWindowsScale() {
        let view = makeView()
        var reported: [CGFloat] = []
        view.onBackingScaleChange = { reported.append($0) }
        view.viewDidChangeBackingProperties()
        #expect(reported.isEmpty, "no window yet")
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(origin: .zero, size: view.frame.size))
        defer { panel.close() }
        panel.contentView = view
        view.viewDidChangeBackingProperties()
        #expect(reported.last == panel.backingScaleFactor)
    }
}
