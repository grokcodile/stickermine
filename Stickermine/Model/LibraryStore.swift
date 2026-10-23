import Foundation
import os

/// `library.json` and `stickers/<uuid>.png` under one root directory
/// (spec section 12). The app passes `defaultRoot()`; tests pass a temporary
/// directory, so they never touch the real Application Support.
///
/// Rules it enforces:
/// - every write is atomic (`Data.write(to:options: .atomic)`);
/// - a library written by a newer build is shown but never written (read-only);
/// - a library that doesn't decode is renamed `library.corrupt-<date>.json` and
///   history is rebuilt from the PNGs;
/// - launch repair drops entries whose PNG is missing and adopts stray PNGs.
///
/// Ordering (callers): write the PNG before the index that names it; to delete,
/// remove the PNG, then save the index.
final class LibraryStore {
    enum LoadResult: Equatable {
        /// No library.json yet (history may still hold adopted PNGs).
        case fresh(Library)
        case loaded(Library)
        /// Written by a newer Stickermine: shown, never written.
        case readOnlyNewer(Library)
        /// library.json didn't decode; it was set aside and history rebuilt.
        case recoveredFromCorrupt(Library)

        var library: Library {
            switch self {
            case .fresh(let library), .loaded(let library),
                 .readOnlyNewer(let library), .recoveredFromCorrupt(let library):
                return library
            }
        }
    }

    enum StoreError: Error, Equatable {
        case readOnly
    }

    /// The three tutorial stickers' fixed IDs, in order: tutorial 1 (the
    /// shortcut card), tutorial 2 (the double-click card), tutorial 3 (Maple).
    static let tutorialIDs: [UUID] = [
        UUID(uuidString: "5A1C0A00-7E57-4A11-8000-000000000001")!,
        UUID(uuidString: "5A1C0A00-7E57-4A11-8000-000000000002")!,
        UUID(uuidString: "5A1C0A00-7E57-4A11-8000-000000000003")!,
    ]

    /// Pixels per point for an adopted PNG that has no DPI.
    static let defaultPixelsPerPoint = 2.0

