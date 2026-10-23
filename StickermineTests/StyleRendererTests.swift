import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct StyleRendererTests {
    private let id = UUID()

    private func request(points: CGSize, scale: CGFloat = 2, rotation: Double = 0, flipped: Bool = false,
                         style: StickerStyle = .outline) -> RenderRequest {
        RenderRequest(sticker: id, style: style, flipped: flipped, rotation: rotation, pointSize: points,
                      backingScale: scale)
    }

    private func renderer(_ master: CGImage?) -> StyleRenderer {
        StyleRenderer(masterProvider: { _ in master })
    }

    /// The baseline's contents are a CGImage.
    private func image(_ rendered: RenderedSticker) throws -> CGImage {
        let contents = rendered.contents as AnyObject
        try #require(CFGetTypeID(contents) == CGImage.typeID)
        return contents as! CGImage
    }

    @Test func rendersAtTheOnScreenPixelSize() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50)))
        #expect(rendered.pixelSize == CGSize(width: 200, height: 100))
        #expect(rendered.pointBounds == CGSize(width: 100, height: 50))
        let bitmap = try image(rendered)
        #expect(bitmap.width == 200)
        #expect(bitmap.height == 100)
    }

    @Test func theLongSideIsCappedAt2048Pixels() async throws {
        let master = Fixtures.image(width: 800, height: 400)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 2000, height: 1000)))
        #expect(rendered.pixelSize == CGSize(width: 2048, height: 1024))
        // The layer scales the capped bitmap back up to the full point size.
        #expect(rendered.pointBounds == CGSize(width: 2000, height: 1000))
        #expect(StyleRenderer.maxPixelLongSide == 2048)
    }

    @Test func rotationIsBakedIntoTheBoundingBox() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let quarter = try await renderer(master).render(request(points: CGSize(width: 100, height: 50), rotation: .pi / 2))
        #expect(quarter.pixelSize == CGSize(width: 100, height: 200))
        #expect(abs(quarter.pointBounds.width - 50) < 1e-9)
        #expect(abs(quarter.pointBounds.height - 100) < 1e-9)
        // A quarter turn counter-clockwise puts the master's left (red) half at the bottom.
        let bitmap = try image(quarter)
        let bottom = TestImages.rgba(of: bitmap, x: 50, y: 190)
        let top = TestImages.rgba(of: bitmap, x: 50, y: 10)
        #expect(bottom[0] > 200 && bottom[2] < 50)
        #expect(top[2] > 200 && top[0] < 50)
    }

    @Test func flipIsBakedIn() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50), flipped: true))
        let bitmap = try image(rendered)
        let left = TestImages.rgba(of: bitmap, x: 10, y: 50)
        let right = TestImages.rgba(of: bitmap, x: 190, y: 50)
        #expect(left[2] > 200 && left[0] < 50)    // blue now on the left
        #expect(right[0] > 200 && right[2] < 50)  // red on the right
    }

    @Test func theAlphaMaskMarksOpaquePixelsOnly() async throws {
        let master = Fixtures.image(width: 400, height: 200, left: [0, 200, 0, 255], right: [0, 0, 0, 0])
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50)))
        let mask = rendered.alphaMask
        #expect(mask.width == 200 && mask.height == 100)
        #expect(mask.isOpaque(atUnit: CGPoint(x: 0.25, y: 0.5)))
        #expect(!mask.isOpaque(atUnit: CGPoint(x: 0.75, y: 0.5)))
        #expect(!mask.isOpaque(atUnit: CGPoint(x: 1.5, y: 0.5)))
    }

    @Test func faintAlphaIsClearedSoItNeverCatchesClicks() async throws {
        // Alpha 3/255 on the right half: below the 0.02 floor.
        let master = Fixtures.image(width: 400, height: 200, left: [255, 255, 255, 255], right: [3, 3, 3, 3])
        let rendered = try await renderer(master).render(request(points: CGSize(width: 200, height: 100), scale: 1))
        let bitmap = try image(rendered)
        #expect(TestImages.rgba(of: bitmap, x: 150, y: 50) == [0, 0, 0, 0])
        #expect(TestImages.rgba(of: bitmap, x: 50, y: 50)[3] == 255)
        #expect(!rendered.alphaMask.isOpaque(atUnit: CGPoint(x: 0.75, y: 0.5)))
    }

    @Test func theMaskStaysSmallForLargeBitmaps() async throws {
        let master = Fixtures.image(width: 800, height: 400)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 1000, height: 500)))
        #expect(rendered.pixelSize == CGSize(width: 2000, height: 1000))
        #expect(rendered.alphaMask.width == 512)
        #expect(rendered.alphaMask.height == 256)
        #expect(rendered.alphaMask.isOpaque(atUnit: CGPoint(x: 0.5, y: 0.5)))
    }

    @Test func theMastersColourSpaceIsKept() async throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let master = Fixtures.image(width: 40, height: 20, colorSpace: p3)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 20, height: 10)))
        #expect(try image(rendered).colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func everyStyleRendersTheBaselineBitmap() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        for style in StickerStyle.allCases {
            let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50), style: style))
            #expect(rendered.pixelSize == CGSize(width: 200, height: 100), "\(style)")
        }
    }

    @Test func aMissingMasterThrows() async {
        await #expect(throws: StyleRenderer.RenderError.missingMaster) {
            _ = try await renderer(nil).render(request(points: CGSize(width: 10, height: 10)))
        }
    }
}
