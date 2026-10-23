import CoreGraphics
import Foundation

/// Pure geometry between the model (normalized poses) and windows (screen
/// points). Drawing never writes: the clamps here only change where a sticker
/// is drawn (spec section 11).
enum StickerGeometry {
    /// A borrowed pose's centre stays this far inside the display's visible
    /// frame, so a sticker never ends up unreachable under the menu bar or Dock.
    static let reachableInset: CGFloat = 8

    struct Layout: Equatable {
        /// The pose used: stored for this size, or borrowed from the closest one.
        let pose: Pose
        let isBorrowed: Bool
        /// Unrotated on-screen size in points (natural size × pose scale).
        let pointSize: CGSize
        /// The rotated sticker's box in screen points, clamped inside the
        /// display's frame. The window is this plus the shadow margin.
        let stickerRect: CGRect
    }

    /// The axis-aligned box of `size` rotated by `rotation` radians.
    static func boundingSize(of size: CGSize, rotation: Double) -> CGSize {
        let c = abs(cos(rotation))
        let s = abs(sin(rotation))
        return CGSize(width: size.width * c + size.height * s, height: size.width * s + size.height * c)
    }

    /// The screen point a pose's normalized centre stands for.
    static func center(of pose: Pose, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(pose.x) * frame.width, y: frame.minY + CGFloat(pose.y) * frame.height)
    }

    /// The pose for a screen-point centre on a display with `frame`.
    static func pose(center: CGPoint, scale: Double, in frame: CGRect) -> Pose {
        Pose(x: Double((center.x - frame.minX) / frame.width),
             y: Double((center.y - frame.minY) / frame.height),
             scale: scale)
    }

    /// `center` moved inside `visibleFrame` inset by `reachableInset`.
    static func reachableCenter(_ center: CGPoint, visibleFrame: CGRect) -> CGPoint {
        let area = visibleFrame.insetBy(dx: reachableInset, dy: reachableInset)
        guard !area.isNull, area.width >= 0, area.height >= 0 else {
            return CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        }
        return CGPoint(x: min(max(center.x, area.minX), area.maxX),
                       y: min(max(center.y, area.minY), area.maxY))
    }

    /// A `size` box centred on `center`, moved fully inside `frame` (centred on
    /// an axis where it is larger than the frame).
    static func clampedRect(size: CGSize, center: CGPoint, within frame: CGRect) -> CGRect {
        func axis(_ c: CGFloat, _ length: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            if length >= upper - lower { return (lower + upper - length) / 2 }
            return min(max(c - length / 2, lower), upper - length)
        }
        return CGRect(x: axis(center.x, size.width, frame.minX, frame.maxX),
                      y: axis(center.y, size.height, frame.minY, frame.maxY),
                      width: size.width, height: size.height)
    }

    /// Where `placement` of a sticker with `natural` point size is drawn on
    /// `display`; nil when the placement has no usable pose.
    static func layout(for placement: Placement, natural: CGSize, on display: DisplayInfo) -> Layout? {
        guard let pose = LayoutResolver.pose(for: placement, at: display.size),
              display.frame.width > 0, display.frame.height > 0
        else { return nil }
        let isBorrowed = placement.poses[display.size.key] == nil
        var center = center(of: pose, in: display.frame)
        if isBorrowed {
            center = reachableCenter(center, visibleFrame: display.visibleFrame)
        }
        let pointSize = CGSize(width: natural.width * CGFloat(pose.scale), height: natural.height * CGFloat(pose.scale))
        let box = boundingSize(of: pointSize, rotation: placement.rotation)
        return Layout(pose: pose, isBorrowed: isBorrowed, pointSize: pointSize,
                      stickerRect: clampedRect(size: box, center: center, within: display.frame))
    }
}
