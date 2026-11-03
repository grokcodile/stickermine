import AppKit
import Testing
@testable import Stickermine

/// The first run against a temporary library and a fake main display at
/// x = 50 000. The display is taken away while the tutorials are saved, so no
/// panel is ordered in across an `await`; tests that need panels put it back
/// and close them in the same synchronous stretch.
@MainActor
struct TutorialStickersTests {
    /// Home's first size (`HomeWindowController.initialSize`).
    static let homeSize = CGSize(width: 640, height: 640)

    private func suite() -> (UserDefaults, String) {
        let name = "StickermineTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    /// Premultiplied sRGB RGBA at (x, y) points from the top-left of a 2 px/pt master.
    private func pixel(_ image: CGImage, _ x: CGFloat, _ y: CGFloat) -> [UInt8] {
        TestImages.rgba(of: image, x: Int(x * 2), y: Int(y * 2))
    }

    private func near(_ rgba: [UInt8], _ expected: [UInt8], _ tolerance: Int = 3) -> Bool {
        zip(rgba, expected).allSatisfy { abs(Int($0) - Int($1)) <= tolerance }
    }

    private func firstRun(_ tutorials: TutorialStickers, screens: FakeScreens,
                          shortcut: Shortcut? = .defaultCapture) async -> Bool {
        await withCheckedContinuation { continuation in
            tutorials.placeFirstRun(shortcut: shortcut, homeSize: Self.homeSize) {
                continuation.resume(returning: $0)
            }
            screens.all = []
        }
    }

    @Test func tutorialOneSaysTheShortcutOrTheMenuBarIcon() {
        #expect(TutorialArt.shortcutText(for: .defaultCapture) == "Press ⌃⌥⌘S\nto make a sticker")
        #expect(TutorialArt.shortcutText(for: Shortcut(keyCode: 96, modifiers: 0)) == "Press F5\nto make a sticker")
        #expect(TutorialArt.shortcutText(for: nil) == "Click the menu bar icon\nto make a sticker")
        #expect(TutorialArt.doubleClickText == "Double-click me to move,\nresize or remove.")
        #expect(TutorialArt.bubbleText == "Make your desktop make you smile!")
    }

    @Test func aCardIsTheFillInsideAWhiteBorderWithTransparentCorners() throws {
        let card = try #require(TutorialArt.card(text: "Hi", fill: TutorialArt.blue, textColor: .white))
        let height = CGFloat(card.height) / 2
        #expect(card.width % 2 == 0 && card.height % 2 == 0)
        #expect(pixel(card, 0, 0)[3] == 0)
        // 1 pt edge, then the 10 pt white border, then the blue fill.
        #expect(near(pixel(card, TutorialArt.edge + 4, height / 2), [255, 255, 255, 255]))
        #expect(near(pixel(card, TutorialArt.edge + TutorialArt.cardBorder + 6, height / 2), [0x3D, 0x4B, 0xE0, 255]))
        let longer = try #require(TutorialArt.card(text: "Hi there, a longer line", fill: TutorialArt.blue, textColor: .white))
        #expect(longer.width > card.width)
        #expect(longer.height == card.height)
        let twoLines = try #require(TutorialArt.card(text: "Hi\nthere", fill: TutorialArt.blue, textColor: .white))
        #expect(twoLines.height > card.height)
    }

    @Test func mapleGetsThePinkBubbleBesideHerMouth() throws {
        let images = try #require(TutorialArt.masters(shortcut: .defaultCapture))
        #expect(images.count == 3)
        let maple = images[2]
        // 8 pt border + 322 pt bubble − 6 pt overlap + Maple's 310 pt, by her 455 pt.
        #expect(maple.width == 1268)
        #expect(maple.height == 910)
        let body = CGPoint(x: TutorialArt.bubbleBorder + 30, y: TutorialArt.bubbleTop + 5)
        #expect(near(pixel(maple, body.x, body.y), [0xFF, 0x4F, 0x81, 255]))
        #expect(near(pixel(maple, body.x, TutorialArt.bubbleTop - 4), [255, 255, 255, 255]))
        #expect(pixel(maple, 2, 2)[3] == 0)
        #expect(pixel(maple, 634 - 155, 455 / 2)[3] == 255)
    }

    @Test func theFirstRunSavesPlacesAndRemembersTheTutorials() async throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let main = Fixtures.main()
        let h = try EditingHarness(.empty, displays: [main])
        defer { h.finish() }
        let tutorials = TutorialStickers(library: h.library, stickers: h.manager, screens: h.screens, defaults: defaults)
        #expect(await firstRun(tutorials, screens: h.screens))
        #expect(defaults.didFirstRun)
        let ids = LibraryStore.tutorialIDs
        let model = h.library.library
        #expect(model.stickers.map(\.id) == ids)
        #expect(model.stickers.allSatisfy { $0.tutorial && $0.lastStyle == .shadow && $0.pixelsPerPoint == 2 })
        let placements = try #require(model.displays[main.uuid]?.placements)
        #expect(placements.map(\.sticker) == ids)
        #expect(placements.allSatisfy { $0.style == .shadow && !$0.flipped && !$0.onTop })
        #expect(placements.map(\.rotation) == TutorialLayout.rotations)
        #expect(placements.allSatisfy { $0.poses.keys.sorted() == [main.size.key] })
        for id in ids {
            let info = try #require(MasterImage.fileInfo(at: h.store.pngURL(for: id)))
            #expect(info.pixelsPerPoint == 2)
            #expect(model.sticker(id)?.pixelWidth == info.pixelWidth)
        }
        // The index is on disk, every entry still marked as a tutorial.
        #expect(!h.library.hasUnsavedChanges)
        let reloaded = LibraryStore(root: h.root).load().library
        #expect(reloaded.stickers.map(\.id) == ids)
        #expect(reloaded.stickers.allSatisfy { $0.tutorial })
        #expect(reloaded.displays[main.uuid]?.placements.map(\.id) == placements.map(\.id))
        // With the display back, the stickers sit where the layout put them.
        h.screens.all = [main]
        h.manager.reconcileNow()
        let items = TutorialLayout.layout(naturalSizes: model.stickers.map(\.naturalPointSize), frame: main.frame,
                                          visibleFrame: main.visibleFrame, homeSize: Self.homeSize)
        for (placement, item) in zip(placements, items) {
            let panel = try h.panel(placement.id)
            #expect(abs(panel.frame.midX - item.rect.midX) <= 1 && abs(panel.frame.midY - item.rect.midY) <= 1)
        }
    }

