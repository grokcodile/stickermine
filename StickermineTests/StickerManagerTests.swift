import AppKit
import Testing
@testable import Stickermine

/// A library on disk, a fake set of displays and a StickerManager over them.
/// Every display sits far off the real screens, so panels ordered in here
/// never appear on the desktop; `finish()` closes them before the test returns.
@MainActor
private final class Harness {
    let root: URL
    let store: LibraryStore
    let library: LibraryController
    let screens: FakeScreens
    let manager: StickerManager
    let master = Fixtures.image(width: 400, height: 200)

    init(_ model: Library, displays: [DisplayInfo], pngs: [UUID]? = nil) throws {
        root = Fixtures.temporaryDirectory()
        store = LibraryStore(root: root)
        for id in pngs ?? model.stickers.map(\.id) {
            try store.writePNG(Fixtures.pngData(width: 400, height: 200, pixelsPerPoint: 2), for: id)
        }
        try store.save(model)
        // Saves would only happen after a minute: a test sees exactly what was scheduled.
        library = LibraryController(store: store, saveDelay: 60)
        screens = FakeScreens(displays)
        let master = self.master
        manager = StickerManager(library: library, screens: screens,
                                 renderer: StyleRenderer(masterProvider: { _ in master }), reconcileDelay: 0.05)
    }

    func savedBytes() throws -> Data {
        try Data(contentsOf: store.libraryURL)
    }

