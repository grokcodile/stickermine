import Foundation
import Testing
@testable import Stickermine

struct HoleFillerTests {
    /// A `size` × `size` mask from `value(x, y)`.
    static func mask(_ size: Int, _ value: (Int, Int) -> Float) -> [Float] {
        (0..<(size * size)).map { value($0 % size, $0 / size) }
    }

    /// A ring: opaque between radius 6 and 15 around (20, 20), a hole inside.
    static func ring(hole: Float = 0) -> [Float] {
        mask(40) { x, y in
            let d = hypot(Double(x) - 20, Double(y) - 20)
            if d < 6 { return hole }
            return d < 15 ? 1 : 0
        }
    }

    @Test func anEnclosedHoleIsFilled() {
        var alpha = Self.ring()
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 20] == 1)          // the centre
        #expect(alpha[0] == 0)                     // the outside stays clear
        #expect(alpha[20 * 40 + 37] == 0)
    }

    @Test func faintSpeckleInsideAHoleIsCleared() {
        var alpha = Self.ring(hole: 0.3)
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 20] == 1)
    }

    @Test func aGapOpenToTheOutsideIsNotAHole() {
        // A C shape: the ring with a slot cut from the hole to the right edge.
        var alpha = Self.mask(40) { x, y in
            let d = hypot(Double(x) - 20, Double(y) - 20)
            if d < 6 || (x >= 20 && abs(y - 20) <= 1) { return 0 }
            return d < 15 ? 1 : 0
        }
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 20] == 0)
    }

    @Test func theSoftOuterEdgeKeepsItsAlpha() {
        // Opaque 20 × 20 block with a 0.6 rim one pixel wide, on clear.
        var alpha = Self.mask(40) { x, y in
            if (10..<30).contains(x) && (10..<30).contains(y) { return 1 }
            if (9..<31).contains(x) && (9..<31).contains(y) { return 0.6 }
            return 0
        }
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[9 * 40 + 20] == 0.6)
        #expect(alpha[20 * 40 + 9] == 0.6)
    }

    @Test func pixelsFartherThanTheEdgeBecomeOpaque() {
        // A 0.7 square: everything deeper than 3 px from the outside becomes 1.
        var alpha = Self.mask(40) { x, y in (10..<30).contains(x) && (10..<30).contains(y) ? 0.7 : 0 }
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 11] == 0.7)    // 2 px in
        #expect(alpha[20 * 40 + 12] == 0.7)    // 3 px in
        #expect(alpha[20 * 40 + 13] == 1)      // 4 px in
    }

    @Test func aMismatchedSizeChangesNothing() {
        var alpha: [Float] = [0, 0.2, 1]
        HoleFiller.fill(alpha: &alpha, width: 2, height: 2, edge: 3)
        #expect(alpha == [0, 0.2, 1])
    }
}
