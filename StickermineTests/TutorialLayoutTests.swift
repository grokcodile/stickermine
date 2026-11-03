import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct TutorialLayoutTests {
    /// A 1512 × 982 built-in display with the menu bar (33 pt) and no Dock.
    private let frame = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let visible = CGRect(x: 0, y: 0, width: 1512, height: 949)
    private let home = CGSize(width: 640, height: 640)
    private let sizes = [CGSize(width: 300, height: 128), CGSize(width: 330, height: 128), CGSize(width: 634, height: 455)]

    private func near(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.01 }

    @Test func homeStartsCentredOnWholePoints() {
        #expect(TutorialLayout.homeFrame(size: home, in: visible) == CGRect(x: 436, y: 155, width: 640, height: 640))
        #expect(TutorialLayout.homeFrame(size: home, in: CGRect(x: 50_000, y: 80, width: 1512, height: 869))
                == CGRect(x: 50_436, y: 195, width: 640, height: 640))
    }

    @Test func cardsStackTopRightAndMapleSitsBottomRight() {
        let items = TutorialLayout.layout(naturalSizes: sizes, frame: frame, visibleFrame: visible, homeSize: home)
        let right = visible.maxX - TutorialLayout.margin
        #expect(items.allSatisfy { near($0.rect.maxX, right) })
        #expect(near(items[0].rect.maxY, visible.maxY - TutorialLayout.margin))
        #expect(near(items[1].rect.maxY, items[0].rect.minY - TutorialLayout.gap))
        #expect(near(items[2].rect.minY, visible.minY + TutorialLayout.margin))
    }

    @Test func everyStickerFitsAThirdOfTheHeightAndTheColumnBesideHome() {
        let items = TutorialLayout.layout(naturalSizes: sizes, frame: frame, visibleFrame: visible, homeSize: home)
        let homeFrame = TutorialLayout.homeFrame(size: home, in: visible)
        for item in items {
            #expect(item.rect.height <= frame.height / 3 + 0.01)
            #expect(item.rect.minX >= homeFrame.maxX + TutorialLayout.margin - 0.01)
            #expect(!item.rect.intersects(homeFrame))
            #expect(visible.contains(item.rect))
            #expect(item.pose.scale <= 1)
        }
        #expect(!items[0].rect.intersects(items[1].rect))
        #expect(!items[1].rect.intersects(items[2].rect))
        // Maple (634 pt wide, turned 3°) is the one the column shrinks.
        #expect(items[2].pose.scale < 1)
        #expect(near(items[2].rect.width, visible.maxX - TutorialLayout.margin - (homeFrame.maxX + TutorialLayout.margin)))
    }

    @Test func smallStickersAreNeverScaledUp() {
        let small = [CGSize(width: 100, height: 40), CGSize(width: 120, height: 40), CGSize(width: 90, height: 120)]
        let items = TutorialLayout.layout(naturalSizes: small, frame: frame, visibleFrame: visible, homeSize: home)
        #expect(items.allSatisfy { $0.pose.scale == 1 })
    }

    @Test func thePosesDrawExactlyWhereTheLayoutSays() {
        let display = Fixtures.display(uuid: Fixtures.mainUUID, id: 1, frame: CGRect(x: 50_000, y: 0, width: 1512, height: 982),
                                       visibleFrame: CGRect(x: 50_000, y: 0, width: 1512, height: 949))
        let items = TutorialLayout.layout(naturalSizes: sizes, frame: display.frame, visibleFrame: display.visibleFrame,
                                          homeSize: home)
        for (index, item) in items.enumerated() {
            let placement = Placement(sticker: UUID(), style: .shadow, rotation: TutorialLayout.rotations[index],
                                      poses: [display.size.key: item.pose])
            let drawn = StickerGeometry.layout(for: placement, natural: sizes[index], on: display)
            #expect(drawn.map { near($0.stickerRect.midX, item.rect.midX) && near($0.stickerRect.midY, item.rect.midY) } == true)
            #expect(drawn.map { near($0.stickerRect.width, item.rect.width) && near($0.stickerRect.height, item.rect.height) } == true)
        }
    }

    @Test func aNarrowDisplayStillGetsAUsableColumn() {
        // Home's full 640 pt here; the app narrows it on such a display (next test).
        let small = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let items = TutorialLayout.layout(naturalSizes: sizes, frame: small, visibleFrame: small, homeSize: home)
        for item in items {
            #expect(near(item.rect.maxX, small.maxX - TutorialLayout.margin))
            #expect(item.rect.width <= TutorialLayout.minimumColumn + 0.01)
            #expect(item.rect.height <= small.height / 3 + 0.01)
        }
    }

    @Test func aSmallDisplayGetsASmallerHomeThatTheTutorialsClear() {
        // 1024 × 640 "Larger Text" on a 13" MacBook Air, below the 33 pt menu bar.
        let small = CGRect(x: 0, y: 0, width: 1024, height: 607)
        let minimum = CGSize(width: 560, height: 480)
        let size = TutorialLayout.homeSize(preferred: home, minimum: minimum, in: small)
        #expect(size == CGSize(width: 560, height: 559))
        let homeFrame = TutorialLayout.homeFrame(size: size, in: small)
        #expect(small.contains(homeFrame))
        let items = TutorialLayout.layout(naturalSizes: sizes, frame: small, visibleFrame: small, homeSize: size)
        #expect(items.allSatisfy { !$0.rect.intersects(homeFrame) })
        // A display with room keeps Home's full size.
        #expect(TutorialLayout.homeSize(preferred: home, minimum: minimum, in: visible) == home)
    }

    @Test func theRotationsStayWithinTheBrandRange() {
        #expect(TutorialLayout.rotations.count == 3)
        #expect(TutorialLayout.rotations.allSatisfy { $0 >= -4 * .pi / 180 && $0 <= 3 * .pi / 180 })
    }
}
