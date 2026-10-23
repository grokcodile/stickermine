import CoreGraphics
import Foundation
import IOSurface
import Testing
@testable import Stickermine

struct StyleRendererTests {
    private let id = UUID()
    private static let kinds: [StyleRenderer.Contents] = [.surface, .image]

    private func request(points: CGSize, scale: CGFloat = 2, rotation: Double = 0, flipped: Bool = false,
                         style: StickerStyle = .outline, sticker: UUID? = nil) -> RenderRequest {
        RenderRequest(sticker: sticker ?? id, style: style, flipped: flipped, rotation: rotation, pointSize: points,
                      backingScale: scale)
    }

    private func renderer(_ master: CGImage?, contents: StyleRenderer.Contents = .image,
                          kernel: Bool = true) -> StyleRenderer {
        StyleRenderer(masterProvider: { _ in master },
                      options: StyleRenderer.Options(contents: contents, closesRim: true, usesPuffyKernel: kernel))
    }

    @Test func theDefaultsComeFromTheSpikeDecision() {
        #expect(StyleRenderer.Options.standard.contents == StyleRenderer.defaultContents)
        #expect(StyleRenderer.Options.standard.closesRim)
        #expect(StyleRenderer.Options.standard.usesPuffyKernel)
    }

    @Test(arguments: kinds)
    func rendersAtTheOnScreenPixelSize(_ kind: StyleRenderer.Contents) async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let rendered = try await renderer(master, contents: kind)
            .render(request(points: CGSize(width: 100, height: 50), style: .shadow))
        #expect(rendered.pixelSize == CGSize(width: 200, height: 100))
        #expect(rendered.pointBounds == CGSize(width: 100, height: 50))
        #expect(rendered.backingScale == 2)
        #expect(RenderedPixels.size(rendered.contents) == CGSize(width: 200, height: 100))
        #expect(kind == .surface ? RenderedPixels.isSurface(rendered.contents) : RenderedPixels.isImage(rendered.contents))
    }

    @Test(arguments: [StickerStyle.puffy, .outline])
    func aRimGrowsTheBitmapSoTheSubjectKeepsItsSize(_ style: StickerStyle) throws {
        // 100 × 50 pt at 2×: r = 12 × 200 / 800 = 3 px, so the rim reaches 4 px = 2 pt.
        let canvas = StyleRenderer.canvas(for: request(points: CGSize(width: 100, height: 50), style: style))
        #expect(canvas.width == 208 && canvas.height == 108)
        #expect(canvas.drawSize == CGSize(width: 200, height: 100))
        #expect(canvas.pointBounds == CGSize(width: 104, height: 54))
        let plain = StyleRenderer.canvas(for: request(points: CGSize(width: 100, height: 50), style: .none))
        #expect(plain.width == 200 && plain.height == 100 && plain.pointBounds == CGSize(width: 100, height: 50))
        // Uncapped, the box in points is the bitmap's whole-pixel box: the layer maps it 1:1.
        for rotation in [0, 0.3, 1.1] {
            let odd = StyleRenderer.canvas(for: request(points: CGSize(width: 151.37, height: 97.81),
                                                        rotation: rotation, style: style))
            #expect(odd.pointBounds == CGSize(width: CGFloat(odd.width) / 2, height: CGFloat(odd.height) / 2))
        }
    }

    @Test(arguments: StickerStyle.allCases)
    func theLongSideIsCappedAt2048PixelsInEveryStyle(_ style: StickerStyle) async throws {
        let master = Fixtures.image(width: 800, height: 400)
        let points = CGSize(width: 2000, height: 1000)
        let rendered = try await renderer(master, contents: .surface).render(request(points: points, style: style))
        // 4000 px on screen: the rim (if any) reaches ceil(60) + 1 = 61 px = 30.5 pt.
        let reach: CGFloat = style == .puffy || style == .outline ? 61 : 0
        let outer = CGSize(width: 4000 + 2 * reach, height: 2000 + 2 * reach)
        let height = (outer.height * 2048 / outer.width - 0.001).rounded(.up)
        #expect(rendered.pixelSize == CGSize(width: 2048, height: height))
        #expect(RenderedPixels.size(rendered.contents) == rendered.pixelSize)
        // The layer scales the capped bitmap back up to the full point size.
        #expect(rendered.pointBounds == CGSize(width: 2000 + reach, height: 1000 + reach))
        #expect(rendered.alphaMask.width == 512)
        #expect(StyleRenderer.maxPixelLongSide == 2048)
    }

    @Test func aHugeMasterRendersAtTheOnScreenSizeNotTheCaptureSize() async throws {
        // A 5K capture shown at 200 × 112.5 pt on a 2× display: 400 × 225 px in memory.
        let master = Fixtures.image(width: 5120, height: 2880)
        for style in StickerStyle.allCases {
            let rendered = try await renderer(master, contents: .surface)
                .render(request(points: CGSize(width: 200, height: 112.5), style: style))
            // Outline and Puffy add their rim: ceil(6) + 1 = 7 px on every side.
            let reach: CGFloat = style == .puffy || style == .outline ? 7 : 0
            #expect(rendered.pixelSize == CGSize(width: 400 + 2 * reach, height: 225 + 2 * reach), "\(style)")
        }
    }

    @Test(arguments: kinds)
    func rotationIsBakedIntoTheBoundingBox(_ kind: StyleRenderer.Contents) async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let quarter = try await renderer(master, contents: kind)
            .render(request(points: CGSize(width: 100, height: 50), rotation: .pi / 2, style: .none))
        #expect(quarter.pixelSize == CGSize(width: 100, height: 200))
        #expect(abs(quarter.pointBounds.width - 50) < 1e-9)
        #expect(abs(quarter.pointBounds.height - 100) < 1e-9)
        // A quarter turn counter-clockwise puts the master's left (red) half at the bottom.
        let bottom = RenderedPixels.rgba(quarter.contents, x: 50, y: 190)
        let top = RenderedPixels.rgba(quarter.contents, x: 50, y: 10)
        #expect(bottom[0] > 200 && bottom[2] < 50)
        #expect(top[2] > 200 && top[0] < 50)
    }

    @Test func flipIsBakedIn() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let rendered = try await renderer(master)
            .render(request(points: CGSize(width: 100, height: 50), flipped: true, style: .none))
        let left = RenderedPixels.rgba(rendered.contents, x: 10, y: 50)
        let right = RenderedPixels.rgba(rendered.contents, x: 190, y: 50)
        #expect(left[2] > 200 && left[0] < 50)    // blue now on the left
        #expect(right[0] > 200 && right[2] < 50)  // red on the right
    }

    @Test(arguments: StickerStyle.allCases, kinds)
    func everyStyleRendersANonEmptyBitmapOfTheExpectedSize(_ style: StickerStyle,
                                                           _ kind: StyleRenderer.Contents) async throws {
        let master = Masters.disc(diameter: 300)
        let rendered = try await renderer(master, contents: kind)
            .render(request(points: CGSize(width: 150, height: 150), style: style))
        // 300 px, plus ceil(4.5) + 1 = 6 px of rim on every side for Outline and Puffy.
        let side: CGFloat = style == .puffy || style == .outline ? 312 : 300
        #expect(rendered.pixelSize == CGSize(width: side, height: side))
        #expect(RenderedPixels.size(rendered.contents) == rendered.pixelSize)
        #expect(RenderedPixels.rgba(rendered.contents, x: Int(side) / 2, y: Int(side) / 2)[3] == 255)
        #expect(RenderedPixels.rgba(rendered.contents, x: 0, y: 0)[3] == 0)
        #expect(rendered.alphaMask.isOpaque(atUnit: CGPoint(x: 0.5, y: 0.5)))
        #expect(!rendered.alphaMask.isOpaque(atUnit: CGPoint(x: 0.01, y: 0.01)))
    }

    @Test func theAlphaMaskMarksOpaquePixelsOnly() async throws {
        let master = Fixtures.image(width: 400, height: 200, left: [0, 200, 0, 255], right: [0, 0, 0, 0])
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50), style: .shadow))
        let mask = rendered.alphaMask
        #expect(mask.width == 200 && mask.height == 100)
        #expect(mask.isOpaque(atUnit: CGPoint(x: 0.25, y: 0.5)))
        #expect(!mask.isOpaque(atUnit: CGPoint(x: 0.75, y: 0.5)))
        #expect(!mask.isOpaque(atUnit: CGPoint(x: 1.5, y: 0.5)))
    }

    @Test(arguments: StickerStyle.allCases, kinds)
    func faintAlphaNeverSurvivesSoItNeverCatchesClicks(_ style: StickerStyle,
                                                       _ kind: StyleRenderer.Contents) async throws {
        let master = Masters.disc(diameter: 200)
        let rendered = try await renderer(master, contents: kind)
            .render(request(points: CGSize(width: 100, height: 100), rotation: 0.3, style: style))
        let alphas = RenderedPixels.alphas(rendered.contents)
        #expect(!alphas.isEmpty)
        #expect(alphas.allSatisfy { $0 == 0 || $0 >= StyleRenderer.alphaFloor })
        #expect(alphas.contains(0) && alphas.contains(255))
    }

    @Test func clampingClearsFaintPixelsAndSkipsRowPadding() {
        // 3 × 2 pixels in rows of 16 bytes (4 bytes of padding, as an IOSurface pads).
        var bytes: [UInt8] = [
            9, 9, 9, 4,   9, 9, 9, 5,   9, 9, 9, 255,   7, 7, 7, 7,
            1, 1, 1, 1,   0, 0, 0, 0,   9, 9, 9, 200,   7, 7, 7, 7,
        ]
        let mask = bytes.withUnsafeMutableBufferPointer {
            StyleRenderer.clampAlphaAndBuildMask(pixels: $0.baseAddress!, width: 3, height: 2, rowBytes: 16)
        }
        #expect(Array(bytes[0..<4]) == [0, 0, 0, 0])       // alpha 4 < 5: cleared
        #expect(Array(bytes[4..<8]) == [9, 9, 9, 5])       // alpha 5 kept
        #expect(Array(bytes[16..<20]) == [0, 0, 0, 0])     // alpha 1 cleared
        #expect(Array(bytes[12..<16]) == [7, 7, 7, 7])     // padding untouched
        #expect(mask.width == 3 && mask.height == 2)
        #expect(mask.bytes == [0, 5, 255, 0, 0, 200])
    }

    @Test func theOutlineIsAWhiteRimRightOutsideTheSubject() async throws {
        // 400 pt at 2×: r = 12 px; the bitmap grows by the rim's reach (13 px) on every side.
        let master = Masters.disc(diameter: 800, rgb: (20, 140, 130))
        let rendered = try await renderer(master).render(request(points: CGSize(width: 400, height: 400), style: .outline))
        let parameters = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 800)
        let reach = Int(parameters.rimReach(for: .outline))
        #expect(rendered.pixelSize == CGSize(width: 800 + 2 * reach, height: 800 + 2 * reach))
        let middle = 400 + reach
        // The disc's left edge is at x = reach on the middle row.
        let rim = RenderedPixels.rgba(rendered.contents, x: reach - Int(parameters.rimRadius / 2), y: middle)
        let subject = RenderedPixels.rgba(rendered.contents, x: reach + 8, y: middle)
        let outside = RenderedPixels.rgba(rendered.contents, x: 0, y: middle)
        #expect(rim[3] == 255 && rim[0] > 245 && rim[1] > 245 && rim[2] > 245)
        #expect(subject[3] == 255 && subject[1] > 120 && subject[0] < 40)
        #expect(outside[3] == 0)
    }

    @Test(arguments: [StickerStyle.none, .shadow])
    func noneAndShadowChokeTheLightHalo(_ style: StickerStyle) async throws {
        // A disc inside a 4 px ring at alpha 0.3, rendered 1:1.
        let master = Masters.fringe(diameter: 200)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 100), style: style))
        let halo = RenderedPixels.rgba(rendered.contents, x: 2, y: 100)    // inside the 0.3 ring
        let body = RenderedPixels.rgba(rendered.contents, x: 20, y: 100)
        #expect(halo[3] == 0)
        #expect(body[3] == 255)
    }

    @Test(arguments: [true, false], kinds)
    func puffyIsLitFromTheTopLeftOnScreenWhateverTheRotation(_ kernel: Bool,
                                                            _ kind: StyleRenderer.Contents) async throws {
        let master = Masters.square(side: 400, rgb: (128, 128, 128))
        let shader = renderer(master, contents: kind, kernel: kernel)
        for rotation in [0, Double.pi] {
            let rendered = try await shader.render(request(points: CGSize(width: 200, height: 200), rotation: rotation,
                                                           flipped: rotation > 0, style: .puffy))
            // Just inside the square's top-left and bottom-right corners (y = 0 is the top).
            let side = Int(rendered.pixelSize.width)
            let topLeft = RenderedPixels.luma(rendered.contents, x: 40, y: 40)
            let bottomRight = RenderedPixels.luma(rendered.contents, x: side - 41, y: side - 41)
            #expect(topLeft > bottomRight + 15, "rotation \(rotation), kernel \(kernel)")
        }
        #expect(shader.lastPuffyPath == (kernel ? .kernel : .builtIn))
    }

    @Test func theInscribedRadiusIsMeasuredOncePerSticker() async throws {
        let shader = renderer(Masters.disc(diameter: 400))
        let other = UUID()
        _ = try await shader.render(request(points: CGSize(width: 200, height: 200), style: .puffy))
        _ = try await shader.render(request(points: CGSize(width: 100, height: 100), style: .puffy))
        #expect(shader.inscribedMeasurementCount == 1)
        _ = try await shader.render(request(points: CGSize(width: 100, height: 100), style: .puffy, sticker: other))
        #expect(shader.inscribedMeasurementCount == 2)
        shader.invalidateCache(for: other)
        _ = try await shader.render(request(points: CGSize(width: 100, height: 100), style: .puffy, sticker: other))
        #expect(shader.inscribedMeasurementCount == 3)
    }

    @Test(arguments: kinds)
    func theMastersColourSpaceIsKept(_ kind: StyleRenderer.Contents) async throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let master = Fixtures.image(width: 40, height: 20, colorSpace: p3)
        let rendered = try await renderer(master, contents: kind).render(request(points: CGSize(width: 20, height: 10)))
        #expect(RenderedPixels.colorSpace(rendered.contents)?.name == CGColorSpace.displayP3)
    }

    @MainActor
    @Test func rendersRunOffTheMainThread() async throws {
        let master = Fixtures.image(width: 40, height: 20)
        let sawMain = Flag()
        let shader = StyleRenderer(masterProvider: { _ in
            if Thread.isMainThread { sawMain.set() }
            return master
        })
        _ = try await shader.render(request(points: CGSize(width: 20, height: 10)))
        #expect(!sawMain.isSet)
    }

    @Test func prewarmReturnsAtOnceAndCompilesTheKernelOffTheMainThread() async throws {
        let shader = renderer(Masters.square(side: 8))
        let start = Date()
        shader.prewarm()
        #expect(Date().timeIntervalSince(start) < 0.05)
        // A render queued after prewarm runs after the compile.
        _ = try await shader.render(request(points: CGSize(width: 4, height: 4), style: .puffy))
        #expect(PuffyKernel.compiled.kernel != nil)
        #expect(!PuffyKernel.compiled.onMainThread)
    }

    @Test func aMissingMasterThrows() async {
        await #expect(throws: StyleRenderer.RenderError.missingMaster) {
            _ = try await renderer(nil).render(request(points: CGSize(width: 10, height: 10)))
        }
    }

    @Test func anEmptySizeThrows() async {
        await #expect(throws: StyleRenderer.RenderError.emptySize) {
            _ = try await renderer(Fixtures.image(width: 4, height: 4)).render(request(points: .zero))
        }
    }

    @Test func onScreenParametersFollowPointsTimesBackingScale() {
        let parameters = request(points: CGSize(width: 200, height: 400), scale: 2).onScreenParameters(sourceLongSide: 512)
        #expect(parameters == StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 512))
        #expect(parameters.shadowRadius == 10)
    }
}

/// A thread-safe one-way flag for checking which thread a closure ran on.
final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func set() {
        lock.lock()
        value = true
        lock.unlock()
    }

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}
