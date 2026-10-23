import CoreImage
import Testing
@testable import Stickermine

struct StyleRecipesTests {
    /// A white square of `side` px with its lower-left corner at `origin` (Core Image's y-up space).
    private func square(_ side: CGFloat, at origin: CGPoint) -> CIImage {
        CIImage(color: .white).cropped(to: CGRect(origin: origin, size: CGSize(width: side, height: side)))
    }

    @Test func placingScalesFlipsAndRotatesAboutTheCanvasCentre() {
        let master = CIImage(cgImage: Fixtures.image(width: 40, height: 20))   // red left, blue right
        let flat = CGRect(x: 0, y: 0, width: 20, height: 10)
        let plain = CIRender.rgba(StyleRecipes.placed(master, size: flat.size, flipped: false, rotation: 0, canvas: flat),
                                  width: 20, height: 10)
        #expect(CIRender.pixel(plain, width: 20, x: 2, y: 5)[0] > 200)
        #expect(CIRender.pixel(plain, width: 20, x: 17, y: 5)[2] > 200)
        let flipped = CIRender.rgba(StyleRecipes.placed(master, size: flat.size, flipped: true, rotation: 0, canvas: flat),
                                    width: 20, height: 10)
        #expect(CIRender.pixel(flipped, width: 20, x: 2, y: 5)[2] > 200)
        // A quarter turn counter-clockwise on a 10 × 20 canvas: the left (red) half ends at the bottom.
        let tall = CGRect(x: 0, y: 0, width: 10, height: 20)
        let turned = CIRender.rgba(StyleRecipes.placed(master, size: flat.size, flipped: false, rotation: .pi / 2,
                                                       canvas: tall), width: 10, height: 20)
        #expect(CIRender.pixel(turned, width: 10, x: 5, y: 17)[0] > 200)
        #expect(CIRender.pixel(turned, width: 10, x: 5, y: 2)[2] > 200)
    }

    @Test func theSilhouetteIsWhiteWithTheImagesAlpha() {
        let half = CIImage(color: CIColor(red: 0.2, green: 0, blue: 0, alpha: 0.5))
            .cropped(to: CGRect(x: 0, y: 0, width: 4, height: 4))
        let bytes = CIRender.rgba(StyleRecipes.silhouette(of: half), width: 4, height: 4)
        let pixel = CIRender.pixel(bytes, width: 4, x: 1, y: 1)
        #expect(pixel.allSatisfy { abs(Int($0) - 128) <= 2 })   // premultiplied white at alpha 0.5
    }

    @Test func growingCoversTheRadiusAroundTheMaskAndNoMore() {
        let canvas = CGRect(x: 0, y: 0, width: 60, height: 60)
        let grown = StyleRecipes.grown(square(20, at: CGPoint(x: 20, y: 20)), by: 5, canvas: canvas)
        let bytes = CIRender.rgba(grown, width: 60, height: 60)
        #expect(CIRender.pixel(bytes, width: 60, x: 30, y: 30)[3] == 255)   // inside
        #expect(CIRender.pixel(bytes, width: 60, x: 17, y: 30)[3] == 255)   // 2.5 px outside
        #expect(CIRender.pixel(bytes, width: 60, x: 12, y: 30)[3] == 0)     // 7.5 px outside
        #expect(grown.extent == canvas)
    }

    @Test func closingBridgesANarrowGap() {
        // Two 30 px squares 8 px apart: a rim of 2 px leaves the gap; closing by 6 bridges it.
        let canvas = CGRect(x: 0, y: 0, width: 100, height: 60)
        let pair = square(30, at: CGPoint(x: 11, y: 15)).composited(over: square(30, at: CGPoint(x: 49, y: 15)))
        let open = CIRender.rgba(StyleRecipes.rim(around: pair, radius: 2, closing: 0, canvas: canvas), width: 100, height: 60)
        let closed = CIRender.rgba(StyleRecipes.rim(around: pair, radius: 2, closing: 6, canvas: canvas), width: 100, height: 60)
        #expect(CIRender.pixel(open, width: 100, x: 45, y: 30)[3] == 0)
        #expect(CIRender.pixel(closed, width: 100, x: 45, y: 30)[3] == 255)
        // Closing doesn't thicken the outer edge: 6 px beyond the left square is clear either way.
        #expect(CIRender.pixel(closed, width: 100, x: 5, y: 30)[3] == 0)
    }

    @Test func chokingRemovesAFaintRingAndKeepsTheBody() {
        let canvas = CGRect(x: 0, y: 0, width: 40, height: 40)
        let ring = CIImage(color: CIColor(red: 0.3, green: 0.3, blue: 0.3, alpha: 0.3))
            .cropped(to: CGRect(x: 6, y: 6, width: 28, height: 28))
        let body = CIImage(color: CIColor(red: 0, green: 0.5, blue: 0.5)).cropped(to: CGRect(x: 10, y: 10, width: 20, height: 20))
        let choked = StyleRecipes.choked(body.composited(over: ring), sigma: 0.5, canvas: canvas)
        let bytes = CIRender.rgba(choked, width: 40, height: 40)
        #expect(CIRender.pixel(bytes, width: 40, x: 8, y: 20)[3] == 0)      // the 0.3 ring
        #expect(CIRender.pixel(bytes, width: 40, x: 20, y: 20)[3] == 255)   // the body
    }
}
