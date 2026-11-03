import AppKit
import Carbon.HIToolbox
import ServiceManagement
import Testing
@testable import Stickermine

/// Home's model without a window: a temporary library, its own defaults
/// suite, a fake login item service, a fake Screen Recording check and
/// recorded actions.
@MainActor
struct HomeModelTests {
    final class Recorded {
        var newStickers = 0
        var replaced: [UUID] = []
        var deleted: [UUID] = []
        var shortcuts: [Shortcut?] = []
        var recording: [Bool] = []
        var menuBarIcon: [Bool] = []
        var sharingHidden: [Bool] = []
        var permissionPanels = 0
        var relaunches = 0
        var quits = 0
    }

    final class FakeAccess: ScreenRecordingAccess {
        var granted = false
        func preflight() -> Bool { granted }
        func request() -> Bool { granted }
    }

    struct Harness {
        let model: HomeModel
        let library: LibraryController
        let defaults: UserDefaults
        let suiteName: String
        let folder: URL
        let recorded: Recorded
        let access: FakeAccess
        let service: LoginItemTests.FakeService

        func finish() {
            defaults.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    static func harness(_ stickers: [StickerRecord] = [], placements: [Placement] = [], readOnly: Bool = false,
                        conflicts: @escaping (Shortcut) -> Bool = { _ in false }) throws -> Harness {
        let folder = Fixtures.temporaryDirectory()
        let store = LibraryStore(root: folder)
        if readOnly {
            try Data(#"{"version": 99, "stickers": [], "displays": {}}"#.utf8)
                .write(to: folder.appendingPathComponent("library.json"))
        } else {
            for sticker in stickers {
                try store.writePNG(Fixtures.pngData(width: 40, height: 40, pixelsPerPoint: 2), for: sticker.id)
            }
            let displays = placements.isEmpty ? [:]
                : [Fixtures.externalUUID: Fixtures.displayRecord(for: Fixtures.external(), placements: placements)]
            try store.save(Library(stickers: stickers, displays: displays))
        }
        let library = LibraryController(store: store, saveDelay: 60)
        let suiteName = "StickermineTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        Settings.register(in: defaults)
        let recorded = Recorded()
        let access = FakeAccess()
        let service = LoginItemTests.FakeService(status: .enabled)
        var actions = HomeModel.Actions()
        actions.newSticker = { recorded.newStickers += 1 }
        actions.replace = { recorded.replaced.append($0) }
        actions.delete = { recorded.deleted.append($0) }
        actions.shortcutChanged = { recorded.shortcuts.append($0) }
        actions.recordingChanged = { recorded.recording.append($0) }
        actions.menuBarIconChanged = { recorded.menuBarIcon.append($0) }
        actions.sharingHiddenChanged = { recorded.sharingHidden.append($0) }
        actions.fixScreenRecording = { recorded.permissionPanels += 1 }
        actions.relaunch = { recorded.relaunches += 1 }
        actions.quit = { recorded.quits += 1 }
        let model = HomeModel(library: library, defaults: defaults,
                              loginItem: LoginItem(service: service, defaults: defaults), access: access,
                              thumbnails: ThumbnailCache(),
                              updater: Updater(appVersion: "1.0", fetch: { nil }, beforeHelper: {}),
                              conflicts: conflicts, actions: actions)
        return Harness(model: model, library: library, defaults: defaults, suiteName: suiteName, folder: folder,
                       recorded: recorded, access: access, service: service)
    }

    private func record(_ id: UUID = UUID(), at seconds: TimeInterval, tutorial: Bool = false) -> StickerRecord {
        StickerRecord(id: id, created: Date(timeIntervalSince1970: seconds), pixelWidth: 40, pixelHeight: 40,
                      pixelsPerPoint: 2, lastStyle: .outline, tutorial: tutorial)
    }

    @Test func theHistoryIsEveryOwnStickerNewestFirstAndFollowsTheLibrary() throws {
        let old = record(at: 100), new = record(at: 200)
        let tutorial = record(LibraryStore.tutorialIDs[2], at: 300, tutorial: true)
        let h = try Self.harness([old, tutorial, new])
        defer { h.finish() }
        #expect(h.model.history.map(\.id) == [new.id, old.id])
        let newest = record(at: 400)
        h.library.mutate { $0.stickers.append(newest) }
        h.model.libraryChanged()
        #expect(h.model.history.map(\.id) == [newest.id, new.id, old.id])
        #expect(h.model.pngURL(for: old.id) == h.library.store.pngURL(for: old.id))
    }

    @Test func newStickerAndReplaceAreIgnoredDuringASession() throws {
        let sticker = record(at: 100)
        let h = try Self.harness([sticker])
        defer { h.finish() }
        h.model.newSticker()
        h.model.replace(sticker.id)
        #expect(h.recorded.newStickers == 1)
        #expect(h.recorded.replaced == [sticker.id])
        h.model.sessionActive = true
        h.model.newSticker()
        h.model.replace(sticker.id)
        #expect(h.recorded.newStickers == 1)
        #expect(h.recorded.replaced == [sticker.id])
    }

    @Test func deleteAsksWithThePlacementCountThenDeletes() throws {
        let sticker = record(at: 100)
        let placements = [EditingFixtures.placement(sticker.id), EditingFixtures.placement(sticker.id)]
        let h = try Self.harness([sticker], placements: placements)
        defer { h.finish() }
        h.model.requestDelete(sticker.id)
        #expect(h.model.pendingDelete == HomeModel.PendingDelete(id: sticker.id,
                                                                 message: HistoryList.deleteMessage(placementCount: 2)))
        h.model.cancelDelete()
        #expect(h.model.pendingDelete == nil)
        #expect(h.recorded.deleted.isEmpty)
        h.model.requestDelete(sticker.id)
        h.model.confirmDelete()
        #expect(h.recorded.deleted == [sticker.id])
        #expect(h.model.pendingDelete == nil)
        h.model.requestDelete(UUID())
        #expect(h.model.pendingDelete == nil)
    }

