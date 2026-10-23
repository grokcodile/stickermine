import Foundation
import Testing
@testable import Stickermine

@MainActor
struct LibraryControllerTests {
    private let fileManager = FileManager.default

    private func saved(_ store: LibraryStore) throws -> Library {
        try LibraryCoding.decoder().decode(Library.self, from: Data(contentsOf: store.libraryURL))
    }

    @Test func loadsTheStoreWhenCreated() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try store.writePNG(Fixtures.pngData(width: 40, height: 20, pixelsPerPoint: 2), for: id)
        let library = Library(stickers: [Fixtures.sticker(id)], displays: [:])
        try store.save(library)
        let controller = LibraryController(store: store)
        #expect(controller.loadResult == .loaded(library))
        #expect(controller.library == library)
        #expect(!controller.isReadOnly)
        #expect(controller.store === store)
    }

    @Test func changesAreSavedOnceAfterTheDelay() async throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let controller = LibraryController(store: store, saveDelay: 0.3)
        let first = Fixtures.sticker()
        let second = Fixtures.sticker()
        controller.mutate { $0.stickers.append(first) }
        try await Task.sleep(for: .milliseconds(100))
        controller.mutate { $0.stickers.append(second) }   // restarts the 0.3 s wait
        #expect(controller.hasPendingSave)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path), "saved before the last change was 0.3 s old")
        try await Task.sleep(for: .milliseconds(450))
        #expect(!controller.hasPendingSave)
        #expect(!controller.hasUnsavedChanges)
        #expect(try saved(store).stickers == [first, second])
    }

    @Test func flushSavesNowAndCancelsThePendingSave() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let controller = LibraryController(store: store, saveDelay: 60)
        let sticker = Fixtures.sticker()
        controller.mutate { $0.stickers.append(sticker) }
        #expect(controller.hasPendingSave)
        controller.flush()
        #expect(!controller.hasPendingSave)
        #expect(try saved(store).stickers == [sticker])
        // Nothing unsaved: a second flush writes nothing.
        try fileManager.removeItem(at: store.libraryURL)
        controller.flush()
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path))
    }

    @Test func aChangeThatChangesNothingSchedulesNothing() {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let controller = LibraryController(store: LibraryStore(root: root), saveDelay: 60)
        var calls = 0
        controller.onChange = { calls += 1 }
        controller.mutate { _ in }
        #expect(!controller.hasPendingSave)
        #expect(calls == 0)
        controller.mutate { $0.stickers.append(Fixtures.sticker()) }
        #expect(calls == 1)
    }

    @Test func aReadOnlyLibraryIgnoresChanges() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.save(Library(version: 2, stickers: [], displays: [:]))
        let controller = LibraryController(store: store, saveDelay: 0)
        #expect(controller.isReadOnly)
        controller.mutate { $0.stickers.append(Fixtures.sticker()) }
        controller.refreshMetadata { $0.stickers.append(Fixtures.sticker()) }
        #expect(controller.library.stickers.isEmpty)
        #expect(!controller.hasPendingSave)
        controller.flush()
        #expect(try saved(store).version == 2)
    }

    @Test func metadataRefreshesWaitForTheNextSave() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let display = Fixtures.external()
        try store.save(Library(stickers: [], displays: [display.uuid: Fixtures.displayRecord(for: display, placements: [])]))
        let before = try Data(contentsOf: store.libraryURL)
        let controller = LibraryController(store: store, saveDelay: 60)
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        controller.refreshMetadata { $0.displays[display.uuid]?.lastSeen = seen }
        #expect(!controller.hasPendingSave)
        #expect(controller.hasUnsavedChanges)
        #expect(try Data(contentsOf: store.libraryURL) == before)
        controller.flush()
        #expect(try saved(store).displays[display.uuid]?.lastSeen == seen)
    }
}
