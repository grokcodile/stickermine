import Foundation
import Testing
@testable import Stickermine

struct LibraryStoreTests {
    private let fileManager = FileManager.default

    private func sample(stickers: [UUID]) -> Library {
        let placements = stickers.map {
            Placement(sticker: $0, style: .outline, poses: ["1920x1080": Pose(x: 0.5, y: 0.5, scale: 1)])
        }
        return Library(stickers: stickers.map { Fixtures.sticker($0) },
                       displays: [Fixtures.externalUUID: Fixtures.displayRecord(for: Fixtures.external(), placements: placements)])
    }

    private func writePNGs(_ ids: [UUID], to store: LibraryStore, pixelsPerPoint: Double? = 2) throws {
        for id in ids {
            try store.writePNG(Fixtures.pngData(width: 400, height: 200, pixelsPerPoint: pixelsPerPoint), for: id)
        }
    }

    private func files(in directory: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test func aFreshFolderLoadsAnEmptyLibrary() {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        #expect(store.load() == .fresh(.empty))
        #expect(!store.isReadOnly)
        #expect(fileManager.fileExists(atPath: store.stickersDirectory.path))
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path))
    }

    @Test func aSavedLibraryLoadsBackUnchanged() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let ids = [UUID(), UUID()]
        try writePNGs(ids, to: store)
        let library = sample(stickers: ids)
        try store.save(library)
        #expect(LibraryStore(root: root).load() == .loaded(library))
        // Atomic writes leave no temporary files behind.
        #expect(files(in: root) == ["library.json", "stickers"])
    }

    @Test func pngsLiveInStickersNamedByUppercaseUUID() {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let id = UUID()
        let url = LibraryStore(root: root).pngURL(for: id)
        #expect(url.lastPathComponent == "\(id.uuidString.uppercased()).png")
        #expect(url.deletingLastPathComponent().lastPathComponent == "stickers")
        #expect(LibraryStore.root(inApplicationSupport: URL(fileURLWithPath: "/tmp/Support")).path
                == "/tmp/Support/com.ethan.stickermine")
    }

    @Test func aNewerLibraryIsShownButNeverWritten() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store)
        var newer = sample(stickers: [id])
        newer.version = 2
        try store.save(newer)
        let before = try Data(contentsOf: store.libraryURL)

        let reopened = LibraryStore(root: root)
        let result = reopened.load()
        #expect(result == .readOnlyNewer(newer))
        #expect(reopened.isReadOnly)
        #expect(throws: LibraryStore.StoreError.readOnly) { try reopened.save(.empty) }
        #expect(throws: LibraryStore.StoreError.readOnly) { try reopened.writePNG(Data([1]), for: UUID()) }
        #expect(throws: LibraryStore.StoreError.readOnly) { try reopened.deletePNG(for: id) }
        #expect(try Data(contentsOf: reopened.libraryURL) == before)
        #expect(fileManager.fileExists(atPath: reopened.pngURL(for: id).path))
    }

    @Test func aNewerLibraryThisBuildCantReadIsStillNeverRenamed() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let json = Data(#"{"version": 7, "stickers": "a new shape"}"#.utf8)
        try json.write(to: store.libraryURL)
        #expect(store.load() == .readOnlyNewer(.empty))
        #expect(try Data(contentsOf: store.libraryURL) == json)
        #expect(files(in: root) == ["library.json", "stickers"])
    }

    @Test func aCorruptFileIsSetAsideAndHistoryRebuiltFromThePNGs() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let ids = [UUID(), UUID()]
        try writePNGs(ids, to: store)
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: store.libraryURL)

        let result = store.load()
        guard case .recoveredFromCorrupt(let library) = result else {
            Issue.record("expected recoveredFromCorrupt, got \(result)")
            return
        }
        #expect(Set(library.stickers.map(\.id)) == Set(ids))
        #expect(library.displays.isEmpty)
        #expect(!store.isReadOnly)
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path))
        let setAside = files(in: root).filter { $0.hasPrefix("library.corrupt-") && $0.hasSuffix(".json") }
        #expect(setAside.count == 1)
        #expect(try Data(contentsOf: root.appendingPathComponent(setAside[0])) == garbage)
    }

    @Test func aLibraryWithoutAVersionCountsAsCorrupt() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try Data(#"{"stickers": []}"#.utf8).write(to: store.libraryURL)
        #expect(store.load() == .recoveredFromCorrupt(.empty))
    }

    @Test func corruptStampHasNoColons() {
        #expect(LibraryStore.corruptStamp(for: Date(timeIntervalSince1970: 1_760_000_000)) == "2025-10-09T08-53-20Z")
    }

    @Test func anEntryWhosePNGIsMissingIsDroppedWithItsPlacements() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let kept = UUID()
        let lost = UUID()
        try writePNGs([kept], to: store)
        try store.save(sample(stickers: [kept, lost]))
        let library = LibraryStore(root: root).load().library
        #expect(library.stickers.map(\.id) == [kept])
        #expect(library.displays[Fixtures.externalUUID]?.placements.map(\.sticker) == [kept])
    }

    @Test func aStrayPNGIsAdoptedWithItsDPI() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let retina = UUID()
        let standard = UUID()
        try writePNGs([retina], to: store, pixelsPerPoint: 2)
        try writePNGs([standard], to: store, pixelsPerPoint: 1)
        try store.save(.empty)
        let library = LibraryStore(root: root).load().library
        let adoptedRetina = try #require(library.sticker(retina))
        let adoptedStandard = try #require(library.sticker(standard))
        #expect(adoptedRetina.pixelWidth == 400 && adoptedRetina.pixelHeight == 200)
        #expect(adoptedRetina.pixelsPerPoint == 2)
        #expect(adoptedStandard.pixelsPerPoint == 1)
        #expect(adoptedRetina.lastStyle == .puffy)
        #expect(!adoptedRetina.tutorial)
        #expect(library.displays.isEmpty)
        let fileDate = try #require(try store.pngURL(for: retina).resourceValues(forKeys: [.creationDateKey]).creationDate)
        #expect(adoptedRetina.created == fileDate)
    }

    @Test func aStrayPNGWithoutDPIGetsTwoPixelsPerPoint() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store, pixelsPerPoint: nil)
        #expect(store.load().library.sticker(id)?.pixelsPerPoint == 2)
    }

    @Test func aStrayFileThatIsntAnImageIsLeftAlone() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try store.writePNG(Data("not a png".utf8), for: id)
        try Data("notes".utf8).write(to: store.stickersDirectory.appendingPathComponent("readme.txt"))
        #expect(store.load() == .fresh(.empty))
        #expect(fileManager.fileExists(atPath: store.pngURL(for: id).path))
    }

    @Test func tutorialUUIDsAreFlaggedWhenAdoptedOrLoaded() throws {
        #expect(LibraryStore.tutorialIDs.count == 3)
        #expect(Set(LibraryStore.tutorialIDs).count == 3)
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let maple = LibraryStore.tutorialIDs[2]
        let card = LibraryStore.tutorialIDs[0]
        try writePNGs([maple, card], to: store)
        // The card's index entry lost its flag; Maple's entry is missing entirely.
        try store.save(Library(stickers: [Fixtures.sticker(card, tutorial: false)], displays: [:]))
        let library = LibraryStore(root: root).load().library
        #expect(library.sticker(card)?.tutorial == true)
        #expect(library.sticker(maple)?.tutorial == true)
    }

    @Test func deletingAPNGIgnoresOneThatIsAlreadyGone() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store)
        try store.deletePNG(for: id)
        #expect(!fileManager.fileExists(atPath: store.pngURL(for: id).path))
        try store.deletePNG(for: id)
    }

    @Test func lenientDecodingKeepsAnOlderOrOddFileUsable() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store)
        let json = """
            {"version": 1, "stickers": [{"id": "\(id.uuidString)", "pixelWidth": 400, "pixelHeight": 200,
              "lastStyle": "holographic"}],
             "displays": {"\(Fixtures.externalUUID)": {"name": "LG", "placements": [
               {"id": "\(UUID().uuidString)", "sticker": "\(id.uuidString)", "style": "glitter",
                "poses": {"1920x1080": {"x": 0.5, "y": 0.5, "scale": 1}}}]}}}
            """
        try Data(json.utf8).write(to: store.libraryURL)
        guard case .loaded(let library) = store.load() else {
            Issue.record("expected the file to load")
            return
        }
        #expect(library.sticker(id)?.lastStyle == .puffy)
        let placement = try #require(library.displays[Fixtures.externalUUID]?.placements.first)
        #expect(placement.style == .puffy)
        #expect(!placement.flipped && !placement.onTop && placement.rotation == 0)
    }
}
