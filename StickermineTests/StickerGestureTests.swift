import AppKit
import Testing
@testable import Stickermine

/// Pinch, rotate and the corner knob: the gesture lifecycle (spec section 10).
/// Bitmaps are rendered first; from the moment a harness orders panels in,
/// nothing suspends until `finish()` has closed them.
@MainActor
struct StickerGestureTests {
    private let sticker = UUID()
    private let center = EditingFixtures.center

    private func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool {
        EditingFixtures.near(a, b, tolerance)
    }

    /// One placement, shown with `first` (200 × 100 pt Outline at 2×), being edited.
    private func editing(_ only: Placement, shown first: RenderedSticker) throws -> EditingHarness {
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]),
                                   displays: [Fixtures.external(), Fixtures.main()])
        h.manager.restoreAll()
        h.manager.commitRender(first, for: EditingFixtures.request(sticker), placement: only.id)
        h.manager.beginEditing(placement: only.id)
        return h
    }

    @Test func aPinchGrowsTheWindowOnceAndOnlyTransformsTheContent() async throws {
        let only = EditingFixtures.placement(sticker)
        let first = try await EditingHarness.render(EditingFixtures.request(sticker))
        let h = try editing(only, shown: first)
        defer { h.finish() }
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        let editor = try h.editor()
        editor.magnify(by: 0.5, phase: .began)
        // The 207 × 107 bitmap's diagonal × 2 + 2 × 14, rounded up: 495 (give or take backing alignment).
        #expect(near(panel.frame.width, 495, 1) && panel.frame.height == panel.frame.width)
        #expect(near(panel.frame.midX, center.x) && near(panel.frame.midY, center.y))
        #expect(h.manager.frameHold(for: only.id) == .live)
        editor.magnify(by: 0.2, phase: .changed)
        editor.rotate(byDegrees: 30, phase: .began)
        #expect(editor.gestureResizeCount == 1)
        #expect(abs(view.contentScale - 1.8) < 1e-9)
        #expect(abs(view.contentRotation - .pi / 6) < 1e-9)
        #expect(editor.activeGestures == [.magnify, .rotate])
        // Nothing is written mid-gesture, and a reconcile leaves the window alone.
        let square = panel.frame
        h.manager.reconcileNow()
        #expect(panel.frame == square)
        #expect(h.library.library.placement(only.id) == only)
        // Outgrowing the square grows it once more.
        editor.magnify(by: 0.5, phase: .changed)
        #expect(editor.gestureResizeCount == 2)
        #expect(panel.frame.width >= EditGeometry.gestureSide(contentSize: view.contentPointSize, factor: 2.7,
                                                              margin: StickerView.editingMargin))
    }

    @Test func aGestureEndWritesThePoseThenSettlesOnTheNewBitmap() async throws {
        let only = EditingFixtures.placement(sticker)
        let quarter = EditGeometry.normalized(90 * Double.pi / 180)
        let after = EditingFixtures.request(sticker, rotation: quarter, size: CGSize(width: 300, height: 150))
        let first = try await EditingHarness.render(EditingFixtures.request(sticker))
        let second = try await EditingHarness.render(after)
        let h = try editing(only, shown: first)
        defer { h.finish() }
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        let editor = try h.editor()
        editor.magnify(by: 0.5, phase: .began)
        editor.rotate(byDegrees: 90, phase: .began)
        editor.magnify(by: 0, phase: .ended)
        // One gesture still runs: nothing is written yet.
        #expect(h.library.library.placement(only.id) == only)
        editor.rotate(byDegrees: 0, phase: .ended)
        let written = try #require(h.library.library.placement(only.id))
        let pose = try #require(written.poses["1920x1080"])
        #expect(abs(pose.scale - 1.5) < 1e-12)
        #expect(abs(pose.x - 0.5) < 1e-9 && abs(pose.y - 0.5) < 1e-9)
        #expect(written.rotation == quarter)
        #expect(h.library.hasPendingSave)
        // Until the new bitmap arrives the window keeps its square and the transform.
        #expect(h.manager.frameHold(for: only.id) == .settling)
        #expect(near(panel.frame.width, 495, 1))
        #expect(abs(view.contentScale - 1.5) < 1e-9)
        #expect(h.manager.renderRequest(for: only.id) == after)
        h.manager.commitRender(second, for: after, placement: only.id)
        #expect(h.manager.frameHold(for: only.id) == .none)
        #expect(view.contentScale == 1 && view.contentRotation == 0)
        #expect(view.contentPointSize == second.pointBounds)
        // The padded box (editing margin 14) around the unchanged centre.
        #expect(near(panel.frame.width, second.pointBounds.width + 28, 1))
        #expect(near(panel.frame.height, second.pointBounds.height + 28, 1))
        #expect(near(panel.frame.midX, center.x) && near(panel.frame.midY, center.y))
        #expect(h.manager.editingPlacement == only.id)
    }

    @Test func aGestureThatChangesNothingWritesNothingAndShowsAWaitingRender() async throws {
        let only = EditingFixtures.placement(sticker)
        let rendered = try await EditingHarness.render(EditingFixtures.request(sticker))
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        h.manager.beginEditing(placement: only.id)
        let editor = try h.editor()
        editor.magnify(by: 0, phase: .began)
        // The render lands mid-gesture: it waits for the gesture's end.
        h.manager.commitRender(rendered, for: EditingFixtures.request(sticker), placement: only.id)
        #expect(view.contentLayer.contents == nil)
        editor.magnify(by: 0, phase: .ended)
        #expect(view.contentLayer.contents != nil)
        #expect(h.manager.frameHold(for: only.id) == .none)
        #expect(h.library.library.placement(only.id) == only)
        #expect(!h.library.hasPendingSave)
        #expect(near(panel.frame.width, rendered.pointBounds.width + 28, 1))
    }

    @Test func theKnobScalesAndRotatesAroundTheCentreAndShiftSnaps() async throws {
        let only = EditingFixtures.placement(sticker)
        let first = try await EditingHarness.render(EditingFixtures.request(sticker))
        let h = try editing(only, shown: first)
        defer { h.finish() }
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        let editor = try h.editor()
        let start = CGPoint(x: panel.frame.minX + view.knobCenter.x, y: panel.frame.minY + view.knobCenter.y)
        let c = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let v = CGVector(dx: start.x - c.x, dy: start.y - c.y)
        editor.knob(.began, at: start, snapping: false)
        editor.knob(.moved, at: CGPoint(x: c.x + 2 * v.dx, y: c.y + 2 * v.dy), snapping: false)
        #expect(abs(view.contentScale - 2) < 1e-9)
        #expect(abs(view.contentRotation) < 1e-9)
        // Twice as far, turned 20° counter-clockwise, with Shift: snapped to 15°.
        let turn = 20 * Double.pi / 180
        let turned = CGPoint(x: c.x + 2 * (v.dx * cos(turn) - v.dy * sin(turn)),
                             y: c.y + 2 * (v.dx * sin(turn) + v.dy * cos(turn)))
        editor.knob(.moved, at: turned, snapping: true)
        #expect(abs(Double(view.contentRotation) - Double.pi / 12) < 1e-9)
        editor.knob(.ended, at: turned, snapping: true)
        let written = try #require(h.library.library.placement(only.id))
        #expect(abs(written.rotation - Double.pi / 12) < 1e-9)
        #expect(abs((written.poses["1920x1080"]?.scale ?? 0) - 2) < 1e-9)
    }

    @Test func theKnobAndPinchStopAtTheScaleLimits() async throws {
        let only = EditingFixtures.placement(sticker)
        let first = try await EditingHarness.render(EditingFixtures.request(sticker))
        let h = try editing(only, shown: first)
        defer { h.finish() }
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        let editor = try h.editor()
        let c = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let start = CGPoint(x: panel.frame.minX + view.knobCenter.x, y: panel.frame.minY + view.knobCenter.y)
        editor.knob(.began, at: start, snapping: false)
        editor.knob(.moved, at: CGPoint(x: c.x + 100 * (start.x - c.x), y: c.y + 100 * (start.y - c.y)),
                    snapping: false)
        // 200 pt wide: at most the display's 1920 pt long side.
        #expect(abs(view.contentScale - 9.6) < 1e-9)
        editor.magnify(by: -0.99, phase: .began)
        // At least 48 pt.
        #expect(abs(view.contentScale - 0.24) < 1e-9)
        editor.magnify(by: 0, phase: .ended)
        editor.knob(.ended, at: CGPoint(x: c.x + 0.01 * (start.x - c.x), y: c.y + 0.01 * (start.y - c.y)),
                    snapping: false)
        #expect(abs((h.library.library.placement(only.id)?.poses["1920x1080"]?.scale ?? 0) - 0.24) < 1e-9)
    }

    @Test(arguments: EditingEndTrigger.allCases)
    func editingThatEndsMidGestureDiscardsIt(_ trigger: EditingEndTrigger) async throws {
        let only = EditingFixtures.placement(sticker)
        let first = try await EditingHarness.render(EditingFixtures.request(sticker))
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]),
                                   displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.commitRender(first, for: EditingFixtures.request(sticker), placement: only.id)
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        let saved = panel.frame
        h.manager.beginEditing(placement: only.id)
        let editor = try h.editor()
        editor.magnify(by: 0.5, phase: .began)
        editor.rotate(byDegrees: 40, phase: .began)
        try h.end(trigger, editing: only.id)
        #expect(h.manager.editingPlacement == nil)
        #expect(!editor.pill.panel.isVisible)
        #expect(view.contentScale == 1 && view.contentRotation == 0)
        #expect(h.manager.frameHold(for: only.id) == .none)
        #expect(panel.frame == saved, "the frame comes back from the last saved pose")
        #expect(h.library.library.placement(only.id) == only)
        #expect(!h.library.hasPendingSave)
    }
}
