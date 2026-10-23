import CoreGraphics
import Testing
@testable import Stickermine

/// Temporary, like DebugMaple itself: M4 deletes this file with it.
struct DebugMapleTests {
    @Test func theStyleComesFromTheArgumentAfterTheFlag() {
        #expect(DebugMaple.styles(in: ["Stickermine", "-debugPlaceMaple"]) == [.shadow])
        #expect(DebugMaple.styles(in: ["Stickermine", "-debugPlaceMaple", "all"]) == StickerStyle.allCases)
        #expect(DebugMaple.styles(in: ["Stickermine", "-debugPlaceMaple", "Puffy"]) == [.puffy])
        #expect(DebugMaple.styles(in: ["Stickermine", "-debugPlaceMaple", "glitter"]) == [.shadow])
        #expect(DebugMaple.styles(in: ["Stickermine"]) == [.shadow])
    }

    @Test func sideBySideCopiesFitInHalfTheDisplay() {
        let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let natural = CGSize(width: 310, height: 455)
        let four = DebugMaple.layout(count: 4, natural: natural, pointer: CGPoint(x: 756, y: 491), frame: frame)
        #expect(four.centers.count == 4)
        // (756 − 3 gaps of 40) / 4 = 159 pt wide each.
        #expect(abs(four.size.width - 159) < 1e-9)
        #expect(abs(four.size.height - 159 * 455 / 310) < 1e-9)
        #expect(four.centers.map(\.y) == [491, 491, 491, 491])
        #expect(abs(four.centers[0].x - (756 - 1.5 * 199)) < 1e-9)
        #expect(abs(four.centers[3].x - (756 + 1.5 * 199)) < 1e-9)
        let one = DebugMaple.layout(count: 1, natural: natural, pointer: CGPoint(x: 100, y: 100), frame: frame)
        #expect(one.size == natural)           // fits: no shrinking
        #expect(one.centers == [CGPoint(x: 100, y: 100)])
    }
}
