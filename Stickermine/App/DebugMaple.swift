import AppKit
import os

/// Temporary (M2): `open Stickermine.app --args -debugPlaceMaple` saves the
/// bundled Maple into the library as an ordinary sticker (PNG first, then the
/// index) and places her, Shadow style, centred on the mouse pointer and fitted
/// within half of that display, so restore, persistence and display changes can
/// be checked end to end before capture exists. M4 deletes this file and its
/// branch in AppDelegate once real captures can be placed.
enum DebugMaple {
    static let launchArgument = "-debugPlaceMaple"
    private static let log = Logger(subsystem: "com.ethan.stickermine", category: "debug")

    @MainActor
    static func place(library: LibraryController, stickers: StickerManager, screens: ScreenProvider) {
        guard !library.isReadOnly else {
            log.error("library is read-only; Maple not placed")
            return
        }
        guard let maple = BundledImages.cgImage(named: BundledImages.mapleName) else {
            log.error("Maple asset missing")
            return
        }
        let id = UUID()
        let pixelsPerPoint = 2.0  // Maple.png is stored @2x
        let store = library.store
        Task.detached {
            do {
                let data = try MasterImage.pngData(maple, pixelsPerPoint: pixelsPerPoint)
                try store.writePNG(data, for: id)
            } catch {
                log.error("writing Maple's PNG failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            await MainActor.run {
                commit(id: id, image: maple, pixelsPerPoint: pixelsPerPoint,
                       library: library, stickers: stickers, screens: screens)
            }
        }
    }

    @MainActor
    private static func commit(id: UUID, image: CGImage, pixelsPerPoint: Double, library: LibraryController,
                               stickers: StickerManager, screens: ScreenProvider) {
        let record = StickerRecord(id: id, created: Date(), pixelWidth: image.width, pixelHeight: image.height,
                                   pixelsPerPoint: pixelsPerPoint, lastStyle: .shadow)
        library.mutate { $0.stickers.append(record) }
        let pointer = NSEvent.mouseLocation
        guard let display = StickerManager.display(containing: pointer, in: screens.currentDisplays()) else { return }
        let natural = record.naturalPointSize
        let fit = min(1, display.frame.width / 2 / natural.width, display.frame.height / 2 / natural.height)
        let size = CGSize(width: natural.width * fit, height: natural.height * fit)
        let placement = stickers.place(sticker: id, style: .shadow, centerOnScreen: pointer, pointSize: size)
        log.notice("placed Maple \(id.uuidString, privacy: .public) as \(placement?.uuidString ?? "nothing", privacy: .public)")
    }
}
