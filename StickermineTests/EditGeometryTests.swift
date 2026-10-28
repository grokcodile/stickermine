import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct EditGeometryTests {
    private let degree = Double.pi / 180

    @Test func anglesAreNormalizedIntoMinusPiToPi() {
        #expect(EditGeometry.normalized(0) == 0)
        #expect(abs(EditGeometry.normalized(3 * Double.pi / 2) + Double.pi / 2) < 1e-12)
        #expect(abs(EditGeometry.normalized(-3 * Double.pi / 2) - Double.pi / 2) < 1e-12)
        #expect(EditGeometry.normalized(Double.pi) == Double.pi)
        #expect(EditGeometry.normalized(-Double.pi) == Double.pi)
        #expect(abs(EditGeometry.normalized(5 * Double.pi) - Double.pi) < 1e-12)
    }

    @Test func snappingGoesToTheNearestFifteenDegrees() {
        #expect(abs(EditGeometry.snapped(20 * degree) - 15 * degree) < 1e-12)
        #expect(abs(EditGeometry.snapped(23 * degree) - 30 * degree) < 1e-12)
        #expect(abs(EditGeometry.snapped(-8 * degree) + 15 * degree) < 1e-12)
        #expect(EditGeometry.snapped(7 * degree) == 0)
        #expect(abs(EditGeometry.snapStep - 15 * degree) < 1e-15)
    }

    @Test func theKnobScalesWithTheDistanceFromTheCentre() {
        let change = EditGeometry.knobChange(from: CGVector(dx: 100, dy: -50), to: CGVector(dx: 200, dy: -100),
                                             baseRotation: 0, snap: false)
        #expect(abs(change.scale - 2) < 1e-12)
        #expect(abs(change.rotation) < 1e-12)
        let half = EditGeometry.knobChange(from: CGVector(dx: 100, dy: -50), to: CGVector(dx: 50, dy: -25),
                                           baseRotation: 0, snap: false)
        #expect(abs(half.scale - 0.5) < 1e-12)
    }

    @Test func theKnobTurnsWithTheAngleAroundTheCentreCounterClockwise() {
        // y is up: from the right to straight up is a quarter turn counter-clockwise.
        let up = EditGeometry.knobChange(from: CGVector(dx: 100, dy: 0), to: CGVector(dx: 0, dy: 100),
                                         baseRotation: 0, snap: false)
        #expect(abs(up.rotation - Double.pi / 2) < 1e-12)
        #expect(abs(up.scale - 1) < 1e-12)
        let down = EditGeometry.knobChange(from: CGVector(dx: 100, dy: 0), to: CGVector(dx: 0, dy: -50),
                                           baseRotation: 0, snap: false)
        #expect(abs(down.rotation + Double.pi / 2) < 1e-12)
        #expect(abs(down.scale - 0.5) < 1e-12)
        // Across the ±180° line the change is the short way round: +20°, not −340°.
        let across = EditGeometry.knobChange(
            from: CGVector(dx: cos(170 * degree), dy: sin(170 * degree)),
            to: CGVector(dx: cos(-170 * degree), dy: sin(-170 * degree)), baseRotation: 0, snap: false)
        #expect(abs(across.rotation - 20 * degree) < 1e-9)
    }

    @Test func shiftSnapsTheResultingRotationNotTheChange() {
        let start = CGVector(dx: 100, dy: 0)
        let twenty = CGVector(dx: 100 * cos(20 * degree), dy: 100 * sin(20 * degree))
        let fromZero = EditGeometry.knobChange(from: start, to: twenty, baseRotation: 0, snap: true)
        #expect(abs(fromZero.rotation - 15 * degree) < 1e-12)
        // Starting at 10°, turning 20° more lands on 30°: a change of 20°.
        let fromTen = EditGeometry.knobChange(from: start, to: twenty, baseRotation: 10 * degree, snap: true)
        #expect(abs(fromTen.rotation - 20 * degree) < 1e-12)
        // Starting at 12°, turning 20° more is 32°, snapped to 30°: a change of 18°.
        let fromTwelve = EditGeometry.knobChange(from: start, to: twenty, baseRotation: 12 * degree, snap: true)
        #expect(abs(fromTwelve.rotation - 18 * degree) < 1e-12)
        #expect(abs(fromTwelve.scale - 1) < 1e-12)
    }

    @Test func aKnobDragFromTheCentreChangesNothing() {
        let change = EditGeometry.knobChange(from: .zero, to: CGVector(dx: 10, dy: 10), baseRotation: 0, snap: true)
        #expect(change == EditGeometry.KnobChange(scale: 1, rotation: 0))
    }

    @Test func theLongSideStaysBetween48PointsAndTheDisplaysLongSide() {
        let limits = EditGeometry.scaleLimits(natural: CGSize(width: 200, height: 100),
                                              displaySize: CGSize(width: 1920, height: 1080))
        #expect(abs(limits.lowerBound - 0.24) < 1e-12)
        #expect(abs(limits.upperBound - 9.6) < 1e-12)
        // A portrait sticker on a portrait display: the long sides count.
        let tall = EditGeometry.scaleLimits(natural: CGSize(width: 50, height: 400),
                                            displaySize: CGSize(width: 1080, height: 1920))
        #expect(abs(tall.lowerBound - 0.12) < 1e-12)
        #expect(abs(tall.upperBound - 4.8) < 1e-12)
        #expect(EditGeometry.scaleLimits(natural: .zero, displaySize: CGSize(width: 10, height: 10)) == 1...1)
    }

    @Test func theKnobAndPinchStopAtTheLimits() {
        let limits = 0.24...9.6
        #expect(EditGeometry.clampedScale(20, current: 1, limits: limits) == 9.6)
        #expect(EditGeometry.clampedScale(0.1, current: 1, limits: limits) == 0.24)
        #expect(EditGeometry.clampedScale(2, current: 1, limits: limits) == 2)
    }

    @Test func aStickerAlreadyOutsideTheLimitsNeitherJumpsNorGoesFurther() {
        let limits = 0.24...9.6
        // Captured at 40 pt: shrinking stops where it is, growing is allowed.
        #expect(EditGeometry.clampedScale(0.1, current: 0.2, limits: limits) == 0.2)
        #expect(EditGeometry.clampedScale(0.22, current: 0.2, limits: limits) == 0.22)
        #expect(EditGeometry.clampedScale(12, current: 10, limits: limits) == 10)
        #expect(EditGeometry.clampedScale(5, current: 10, limits: limits) == 5)
    }

    @Test func aDroppedStickerStaysReachableAndOnItsDisplay() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        let visible = CGRect(x: 0, y: 70, width: 1920, height: 985)   // Dock 70 pt, menu bar 25 pt
        let box = CGSize(width: 200, height: 100)
        // Inside: unchanged.
        #expect(EditGeometry.settledCenter(CGPoint(x: 600, y: 500), boxSize: box, frame: frame, visibleFrame: visible)
                == CGPoint(x: 600, y: 500))
        // Under the menu bar: the box stays inside the frame (centre 1030), which is reachable.
        #expect(EditGeometry.settledCenter(CGPoint(x: 600, y: 1075), boxSize: box, frame: frame, visibleFrame: visible)
                == CGPoint(x: 600, y: 1030))
        // Over the Dock: the centre comes up to the visible frame inset by 8 pt.
        #expect(EditGeometry.settledCenter(CGPoint(x: 600, y: 60), boxSize: box, frame: frame, visibleFrame: visible)
                == CGPoint(x: 600, y: 78))
        // Half off the left edge: the box moves fully inside.
        #expect(EditGeometry.settledCenter(CGPoint(x: 30, y: 500), boxSize: box, frame: frame, visibleFrame: visible)
                == CGPoint(x: 100, y: 500))
        // Bigger than the display: centred.
        #expect(EditGeometry.settledCenter(CGPoint(x: 30, y: 500), boxSize: CGSize(width: 2500, height: 100),
                                           frame: frame, visibleFrame: visible) == CGPoint(x: 960, y: 500))
    }

    @Test func theGestureSquareFitsTheBitmapTurnedAnyWayPlusItsMargin() {
        // diagonal 500 × 2 + 2 × 14
        #expect(EditGeometry.gestureSide(contentSize: CGSize(width: 300, height: 400), factor: 2, margin: 14) == 1028)
        // Rounded up to whole points.
        #expect(EditGeometry.gestureSide(contentSize: CGSize(width: 100, height: 100), factor: 1, margin: 0) == 142)
    }
}
