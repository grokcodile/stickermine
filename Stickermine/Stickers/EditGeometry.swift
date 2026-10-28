import CoreGraphics
import Foundation

/// The pure math behind editing a sticker (spec sections 10 and 11): the
/// corner knob, Shift snapping, the scale limits, where a sticker settles at
/// the end of a drag or gesture, and how big the window grows for a gesture.
/// Rotations are radians, counter-clockwise on screen (Cocoa, y up).
enum EditGeometry {
    /// Shift snaps the knob's rotation to multiples of 15°.
    static let snapStep = Double.pi / 12
    /// A sticker's long side never goes below this many points.
    static let minimumLongSide: Double = 48
    /// At a gesture's start the window grows to fit the sticker at up to this
    /// multiple of its size, turned any way.
    static let gestureHeadroom: Double = 2

    /// The knob's change since its drag began: a factor on the scale the drag
    /// started with, and a rotation to add to the rotation it started with.
    struct KnobChange: Equatable {
        let scale: Double
        let rotation: Double
    }

    /// `angle` in (−π, π].
    static func normalized(_ angle: Double) -> Double {
        var result = remainder(angle, 2 * Double.pi)
        if result <= -Double.pi { result += 2 * Double.pi }
        return result
    }

    /// The multiple of `step` nearest to `angle`, normalized.
    static func snapped(_ angle: Double, step: Double = snapStep) -> Double {
        normalized((angle / step).rounded() * step)
    }

    /// One knob drag: `start` and `current` point from the sticker's centre to
    /// where the drag began and to the cursor now. The scale follows the
    /// distance from the centre and the rotation the angle around it, so the
    /// knob stays under the cursor. With `snap` (Shift held), the sticker's
    /// resulting rotation, `baseRotation` plus the change, lands on a
    /// multiple of 15°.
    static func knobChange(from start: CGVector, to current: CGVector, baseRotation: Double,
                           snap: Bool) -> KnobChange {
        let startLength = Double(hypot(start.dx, start.dy))
        guard startLength > 0 else { return KnobChange(scale: 1, rotation: 0) }
        let scale = Double(hypot(current.dx, current.dy)) / startLength
        var rotation = normalized(Double(atan2(current.dy, current.dx)) - Double(atan2(start.dy, start.dx)))
        if snap {
            rotation = normalized(snapped(baseRotation + rotation) - baseRotation)
        }
        return KnobChange(scale: scale, rotation: rotation)
    }

    /// The pose scales a sticker of `natural` point size may have on a display
    /// of `displaySize` points: its long side between 48 pt and the display's
    /// long side.
    static func scaleLimits(natural: CGSize, displaySize: CGSize) -> ClosedRange<Double> {
        let longSide = Double(max(natural.width, natural.height))
        guard longSide > 0 else { return 1...1 }
        let lower = minimumLongSide / longSide
        let upper = Double(max(displaySize.width, displaySize.height)) / longSide
        return lower...max(lower, upper)
    }

    /// `proposed` stopped at `limits`. A sticker that is already outside them
    /// (one captured smaller than 48 pt) is never pushed further out and never
    /// jumps in: the knob and pinch just stop.
    static func clampedScale(_ proposed: Double, current: Double, limits: ClosedRange<Double>) -> Double {
        let lower = min(limits.lowerBound, current)
        let upper = max(limits.upperBound, current)
        return min(max(proposed, lower), upper)
    }

    /// Where a sticker's centre settles when a drag or gesture ends: inside
    /// `visibleFrame` inset by 8 pt (never unreachable under the menu bar or
    /// Dock), with its `boxSize` box inside the display's `frame` (spec
    /// section 11).
    static func settledCenter(_ center: CGPoint, boxSize: CGSize, frame: CGRect, visibleFrame: CGRect) -> CGPoint {
        let reachable = StickerGeometry.reachableCenter(center, visibleFrame: visibleFrame)
        let rect = StickerGeometry.clampedRect(size: boxSize, center: reachable, within: frame)
        return StickerGeometry.reachableCenter(CGPoint(x: rect.midX, y: rect.midY), visibleFrame: visibleFrame)
    }

    /// The side of the square window a gesture uses: the shown bitmap's
    /// diagonal at `factor` times its size (so it can turn freely), plus
    /// `margin` on every side, rounded up to whole points.
    static func gestureSide(contentSize: CGSize, factor: Double, margin: CGFloat) -> CGFloat {
        (hypot(contentSize.width, contentSize.height) * CGFloat(factor) + 2 * margin).rounded(.up)
    }
}
