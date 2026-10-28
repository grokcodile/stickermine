import AppKit
import Testing
@testable import Stickermine

/// Entering and ending editing, focus, keys and the toolbar pill (spec
/// section 10). Nothing here suspends while a panel is ordered in.
@MainActor
struct StickerEditingTests {
    private let sticker = UUID()

    private func placement(x: Double = 0.5) -> Placement {
        EditingFixtures.placement(sticker, x: x)
    }

    private func harness(_ placements: [Placement]) throws -> EditingHarness {
        try EditingHarness(EditingFixtures.library(sticker, external: placements),
                           displays: [Fixtures.external(), Fixtures.main()])
    }

    @Test func aDoubleClickEntersEditingBringsTheStickerToFrontAndTakesFocus() throws {
        let back = placement(x: 0.3), front = placement(x: 0.7)
        let h = try harness([back, front])
        defer { h.finish() }
        h.manager.restoreAll()
        #expect(!h.library.hasPendingSave)
        let panel = try h.panel(back.id)
        let view = try h.view(back.id)
        view.onDoubleClick?()
        #expect(h.manager.editingPlacement == back.id)
        #expect(panel.isEditing && panel.canBecomeKey)
        #expect(view.isShowingEditingChrome)
        #expect(h.focus.taken.count == 1 && h.focus.taken.first === panel)
        // Bring to front is saved: the record's list is the z-order, back to front.
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.map(\.id) == [front.id, back.id])
        #expect(h.library.hasPendingSave)
        // The window grows by the editing margin around the same centre (no bitmap yet: 200 × 100).
        #expect(panel.frame == CGRect(x: 40_576 - 100 - 14, y: 490 - 14, width: 228, height: 128))
    }

    @Test func aStickerAlreadyInFrontWritesNothing() throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: only.id)
        #expect(h.manager.editingPlacement == only.id)
        #expect(!h.library.hasPendingSave)
    }

    @Test func noEditingDuringASessionOrInANewerLibrary() throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.isSessionActive = { true }
        try h.view(only.id).onDoubleClick?()
        #expect(h.manager.editingPlacement == nil)
        #expect(h.focus.taken.isEmpty)

        var newer = EditingFixtures.library(sticker, external: [only])
        newer.version = 2
        let readOnly = try EditingHarness(newer, displays: [Fixtures.external()])
        defer { readOnly.finish() }
        readOnly.manager.restoreAll()
        readOnly.manager.beginEditing(placement: only.id)
        #expect(readOnly.manager.editingPlacement == nil)
    }

    @Test func escEndsEditingAndHandsFocusBack() throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        let view = try h.view(only.id)
        h.manager.beginEditing(placement: only.id)
        let pill = try h.editor().pill.panel
        view.keyDown(with: try EditingHarness.keyEvent(53, "\u{1b}"))
        #expect(h.manager.editingPlacement == nil)
        #expect(!panel.isEditing && !panel.canBecomeKey)
        #expect(!view.isShowingEditingChrome)
        #expect(view.onKeyDown == nil)
        #expect(h.focus.returned.count == 1)
        #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        #expect(!pill.isVisible)
        #expect(pill.parent == nil)
        #expect(!h.library.hasPendingSave)
    }

    @Test(arguments: EditingEndTrigger.allCases)
    func editingEnds(_ trigger: EditingEndTrigger) throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        let view = try h.view(only.id)
        h.manager.beginEditing(placement: only.id)
        let pill = try h.editor().pill.panel
        try h.end(trigger, editing: only.id)
        #expect(h.manager.editingPlacement == nil)
        #expect(!view.isShowingEditingChrome)
        #expect(!pill.isVisible)
        #expect(h.focus.returned.count == 1)
        #expect(!h.library.hasPendingSave)
    }

    @Test func aClickOnAnotherStickerEndsEditingAndHandsFocusBackAfterTheDoubleClickInterval() async throws {
        let a = placement(x: 0.3), b = placement(x: 0.7)
        let h = try harness([a, b])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: a.id)
        try h.view(a.id).onInactiveMouseDown?()   // the edited sticker's own view: ignored
        #expect(h.manager.editingPlacement == a.id)
        try h.view(b.id).onInactiveMouseDown?()
        #expect(h.manager.editingPlacement == nil)
        // It may be the first click of a double-click on b: focus stays for now.
        #expect(h.focus.returned.isEmpty)
        h.finish()
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.3) * 1_000_000_000))
        #expect(h.focus.returned.count == 1)
    }

    @Test func doubleClickingAnotherStickerSwitchesEditingAndKeepsTheFirstFocusOwner() throws {
        let a = placement(x: 0.3), b = placement(x: 0.7)
        let h = try harness([a, b])
        defer { h.finish() }
        h.manager.restoreAll()
        h.focus.frontmost = NSRunningApplication.current
        h.manager.beginEditing(placement: a.id)
        h.focus.frontmost = nil
        // A real double-click on b: two mouse-downs (the second with clickCount 2), then the double-click.
        let other = try h.view(b.id)
        other.onInactiveMouseDown?()
        other.onInactiveMouseDown?()
        other.onDoubleClick?()
        #expect(h.manager.editingPlacement == b.id)
        #expect(try !h.panel(a.id).isEditing)
        #expect(h.focus.returned.isEmpty)
        #expect(try h.editor().previousApp?.processIdentifier == ProcessInfo.processInfo.processIdentifier)
        #expect(h.focus.taken.count == 2)
    }

    @Test func thePillIsAChildPanelUnderTheStickerAtItsLevel() throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        h.manager.beginEditing(placement: only.id)
        let pill = try h.editor().pill.panel
        #expect(pill.parent === panel)
        #expect(pill.isVisible)
        #expect(!pill.canBecomeKey)
        #expect(pill.level == panel.level)
        #expect(pill.collectionBehavior == PanelPolicy.stickerBehavior)
        #expect(pill.sharingType == panel.sharingType)
        // Centred under the 200 × 100 sticker rect, 8 pt below the knob.
        #expect(pill.frame.maxY == 490 - 9 - ToolbarPill.gap)   // 9: the knob's reach below the box
        #expect(EditingFixtures.near(pill.frame.midX, EditingFixtures.center.x))
    }

    @Test func styleFlipAndFloatOnTopWriteRedrawAndShowInThePill() throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        h.manager.beginEditing(placement: only.id)
        let pill = try h.editor().pill
        let renders = h.manager.renderRequestsIssued

        pill.model.onStyle?(.puffy)
        #expect(h.library.library.placement(only.id)?.style == .puffy)
        #expect(h.library.library.sticker(sticker)?.lastStyle == .puffy)
        #expect(h.manager.renderRequestsIssued == renders + 1)
        #expect(pill.model.style == .puffy)

        pill.model.onFlip?()
        #expect(h.library.library.placement(only.id)?.flipped == true)
        #expect(h.manager.renderRequestsIssued == renders + 2)
        #expect(pill.model.flipped)

        pill.model.onFloatOnTop?()
        #expect(h.library.library.placement(only.id)?.onTop == true)
        #expect(panel.level == .floating)
        #expect(pill.panel.level == .floating)
        #expect(pill.model.onTop)
        pill.model.onFloatOnTop?()
        #expect(panel.level == PanelPolicy.stickerLevel)
        #expect(pill.panel.level == PanelPolicy.stickerLevel)
        #expect(h.library.hasPendingSave)
        #expect(h.manager.editingPlacement == only.id)
    }

    @Test func removeFromThePillDeletesOnlyThePlacement() throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: only.id)
        let pill = try h.editor().pill
        pill.model.onRemove?()
        #expect(h.manager.editingPlacement == nil)
        #expect(h.manager.panel(for: only.id) == nil)
        #expect(!pill.panel.isVisible)
        #expect(h.library.library.placement(only.id) == nil)
        #expect(h.library.library.sticker(sticker) != nil)
    }

    @Test func inTheFallbackModeAnEditedStickerTakesItsWholeFrameUntilEditingEnds() throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.enableClickThroughFallback()
        h.manager.restoreAll()
        let panel = try h.panel(only.id)
        #expect(panel.ignoresMouseEvents)
        h.manager.beginEditing(placement: only.id)
        // The editing margin is transparent (no bitmap pixel): the hit pad's whole frame takes the mouse.
        let corner = CGPoint(x: panel.frame.minX + 3, y: panel.frame.minY + 3)
        h.manager.updateClickThrough(at: corner)
        #expect(!panel.ignoresMouseEvents)
        h.manager.endEditing(discardGesture: true)
        // The real cursor is never near x = 40 000: the panel lets the mouse through again at once.
        #expect(panel.ignoresMouseEvents)
        h.manager.updateClickThrough(at: corner)
        #expect(panel.ignoresMouseEvents)
    }

    @Test func deleteRemovesThePlacementOnTheNextTurn() async throws {
        let only = placement()
        let h = try harness([only])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: only.id)
        try h.view(only.id).keyDown(with: try EditingHarness.keyEvent(51, "\u{7f}"))
        // Not inside the panel's own key event.
        #expect(h.library.library.placement(only.id) != nil)
        h.finish()
        #expect(await PickerModelTests.waitUntil { h.library.library.placement(only.id) == nil })
        #expect(h.library.library.sticker(sticker) != nil)
    }
}