    let root: URL
    private(set) var isReadOnly = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "library")

    init(root: URL) {
        self.root = root
    }

    var libraryURL: URL { root.appendingPathComponent("library.json") }
    var stickersDirectory: URL { root.appendingPathComponent("stickers", isDirectory: true) }

    /// `~/Library/Application Support/com.ethan.stickermine`, created if needed.
    static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = root(inApplicationSupport: support)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func root(inApplicationSupport support: URL) -> URL {
        support.appendingPathComponent("com.ethan.stickermine", isDirectory: true)
    }

    // MARK: Loading

    private struct VersionProbe: Decodable {
        let version: Int
    }

    /// Reads library.json, applying the version gate, corrupt-file recovery and
    /// launch repair. It writes nothing except the corrupt file's rename; the
    /// repaired library is saved with the next user change.
    func load() -> LoadResult {
        isReadOnly = false
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: stickersDirectory, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return .fresh(repair(.empty))
        }
        let decoder = LibraryCoding.decoder()
        guard let data = try? Data(contentsOf: libraryURL),
              let probe = try? decoder.decode(VersionProbe.self, from: data)
        else {
            return .recoveredFromCorrupt(setAsideCorruptFile())
        }
        if probe.version > Library.currentVersion {
            isReadOnly = true
            log.notice("library.json is version \(probe.version); this build reads \(Library.currentVersion). Read-only.")
            // Whatever this build can read of it; never renamed, never repaired.
            return .readOnlyNewer((try? decoder.decode(Library.self, from: data)) ?? .empty)
        }
        guard let library = try? decoder.decode(Library.self, from: data) else {
            return .recoveredFromCorrupt(setAsideCorruptFile())
        }
        return .loaded(repair(library))
    }

    /// Renames library.json to `library.corrupt-<date>.json` and rebuilds
    /// history from the PNGs (placements are lost). If the rename fails, the
    /// store turns read-only so the unreadable file is never overwritten.
    private func setAsideCorruptFile() -> Library {
        let stamp = Self.corruptStamp(for: Date())
        var target = root.appendingPathComponent("library.corrupt-\(stamp).json")
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = root.appendingPathComponent("library.corrupt-\(stamp)-\(counter).json")
            counter += 1
        }
        do {
            try FileManager.default.moveItem(at: libraryURL, to: target)
            log.error("library.json didn't decode; moved to \(target.lastPathComponent, privacy: .public)")
        } catch {
            isReadOnly = true
            log.error("library.json didn't decode and couldn't be moved aside: \(error.localizedDescription, privacy: .public)")
        }
        return repair(.empty)
    }

    /// "2026-10-15T21-02-33Z": ISO-8601 with dashes for colons, safe in Finder.
    static func corruptStamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    /// Launch repair (spec section 12): drops entries whose PNG is missing (and
    /// their placements), adopts stray PNGs (pixel size from the image, pixels
    /// per point from its DPI or 2.0, created from the file's creation date,
    /// lastStyle puffy, no placements), and flags the fixed tutorial IDs.
    func repair(_ library: Library) -> Library {
        var result = library
        let onDisk = pngFiles()
        result.stickers.removeAll { onDisk[$0.id] == nil }
        let known = Set(result.stickers.map(\.id))
        let adopted = onDisk
            .filter { !known.contains($0.key) }
            .compactMap { adoptedRecord(id: $0.key, url: $0.value) }
            .sorted { ($0.created, $0.id.uuidString) < ($1.created, $1.id.uuidString) }
        result.stickers.append(contentsOf: adopted)
        for index in result.stickers.indices where Self.tutorialIDs.contains(result.stickers[index].id) {
            result.stickers[index].tutorial = true
        }
        let live = Set(result.stickers.map(\.id))
        for key in Array(result.displays.keys) {
            result.displays[key]?.placements.removeAll { !live.contains($0.sticker) }
        }
        return result
    }

    /// `stickers/<UUID>.png` files on disk, by sticker ID.
    private func pngFiles() -> [UUID: URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: stickersDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        var result: [UUID: URL] = [:]
        for url in urls where url.pathExtension.lowercased() == "png" {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                result[id] = url
            }
        }
        return result
    }

    private func adoptedRecord(id: UUID, url: URL) -> StickerRecord? {
        guard let info = MasterImage.fileInfo(at: url) else {
            log.error("stray \(url.lastPathComponent, privacy: .public) isn't a readable image; not adopted")
            return nil
        }
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        return StickerRecord(
            id: id,
            created: created,
            pixelWidth: info.pixelWidth,
            pixelHeight: info.pixelHeight,
            pixelsPerPoint: info.pixelsPerPoint ?? Self.defaultPixelsPerPoint,
            lastStyle: .puffy,
            tutorial: Self.tutorialIDs.contains(id)
        )
    }

    // MARK: Writing

    /// Writes library.json atomically. Throws `StoreError.readOnly` for a newer library.
    func save(_ library: Library) throws {
        guard !isReadOnly else { throw StoreError.readOnly }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try LibraryCoding.encoder().encode(library)
        try data.write(to: libraryURL, options: .atomic)
    }

    func pngURL(for sticker: UUID) -> URL {
        stickersDirectory.appendingPathComponent("\(sticker.uuidString).png")
    }

    /// Writes a master PNG atomically (call off the main thread for real captures).
    func writePNG(_ data: Data, for sticker: UUID) throws {
        guard !isReadOnly else { throw StoreError.readOnly }
        try FileManager.default.createDirectory(at: stickersDirectory, withIntermediateDirectories: true)
        try data.write(to: pngURL(for: sticker), options: .atomic)
    }

    /// Removes a master PNG; a PNG that is already gone is not an error.
    func deletePNG(for sticker: UUID) throws {
        guard !isReadOnly else { throw StoreError.readOnly }
        let url = pngURL(for: sticker)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
