import AppKit
import Testing
@testable import Stickermine

/// Records where editing would move focus, without activating anything.
@MainActor
final class RecordingFocus: EditingFocus {
    /// What `frontmostOtherApp()` answers.
    var frontmost: NSRunningApplication?
    private(set) var taken: [NSPanel] = []
    private(set) var returned: [NSRunningApplication?] = []

    func frontmostOtherApp() -> NSRunningApplication? { frontmost }
    func takeFocus(for panel: NSPanel) { taken.append(panel) }
    func returnFocus(to app: NSRunningApplication?) { returned.append(app) }
}

/// What can end editing (spec section 10), other than Remove and a session.
enum EditingEndTrigger: CaseIterable {
    case escape, resignKey, sleepOrLock, displayRemoved, displayGone, rebuild
}

/// Placements, libraries and render requests for the editing tests: one
/// 200 × 100 pt sticker (400 × 200 px at 2 px/pt) in Outline.
enum EditingFixtures {
    /// The centre of the external display in the fixtures (1920 × 1080 at x = 40 000).
    static let center = CGPoint(x: 40_960, y: 540)

    static func placement(_ sticker: UUID, x: Double = 0.5, y: Double = 0.5, scale: Double = 1,
                          poses: [String: Pose]? = nil) -> Placement {
        Placement(sticker: sticker, style: .outline, poses: poses ?? ["1920x1080": Pose(x: x, y: y, scale: scale)])
    }

    /// `external` on the external display; `main` on the main display, which
    /// has no record when it is nil.
    static func library(_ sticker: UUID, external: [Placement], main: [Placement]? = nil) -> Library {
        var displays = [Fixtures.externalUUID: Fixtures.displayRecord(for: Fixtures.external(), placements: external)]
        if let main {
            displays[Fixtures.mainUUID] = Fixtures.displayRecord(for: Fixtures.main(), placements: main)
        }
        return Library(stickers: [Fixtures.sticker(sticker)], displays: displays)
    }

    /// The request StickerManager issues for an unflipped Outline placement.
    static func request(_ sticker: UUID, rotation: Double = 0, size: CGSize = CGSize(width: 200, height: 100),
                        backingScale: CGFloat = 2) -> RenderRequest {
        RenderRequest(sticker: sticker, style: .outline, flipped: false, rotation: rotation, pointSize: size,
                      backingScale: backingScale)
    }

    static func near(_ a: CGFloat, _ b: CGFloat, _ tolerance: CGFloat = 0.5) -> Bool {
        abs(a - b) <= tolerance
    }
}

/// A library on disk, fake displays and a StickerManager with a recording
/// focus. Every display sits at x ≥ 40 000 pt, so panels ordered in never
/// appear on the desktop; `finish()` closes them (the pill too). A test
/// renders the bitmaps it needs first and never suspends between ordering
/// panels in and `finish()`.
@MainActor
final class EditingHarness {
    let root: URL
    let store: LibraryStore
    let library: LibraryController
    let screens: FakeScreens
    let focus = RecordingFocus()
    let manager: StickerManager

    init(_ model: Library, displays: [DisplayInfo]) throws {
        root = Fixtures.temporaryDirectory()
        store = LibraryStore(root: root)
        for sticker in model.stickers {
            try store.writePNG(Fixtures.pngData(width: 400, height: 200, pixelsPerPoint: 2), for: sticker.id)
        }
        try store.save(model)
        // Saves would only happen after a minute: a test sees exactly what was scheduled.
        library = LibraryController(store: store, saveDelay: 60)
        screens = FakeScreens(displays)
        manager = StickerManager(library: library, screens: screens,
                                 renderer: StyleRenderer(masterProvider: { _ in EditingHarness.master }),
                                 reconcileDelay: 0.05, focus: focus)
    }

    /// Every sticker's master: 400 × 200 px.
    nonisolated static let master = Fixtures.image(width: 400, height: 200)

    /// A bitmap for `request`, rendered before any panel exists.
    static func render(_ request: RenderRequest) async throws -> RenderedSticker {
        try await StyleRenderer(masterProvider: { _ in master }).render(request)
    }

    func panel(_ id: UUID) throws -> StickerPanel {
        try #require(manager.panel(for: id))
    }

    func view(_ id: UUID) throws -> StickerView {
        try #require(manager.panel(for: id)?.contentView as? StickerView)
    }

    func editor() throws -> StickerEditor {
        try #require(manager.editor)
    }

    /// Ends editing of `id` (on the external display) the way `trigger`
    /// does. The external display's runtime ID is 3; `displayGone` unplugs it
    /// and runs the reconcile the display change schedules.
    func end(_ trigger: EditingEndTrigger, editing id: UUID) throws {
        switch trigger {
        case .escape: try view(id).keyDown(with: try Self.keyEvent(53, "\u{1b}"))
        case .resignKey: try panel(id).onResignKey?()
        case .sleepOrLock: manager.systemWillSleepOrLock()
        case .displayRemoved: manager.handleDisplayRemoved(displayID: 3)
        case .displayGone:
            screens.all = screens.all.filter { $0.uuid != Fixtures.externalUUID }
            manager.reconcileNow()
        case .rebuild: manager.rebuildAllPanels()
        }
    }

    func finish() {
        manager.closeAllPanels()
        try? FileManager.default.removeItem(at: root)
    }

    static func keyEvent(_ keyCode: UInt16, _ characters: String) throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, characters: characters,
                                      charactersIgnoringModifiers: characters, isARepeat: false, keyCode: keyCode))
    }
}