    func finish() {
        manager.closeAllPanels()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
struct StickerManagerTests {
    private let sticker = UUID()
    private let absentUUID = "0F0F0F0F-1111-4222-8333-444444444444"

    private func placement(_ sticker: UUID, x: Double = 0.5, y: Double = 0.5, scale: Double = 1,
                           onTop: Bool = false) -> Placement {
        Placement(sticker: sticker, style: .outline, onTop: onTop, poses: ["1920x1080": Pose(x: x, y: y, scale: scale)])
    }

    /// One sticker placed on the external display (and optionally on a display that isn't connected).
    private func model(_ onExternal: [Placement], absent: [Placement] = [], stickers: [StickerRecord]? = nil) -> Library {
        var displays = [Fixtures.externalUUID: Fixtures.displayRecord(for: Fixtures.external(), placements: onExternal)]
        if !absent.isEmpty {
            let other = Fixtures.display(uuid: absentUUID, id: 9, frame: .zero, name: "Studio Display",
                                         vendor: 1552, model: 44_828, serial: 77)
            displays[absentUUID] = Fixtures.displayRecord(for: other, placements: absent)
        }
        return Library(stickers: stickers ?? [Fixtures.sticker(sticker)], displays: displays)
    }

    @Test func restoreCreatesPanelsOnlyForConnectedDisplays() throws {
        let here = placement(sticker)
        let away = placement(sticker)
        let h = try Harness(model([here], absent: [away]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        #expect(h.manager.placementsWithPanels == [here.id])
        let panel = try #require(h.manager.panel(for: here.id))
        #expect(panel.isVisible)
        #expect(panel.placementID == here.id)
        // 200 × 100 pt centred on the 1920 × 1080 display at x = 40 000.
        #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        #expect(panel.level == PanelPolicy.stickerLevel)
        #expect(panel.sharingType == .none)
        #expect(panel.mouseFlagWrites == 0 && panel.floatingFlagWrites == 0)
        #expect(h.manager.panel(for: away.id) == nil)
        // A display without a record shows nothing and gets no record (spec section 11).
        #expect(h.library.library.displays[Fixtures.mainUUID] == nil)
    }

    @Test func floatOnTopPlacementsUseTheFloatingLevel() throws {
        let floating = placement(sticker, onTop: true)
        let h = try Harness(model([floating]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        #expect(h.manager.panel(for: floating.id)?.level == .floating)
    }

    @Test func aDisconnectedDisplaysPanelsAreOrderedOutKeptAndNothingIsWritten() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let frame = panel.frame
        let saved = try h.savedBytes()

        h.screens.all = [Fixtures.main()]
        h.manager.reconcileNow()
        #expect(h.manager.panel(for: here.id) === panel)
        #expect(!panel.isVisible)
        #expect(panel.frame == frame)
        #expect(!h.library.hasPendingSave)
        #expect(try h.savedBytes() == saved)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements == [here])
    }

    @Test func aReconnectedDisplayGetsTheSamePanelsBackInPlace() throws {
        let back = placement(sticker, x: 0.2, y: 0.3)
        let front = placement(sticker, x: 0.7, y: 0.6)
        let h = try Harness(model([back, front]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panels = try [back, front].map { try #require(h.manager.panel(for: $0.id)) }
        let frames = panels.map(\.frame)
        let saved = try h.savedBytes()
        let seenBefore = try #require(h.library.library.displays[Fixtures.externalUUID]?.lastSeen)

        h.screens.all = [Fixtures.main()]
        h.manager.reconcileNow()
        h.screens.all = [Fixtures.main(), Fixtures.external()]
        h.manager.reconcileNow()

        for (index, panel) in panels.enumerated() {
            #expect(h.manager.panel(for: [back, front][index].id) === panel)
            #expect(panel.isVisible)
            #expect(panel.frame == frames[index])
        }
        // Nothing is written; lastSeen is refreshed in memory for the next save.
        #expect(!h.library.hasPendingSave)
        #expect(try h.savedBytes() == saved)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements == [back, front])
        #expect((h.library.library.displays[Fixtures.externalUUID]?.lastSeen ?? .distantPast) >= seenBefore)
    }

    @Test func noUsableDisplayChangesNothing() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let ghost = Fixtures.display(uuid: "GHOST", id: 7, frame: CGRect(x: 60_000, y: 0, width: 1, height: 1),
                                     vendor: 0x756E6B6E, model: 0x76697274)
        for displays in [[], [ghost]] {
            h.screens.all = displays
            h.manager.reconcileNow()
            #expect(panel.isVisible)
            #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        }
    }

    @Test func framesAreReappliedEvenWhenNothingChanged() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let renders = h.manager.renderRequestsIssued
        // As if AppKit had moved the window to another screen.
        panel.setFrame(CGRect(x: 52_000, y: 300, width: 200, height: 100), display: false)
        h.manager.reconcileNow()
        #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        // The snapshot didn't change: no re-resolution, no re-render.
        #expect(h.manager.renderRequestsIssued == renders)
    }

    @Test func aPlacementChangedInTheModelIsRedrawnOnRefresh() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        // What M5 does at a drag's end: write the pose, then refresh the panel.
        h.library.mutate { library in
            library.displays[Fixtures.externalUUID]?.placements[0].poses["1920x1080"] = Pose(x: 0.25, y: 0.25, scale: 1)
        }
        h.manager.reconcileNow()
        #expect(h.manager.panel(for: here.id)?.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100),
                "a plain reconcile keeps the cached layout")
        h.manager.refreshPanel(for: here.id)
        #expect(h.manager.panel(for: here.id)?.frame == CGRect(x: 40_380, y: 220, width: 200, height: 100))
    }

    @Test func aResolutionChangeBorrowsTheClosestSizeAndWritesNothing() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let renders = h.manager.renderRequestsIssued
        let saved = try h.savedBytes()
        h.screens.all = [Fixtures.external(frame: CGRect(x: 40_000, y: 0, width: 2560, height: 1440))]
        h.manager.reconcileNow()
        let frame = try #require(h.manager.panel(for: here.id)?.frame)
        // scale × min(2560/1920, 1440/1080) = 4/3, centred on the bigger display.
        #expect(abs(frame.width - 800.0 / 3) <= 1)
        #expect(abs(frame.height - 400.0 / 3) <= 1)
        #expect(abs(frame.midX - 41_280) <= 1)
        #expect(abs(frame.midY - 720) <= 1)
        #expect(h.manager.renderRequestsIssued == renders + 1)
        #expect(!h.library.hasPendingSave)
        #expect(try h.savedBytes() == saved)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements == [here])
    }

    @Test func aBackingScaleChangeReRendersAtTheSameFrame() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external(scale: 2)])
        defer { h.finish() }
        h.manager.restoreAll()
        let frame = try #require(h.manager.panel(for: here.id)?.frame)
        let renders = h.manager.renderRequestsIssued
        h.screens.all = [Fixtures.external(scale: 1)]
        h.manager.reconcileNow()
        #expect(h.manager.renderRequestsIssued == renders + 1)
        #expect(h.manager.panel(for: here.id)?.frame == frame)
    }

    @Test func aRemoveCallbackOrdersThatDisplayOutAtOnce() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        h.manager.handleDisplayRemoved(displayID: 99)   // unknown ID: nothing happens
        #expect(panel.isVisible)
        h.manager.handleDisplayRemoved(displayID: 3)    // the external display's runtime ID
        #expect(!panel.isVisible)
        #expect(h.manager.panel(for: here.id) === panel)
    }

