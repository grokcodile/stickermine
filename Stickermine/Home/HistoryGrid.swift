import AppKit
import ImageIO
import SwiftUI

/// Which stickers the history grid shows, and what deleting one says (spec
/// sections 12 and 13). Pure.
enum HistoryList {
    /// Every non-tutorial sticker, newest first (ties by ID, so the order is stable).
    static func items(in library: Library) -> [StickerRecord] {
        library.stickers
            .filter { !$0.tutorial }
            .sorted { ($0.created, $0.id.uuidString) > ($1.created, $1.id.uuidString) }
    }

    static let deleteTitle = "Delete from History?"

    /// The confirmation states how many placements go with it (on every
    /// display, connected or not).
    static func deleteMessage(placementCount: Int) -> String {
        switch placementCount {
        case 0: return "This sticker isn’t on your desktop. Deleting it can’t be undone."
        case 1: return "This also removes it from 1 place on your desktops. Deleting it can’t be undone."
        default: return "This also removes it from \(placementCount) places on your desktops. Deleting it can’t be undone."
        }
    }
}

/// The session as Delete from History sees it (`SessionCoordinator`; tests use a fake).
@MainActor
protocol StickerSession: AnyObject {
    /// The sticker the running session works on, once known.
    var currentSticker: UUID? { get }
    func cancel()
}

extension SessionCoordinator: StickerSession {}

/// Delete from History (spec section 12).
@MainActor
enum HistoryDeletion {
    /// Cancels a session working on the sticker (a re-place from history, or
    /// a fresh one already saved), then deletes it everywhere: editing of any
    /// of its placements ends (a gesture is discarded), every placement on
    /// every display goes, then the PNG, then the entry (`StickerManager`).
    /// A render that finishes later finds its placement gone and is dropped.
    static func delete(_ sticker: UUID, session: StickerSession?, stickers: StickerManager,
                       thumbnails: ThumbnailCache?) {
        if let session, session.currentSticker == sticker { session.cancel() }
        stickers.deleteSticker(sticker)
        thumbnails?.remove(sticker)
    }
}

/// History thumbnails: `CGImageSourceCreateThumbnailAtIndex` at 256 px at
/// most, kept in memory (spec section 12). Loaded off the main thread.
@MainActor
final class ThumbnailCache {
    nonisolated static let maxPixelSize = 256

    private let cache = NSCache<NSUUID, CGImage>()

    init() {}

    func cached(_ sticker: UUID) -> CGImage? {
        cache.object(forKey: sticker as NSUUID)
    }

    func thumbnail(for sticker: UUID, at url: URL) async -> CGImage? {
        if let hit = cached(sticker) { return hit }
        let image = await Task.detached(priority: .utility) { Self.makeThumbnail(at: url) }.value
        if let image { cache.setObject(image, forKey: sticker as NSUUID) }
        return image
    }

    func remove(_ sticker: UUID) {
        cache.removeObject(forKey: sticker as NSUUID)
    }

    /// The PNG scaled so its long side is at most `maxPixelSize`.
    nonisolated static func makeThumbnail(at url: URL, maxPixelSize: Int = ThumbnailCache.maxPixelSize) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
