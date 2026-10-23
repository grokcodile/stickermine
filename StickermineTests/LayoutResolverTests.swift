import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct LayoutResolverTests {
    private func placement(_ poses: [String: Pose]) -> Placement {
        Placement(sticker: UUID(), style: .puffy, rotation: 0.3, poses: poses)
    }

    private func size(_ key: String) -> DisplaySize {
        DisplaySize(key: key)!
    }

    @Test func displaySizeKeys() {
        #expect(DisplaySize(width: 1920, height: 1080).key == "1920x1080")
        #expect(DisplaySize(CGSize(width: 1512.9, height: 982.2)).key == "1512x982")
        #expect(DisplaySize(key: "2560x1440") == DisplaySize(width: 2560, height: 1440))
        for bad in ["", "1920", "1920x", "x1080", "0x100", "100x-5", "1920x1080x1", "axb"] {
            #expect(DisplaySize(key: bad) == nil, "\(bad) should not parse")
        }
    }

    @Test func anExactKeyIsUsedAsIs() {
        let stored = Pose(x: 0.81, y: 0.22, scale: 1.3)
        let p = placement(["1920x1080": stored, "2560x1440": Pose(x: 0.1, y: 0.1, scale: 2)])
        #expect(LayoutResolver.pose(for: p, at: size("1920x1080")) == stored)
    }

    @Test func nothingStoredResolvesToNil() {
        #expect(LayoutResolver.pose(for: placement([:]), at: size("1920x1080")) == nil)
        #expect(LayoutResolver.pose(for: placement(["garbage": Pose(x: 0, y: 0, scale: 1)]), at: size("1920x1080")) == nil)
    }

    @Test func theSameOrientationWinsOverACloserSize() {
        // 1000x990 is far closer by log distance, but it is landscape and the target is portrait.
        let p = placement(["1000x990": Pose(x: 0.5, y: 0.5, scale: 1), "600x2000": Pose(x: 0.2, y: 0.8, scale: 1)])
        #expect(LayoutResolver.closestStoredSize(in: p.poses, to: size("1000x1100")) == size("600x2000"))
    }

    @Test func otherOrientationsAreUsedWhenNothingElseIsStored() throws {
        let p = placement(["1920x1080": Pose(x: 0.25, y: 0.75, scale: 1)])
        let pose = try #require(LayoutResolver.pose(for: p, at: size("1080x1920")))
        #expect(pose.x == 0.25)
        #expect(pose.y == 0.75)
        #expect(abs(pose.scale - 0.5625) < 1e-12)
    }

    @Test func theSmallestLogDistanceWins() {
        let p = placement([
            "1280x800": Pose(x: 0, y: 0, scale: 1),
            "2560x1440": Pose(x: 0, y: 0, scale: 1),
            "3840x2160": Pose(x: 0, y: 0, scale: 1),
        ])
        #expect(LayoutResolver.closestStoredSize(in: p.poses, to: size("2240x1260")) == size("2560x1440"))
    }

    @Test func aTieGoesToTheLargerAreaWhateverTheDictionaryOrder() throws {
        // The spec's example: 1920x1080 is exactly as far from 2304x1296 as from 1600x900.
        let a = Pose(x: 0.3, y: 0.4, scale: 1.2)
        let b = Pose(x: 0.7, y: 0.6, scale: 0.8)
        let entries = [("2304x1296", a), ("1600x900", b), ("800x600", Pose(x: 0, y: 0, scale: 1))]
        var generator = SystemRandomNumberGenerator()
        for round in 0..<200 {
            var poses = [String: Pose](minimumCapacity: round % 7 + 1)
            for (key, pose) in entries.shuffled(using: &generator) { poses[key] = pose }
            let resolved = try #require(LayoutResolver.pose(for: placement(poses), at: size("1920x1080")))
            #expect(resolved.x == 0.3 && resolved.y == 0.4, "round \(round) picked \(resolved)")
            #expect(abs(resolved.scale - 1.2 * (1920.0 / 2304.0)) < 1e-12)
        }
    }

    @Test func aTieOnDistanceAndAreaGoesToTheSmallerKey() {
        // 6000x1000 and 3000x2000 are both ln 2 from 3000x1000, both landscape,
        // both 6 000 000 pt²; "3000x2000" < "6000x1000".
        let poses = ["6000x1000": Pose(x: 0.9, y: 0.9, scale: 1), "3000x2000": Pose(x: 0.1, y: 0.1, scale: 1)]
        for _ in 0..<50 {
            var shuffled: [String: Pose] = [:]
            for (key, pose) in poses.shuffled() { shuffled[key] = pose }
            #expect(LayoutResolver.closestStoredSize(in: shuffled, to: size("3000x1000")) == size("3000x2000"))
        }
        #expect(LayoutResolver.pose(for: placement(poses), at: size("3000x1000"))?.scale == 0.5)
    }

    @Test func scaleIsMultipliedByTheSmallerRatio() throws {
        let p = placement(["2560x1440": Pose(x: 0.5, y: 0.5, scale: 2)])
        let pose = try #require(LayoutResolver.pose(for: p, at: size("2240x1260")))
        #expect(abs(pose.scale - 1.75) < 1e-12)
        // A wider display at the same height: the height ratio (1) is the smaller one.
        let wide = try #require(LayoutResolver.pose(for: p, at: size("3440x1440")))
        #expect(wide.scale == 2)
    }

    @Test func writingTouchesOnlyThisSize() {
        let original = placement(["1920x1080": Pose(x: 0.1, y: 0.2, scale: 1)])
        let moved = LayoutResolver.writing(Pose(x: 0.5, y: 0.5, scale: 1.5), to: original, at: size("2560x1440"))
        #expect(moved.poses == ["1920x1080": Pose(x: 0.1, y: 0.2, scale: 1),
                                "2560x1440": Pose(x: 0.5, y: 0.5, scale: 1.5)])
        #expect(moved.rotation == original.rotation)
        #expect(moved.id == original.id)
    }

    @Test func placingReplacesEveryPose() {
        let original = placement(["1920x1080": Pose(x: 0.1, y: 0.2, scale: 1), "2560x1440": Pose(x: 0.3, y: 0.3, scale: 1)])
        let placed = LayoutResolver.placing(Pose(x: 0.6, y: 0.4, scale: 0.9), to: original, at: size("1512x982"))
        #expect(placed.poses == ["1512x982": Pose(x: 0.6, y: 0.4, scale: 0.9)])
    }

    @Test func nonFinitePosesAreNeverWritten() {
        // One NaN or infinity in library.json makes every later save throw, so a
        // non-finite pose leaves the placement as it was.
        let size = DisplaySize(width: 1920, height: 1080)
        let start = Placement(sticker: UUID(), style: .puffy, poses: [size.key: Pose(x: 0.5, y: 0.5, scale: 1)])
        for bad in [Pose(x: .nan, y: 0.5, scale: 1), Pose(x: 0.5, y: .infinity, scale: 1), Pose(x: 0.5, y: 0.5, scale: -.infinity)] {
            #expect(LayoutResolver.writing(bad, to: start, at: size) == start)
            #expect(LayoutResolver.placing(bad, to: start, at: size) == start)
        }
    }
}
