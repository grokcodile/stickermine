import AppKit
import os

/// The tutorial stickers' artwork (spec section 13), drawn in code at 2 px
/// per point: two text cards in SF Pro Rounded on sticker-shaped cards in the
/// brand colours with their own 10 pt white border (the website's
/// description card), and Maple with the website's pink speech bubble beside
/// her mouth (#FF4F81, 8 pt white border, white SF Pro Rounded text). Their
/// borders are in the image, so they use the Shadow style.
@MainActor
enum TutorialArt {
    static let pixelsPerPoint: CGFloat = 2

    static let blue = NSColor(srgbRed: 0x3D / 255.0, green: 0x4B / 255.0, blue: 0xE0 / 255.0, alpha: 1)
    static let mint = NSColor(srgbRed: 0x8F / 255.0, green: 0xE3 / 255.0, blue: 0xBE / 255.0, alpha: 1)
    static let ink = NSColor(srgbRed: 0x1F / 255.0, green: 0x23 / 255.0, blue: 0x40 / 255.0, alpha: 1)
    static let pink = NSColor(srgbRed: 0xFF / 255.0, green: 0x4F / 255.0, blue: 0x81 / 255.0, alpha: 1)

    // Card metrics in points (the site's card: 10 px border, 36 px radius, 18 × 34 px padding).
    static let cardFontSize: CGFloat = 24
    static let cardPadding = CGSize(width: 34, height: 18)
    static let cardRadius: CGFloat = 36
    static let cardBorder: CGFloat = 10
    static let lineGap: CGFloat = 2
    /// Transparent edge around every master, like a cutout's crop padding.
    static let edge: CGFloat = 1

    // Maple and her bubble, in points from the top-left, as on the website:
    // a 322 × 44 bubble whose right edge sits 6 pt into Maple's box, its top
    // 100 pt below hers, its tail reaching down to y = 62.
    static let bubbleSize = CGSize(width: 322, height: 44)
    static let bubbleBorder: CGFloat = 8
    static let bubbleTop: CGFloat = 100
    static let bubbleOverlap: CGFloat = 6
    static let bubbleFontSize: CGFloat = 18

    static let doubleClickText = "Double-click me to move,\nresize or remove."
    static let bubbleText = "Make your desktop make you smile!"

    /// Tutorial 1's words: the current shortcut, or the menu bar icon when none is set.
    static func shortcutText(for shortcut: Shortcut?) -> String {
        guard let shortcut else { return "Click the menu bar icon\nto make a sticker" }
        return "Press \(shortcut.label)\nto make a sticker"
    }

    /// The three masters in `LibraryStore.tutorialIDs` order; nil when one
    /// can't be drawn (Maple's asset missing).
    static func masters(shortcut: Shortcut?) -> [CGImage]? {
        guard let first = shortcutCard(for: shortcut),
              let second = card(text: doubleClickText, fill: mint, textColor: ink),
              let maple = BundledImages.cgImage(named: BundledImages.mapleName),
              let third = mapleWithBubble(maple)
        else { return nil }
        return [first, second, third]
    }

    static func shortcutCard(for shortcut: Shortcut?) -> CGImage? {
        card(text: shortcutText(for: shortcut), fill: blue, textColor: .white)
    }

    static func roundedFont(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(.rounded),
              let rounded = NSFont(descriptor: descriptor, size: size)
        else { return base }
        return rounded
    }

