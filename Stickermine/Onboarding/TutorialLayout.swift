import CoreGraphics
import Foundation

/// Where the first-run tutorial stickers go (spec section 13). Pure.
///
/// On the main display, clear of Home's initial frame (centred in the
/// visible frame): the two text cards stacked in the top-right corner,
/// Maple in the bottom-right corner, all right-aligned in the column between
/// Home's right edge and the visible frame's right edge, `margin` from every
/// edge. Each sticker, turned by its small rotation (the brand's "slight
/// rotation between −4° and +3°"), is scaled down (never up) to fit within a
/// third of the display's height and the column's width. On a small display
/// Home starts smaller (`homeSize`) so the column keeps `minimumColumn`; a
/// column still narrower than that is widened to it, leftwards.
enum TutorialLayout {
    static let margin: CGFloat = 24
    static let gap: CGFloat = 16
    static let minimumColumn: CGFloat = 200
    /// Tutorial 1, 2 and Maple: −2°, +1.5°, +3° (radians, counter-clockwise).
    static let rotations: [Double] = [-2 * .pi / 180, 1.5 * .pi / 180, 3 * .pi / 180]

    struct Item: Equatable {
        /// The rotated sticker's box on screen.
        let rect: CGRect
        let pose: Pose
    }

    /// Home's first frame: `size` centred in `visibleFrame`, on whole points.
    static func homeFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: (visibleFrame.midX - size.width / 2).rounded(), y: (visibleFrame.midY - size.height / 2).rounded(),
               width: size.width, height: size.height)
    }

    /// Home's first size on a display: `preferred`, narrowed (never below
    /// `minimum`) so the column right of it keeps `minimumColumn`, and
    /// shortened to fit `visibleFrame` with `margin` above and below.
    static func homeSize(preferred: CGSize, minimum: CGSize, in visibleFrame: CGRect) -> CGSize {
        let width = min(preferred.width, visibleFrame.width - 2 * (minimumColumn + 2 * margin))
        let height = min(preferred.height, visibleFrame.height - 2 * margin)
        return CGSize(width: max(minimum.width, width.rounded(.down)), height: max(minimum.height, height.rounded(.down)))
    }

    /// One item per natural size (tutorial 1, 2, Maple), with `rotations` in the same order.
    static func layout(naturalSizes: [CGSize], rotations: [Double] = rotations, frame: CGRect,
                       visibleFrame: CGRect, homeSize: CGSize) -> [Item] {
        precondition(naturalSizes.count == 3 && rotations.count == 3, "three tutorial stickers")
        let home = homeFrame(size: homeSize, in: visibleFrame)
        let right = visibleFrame.maxX - margin
        let column = max(right - (home.maxX + margin), minimumColumn)
        let maxHeight = frame.height / 3
        let boxes: [(size: CGSize, scale: Double)] = zip(naturalSizes, rotations).map { natural, rotation in
            let box = StickerGeometry.boundingSize(of: natural, rotation: rotation)
            guard box.width > 0, box.height > 0 else { return (.zero, 1) }
            let scale = min(1, Double(maxHeight / box.height), Double(column / box.width))
            return (CGSize(width: box.width * CGFloat(scale), height: box.height * CGFloat(scale)), scale)
        }
        let first = CGRect(x: right - boxes[0].size.width, y: visibleFrame.maxY - margin - boxes[0].size.height,
                           width: boxes[0].size.width, height: boxes[0].size.height)
        let second = CGRect(x: right - boxes[1].size.width, y: first.minY - gap - boxes[1].size.height,
                            width: boxes[1].size.width, height: boxes[1].size.height)
        let maple = CGRect(x: right - boxes[2].size.width, y: visibleFrame.minY + margin,
                           width: boxes[2].size.width, height: boxes[2].size.height)
        return zip([first, second, maple], boxes).map { rect, box in
            Item(rect: rect, pose: StickerGeometry.pose(center: CGPoint(x: rect.midX, y: rect.midY), scale: box.scale,
                                                         in: frame))
        }
    }
}
