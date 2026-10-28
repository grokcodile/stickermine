import AppKit
import Testing
@testable import Stickermine

/// Sessions from the trigger to the placement. Never runs screencapture (a
/// shell command stands in), never shows a panel (the HUD, the permission
/// panel, the picker and the placement are replaced) and never moves focus.
@MainActor
struct SessionCoordinatorTests {
    final class Recorder {
        var messages: [String] = []
        var permissionPanels = 0
        var activity: [Bool] = []
    }

    final class FakeAccess: ScreenRecordingAccess {
        var granted: Bool
        init(granted: Bool) { self.granted = granted }
        func preflight() -> Bool { granted }
        func request() -> Bool { granted }
    }

    struct Harness {
        let folder: URL
        let session: SessionCoordinator
        let capture: CaptureService
        let recorder: Recorder
        let library: LibraryController
    }

    static func harness(script: String, granted: Bool = true, readOnly: Bool = false) throws -> Harness {
        let folder = Fixtures.temporaryDirectory()
        if readOnly {
            try Data(#"{"version": 99, "stickers": [], "displays": {}}"#.utf8)
                .write(to: folder.appendingPathComponent("library.json"))
        }
        let store = LibraryStore(root: folder)
        let library = LibraryController(store: store, saveDelay: 60)
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let screens = FakeScreens([Fixtures.external()])
        let stickers = StickerManager(library: library, screens: screens, renderer: renderer)
        let capture = CaptureService(command: CaptureServiceTests.shell(script), temporaryDirectory: folder,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { false })
        let recorder = Recorder()
        let session = SessionCoordinator(capture: capture, cutout: CutoutEngine(perform: { _ in nil }),
                                         stickers: stickers, library: library, store: store, renderer: renderer,
                                         screens: screens, access: FakeAccess(granted: granted),
                                         showMessage: { recorder.messages.append($0) },
                                         presentPermission: { recorder.permissionPanels += 1 },
                                         restoresFocus: false)
        session.onActiveChange = { recorder.activity.append($0) }
        return Harness(folder: folder, session: session, capture: capture, recorder: recorder, library: library)
    }

    static func waitUntilIdle(_ session: SessionCoordinator) async -> Bool {
        await PickerModelTests.waitUntil { !session.isActive }
    }

    @Test func withoutScreenRecordingThePermissionPanelShowsInsteadOfACapture() throws {
        let h = try Self.harness(script: #"printf png > "$1""#, granted: false)
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(h.recorder.permissionPanels == 1)
        #expect(!h.session.isActive)
        #expect(!h.capture.isRunning)
        #expect(h.recorder.activity.isEmpty)
    }

    @Test func oneSessionAtATimeAndCancelEndsIt() throws {
        let h = try Self.harness(script: "exec sleep 5")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(h.session.isActive)
        #expect(h.session.stage == .capturing)
        #expect(h.capture.isRunning)
        h.session.startCapture()
        h.session.startReplace(sticker: UUID())
        #expect(h.recorder.activity == [true])
        h.session.cancel()
        #expect(!h.session.isActive)
        #expect(!h.capture.isRunning)
        #expect(h.recorder.activity == [true, false])
        #expect(h.recorder.messages.isEmpty)
    }

    @Test func controlHeldAtMouseUpIsExplained() async throws {
        let h = try Self.harness(script: "exit 0")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        var count = 0
        let capture = CaptureService(command: CaptureServiceTests.shell("exit 0"), temporaryDirectory: h.folder,
                                     pasteboardChangeCount: { count += 1; return count }, modifiersHeld: { false })
        let recorder = Recorder()
        let library = LibraryController(store: LibraryStore(root: h.folder), saveDelay: 60)
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let screens = FakeScreens([Fixtures.external()])
        let session = SessionCoordinator(capture: capture, cutout: CutoutEngine(perform: { _ in nil }),
                                         stickers: StickerManager(library: library, screens: screens, renderer: renderer),
                                         library: library, store: library.store, renderer: renderer, screens: screens,
                                         access: FakeAccess(granted: true),
                                         showMessage: { recorder.messages.append($0) },
                                         presentPermission: { recorder.permissionPanels += 1 }, restoresFocus: false)
        session.startCapture()
        #expect(await Self.waitUntilIdle(session))
        #expect(recorder.messages == [HUD.controlHeldMessage])
    }

    @Test func aBusyCaptureIsExplained() async throws {
        let h = try Self.harness(script: "exit 1")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(await Self.waitUntilIdle(h.session))
        #expect(h.recorder.messages == [HUD.couldNotStartMessage])
        #expect(h.recorder.activity == [true, false])
    }

    @Test func aCancelledCaptureEndsSilently() async throws {
        let h = try Self.harness(script: "exit 0")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(await Self.waitUntilIdle(h.session))
        #expect(h.recorder.messages.isEmpty)
        #expect(h.recorder.activity == [true, false])
    }

    @Test func anUnreadableCaptureIsDeletedAndExplained() async throws {
        let h = try Self.harness(script: #"printf 'not a png' > "$1""#)
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(await Self.waitUntilIdle(h.session))
        #expect(h.recorder.messages == [HUD.couldNotStartMessage])
        let left = try FileManager.default.contentsOfDirectory(atPath: h.folder.path)
        #expect(!left.contains { $0.hasPrefix(CaptureService.filePrefix) })
    }

    @Test func aReadOnlyLibraryRefusesSessions() throws {
        let h = try Self.harness(script: #"printf png > "$1""#, readOnly: true)
        defer { try? FileManager.default.removeItem(at: h.folder) }
        #expect(h.library.isReadOnly)
        h.session.startCapture()
        h.session.startReplace(sticker: UUID())
        #expect(!h.session.isActive)
        #expect(!h.capture.isRunning)
        #expect(h.recorder.messages == [HUD.readOnlyMessage, HUD.readOnlyMessage])
    }

    @Test func rePlacingAnUnknownStickerDoesNothing() throws {
        let h = try Self.harness(script: "exit 0")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startReplace(sticker: UUID())
        #expect(!h.session.isActive)
        #expect(h.recorder.activity.isEmpty)
    }

    // MARK: The main path, past the capture

    /// What a main-path test drives. The coordinator hands the picker and the
    /// placement to the test instead of showing them, so no window appears and
    /// focus never moves.
    @MainActor
    final class Flow {
        let folder: URL
        let store: LibraryStore
        let library: LibraryController
        let renderer: StyleRenderer
        let stickers: StickerManager
        let recorder = Recorder()
        var session: SessionCoordinator!
        var placed: [(placement: UUID, sticker: UUID)] = []

        /// The capture copies a 300 × 200 px PNG at 72 dpi (1 px/pt, not the
        /// 2 px/pt every fallback uses) and Vision finds no subject, so the
        /// picker offers the whole image.
        init(presentPicker: @escaping (Flow, PickerController) -> Void,
             presentPlacement: @escaping (Flow, PlacementSession) -> Void) throws {
            folder = Fixtures.temporaryDirectory()
            let source = folder.appendingPathComponent("source.png")
            try Fixtures.pngData(width: 300, height: 200, pixelsPerPoint: 1).write(to: source)
            store = LibraryStore(root: folder)
            library = LibraryController(store: store, saveDelay: 60)
            renderer = StyleRenderer(masterProvider: { _ in nil })
            let screens = FakeScreens([Fixtures.external()])
            stickers = StickerManager(library: library, screens: screens, renderer: renderer)
            let capture = CaptureService(command: CaptureServiceTests.shell("cp '\(source.path)' \"$1\""),
                                         temporaryDirectory: folder, pasteboardChangeCount: { 7 },
                                         modifiersHeld: { false })
            let recorder = self.recorder
            session = SessionCoordinator(
                capture: capture, cutout: CutoutEngine(perform: { _ in nil }), stickers: stickers, library: library,
                store: store, renderer: renderer, screens: screens, access: FakeAccess(granted: true),
                showMessage: { recorder.messages.append($0) },
                presentPermission: { recorder.permissionPanels += 1 },
                presentPicker: { [unowned self] in presentPicker(self, $0) },
                presentPlacement: { [unowned self] in presentPlacement(self, $0) },
                restoresFocus: false)
            session.onActiveChange = { recorder.activity.append($0) }
            session.onPlaced = { [unowned self] in self.placed.append(($0, $1)) }
        }
    }

    @Test func aConfirmedCaptureIsSavedIndexedAndPlaced() async throws {
        var flagWrites: [Int] = []
        let flow = try Flow(presentPicker: { _, picker in picker.model.confirm(.outline) },
                            presentPlacement: { flow, placement in
            // Started and clicked in one turn of the main actor, so no panel is
            // ever on screen; the sticker panel it hands over is checked, then closed.
            placement.start()
            placement.place()
            for (id, _) in flow.placed {
                if let panel = flow.stickers.panel(for: id) {
                    flagWrites.append(panel.mouseFlagWrites + panel.floatingFlagWrites)
                }
            }
            flow.stickers.closeAllPanels()
        })
        defer { try? FileManager.default.removeItem(at: flow.folder) }
        flow.session.startCapture()
        #expect(await Self.waitUntilIdle(flow.session))
        #expect(flow.recorder.messages.isEmpty)
        #expect(flow.recorder.activity == [true, false])
        let record = try #require(flow.library.library.stickers.first)
        #expect(flow.library.library.stickers.count == 1)
        #expect(record.pixelWidth == 300 && record.pixelHeight == 200)
        #expect(record.pixelsPerPoint == 1)
        #expect(record.lastStyle == .outline)
        #expect(MasterImage.fileInfo(at: flow.store.pngURL(for: record.id))
                == MasterImage.FileInfo(pixelWidth: 300, pixelHeight: 200, pixelsPerPoint: 1))
        let placed = try #require(flow.placed.first)
        #expect(flow.placed.count == 1 && placed.sticker == record.id)
        let placement = try #require(flow.library.library.placement(placed.placement))
        #expect(placement.sticker == record.id && placement.style == .outline)
        #expect(flagWrites == [0])
        #expect(flow.renderer.inFlightMasterCount == 0)
        let left = try FileManager.default.contentsOfDirectory(atPath: flow.folder.path)
        #expect(!left.contains { $0.hasPrefix(CaptureService.filePrefix) })
    }

    /// Cancelled while the PNG is written: nothing is indexed and the PNG goes
    /// too, or launch repair would adopt it as a new sticker.
    @Test func cancellingWhileSavingIndexesNothingAndDeletesThePNG() async throws {
        var saving: UUID?
        let flow = try Flow(presentPicker: { flow, picker in
            let confirmed = picker.model.onConfirm
            picker.model.onConfirm = { confirmation in
                confirmed?(confirmation)   // the session starts writing the PNG off the main actor
                if flow.session.stage == .saving { saving = confirmation.sticker }
                flow.session.cancel()      // and is cancelled before the write is back
            }
            picker.model.confirm(.none)
        }, presentPlacement: { _, _ in Issue.record("nothing may be placed") })
        defer { try? FileManager.default.removeItem(at: flow.folder) }
        flow.session.startCapture()
        #expect(await Self.waitUntilIdle(flow.session))
        let sticker = try #require(saving)
        // The write and its clean-up take milliseconds, with no event to wait for.
        try await Task.sleep(nanoseconds: 500_000_000)
        #expect(!FileManager.default.fileExists(atPath: flow.store.pngURL(for: sticker).path))
        #expect(flow.library.library.stickers.isEmpty)
        #expect(flow.recorder.activity == [true, false])
        #expect(flow.renderer.inFlightMasterCount == 0)
    }
}
