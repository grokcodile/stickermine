import CoreGraphics
import CoreVideo
import Testing
@testable import Stickermine

/// Synthetic 512 × 512 coverage masks, rows top-down, with padded rows.
struct MaskSamplerTests {
    /// Instance 1 covers the top-left quarter, instance 2 the bottom-right quarter.
    static let masks: [(index: Int, mask: CVPixelBuffer)] = [
        (1, CaptureImages.maskBuffer { x, y in x < 256 && y < 256 ? 1 : 0 }),
        (2, CaptureImages.maskBuffer { x, y in x >= 256 && y >= 256 ? 0.9 : 0 }),
    ]

    @Test func rowsAreReadTopDown() {
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.25, y: 0.25), masks: Self.masks) == 1)
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.75, y: 0.75), masks: Self.masks) == 2)
    }

    @Test func backgroundIsNil() {
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.25, y: 0.75), masks: Self.masks) == nil)
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.75, y: 0.25), masks: Self.masks) == nil)
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.5, y: 0.5), masks: []) == nil)
    }

    @Test func coverageMustBeAboveOneHalf() {
        let half: [(index: Int, mask: CVPixelBuffer)] = [(3, CaptureImages.maskBuffer { _, _ in 0.5 })]
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.5, y: 0.5), masks: half) == nil)
        let more: [(index: Int, mask: CVPixelBuffer)] = [(3, CaptureImages.maskBuffer { _, _ in 0.51 })]
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.5, y: 0.5), masks: more) == 3)
    }

    @Test func overlappingSubjectsGoToTheStrongerOne() {
        let overlap: [(index: Int, mask: CVPixelBuffer)] = [
            (1, CaptureImages.maskBuffer { _, _ in 0.6 }),
            (2, CaptureImages.maskBuffer { _, _ in 0.8 }),
        ]
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.1, y: 0.1), masks: overlap) == 2)
    }

    @Test func edgesAndOutsidePoints() {
        #expect(MaskSampler.value(in: Self.masks[0].mask, atUnitTopLeft: CGPoint(x: 0, y: 0)) == 1)
        // u = 1 or v = 1 reads the last column or row.
        #expect(MaskSampler.value(in: Self.masks[1].mask, atUnitTopLeft: CGPoint(x: 1, y: 1)) == 0.9)
        #expect(MaskSampler.value(in: Self.masks[0].mask, atUnitTopLeft: CGPoint(x: -0.1, y: 0.5)) == nil)
        #expect(MaskSampler.value(in: Self.masks[0].mask, atUnitTopLeft: CGPoint(x: 0.5, y: 1.2)) == nil)
    }

    @Test func boundsAreUnitTopLeft() throws {
        let box = try #require(MaskSampler.bounds(of: Self.masks[1].mask))
        #expect(box == CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let empty = CaptureImages.maskBuffer { _, _ in 0 }
        #expect(MaskSampler.bounds(of: empty) == nil)
    }
}
