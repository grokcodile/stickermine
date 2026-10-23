import CoreGraphics
import Testing
@testable import Stickermine

struct BundledImagesTests {
    @Test func mapleLoadsAtFullResolutionWithItsTransparency() throws {
        let maple = try #require(BundledImages.cgImage(named: BundledImages.mapleName))
        #expect(maple.width == 620)
        #expect(maple.height == 910)
        #expect(TestImages.rgba(of: maple, x: 0, y: 0)[3] == 0)
        #expect(TestImages.rgba(of: maple, x: 310, y: 455)[3] == 255)
    }

    @Test func aMissingAssetIsNil() {
        #expect(BundledImages.cgImage(named: "NoSuchAsset") == nil)
    }
}
