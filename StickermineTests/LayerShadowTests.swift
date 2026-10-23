import CoreGraphics
import Testing
@testable import Stickermine

struct LayerShadowTests {
    @Test func marginIsThreeRadiiRoundedUpPlusTheOffset() {
        #expect(LayerShadow(radius: 4, opacity: 0.35, offset: 2).margin == 14)
        #expect(LayerShadow(radius: 3.2, opacity: 0.35, offset: -2).margin == 12)
        #expect(LayerShadow(radius: 0, opacity: 0, offset: 0).margin == 0)
    }
}
