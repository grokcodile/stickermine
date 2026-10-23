import AppKit
import Testing
@testable import Stickermine

/// Sessions up to the capture's outcome. Never runs screencapture (a shell
/// command stands in), never shows a panel (the HUD and the permission panel
/// are replaced) and never moves focus.
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
}