    /// A text card: each line centred, on `fill`, inside a white border.
    static func card(text: String, fill: NSColor, textColor: NSColor) -> CGImage? {
        let font = roundedFont(size: cardFontSize, weight: .semibold)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: textColor]
        let lines = text.components(separatedBy: "\n").map { NSAttributedString(string: $0, attributes: attributes) }
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        let textWidth = ceil(lines.map { $0.size().width }.max() ?? 0)
        let textHeight = lineHeight * CGFloat(lines.count) + lineGap * CGFloat(max(lines.count - 1, 0))
        let outer = CGRect(x: edge, y: edge, width: textWidth + 2 * (cardPadding.width + cardBorder),
                           height: textHeight + 2 * (cardPadding.height + cardBorder))
        return draw(size: CGSize(width: outer.width + 2 * edge, height: outer.height + 2 * edge)) { context in
            fillRoundedRect(outer, radius: min(cardRadius + cardBorder, outer.height / 2), color: .white, in: context)
            let inner = outer.insetBy(dx: cardBorder, dy: cardBorder)
            fillRoundedRect(inner, radius: min(cardRadius, inner.height / 2), color: fill, in: context)
            var top = inner.maxY - cardPadding.height
            for line in lines {
                let size = line.size()
                line.draw(at: CGPoint(x: inner.midX - size.width / 2, y: top - lineHeight + (lineHeight - size.height) / 2))
                top -= lineHeight + lineGap
            }
        }
    }

    /// Maple (her asset is 2 px per point) with the pink bubble on her left.
    static func mapleWithBubble(_ maple: CGImage) -> CGImage? {
        let mapleSize = CGSize(width: CGFloat(maple.width) / pixelsPerPoint, height: CGFloat(maple.height) / pixelsPerPoint)
        let bubbleLeft = bubbleBorder
        let mapleLeft = bubbleLeft + bubbleSize.width - bubbleOverlap
        let height = max(mapleSize.height, bubbleTop + 62 + bubbleBorder)
        let size = CGSize(width: mapleLeft + mapleSize.width, height: height)
        return draw(size: size) { context in
            context.interpolationQuality = .high
            context.draw(maple, in: CGRect(x: mapleLeft, y: height - mapleSize.height,
                                           width: mapleSize.width, height: mapleSize.height))
            // The website's SVG path, in its own top-down coordinates.
            var flip = CGAffineTransform(translationX: bubbleLeft, y: height - bubbleTop).scaledBy(x: 1, y: -1)
            guard let path = bubblePath().copy(using: &flip) else { return }
            context.addPath(path)
            context.setLineJoin(.round)
            context.setLineWidth(bubbleBorder * 2)
            context.setStrokeColor(NSColor.white.cgColor)
            context.setFillColor(NSColor.white.cgColor)
            context.drawPath(using: .fillStroke)
            context.addPath(path)
            context.setFillColor(pink.cgColor)
            context.fillPath()
            let font = roundedFont(size: bubbleFontSize, weight: .medium)
            let text = NSAttributedString(string: bubbleText, attributes: [.font: font, .foregroundColor: NSColor.white])
            let textSize = text.size()
            let body = CGRect(x: bubbleLeft, y: height - bubbleTop - bubbleSize.height,
                              width: bubbleSize.width, height: bubbleSize.height)
            text.draw(at: CGPoint(x: body.midX - textSize.width / 2, y: body.midY - textSize.height / 2))
        }
    }

    /// `M 18 0 H 304 C 314 0 322 8 322 18 V 26 C 322 32 317 36 310 39 C 313 46 316 52 322 58
    /// C 323 60 321 62 319 61 C 307 57 299 51 294 44 H 18 C 8 44 0 36 0 26 V 18 C 0 8 8 0 18 0 Z`
    static func bubblePath() -> CGPath {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 18, y: 0))
        path.addLine(to: CGPoint(x: 304, y: 0))
        path.addCurve(to: CGPoint(x: 322, y: 18), control1: CGPoint(x: 314, y: 0), control2: CGPoint(x: 322, y: 8))
        path.addLine(to: CGPoint(x: 322, y: 26))
        path.addCurve(to: CGPoint(x: 310, y: 39), control1: CGPoint(x: 322, y: 32), control2: CGPoint(x: 317, y: 36))
        path.addCurve(to: CGPoint(x: 322, y: 58), control1: CGPoint(x: 313, y: 46), control2: CGPoint(x: 316, y: 52))
        path.addCurve(to: CGPoint(x: 319, y: 61), control1: CGPoint(x: 323, y: 60), control2: CGPoint(x: 321, y: 62))
        path.addCurve(to: CGPoint(x: 294, y: 44), control1: CGPoint(x: 307, y: 57), control2: CGPoint(x: 299, y: 51))
        path.addLine(to: CGPoint(x: 18, y: 44))
        path.addCurve(to: CGPoint(x: 0, y: 26), control1: CGPoint(x: 8, y: 44), control2: CGPoint(x: 0, y: 36))
        path.addLine(to: CGPoint(x: 0, y: 18))
        path.addCurve(to: CGPoint(x: 18, y: 0), control1: CGPoint(x: 0, y: 8), control2: CGPoint(x: 8, y: 0))
        path.closeSubpath()
        return path
    }

    private static func fillRoundedRect(_ rect: CGRect, radius: CGFloat, color: NSColor, in context: CGContext) {
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.setFillColor(color.cgColor)
        context.fillPath()
    }

    /// An sRGB, premultiplied bitmap of `size` points at `pixelsPerPoint`,
    /// y up, with AppKit text drawing pointed at it.
    private static func draw(size: CGSize, _ body: (CGContext) -> Void) -> CGImage? {
        let width = Int((size.width * pixelsPerPoint).rounded(.up))
        let height = Int((size.height * pixelsPerPoint).rounded(.up))
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: pixelsPerPoint, y: pixelsPerPoint)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        body(context)
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}

/// The first-run tutorial stickers (spec section 13). On a user launch with
/// `didFirstRun` false and no stickers in the library, the three masters are
/// drawn once and saved as ordinary `stickers/<uuid>.png` entries under the
/// fixed `LibraryStore.tutorialIDs` with `tutorial: true` (PNGs first, then
/// the index), placed on the main display in Shadow, and `didFirstRun` is
/// set once the index is saved. They are never made again: removing one
/// deletes it outright (`StickerManager.remove`), and they never show in the
/// history or count towards the support ask. While tutorial 1 exists, a
/// shortcut change redraws its master in place and re-renders its placements.
@MainActor
final class TutorialStickers {
    static let style: StickerStyle = .shadow