    @Test func onlyAnAfterPassWithTheRemoveFlagActs() {
        #expect(StickerManager.ordersOutImmediately(for: [.removeFlag]))
        #expect(StickerManager.ordersOutImmediately(for: [.removeFlag, .disabledFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.beginConfigurationFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.beginConfigurationFlag, .removeFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.addFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.setModeFlag, .movedFlag]))
    }

    @Test func placingCreatesTheDisplayRecordAndOnePoseForThisSize() throws {
        let h = try Harness(Library(stickers: [Fixtures.sticker(sticker)], displays: [:]),
                            displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let id = try #require(h.manager.place(sticker: sticker, style: .shadow,
                                              centerOnScreen: NSPoint(x: 40_480, y: 270),
                                              pointSize: CGSize(width: 100, height: 50)))
        let record = try #require(h.library.library.displays[Fixtures.externalUUID])
        #expect(record.name == "LG UltraFine")
        #expect(record.vendor == 7789 && record.model == 23305 && record.serial == 848_464 && !record.builtin)
        #expect(record.placements.count == 1)
        let placed = record.placements[0]
        #expect(placed.id == id)
        #expect(placed.sticker == sticker)
        #expect(placed.style == .shadow)
        #expect(!placed.flipped && !placed.onTop && placed.rotation == 0)
        #expect(placed.poses == ["1920x1080": Pose(x: 0.25, y: 0.25, scale: 0.5)])
        #expect(h.library.hasPendingSave)
        let panel = try #require(h.manager.panel(for: id))
        #expect(panel.isVisible)
        #expect(panel.frame == CGRect(x: 40_430, y: 245, width: 100, height: 50))
        #expect(panel.mouseFlagWrites == 0 && panel.floatingFlagWrites == 0)
    }

    @Test func aNewPlacementGoesOnTopOfItsDisplay() throws {
        let existing = placement(sticker)
        let h = try Harness(model([existing]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let id = try #require(h.manager.place(sticker: sticker, style: .none, centerOnScreen: NSPoint(x: 41_000, y: 500),
                                              pointSize: CGSize(width: 200, height: 100)))
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.map(\.id) == [existing.id, id])
    }

    @Test func aFingerprintAdoptedDisplayShowsTheOldRecordUntilAUserEdit() throws {
        // The external display came back with a new UUID; its old record matches its fingerprint.
        let old = placement(sticker)
        let renamed = Fixtures.display(uuid: "NEW-UUID-0000-4000-8000-000000000000", id: 3,
                                       frame: CGRect(x: 40_000, y: 0, width: 1920, height: 1080), name: "LG UltraFine")
        let h = try Harness(model([old]), displays: [renamed, Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: old.id))
        #expect(panel.isVisible)
        #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        #expect(!h.library.hasPendingSave)
        #expect(h.library.library.displays[Fixtures.externalUUID] != nil)

        let added = try #require(h.manager.place(sticker: sticker, style: .puffy, centerOnScreen: NSPoint(x: 40_200, y: 200),
                                                 pointSize: CGSize(width: 100, height: 50)))
        #expect(h.library.library.displays[Fixtures.externalUUID] == nil)
        #expect(h.library.library.displays[renamed.uuid]?.placements.map(\.id) == [old.id, added])
        #expect(h.library.hasPendingSave)
    }

    @Test func removeDeletesOnlyThePlacement() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let view = try #require(panel.contentView as? StickerView)
        h.manager.remove(placement: here.id)
        #expect(h.manager.panel(for: here.id) == nil)
        #expect(!panel.isVisible)
        #expect(view.contentLayer.contents == nil)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.isEmpty == true)
        #expect(h.library.library.sticker(sticker) != nil)
        #expect(FileManager.default.fileExists(atPath: h.store.pngURL(for: sticker).path))
        #expect(h.library.hasPendingSave)
    }

    @Test func removingATutorialStickerDeletesItOutright() throws {
        let maple = LibraryStore.tutorialIDs[2]
        let here = placement(maple)
        let h = try Harness(model([here], stickers: [Fixtures.sticker(maple, tutorial: true)]),
                            displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.remove(placement: here.id)
        #expect(h.library.library.sticker(maple) == nil)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: h.store.pngURL(for: maple).path))
    }

    @Test func deletingAStickerRemovesEveryPlacementEverywhereAndItsPNG() throws {
        let other = UUID()
        let here = placement(sticker)
        let away = placement(sticker)
        let kept = placement(other, x: 0.1, y: 0.1)
        let h = try Harness(model([here, kept], absent: [away], stickers: [Fixtures.sticker(sticker), Fixtures.sticker(other)]),
                            displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        #expect(h.library.library.placementCount(of: sticker) == 2)
        h.manager.deleteSticker(sticker)
        #expect(h.manager.placementsWithPanels == [kept.id])
        #expect(h.library.library.sticker(sticker) == nil)
        #expect(h.library.library.placementCount(of: sticker) == 0)
        #expect(h.library.library.displays[absentUUID]?.placements.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: h.store.pngURL(for: sticker).path))
        #expect(FileManager.default.fileExists(atPath: h.store.pngURL(for: other).path))
    }

    @Test func theSharingSettingAppliesToEveryPanelLive() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let hidden = try #require(h.manager.panel(for: here.id))
        #expect(hidden.sharingType == .none)
        h.manager.setSharingHidden(false)
        // On macOS 27.2 a panel once set to .none keeps reporting .none: it is recreated in place.
        let shown = try #require(h.manager.panel(for: here.id))
        #expect(shown.sharingType == .readOnly)
        #expect(shown.isVisible)
        #expect(shown.frame == hidden.frame)
        #expect(shown.mouseFlagWrites == 0 && shown.floatingFlagWrites == 0)
        let added = try #require(h.manager.place(sticker: sticker, style: .none, centerOnScreen: NSPoint(x: 41_000, y: 500),
                                                 pointSize: CGSize(width: 100, height: 50)))
        #expect(h.manager.panel(for: added)?.sharingType == .readOnly)
        // Hiding applies to the existing windows.
        h.manager.setSharingHidden(true)
        #expect(h.manager.panel(for: here.id) === shown)
        #expect(shown.sharingType == .none)
        #expect(h.manager.panel(for: added)?.sharingType == sharingNone)
    }

    @Test func aPanelRecreatedForSharingKeepsItsBitmap() async throws {
        let here = placement(sticker)
        let request = RenderRequest(sticker: sticker, style: .outline, flipped: false, rotation: 0,
                                    pointSize: CGSize(width: 200, height: 100), backingScale: 2)
        let rendered = try await StyleRenderer(masterProvider: { _ in Fixtures.image(width: 400, height: 200) })
            .render(request)
        // From here on nothing suspends, so no other test sees these panels.
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.commitRender(rendered, for: request, placement: here.id)
        let renders = h.manager.renderRequestsIssued
        let old = try #require(h.manager.panel(for: here.id))
        h.manager.setSharingHidden(false)
        // On macOS 27.2 the old panel keeps reporting .none, so it is replaced.
        let new = try #require(h.manager.panel(for: here.id))
        #expect(new !== old)
        let view = try #require(new.contentView as? StickerView)
        #expect(view.contentLayer.contents != nil)
        // Outline's bitmap is the sticker plus its rim on every side.
        #expect(view.contentPointSize == rendered.pointBounds)
        #expect(h.manager.renderRequestsIssued == renders)
    }

    @Test func fallbackModePanelsIgnoreTheMouseUntilHovered() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        #expect(!h.manager.isClickThroughFallbackEnabled)
        h.manager.enableClickThroughFallback()
        #expect(h.manager.isClickThroughFallbackEnabled)
        h.manager.restoreAll()
        #expect(h.manager.panel(for: here.id)?.ignoresMouseEvents == true)
    }

    @Test func rebuildRecreatesEveryPanelInPlace() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let old = try #require(h.manager.panel(for: here.id))
        h.manager.rebuildAllPanels()
        let new = try #require(h.manager.panel(for: here.id))
        #expect(new !== old)
        #expect(!old.isVisible)
        #expect(new.isVisible)
        #expect(new.frame == old.frame)
        #expect(new.mouseFlagWrites == 0 && new.floatingFlagWrites == 0)
    }

    @Test func onlyTheNewestRenderIsShown() async throws {
        let here = placement(sticker)
        let current = RenderRequest(sticker: sticker, style: .outline, flipped: false, rotation: 0,
                                    pointSize: CGSize(width: 200, height: 100), backingScale: 2)
        let stale = RenderRequest(sticker: sticker, style: .outline, flipped: false, rotation: 0,
                                  pointSize: CGSize(width: 200, height: 100), backingScale: 1)
        let rendered = try await StyleRenderer(masterProvider: { _ in Fixtures.image(width: 400, height: 200) })
            .render(current)
        // From here on nothing suspends, so no other test sees these panels.
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let view = try #require(h.manager.panel(for: here.id)?.contentView as? StickerView)
        h.manager.commitRender(rendered, for: stale, placement: here.id)
        #expect(view.contentLayer.contents == nil)
        h.manager.commitRender(rendered, for: current, placement: here.id)
        #expect(view.contentLayer.contents != nil)
        // Outline's bitmap is the sticker plus its rim on every side.
        #expect(view.contentPointSize == rendered.pointBounds)
        h.manager.remove(placement: here.id)
        h.manager.commitRender(rendered, for: current, placement: here.id)   // placement gone: ignored
    }

    @Test func displayEventsAreDebounced() async throws {
        let h = try Harness(Library(stickers: [], displays: [:]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.scheduleReconcile()
        h.manager.scheduleReconcile()
        h.manager.scheduleReconcile()
        #expect(h.manager.reconcileCount == 0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(h.manager.reconcileCount == 1)
    }

    @Test func screenWakeAndUnlockEventsShareTheDebounce() async throws {
        let h = try Harness(Library(stickers: [], displays: [:]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.systemEvent(recheckLater: false)
        h.manager.scheduleReconcile()
        h.manager.systemEvent(recheckLater: false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(h.manager.reconcileCount == 1)
    }

    @Test func aNewerLibraryIsShownButCantBeEdited() throws {
        let here = placement(sticker)
        var newer = model([here])
        newer.version = 2
        let h = try Harness(newer, displays: [Fixtures.external()])
        defer { h.finish() }
        #expect(h.library.isReadOnly)
        h.manager.restoreAll()
        #expect(h.manager.panel(for: here.id)?.isVisible == true)
        #expect(h.manager.place(sticker: sticker, style: .none, centerOnScreen: NSPoint(x: 41_000, y: 500),
                                pointSize: CGSize(width: 100, height: 50)) == nil)
        h.manager.remove(placement: here.id)
        h.manager.deleteSticker(sticker)
        #expect(h.manager.panel(for: here.id) != nil)
        #expect(h.library.library.placementCount(of: sticker) == 1)
        #expect(FileManager.default.fileExists(atPath: h.store.pngURL(for: sticker).path))
    }

    @Test func theDisplayUnderAPointOrTheNearestOne() {
        let external = Fixtures.external()
        let main = Fixtures.main()
        #expect(StickerManager.display(containing: NSPoint(x: 40_100, y: 100), in: [main, external])?.uuid == external.uuid)
        #expect(StickerManager.display(containing: NSPoint(x: 50_100, y: 100), in: [main, external])?.uuid == main.uuid)
        // In the gap between them: the external display's right edge is nearer.
        #expect(StickerManager.display(containing: NSPoint(x: 42_000, y: 100), in: [main, external])?.uuid == external.uuid)
        #expect(StickerManager.display(containing: .zero, in: []) == nil)
    }

    @Test func aNonFinitePlacementIsRefused() throws {
        let h = try Harness(Library(stickers: [Fixtures.sticker(sticker)], displays: [:]),
                            displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        for size in [CGSize(width: CGFloat.infinity, height: 50), CGSize(width: CGFloat.nan, height: 50)] {
            #expect(h.manager.place(sticker: sticker, style: .shadow, centerOnScreen: NSPoint(x: 40_480, y: 270),
                                    pointSize: size) == nil)
        }
        #expect(h.manager.place(sticker: sticker, style: .shadow,
                                centerOnScreen: NSPoint(x: CGFloat.nan, y: 270),
                                pointSize: CGSize(width: 100, height: 50)) == nil)
        #expect(h.library.library.displays[Fixtures.externalUUID] == nil)
        #expect(!h.library.hasPendingSave)
    }
}

/// `.none` next to an Optional reads as `Optional.none`; spell the sharing type out.
private let sharingNone = NSWindow.SharingType.none