    @Test func removingATutorialDeletesItOutright() async throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let main = Fixtures.main()
        let h = try EditingHarness(.empty, displays: [main])
        defer { h.finish() }
        let tutorials = TutorialStickers(library: h.library, stickers: h.manager, screens: h.screens, defaults: defaults)
        #expect(await firstRun(tutorials, screens: h.screens))
        let second = LibraryStore.tutorialIDs[1]
        let placement = try #require(h.library.library.displays[main.uuid]?.placements.first { $0.sticker == second })
        h.manager.remove(placement: placement.id)
        #expect(h.library.library.sticker(second) == nil)
        #expect(!FileManager.default.fileExists(atPath: h.store.pngURL(for: second).path))
    }

    @Test func aShortcutChangeRedrawsTutorialOneInPlace() async throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let main = Fixtures.main()
        let h = try EditingHarness(.empty, displays: [main])
        defer { h.finish() }
        let tutorials = TutorialStickers(library: h.library, stickers: h.manager, screens: h.screens, defaults: defaults)
        #expect(await firstRun(tutorials, screens: h.screens))
        let first = LibraryStore.tutorialIDs[0]
        let before = try #require(h.library.library.sticker(first))
        let placementsBefore = h.library.library.displays[main.uuid]?.placements
        await withCheckedContinuation { continuation in
            tutorials.shortcutChanged(to: nil) { continuation.resume() }
        }
        let after = try #require(h.library.library.sticker(first))
        let expected = try #require(TutorialArt.shortcutCard(for: nil))
        #expect(after.pixelWidth == expected.width)
        #expect(after.pixelWidth != before.pixelWidth)
        #expect(MasterImage.fileInfo(at: h.store.pngURL(for: first))?.pixelWidth == expected.width)
        // Only the master changed: the placements keep their poses.
        #expect(h.library.library.displays[main.uuid]?.placements == placementsBefore)
    }

    @Test func noTutorialOneMeansNothingToRedraw() async throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let h = try EditingHarness(.empty, displays: [Fixtures.main()])
        defer { h.finish() }
        let tutorials = TutorialStickers(library: h.library, stickers: h.manager, screens: h.screens, defaults: defaults)
        await withCheckedContinuation { continuation in
            tutorials.shortcutChanged(to: nil) { continuation.resume() }
        }
        #expect(!FileManager.default.fileExists(atPath: h.store.pngURL(for: LibraryStore.tutorialIDs[0]).path))
        #expect(h.library.library.stickers.isEmpty)
    }

    @Test func aNewerLibraryGetsNoTutorials() async throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"{"version": 99, "stickers": [], "displays": {}}"#.utf8).write(to: folder.appendingPathComponent("library.json"))
        let library = LibraryController(store: LibraryStore(root: folder), saveDelay: 60)
        let screens = FakeScreens([Fixtures.main()])
        let manager = StickerManager(library: library, screens: screens, renderer: StyleRenderer(masterProvider: { _ in nil }))
        let tutorials = TutorialStickers(library: library, stickers: manager, screens: screens, defaults: defaults)
        #expect(!(await firstRun(tutorials, screens: screens)))
        #expect(!defaults.didFirstRun)
        #expect(!FileManager.default.fileExists(atPath: library.store.pngURL(for: LibraryStore.tutorialIDs[0]).path))
    }

    @Test func aChangedMasterRendersAgainEvenWithTheSameRequest() throws {
        let sticker = UUID()
        let placement = EditingFixtures.placement(sticker)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [placement]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let issued = h.manager.renderRequestsIssued
        h.manager.reconcileNow()
        #expect(h.manager.renderRequestsIssued == issued)
        h.manager.masterChanged(for: sticker)
        #expect(h.manager.renderRequestsIssued == issued + 1)
        #expect(h.manager.renderRequest(for: placement.id) == EditingFixtures.request(sticker))
        h.manager.masterChanged(for: UUID())
        #expect(h.manager.renderRequestsIssued == issued + 1)
    }
}
