import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct StickerGeometryTests {
    private let frame = CGRect(x: 40_000, y: 100, width: 1920, height: 1080)

    @Test func aPoseCentreIsRelativeToItsDisplaysFrame() {
        let center = StickerGeometry.center(of: Pose(x: 0.25, y: 0.5, scale: 1), in: frame)
        #expect(center == CGPoint(x: 40_480, y: 640))
        let pose = StickerGeometry.pose(center: center, scale: 1.5, in: frame)
        #expect(pose == Pose(x: 0.25, y: 0.5, scale: 1.5))
    }

    @Test func theStickerIsClampedInsideTheFrame() {
        let rect = StickerGeometry.clampedRect(size: CGSize(width: 200, height: 100),
                                               center: CGPoint(x: frame.maxX - 10, y: frame.minY + 5), within: frame)
        #expect(rect == CGRect(x: frame.maxX - 200, y: frame.minY, width: 200, height: 100))
    }

    @Test func aStickerLargerThanTheDisplayIsCentredOnThatAxis() {
        let rect = StickerGeometry.clampedRect(size: CGSize(width: 3000, height: 100),
                                               center: CGPoint(x: frame.minX, y: frame.midY), within: frame)
        #expect(rect.midX == frame.midX)
        #expect(rect.midY == frame.midY)
    }

    @Test func aCentreIsPulledInsideTheVisibleFrame() {
        let visible = CGRect(x: 40_000, y: 180, width: 1920, height: 970)   // Dock below, menu bar above
        #expect(StickerGeometry.reachableCenter(CGPoint(x: 40_000, y: 1180), visibleFrame: visible)
                == CGPoint(x: 40_008, y: 1142))
        #expect(StickerGeometry.reachableCenter(CGPoint(x: 41_000, y: 600), visibleFrame: visible)
                == CGPoint(x: 41_000, y: 600))
    }

    @Test func rotationGrowsTheBoundingBox() {
        let quarter = StickerGeometry.boundingSize(of: CGSize(width: 200, height: 100), rotation: .pi / 2)
        #expect(abs(quarter.width - 100) < 1e-9 && abs(quarter.height - 200) < 1e-9)
        let eighth = StickerGeometry.boundingSize(of: CGSize(width: 100, height: 100), rotation: .pi / 4)
        #expect(abs(eighth.width - 100 * 2.0.squareRoot()) < 1e-9)
    }

    @Test func aStoredPoseIsDrawnWhereItSays() throws {
        let display = Fixtures.display(uuid: "A", id: 3, frame: frame,
                                       visibleFrame: CGRect(x: 40_000, y: 100, width: 1920, height: 1050))
        // Near the top edge, under the menu bar: stored poses are not pulled in.
        let placement = Placement(sticker: UUID(), style: .shadow, poses: ["1920x1080": Pose(x: 0.5, y: 0.99, scale: 0.5)])
        let layout = try #require(StickerGeometry.layout(for: placement, natural: CGSize(width: 200, height: 100), on: display))
        #expect(!layout.isBorrowed)
        #expect(layout.pointSize == CGSize(width: 100, height: 50))
        // Clamped inside the frame: top edge at the frame's top.
        #expect(layout.stickerRect == CGRect(x: 40_910, y: 1130, width: 100, height: 50))
    }

    @Test func aBorrowedPoseHasItsCentreMadeReachable() throws {
        let display = Fixtures.display(uuid: "A", id: 3, frame: frame,
                                       visibleFrame: CGRect(x: 40_000, y: 100, width: 1920, height: 1050))
        let placement = Placement(sticker: UUID(), style: .shadow, poses: ["2560x1440": Pose(x: 0.5, y: 0.999, scale: 0.1)])
        let layout = try #require(StickerGeometry.layout(for: placement, natural: CGSize(width: 200, height: 100), on: display))
        #expect(layout.isBorrowed)
        #expect(layout.stickerRect.midY == 1142)   // visible maxY 1150 − 8
        #expect(abs(layout.pose.scale - 0.075) < 1e-12)
    }

    @Test func noPoseMeansNoLayout() {
        let display = Fixtures.display(uuid: "A", id: 3, frame: frame)
        let placement = Placement(sticker: UUID(), style: .shadow, poses: [:])
        #expect(StickerGeometry.layout(for: placement, natural: CGSize(width: 10, height: 10), on: display) == nil)
    }
}