    @Test func aReadOnlyLibraryShowsTheNoticeAndChangesNothing() throws {
        let h = try Self.harness(readOnly: true)
        defer { h.finish() }
        #expect(h.model.isReadOnly)
        h.model.newSticker()
        h.model.replace(UUID())
        #expect(h.recorded.newStickers == 0)
        #expect(h.recorded.replaced.isEmpty)
        #expect(HUD.readOnlyMessage == "This library was saved by a newer Stickermine. Update to make changes.")
    }

    @Test func aRecordedShortcutIsStoredCheckedAndPassedOn() throws {
        let clash = Shortcut(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey))
        let h = try Self.harness(conflicts: { $0 == clash })
        defer { h.finish() }
        #expect(h.model.shortcut == .defaultCapture)
        #expect(!h.model.shortcutConflicts)
        h.model.recordingChanged(true)
        h.model.setShortcut(clash)
        h.model.recordingChanged(false)
        #expect(h.defaults.captureShortcut == clash)
        #expect(h.model.shortcutConflicts)
        h.model.setShortcut(nil)
        #expect(h.defaults.captureShortcut == nil)
        #expect(!h.model.shortcutConflicts)
        #expect(h.recorded.shortcuts == [clash, nil])
        #expect(h.recorded.recording == [true, false])
    }

    @Test func aRefusedChordShowsUntilTheNextRecording() throws {
        let h = try Self.harness()
        defer { h.finish() }
        h.model.rejectChord()
        #expect(h.model.chordRejected)
        h.model.recordingChanged(true)
        #expect(!h.model.chordRejected)
        h.model.rejectChord()
        h.model.setShortcut(.defaultCapture)
        #expect(!h.model.chordRejected)
    }

    @Test func theTogglesWriteTheirSettingsAndActLive() throws {
        let h = try Self.harness()
        defer { h.finish() }
        h.model.setShowMenuBarIcon(false)
        h.model.setHideFromSharing(false)
        #expect(!h.defaults.showMenuBarIcon)
        #expect(!h.defaults.hideFromSharing)
        #expect(!h.model.showMenuBarIcon)
        #expect(!h.model.hideFromSharing)
        #expect(h.recorded.menuBarIcon == [false])
        #expect(h.recorded.sharingHidden == [false])
        h.model.setLaunchAtLogin(false)
        #expect(h.model.loginState == .off)
        #expect(h.service.unregisters == 1)
        h.service.statusAfterRegister = .requiresApproval
        h.model.setLaunchAtLogin(true)
        #expect(h.model.loginState == .requiresApproval)
        #expect(h.service.settingsOpened == 1)
        h.model.openLoginItems()
        #expect(h.service.settingsOpened == 2)
        h.model.quit()
        #expect(h.recorded.quits == 1)
    }

    @Test func screenRecordingIsReadAgainOnRefresh() throws {
        let h = try Self.harness()
        defer { h.finish() }
        #expect(!h.model.screenRecordingOn)
        h.model.fixScreenRecording()
        #expect(h.recorded.permissionPanels == 1)
        #expect(!h.model.screenRecordingRequested)
        h.defaults.didRequestScreenCapture = true
        h.model.refresh()
        #expect(h.model.screenRecordingRequested)
        h.model.relaunch()
        #expect(h.recorded.relaunches == 1)
        h.access.granted = true
        #expect(!h.model.screenRecordingOn)
        h.model.refresh()
        #expect(h.model.screenRecordingOn)
    }
}
