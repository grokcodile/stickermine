import AppKit
import Testing
@testable import Stickermine

@MainActor
struct HistoryGridTests {
    final class FakeSession: StickerSession {
        var currentSticker: UUID?
        var cancels = 0
        init(_ sticker: UUID?) { currentSticker = sticker }
        func cancel() { cancels += 1 }
    }

    private func record(_ id: UUID, at seconds: TimeInterval, tutorial: Bool = false) -> StickerRecord {
        StickerRecord(id: id, created: Date(timeIntervalSince1970: seconds), pixelWidth: 40, pixelHeight: 40,
                      pixelsPerPoint: 2, lastStyle: .puffy, tutorial: tutorial)
    }

    @Test func theGridShowsNonTutorialStickersNewestFirst() {
        let old = UUID(), new = UUID(), tutorial = LibraryStore.tutorialIDs[0]
        let a = UUID(uuidString: "00000000-0000-4000-8000-00000000000A")!
        let b = UUID(uuidString: "00000000-0000-4000-8000-00000000000B")!
        let library = Library(stickers: [record(old, at: 100), record(tutorial, at: 500, tutorial: true),
                                         record(new, at: 300), record(a, at: 200), record(b, at: 200)],
                              displays: [:])
        #expect(HistoryList.items(in: library).map(\.id) == [new, b, a, old])
    }

    @Test func theConfirmationStatesThePlacementCount() {
        #expect(HistoryList.deleteMessage(placementCount: 0) == "This sticker isn’t on your desktop. Deleting it can’t be undone.")
        #expect(HistoryList.deleteMessage(placementCount: 1)
                == "This also removes it from 1 place on your desktops. Deleting it can’t be undone.")
        #expect(HistoryList.deleteMessage(placementCount: 3)
                == "This also removes it from 3 places on your desktops. Deleting it can’t be undone.")
    }

    @Test func thumbnailsAreAtMost256PixelsAndCached() async throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("big.png")
        try Fixtures.pngData(width: 1000, height: 500, pixelsPerPoint: 2).write(to: url)
        let cache = ThumbnailCache()
        let id = UUID()
        #expect(cache.cached(id) == nil)
        let thumbnail = try #require(await cache.thumbnail(for: id, at: url))
        #expect(max(thumbnail.width, thumbnail.height) == 256)
        #expect(thumbnail.width == 256 && thumbnail.height == 128)
        #expect(cache.cached(id) === thumbnail)
        // A cached thumbnail never touches the file again.
        try FileManager.default.removeItem(at: url)
        #expect(await cache.thumbnail(for: id, at: url) === thumbnail)
        cache.remove(id)
        #expect(cache.cached(id) == nil)
        #expect(await cache.thumbnail(for: id, at: url) == nil)
    }

    @Test func deletingCancelsTheSessionWorkingOnThatStickerAndRemovesItEverywhere() throws {
        let sticker = UUID()
        let here = EditingFixtures.placement(sticker)
        let elsewhere = EditingFixtures.placement(sticker)
        let h = try EditingHarness(EditingFixtures.library(sticker, external: [here], main: [elsewhere]),
                                   displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let thumbnails = ThumbnailCache()
        let session = FakeSession(sticker)
        HistoryDeletion.delete(sticker, session: session, stickers: h.manager, thumbnails: thumbnails)
        #expect(session.cancels == 1)
        #expect(h.library.library.sticker(sticker) == nil)
        // Also the placement on the main display, which isn't connected here.
        #expect(h.library.library.placementCount(of: sticker) == 0)
        #expect(h.manager.panel(for: here.id) == nil)
        #expect(!FileManager.default.fileExists(atPath: h.store.pngURL(for: sticker).path))
    }

    @Test func deletingLeavesAnotherStickersSessionAlone() throws {
        let sticker = UUID()
        let h = try EditingHarness(EditingFixtures.library(sticker, external: []), displays: [Fixtures.external()])
        defer { h.finish() }
        let session = FakeSession(UUID())
        HistoryDeletion.delete(sticker, session: session, stickers: h.manager, thumbnails: nil)
        #expect(session.cancels == 0)
        #expect(h.library.library.sticker(sticker) == nil)
        let idle = FakeSession(nil)
        HistoryDeletion.delete(UUID(), session: idle, stickers: h.manager, thumbnails: nil)
        #expect(idle.cancels == 0)
    }
}
