import CoreGraphics
import CoreVideo
import IOSurface
import Testing
@testable import Stickermine

struct SurfaceContentsTests {
    @Test func surfaceIsUprightPremultipliedBGRA() throws {
        let image = TestImages.bands(width: 8, height: 8, top: (255, 0, 0), bottom: (0, 0, 255))
        let surface = try #require(SurfaceContents.make(from: image))
        #expect(surface.width == 8)
        #expect(surface.height == 8)
        #expect(surface.pixelFormat == kCVPixelFormatType_32BGRA)
        _ = surface.lock(options: .readOnly, seed: nil)
        defer { _ = surface.unlock(options: .readOnly, seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let rowBytes = surface.bytesPerRow
        func bgra(_ x: Int, _ y: Int) -> [UInt8] { (0..<4).map { bytes[y * rowBytes + x * 4 + $0] } }
        let top = bgra(1, 0)        // memory row 0 must be the image's top (red)
        let bottom = bgra(1, 7)     // the last row its bottom (blue)
        let clear = bgra(7, 0)      // the transparent column stays transparent
        #expect(top[2] > 250 && top[0] < 5 && top[3] == 255)
        #expect(bottom[0] > 250 && bottom[2] < 5 && bottom[3] == 255)
        #expect(clear == [0, 0, 0, 0])
    }

    @Test func surfaceIsTaggedWithTheImageColourSpace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = TestImages.bands(width: 4, height: 4, top: (255, 0, 0), bottom: (0, 255, 0), colorSpace: p3)
        let surface = try #require(SurfaceContents.make(from: image))
        let tag = try #require(IOSurfaceCopyValue(surface, kIOSurfaceColorSpace))
        let space = try #require(CGColorSpace(propertyListPlist: tag))
        #expect(space.name == CGColorSpace.displayP3)
    }

    @Test func aGrayImageBecomesAnSRGBSurface() throws {
        // M3 can meet gray masters and bundled art; a BGRA surface can't be tagged gray.
        let gray = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let surface = try #require(SurfaceContents.make(from: image))
        let tag = try #require(IOSurfaceCopyValue(surface, kIOSurfaceColorSpace))
        let space = try #require(CGColorSpace(propertyListPlist: tag))
        #expect(space.model == .rgb)
        #expect(space.name == CGColorSpace.sRGB)
        _ = surface.lock(options: .readOnly, seed: nil)
        defer { _ = surface.unlock(options: .readOnly, seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        // White stays white: B, G, R and A all near 255.
        #expect((0..<4).allSatisfy { bytes[$0] > 250 })
    }

    @Test func aBlankSurfaceIsBGRAWithRowsAtLeastFourBytesAPixel() throws {
        let surface = try #require(SurfaceContents.blank(width: 13, height: 5))
        #expect(surface.width == 13 && surface.height == 5)
        #expect(surface.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(surface.bytesPerElement == 4)
        #expect(surface.bytesPerRow >= 13 * 4)
        #expect(SurfaceContents.blank(width: 0, height: 5) == nil)
    }

    @Test func taggingRecordsTheColourSpace() throws {
        let surface = try #require(SurfaceContents.blank(width: 2, height: 2))
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        SurfaceContents.tag(surface, with: p3)
        let tag = try #require(IOSurfaceCopyValue(surface, kIOSurfaceColorSpace))
        #expect(CGColorSpace(propertyListPlist: tag)?.name == CGColorSpace.displayP3)
    }
}
