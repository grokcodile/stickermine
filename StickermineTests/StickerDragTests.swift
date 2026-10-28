import AppKit
import Testing
@testable import Stickermine

/// Dragging an edited sticker, on its display and onto another one (spec
/// sections 10 and 11). The editor gets the cursor's screen positions the
/// view would report; nothing here suspends while a panel is ordered in.
@MainActor
struct StickerDragTests {
    private let sticker = UUID()

    private func near(_ a: CGFloat, _ b: CGFloat) -> Bool {
        EditingFixtures.near(a, b)
    }

    /// The main display at 1×, 1512 × 982 at x = 50 000.
    private func main(scale: CGFloat = 1) -> DisplayInfo {
        Fixtures.display(uuid: Fixtures.mainUUID, id: 1, frame: CGRect(x: 50_000, y: 0, width: 1512, height: 982),
                         scale: scale, name: "Built-in Retina Display", vendor: 1552, model: 41_013, serial: 0,
                         builtin: true)
    }

    /// Drags the edited sticker from its centre by `delta`, through its midpoint.
    private func drag(_ h: EditingHarness, _ id: UUID, by delta: CGVector) throws {
        let panel = try h.panel(id)
        let editor = try h.editor()
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        editor.drag(.began, at: start)
        editor.drag(.moved, at: CGPoint(x: start.x + delta.dx / 2, y: start.y + delta.dy / 2))
        editor.drag(.ended, at: CGPoint(x: start.x + delta.dx, y: start.y + delta.dy))
    }

    @Test func theWindowAndThePillFollowEveryStepAndAReconcileLeavesThemThere() throws {
        let only = EditingFixtures.placement(sticker)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        h.manager.beginEditing(placement: only.id)
        let editor = try h.editor()
        let pill = editor.pill.panel
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        let size = panel.frame.size
        editor.drag(.began, at: start)
        #expect(h.manager.frameHold(for: only.id) == .live)
        editor.drag(.moved, at: CGPoint(x: start.x + 300, y: start.y - 200))
        #expect(near(panel.frame.midX, start.x + 300) && near(panel.frame.midY, start.y - 200))
        #expect(panel.frame.size == size)
        // The pill stays centred under the sticker rect (100 pt tall), its gap below the knob.
        #expect(near(pill.frame.midX, start.x + 300))
        #expect(pill.frame.maxY == (start.y - 200 - 50 - 9 - ToolbarPill.gap).rounded())
        // A display event mid-drag doesn't snap the window back, and nothing is written yet.
        let moved = panel.frame
        h.manager.reconcileNow()
        #expect(panel.frame == moved)
        #expect(h.library.library.placement(only.id) == only)
        #expect(!h.library.hasPendingSave)
        editor.drag(.ended, at: CGPoint(x: start.x + 300, y: start.y - 200))
        #expect(h.manager.frameHold(for: only.id) == .none)
        #expect(h.library.hasPendingSave)
    }

    @Test func aRenderThatLandsMidDragIsShownWhenTheDragEnds() async throws {
        let only = EditingFixtures.placement(sticker)
        let rendered = try await EditingHarness.render(EditingFixtures.request(sticker))
        // From here on nothing suspends, so no other test sees these panels.
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        h.manager.beginEditing(placement: only.id)
        let editor = try h.editor()
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        editor.drag(.began, at: start)
        editor.drag(.moved, at: CGPoint(x: start.x + 100, y: start.y))
        h.manager.commitRender(rendered, for: EditingFixtures.request(sticker), placement: only.id)
        #expect(view.contentLayer.contents == nil)
        #expect(near(panel.frame.midX, start.x + 100))
        editor.drag(.ended, at: CGPoint(x: start.x + 100, y: start.y))
        #expect(view.contentLayer.contents != nil)
        #expect(view.contentPointSize == rendered.pointBounds)
        // The bitmap's box (Outline's rim included) plus the 14 pt editing margin, at the drop.
        #expect(abs(panel.frame.width - (rendered.pointBounds.width + 28)) <= 1)
        #expect(near(panel.frame.midX, start.x + 100) && near(panel.frame.midY, start.y))
    }

