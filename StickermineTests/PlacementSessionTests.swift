import AppKit
import Testing
@testable import Stickermine

/// Displays sit at x ≥ 40 000 pt and nothing waits while a panel is ordered
/// in, so the test host never shows a window.
@MainActor
struct PlacementSessionTests {
    @Test func aStickerKeepsItsNaturalSizeWhenItFitsInHalfTheDisplay() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(PlacementSession.fittedSize(natural: CGSize(width: 400, height: 300), in: frame)
                == CGSize(width: 400, height: 300))
    }

    @Test func aLargeStickerIsScaledDownToHalfTheWidthOrHeight() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(PlacementSession.fittedSize(natural: CGSize(width: 2000, height: 500), in: frame)
                == CGSize(width: 960, height: 240))
        #expect(PlacementSession.fittedSize(natural: CGSize(width: 300, height: 1080), in: frame)
                == CGSize(width: 150, height: 540))
    }

    @Test func thePanelTakesClicksOnItsWholeRectAndCanBecomeKey() {
        let panel = PlacementSession.makePanel()
        defer { panel.close() }
        #expect(panel.canBecomeKey)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.acceptsMouseMovedEvents)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isVisible)
    }

    /// Hide (⌘H) must not take the following sticker out of sight while the
    /// session ignores every trigger.
    @Test func thePlacementPanelIsNeverHidden() {
        let panel = PlacementSession.makePanel()
        defer { panel.close() }
        #expect(!panel.canHide)
    }

    @Test func theViewTakesEveryClickItself() throws {
        let view = PlacementView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(view.hitTest(NSPoint(x: 50, y: 50)) === view)
        #expect(view.hitTest(NSPoint(x: 150, y: 50)) == nil)
        #expect(view.acceptsFirstMouse(for: nil))
        var events: [String] = []
        view.onPlace = { events.append("place") }
        view.onCancel = { events.append("cancel") }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                                   timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                   clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        let right = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                    clickCount: 1, pressure: 1))
        view.rightMouseDown(with: right)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, characters: "\u{1b}",
                                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                                   keyCode: 53))
        view.keyDown(with: escape)
        #expect(events == ["place", "cancel", "cancel"])
    }

    /// A library with one 400 × 200 pt sticker on a temporary store.
    static func harness() -> (folder: URL, library: LibraryController, stickers: StickerManager, sticker: StickerRecord) {
        let folder = Fixtures.temporaryDirectory()
        let library = LibraryController(store: LibraryStore(root: folder), saveDelay: 60)
        let sticker = Fixtures.sticker(width: 400, height: 200)
        library.mutate { $0.stickers.append(sticker) }
        let stickers = StickerManager(library: library, screens: FakeScreens([Fixtures.external()]),
                                      renderer: StyleRenderer(masterProvider: { _ in nil }))
        return (folder, library, stickers, sticker)
    }

    @Test func aClickPlacesOnTheDisplayUnderTheCursorAtTheFittedSize() throws {
        let h = Self.harness()
        defer { try? FileManager.default.removeItem(at: h.folder) }
        let display = Fixtures.external()
        let cursor = NSPoint(x: display.frame.midX, y: display.frame.midY)
        let session = PlacementSession(sticker: h.sticker.id, style: .puffy, natural: h.sticker.naturalPointSize,
                                       sourceLongSide: 800, renderer: StyleRenderer(masterProvider: { _ in nil }),
                                       stickers: h.stickers, screens: FakeScreens([display]),
                                       mouseLocation: { cursor })
        var outcome: PlacementSession.Outcome?
        session.onEnd = { outcome = $0 }
        session.start()
        #expect(session.pointSize == CGSize(width: 400, height: 200))
        session.place()
        h.stickers.closeAllPanels()
        guard case .placed(let id) = outcome else {
            Issue.record("expected a placement, got \(String(describing: outcome))")
            return
        }
        let placement = try #require(h.library.library.placement(id))
        #expect(placement.style == .puffy)
        #expect(!placement.flipped && !placement.onTop && placement.rotation == 0)
        // The panel's centre, which is the cursor give or take its rounding.
        let pose = try #require(placement.poses[display.size.key])
        #expect(abs(pose.x - 0.5) < 0.001 && abs(pose.y - 0.5) < 0.001)
        #expect(pose.scale == 1)
        #expect(placement.poses.count == 1)
        #expect(h.library.library.displays[display.uuid]?.placements.last?.id == id)
        session.place()   // a second click after the end does nothing
        #expect(h.library.library.displays[display.uuid]?.placements.count == 1)
    }

    @Test func cancellingPlacesNothing() {
        let h = Self.harness()
        defer { try? FileManager.default.removeItem(at: h.folder) }
        let display = Fixtures.external()
        let session = PlacementSession(sticker: h.sticker.id, style: .none, natural: h.sticker.naturalPointSize,
                                       sourceLongSide: 800, renderer: StyleRenderer(masterProvider: { _ in nil }),
                                       stickers: h.stickers, screens: FakeScreens([display]),
                                       mouseLocation: { NSPoint(x: display.frame.midX, y: display.frame.midY) })
        var outcome: PlacementSession.Outcome?
        session.onEnd = { outcome = $0 }
        session.start()
        session.cancel()
        session.place()
        #expect(outcome == .cancelled)
        #expect(h.library.library.displays.isEmpty)
        #expect(h.library.library.stickers.count == 1)   // the sticker stays in history
    }
}