    private let library: LibraryController
    private let stickers: StickerManager
    private let screens: ScreenProvider
    private let defaults: UserDefaults
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "tutorial")

    init(library: LibraryController, stickers: StickerManager, screens: ScreenProvider, defaults: UserDefaults) {
        self.library = library
        self.stickers = stickers
        self.screens = screens
        self.defaults = defaults
    }

    /// Draws, saves and places the three tutorials, clear of a Home window of
    /// `homeSize` centred on the main display. `completion` says whether the
    /// index was saved (and `didFirstRun` set).
    func placeFirstRun(shortcut: Shortcut?, homeSize: CGSize, completion: ((Bool) -> Void)? = nil) {
        guard !library.isReadOnly, let display = screens.mainDisplay,
              let images = TutorialArt.masters(shortcut: shortcut)
        else {
            log.error("first run: no main display or no artwork")
            completion?(false)
            return
        }
        let pngs = zip(LibraryStore.tutorialIDs, images).compactMap { id, image in
            (try? MasterImage.pngData(image, pixelsPerPoint: Double(TutorialArt.pixelsPerPoint))).map { (id, $0) }
        }
        guard pngs.count == images.count else {
            completion?(false)
            return
        }
        let store = library.store
        Task { [weak self] in
            let written = await Self.write(pngs, to: store)
            self?.firstRunWritten(images, written: written, display: display, homeSize: homeSize,
                                  completion: completion)
        }
    }

    /// Writes PNGs off the main actor (spec section 12).
    nonisolated private static func write(_ pngs: [(UUID, Data)], to store: LibraryStore) async -> Bool {
        do {
            for (id, data) in pngs { try store.writePNG(data, for: id) }
            return true
        } catch {
            return false
        }
    }

    private func firstRunWritten(_ images: [CGImage], written: Bool, display: DisplayInfo, homeSize: CGSize,
                                 completion: ((Bool) -> Void)?) {
        let ids = LibraryStore.tutorialIDs
        guard written, !library.isReadOnly else {
            for id in ids { try? library.store.deletePNG(for: id) }
            log.error("first run: writing the tutorial PNGs failed")
            completion?(false)
            return
        }
        let created = Date()
        let records = zip(ids, images).map { id, image in
            StickerRecord(id: id, created: created, pixelWidth: image.width, pixelHeight: image.height,
                          pixelsPerPoint: Double(TutorialArt.pixelsPerPoint), lastStyle: Self.style, tutorial: true)
        }
        let items = TutorialLayout.layout(naturalSizes: records.map(\.naturalPointSize), frame: display.frame,
                                          visibleFrame: display.visibleFrame, homeSize: homeSize)
        // First-run tutorial placement is one of the spec's write exceptions (section 11).
        let key = stickers.recordKeyForUserEdit(on: display)
        library.mutate { library in
            library.stickers.removeAll { ids.contains($0.id) }
            library.stickers.append(contentsOf: records)
            for (index, record) in records.enumerated() {
                let placement = Placement(sticker: record.id, style: Self.style,
                                          rotation: TutorialLayout.rotations[index],
                                          poses: [display.size.key: items[index].pose])
                library.displays[key]?.placements.append(placement)
            }
        }
        library.flush()
        let saved = !library.hasUnsavedChanges
        if saved { defaults.didFirstRun = true }
        stickers.reconcileNow()
        log.notice("first run: tutorial stickers placed (saved: \(saved))")
        completion?(saved)
    }

    /// The capture shortcut changed: while tutorial 1 exists, its master is
    /// redrawn with the new shortcut (PNG first, then the index's pixel size)
    /// and its placements re-rendered.
    func shortcutChanged(to shortcut: Shortcut?, completion: (() -> Void)? = nil) {
        let id = LibraryStore.tutorialIDs[0]
        guard !library.isReadOnly, library.library.sticker(id) != nil,
              let image = TutorialArt.shortcutCard(for: shortcut),
              let data = try? MasterImage.pngData(image, pixelsPerPoint: Double(TutorialArt.pixelsPerPoint))
        else {
            completion?()
            return
        }
        let store = library.store
        Task { [weak self] in
            let written = await Self.write([(id, data)], to: store)
            self?.shortcutCardWritten(id, image: image, written: written)
            completion?()
        }
    }

    private func shortcutCardWritten(_ id: UUID, image: CGImage, written: Bool) {
        guard written, !library.isReadOnly else { return }
        guard library.library.sticker(id) != nil else {
            // Removed while the PNG was written: launch repair would adopt it.
            try? library.store.deletePNG(for: id)
            return
        }
        library.mutate { library in
            guard let index = library.stickers.firstIndex(where: { $0.id == id }) else { return }
            library.stickers[index].pixelWidth = image.width
            library.stickers[index].pixelHeight = image.height
        }
        stickers.masterChanged(for: id)
    }
}