    @Test func aDragOnTheSameDisplayWritesOnlyThisSizesPose() throws {
        let other = Pose(x: 0.2, y: 0.2, scale: 2)
        let only = EditingFixtures.placement(sticker, poses: ["1920x1080": Pose(x: 0.5, y: 0.5, scale: 1),
                                                              "2560x1440": other])
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        h.manager.beginEditing(placement: only.id)
        try drag(h, only.id, by: CGVector(dx: 192, dy: 108))
        let poses = try #require(h.library.library.placement(only.id)?.poses)
        #expect(poses["2560x1440"] == other)
        let pose = try #require(poses["1920x1080"])
        #expect(abs(pose.x - 0.6) < 1e-3 && abs(pose.y - 0.6) < 1e-3 && pose.scale == 1)
        #expect(h.library.hasPendingSave)
        // The window is re-applied from the new pose, still editing, and the pill follows.
        #expect(near(panel.frame.midX, 41_152) && near(panel.frame.midY, 648))
        #expect(h.manager.editingPlacement == only.id)
        #expect(try h.editor().pill.panel.frame.maxY == 648 - 50 - 9 - ToolbarPill.gap)
    }

    @Test func aDragOfABorrowedPoseCreatesThisSizesPoseAtTheSizeItWasDrawn() throws {
        let borrowed = Pose(x: 0.5, y: 0.5, scale: 1.5)
        let only = EditingFixtures.placement(sticker, poses: ["2560x1440": borrowed])
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: only.id)
        try drag(h, only.id, by: CGVector(dx: -96, dy: 0))
        let poses = try #require(h.library.library.placement(only.id)?.poses)
        #expect(poses["2560x1440"] == borrowed)
        // 1.5 × min(1920/2560, 1080/1440) = 1.125.
        let pose = try #require(poses["1920x1080"])
        #expect(abs(pose.scale - 1.125) < 1e-12)
        #expect(abs(pose.x - 0.45) < 1e-3 && abs(pose.y - 0.5) < 1e-3)
    }

    @Test func aDropUnderTheMenuBarIsPulledBackOntoTheDisplay() throws {
        let only = EditingFixtures.placement(sticker)
        let withMenuBar = Fixtures.display(uuid: Fixtures.externalUUID, id: 3,
                                           frame: CGRect(x: 40_000, y: 0, width: 1920, height: 1080),
                                           visibleFrame: CGRect(x: 40_000, y: 0, width: 1920, height: 1055),
                                           name: "LG UltraFine")
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [withMenuBar])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: only.id)
        // From the centre (y 540) to y 1075, under the menu bar.
        try drag(h, only.id, by: CGVector(dx: 0, dy: 535))
        let pose = try #require(h.library.library.placement(only.id)?.poses["1920x1080"])
        // The 100 pt tall box stays on the display (centre 1030), which is reachable.
        #expect(abs(pose.y - 1030.0 / 1080) < 1e-9)
        #expect(abs(pose.x - 0.5) < 1e-9)
    }

    @Test func aDropOnAnotherDisplayIsAPlacementThereOnTopAtTheSameSize() throws {
        let moved = EditingFixtures.placement(sticker, scale: 0.5)
        let resident = Placement(sticker: sticker, style: .none, poses: ["1512x982": Pose(x: 0.1, y: 0.1, scale: 1)])
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [moved], main: [resident]),
                                   displays: [Fixtures.external(), main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(moved.id)
        h.manager.beginEditing(placement: moved.id)
        let renders = h.manager.renderRequestsIssued
        // While editing, a backing-scale change waits for the drop.
        h.manager.backingScaleChanged(for: moved.id, to: 1)
        #expect(h.manager.renderRequestsIssued == renders)
        // From the external display's centre (40 960, 540) to the main display's (50 756, 491).
        let editor = try h.editor()
        editor.drag(.began, at: CGPoint(x: 40_960, y: 540))
        editor.drag(.moved, at: CGPoint(x: 50_756, y: 491))
        // Over the main display, the pill is placed on it.
        let mainFrame = main().frame
        #expect(mainFrame.contains(editor.pill.panel.frame))
        #expect(near(editor.pill.panel.frame.midX, 50_756))
        editor.drag(.ended, at: CGPoint(x: 50_756, y: 491))
        let model = h.library.library
        #expect(model.displays[Fixtures.externalUUID]?.placements.isEmpty == true)
        #expect(model.displays[Fixtures.mainUUID]?.placements.map(\.id) == [resident.id, moved.id])
        // poses = [B: pose] at the same on-screen size: still 100 × 50 pt.
        #expect(model.placement(moved.id)?.poses == ["1512x982": Pose(x: 0.5, y: 0.5, scale: 0.5)])
        // Rendered once, at the new display's scale.
        #expect(h.manager.renderRequestsIssued == renders + 1)
        #expect(h.manager.renderRequest(for: moved.id)?.backingScale == 1)
        #expect(h.manager.renderRequest(for: moved.id)?.pointSize == CGSize(width: 100, height: 50))
        #expect(h.manager.editingPlacement == moved.id)
        #expect(near(panel.frame.midX, 50_756) && near(panel.frame.midY, 491))
    }

    @Test func aDropOnADisplayWithoutARecordCreatesIt() throws {
        let moved = EditingFixtures.placement(sticker)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [moved]),
                                   displays: [Fixtures.external(), main(scale: 2)])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: moved.id)
        // From (40 960, 540) to (50 500, 450).
        try drag(h, moved.id, by: CGVector(dx: 9_540, dy: -90))
        let record = try #require(h.library.library.displays[Fixtures.mainUUID])
        #expect(record.name == "Built-in Retina Display" && record.builtin)
        #expect(record.placements.map(\.id) == [moved.id])
        #expect(record.placements.first?.poses.keys.sorted() == ["1512x982"])
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.isEmpty == true)
    }

    @Test func aDropOffEveryDisplayGoesToTheNearestOne() throws {
        let moved = EditingFixtures.placement(sticker)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [moved]),
                                   displays: [Fixtures.external(), main(scale: 2)])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: moved.id)
        // To (49 000, 500): in the gap, 1 000 pt from the main display and 7 080 pt from the external one.
        try drag(h, moved.id, by: CGVector(dx: 8_040, dy: -40))
        let record = try #require(h.library.library.displays[Fixtures.mainUUID])
        #expect(record.placements.map(\.id) == [moved.id])
        // Pulled onto the main display: the 200 pt wide box's centre at x = 50 100.
        let pose = try #require(record.placements.first?.poses["1512x982"])
        #expect(abs(pose.x - 100.0 / 1512) < 1e-9)
    }

    @Test func aDragThatDidntMoveWritesNothing() throws {
        let only = EditingFixtures.placement(sticker)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        let frame = panel.frame
        h.manager.beginEditing(placement: only.id)
        let editing = panel.frame
        try drag(h, only.id, by: CGVector(dx: 0.4, dy: 0))
        #expect(!h.library.hasPendingSave)
        #expect(h.library.library.placement(only.id) == only)
        #expect(panel.frame == editing)
        #expect(h.manager.frameHold(for: only.id) == .none)
        h.manager.endEditing(discardGesture: true)
        #expect(panel.frame == frame)
    }

    @Test(arguments: EditingEndTrigger.allCases)
    func editingThatEndsMidDragPutsTheStickerBackAndWritesNothing(_ trigger: EditingEndTrigger) throws {
        let only = EditingFixtures.placement(sticker)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]),
                                   displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        let saved = panel.frame
        h.manager.beginEditing(placement: only.id)
        let editor = try h.editor()
        let start = CGPoint(x: panel.frame.midX, y: panel.frame.midY)
        editor.drag(.began, at: start)
        editor.drag(.moved, at: CGPoint(x: start.x + 250, y: start.y + 120))
        try h.end(trigger, editing: only.id)
        #expect(h.manager.editingPlacement == nil)
        #expect(!editor.isDragging)
        #expect(h.manager.frameHold(for: only.id) == .none)
        #expect(panel.frame == saved, "the frame comes back from the last saved pose")
        #expect(h.library.library.placement(only.id) == only)
        #expect(!h.library.hasPendingSave)
        // A mouse-up that arrives afterwards changes nothing.
        editor.drag(.ended, at: CGPoint(x: start.x + 300, y: start.y))
        #expect(h.library.library.placement(only.id) == only)
    }
}
