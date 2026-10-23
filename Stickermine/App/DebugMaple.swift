import AppKit
import os

/// Temporary (M2, styles added in M3): `open Stickermine.app --args
/// -debugPlaceMaple [style|all]` saves the bundled Maple into the library as
/// an ordinary sticker (PNG first, then the index) and places her centred on
/// the mouse pointer: once in Shadow style without a style argument, once in
/// the named style (`puffy`, `outline`, `shadow`, `none`), or four times side
/// by side in UI order for `all`. Together the placements fit within half of
/// that display. So restore, persistence, display changes and the styles can
/// be checked end to end before capture exists. M4 deletes this file and its
/// branch in AppDelegate once real captures can be placed.
enum DebugMaple {
    static let launchArgument = "-debugPlaceMaple"
    /// Space between side-by-side Maples, in points.
    static let gap: CGFloat = 40
    private static let log = Logger(subsystem: "com.ethan.stickermine", category: "debug")

    /// The styles asked for by the argument after `-debugPlaceMaple`; Shadow
    /// when there is none or it isn't a style.
    static func styles(in arguments: [String]) -> [StickerStyle] {
        guard let index = arguments.firstIndex(of: launchArgument), index + 1 < arguments.count else {
            return [.shadow]
        }
        let word = arguments[index + 1].lowercased()
        if word == "all" { return StickerStyle.allCases }
        return StickerStyle(rawValue: word).map { [$0] } ?? [.shadow]
    }

    @MainActor
    static func place(library: LibraryController, stickers: StickerManager, screens: ScreenProvider,
                      styles: [StickerStyle] = [.shadow]) {
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
        let styles = styles.isEmpty ? [StickerStyle.shadow] : styles
        Task.detached {
            do {
                let data = try MasterImage.pngData(maple, pixelsPerPoint: pixelsPerPoint)
                try store.writePNG(data, for: id)
            } catch {
                log.error("writing Maple's PNG failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            await MainActor.run {
                commit(id: id, image: maple, pixelsPerPoint: pixelsPerPoint, styles: styles,
                       library: library, stickers: stickers, screens: screens)
            }
        }
    }

    /// The centres and the common point size of `count` side-by-side copies of
    /// a `natural`-sized sticker around `pointer`, fitted within half of `frame`.
    static func layout(count: Int, natural: CGSize, pointer: CGPoint, frame: CGRect) -> (size: CGSize, centers: [CGPoint]) {
        let n = CGFloat(max(count, 1))
        let fit = min(1, (frame.width / 2 - gap * (n - 1)) / n / natural.width, frame.height / 2 / natural.height)
        let size = CGSize(width: natural.width * fit, height: natural.height * fit)
        let step = size.width + gap
        let centers = (0..<max(count, 1)).map { index in
            CGPoint(x: pointer.x + (CGFloat(index) - (n - 1) / 2) * step, y: pointer.y)
        }
        return (size, centers)
    }

    @MainActor
    private static func commit(id: UUID, image: CGImage, pixelsPerPoint: Double, styles: [StickerStyle],
                               library: LibraryController, stickers: StickerManager, screens: ScreenProvider) {
        let record = StickerRecord(id: id, created: Date(), pixelWidth: image.width, pixelHeight: image.height,
                                   pixelsPerPoint: pixelsPerPoint, lastStyle: styles[0])
        library.mutate { $0.stickers.append(record) }
        let pointer = NSEvent.mouseLocation
        guard let display = StickerManager.display(containing: pointer, in: screens.currentDisplays()) else { return }
        let plan = layout(count: styles.count, natural: record.naturalPointSize, pointer: pointer, frame: display.frame)
        for (style, center) in zip(styles, plan.centers) {
            let placement = stickers.place(sticker: id, style: style, centerOnScreen: center, pointSize: plan.size)
            log.notice("placed Maple \(id.uuidString, privacy: .public) as \(placement?.uuidString ?? "nothing", privacy: .public) (\(style.rawValue, privacy: .public))")
        }
    }
}
