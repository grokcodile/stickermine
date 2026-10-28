import AppKit
import Testing
@testable import Stickermine

/// Editing and sessions (spec section 5.2): a session ends editing and takes
/// over handing focus back; double-clicks don't enter editing while it runs.
@MainActor
struct EditingWiringTests {
    private let sticker = UUID()

    @Test func startingASessionEndsEditingDiscardsTheGestureAndTakesOverTheFocus() async throws {
        let only = EditingFixtures.placement(sticker)
        let first = try await EditingHarness.render(EditingFixtures.request(sticker))
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [only]), displays: [Fixtures.external()])
        defer { h.finish() }
        let capture = CaptureService(command: CaptureServiceTests.shell("exec sleep 5"), temporaryDirectory: h.root,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { false })
        let session = SessionCoordinator(capture: capture, cutout: CutoutEngine(perform: { _ in nil }),
                                         stickers: h.manager, library: h.library, store: h.store,
                                         renderer: StyleRenderer(masterProvider: { _ in nil }), screens: h.screens,
                                         access: SessionCoordinatorTests.FakeAccess(granted: true),
                                         showMessage: { _ in }, presentPermission: {}, restoresFocus: false)
        defer { session.cancel() }
        h.manager.isSessionActive = { session.isActive }
        h.manager.restoreAll()
        h.manager.commitRender(first, for: EditingFixtures.request(sticker), placement: only.id)
        let panel = try h.panel(only.id)
        let saved = panel.frame
        h.manager.beginEditing(placement: only.id)
        try h.editor().magnify(by: 0.5, phase: .began)
        session.startCapture()
        #expect(session.isActive)
        #expect(h.manager.editingPlacement == nil)
        #expect(h.focus.returned.isEmpty, "the session hands focus back when it ends")
        #expect(try h.view(only.id).contentScale == 1)
        #expect(panel.frame == saved)
        #expect(h.library.library.placement(only.id) == only)
        #expect(!h.library.hasPendingSave)
        // While the session runs, a double-click doesn't enter editing.
        try h.view(only.id).onDoubleClick?()
        #expect(h.manager.editingPlacement == nil)
    }

    @Test func aSessionStartedRightAfterAClickOnAnotherStickerTakesOverTheFocus() async throws {
        let a = EditingFixtures.placement(sticker, x: 0.3), b = EditingFixtures.placement(sticker, x: 0.7)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [a, b]), displays: [Fixtures.external()])
        defer { h.finish() }
        let capture = CaptureService(command: CaptureServiceTests.shell("exec sleep 5"), temporaryDirectory: h.root,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { false })
        let session = SessionCoordinator(capture: capture, cutout: CutoutEngine(perform: { _ in nil }),
                                         stickers: h.manager, library: h.library, store: h.store,
                                         renderer: StyleRenderer(masterProvider: { _ in nil }), screens: h.screens,
                                         access: SessionCoordinatorTests.FakeAccess(granted: true),
                                         showMessage: { _ in }, presentPermission: {}, restoresFocus: false)
        defer { session.cancel() }
        h.manager.restoreAll()
        h.manager.beginEditing(placement: a.id)
        try h.view(b.id).onInactiveMouseDown?()
        session.startCapture()
        #expect(session.isActive)
        h.finish()
        try await Task.sleep(nanoseconds: UInt64((NSEvent.doubleClickInterval + 0.3) * 1_000_000_000))
        #expect(h.focus.returned.isEmpty, "the session hands focus back when it ends")
    }

    @Test func theAppGatesEditingOnTheSession() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(delegate.contains("stickers.isSessionActive = { [weak session] in session?.isActive ?? false }"))
        let coordinator = try SourceFiles.contents(of: "App/SessionCoordinator.swift")
        #expect(coordinator.contains("stickers.endEditing(discardGesture: true, returningFocus: false)"))
        #expect(!coordinator.contains("stickers.endEditing(discardGesture: true)\n"))
    }
}
