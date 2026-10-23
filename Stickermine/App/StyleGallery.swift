import AppKit
import os

/// Debug tool for reviewing the style recipes by eye (spec section 8):
/// `build/Stickermine.app/Contents/MacOS/Stickermine -styleGallery` renders
/// Maple and generated test shapes in every style into PNGs in a new folder
/// under the temporary directory, prints the folder's path and quits. It never
/// touches the library and opens no window.
///
/// Per subject it writes one transparent PNG per variant, exactly the bitmap a
/// sticker window shows (Core Animation adds the drop shadow on screen, so it
/// isn't in these), and `<subject>-sheet.png`: every variant, labelled, on a
/// light row and a dark row, with an approximate drop shadow drawn by Core
/// Graphics. `timings.txt` starts with the Puffy kernel's compile time, then
/// lists each render's pixel size, time and Puffy recipe.
enum StyleGallery {
    static let launchArgument = "-styleGallery"
    static let backingScale: CGFloat = 2
    /// Generated shapes are this many pixels on the long side (300 pt at 2×).
    static let shapeLongSide = 600

    /// Generated test shapes: a plain convex shape, a hole, sharp concave
    /// corners, a thin bar, a whole-image rectangle, a cutout with a light halo
    /// (what a 512 px Vision mask leaves) and a Display P3 colour outside sRGB.
    enum Shape: String, CaseIterable {
        case disc, ring, star, bar, window, fringe, p3
    }

    struct Subject {
        let name: String
        let image: CGImage
        let pointSize: CGSize
        var rotation: Double = 0
        var flipped: Bool = false
    }

    struct Variant {
        let name: String
        let style: StickerStyle
        let closesRim: Bool
        let usesPuffyKernel: Bool
    }

    /// UI order; each comparison variant follows its style.
    static let variants: [Variant] = [
        Variant(name: "puffy", style: .puffy, closesRim: true, usesPuffyKernel: true),
        Variant(name: "puffy-builtin", style: .puffy, closesRim: true, usesPuffyKernel: false),
        Variant(name: "outline", style: .outline, closesRim: true, usesPuffyKernel: true),
        Variant(name: "outline-open", style: .outline, closesRim: false, usesPuffyKernel: true),
        Variant(name: "shadow", style: .shadow, closesRim: true, usesPuffyKernel: true),
        Variant(name: "none", style: .none, closesRim: true, usesPuffyKernel: true),
    ]

    private static let log = Logger(subsystem: "com.ethan.stickermine", category: "gallery")

    /// Maple at her natural size, Maple turned 30° and flipped (Puffy's light
    /// must still come from the top-left), and every generated shape.
    static func defaultSubjects(maple: CGImage?) -> [Subject] {
        var subjects: [Subject] = []
        if let maple {
            let size = CGSize(width: CGFloat(maple.width) / backingScale, height: CGFloat(maple.height) / backingScale)
            subjects.append(Subject(name: "maple", image: maple, pointSize: size))
            subjects.append(Subject(name: "maple-turned", image: maple, pointSize: size, rotation: .pi / 6, flipped: true))
        }
        for shape in Shape.allCases {
            let image = image(of: shape, longSide: shapeLongSide)
            let size = CGSize(width: CGFloat(image.width) / backingScale, height: CGFloat(image.height) / backingScale)
            subjects.append(Subject(name: shape.rawValue, image: image, pointSize: size))
        }
        return subjects
    }

    /// A premultiplied RGBA image of `shape`, `longSide` px on its long side,
    /// with a 2 px transparent border like a cropped master (spec section 6.8).
    static func image(of shape: Shape, longSide: Int) -> CGImage {
        let side = max(longSide, 16)
        let size: (Int, Int)
        switch shape {
        case .bar: size = (side, max(8, side / 10))
        case .window: size = (side, side * 2 / 3)
        default: size = (side, side)
        }
        let space = CGColorSpace(name: shape == .p3 ? CGColorSpace.displayP3 : CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: size.0, height: size.1, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let box = CGRect(x: 0, y: 0, width: size.0, height: size.1).insetBy(dx: 2, dy: 2)
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: space, components: [r, g, b, a])!
        }
        func gradient(in path: CGPath, from top: CGColor, to bottom: CGColor) {
            context.saveGState()
            context.addPath(path)
            context.clip(using: .evenOdd)
            let colors = [top, bottom] as CFArray
            let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
            context.drawLinearGradient(gradient, start: CGPoint(x: box.midX, y: box.maxY),
                                       end: CGPoint(x: box.midX, y: box.minY), options: [])
            context.restoreGState()
        }
        let orange = color(1, 0.62, 0.2)
        let purple = color(0.45, 0.2, 0.75)
        switch shape {
        case .disc:
            gradient(in: CGPath(ellipseIn: box, transform: nil), from: orange, to: purple)
        case .ring:
            let path = CGMutablePath()
            path.addEllipse(in: box)
            path.addEllipse(in: box.insetBy(dx: box.width * 0.3, dy: box.height * 0.3))
            gradient(in: path, from: orange, to: purple)
        case .star:
            let path = CGMutablePath()
            let outer = box.width / 2
            let inner = outer * 0.4
            for index in 0..<10 {
                let radius = index.isMultiple(of: 2) ? outer : inner
                let angle = CGFloat.pi / 2 + CGFloat(index) * .pi / 5
                let point = CGPoint(x: box.midX + radius * cos(angle), y: box.midY + radius * sin(angle))
                if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            path.closeSubpath()
            gradient(in: path, from: color(1, 0.85, 0.2), to: color(0.95, 0.45, 0.1))
        case .bar:
            let radius = box.height / 2
            gradient(in: CGPath(roundedRect: box, cornerWidth: radius, cornerHeight: radius, transform: nil),
                     from: color(0.2, 0.7, 0.95), to: color(0.1, 0.35, 0.8))
        case .window:
            let corner = min(box.width, box.height) * 0.04
            gradient(in: CGPath(roundedRect: box, cornerWidth: corner, cornerHeight: corner, transform: nil),
                     from: color(0.93, 0.95, 0.98), to: color(0.78, 0.82, 0.9))
            context.setFillColor(color(0.2, 0.45, 0.9))
            for row in 0..<3 {
                let y = box.maxY - box.height * (0.25 + 0.2 * CGFloat(row))
                context.fill(CGRect(x: box.minX + box.width * 0.1, y: y, width: box.width * 0.8, height: box.height * 0.08))
            }
        case .fringe:
            // An opaque disc inside a 4 px ring of light pixels at alpha 0.3.
            context.setFillColor(color(1, 1, 1, 0.3))
            context.fillEllipse(in: box)
            context.setFillColor(color(0.1, 0.55, 0.5))
            context.fillEllipse(in: box.insetBy(dx: 4, dy: 4))
        case .p3:
            context.setFillColor(color(1, 0, 0))
            context.fillEllipse(in: box)
        }
        return context.makeImage()!
    }

    /// Renders every subject in every variant into `folder` (created if needed)
    /// and returns the files written, timings last.
    @discardableResult
    static func run(subjects: [Subject], into folder: URL) throws -> [URL] {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var written: [URL] = []
        // Compile the kernel first, so its one-off cost isn't in a render's time.
        let kernel = PuffyKernel.compiled
        var timings = [kernel.kernel != nil
                       ? "# Puffy kernel compiled in \(Int(kernel.seconds * 1000)) ms"
                       : "# Puffy kernel failed to compile: \(String(describing: kernel.error))",
                       "subject\tvariant\tpixels\tms\tpuffy"]
        for subject in subjects {
            var cells: [(variant: Variant, image: CGImage, margin: Double, shadow: StyleParameters)] = []
            for variant in variants {
                let options = StyleRenderer.Options(contents: .image, closesRim: variant.closesRim,
                                                    usesPuffyKernel: variant.usesPuffyKernel)
                let renderer = StyleRenderer(masterProvider: { _ in subject.image }, options: options)
                let request = RenderRequest(sticker: UUID(), style: variant.style, flipped: subject.flipped,
                                            rotation: subject.rotation, pointSize: subject.pointSize,
                                            backingScale: backingScale)
                let start = Date()
                let rendered = try renderer.renderNow(request)
                let milliseconds = Date().timeIntervalSince(start) * 1000
                let contents = rendered.contents as AnyObject
                guard CFGetTypeID(contents) == CGImage.typeID else { continue }
                let image = contents as! CGImage
                let url = folder.appendingPathComponent("\(subject.name)-\(variant.name).png")
                try MasterImage.pngData(image, pixelsPerPoint: Double(backingScale)).write(to: url, options: .atomic)
                written.append(url)
                let path = variant.style == .puffy ? (renderer.lastPuffyPath?.rawValue ?? "?") : "-"
                timings.append("\(subject.name)\t\(variant.name)\t\(image.width)x\(image.height)\t"
                               + String(format: "%.1f", milliseconds) + "\t\(path)")
                let parameters = request.onScreenParameters(
                    sourceLongSide: Double(max(subject.image.width, subject.image.height)))
                cells.append((variant, image, parameters.shadowMargin(for: variant.style), parameters))
            }
            if let sheet = contactSheet(cells) {
                let url = folder.appendingPathComponent("\(subject.name)-sheet.png")
                try MasterImage.pngData(sheet, pixelsPerPoint: Double(backingScale)).write(to: url, options: .atomic)
                written.append(url)
            }
        }
        let timingsURL = folder.appendingPathComponent("timings.txt")
        try (timings.joined(separator: "\n") + "\n").write(to: timingsURL, atomically: true, encoding: .utf8)
        written.append(timingsURL)
        return written
    }

    /// Every variant side by side on a light row and a dark row, labelled, with
    /// a Core Graphics drop shadow approximating the layer shadow.
    static func contactSheet(_ cells: [(variant: Variant, image: CGImage, margin: Double, shadow: StyleParameters)]) -> CGImage? {
        guard !cells.isEmpty, let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let label = 36
        let margin = Int(cells.map(\.margin).max()?.rounded(.up) ?? 0) + 16
        let cellWidth = (cells.map(\.image.width).max() ?? 0) + 2 * margin
        let cellHeight = (cells.map(\.image.height).max() ?? 0) + 2 * margin
        let width = cellWidth * cells.count
        let height = 2 * cellHeight + label
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 0.93, alpha: 1))
        context.fill(CGRect(x: 0, y: cellHeight, width: width, height: cellHeight + label))
        context.setFillColor(CGColor(gray: 0.16, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: cellHeight))
        for (column, cell) in cells.enumerated() {
            for row in 0..<2 {
                let x = column * cellWidth + (cellWidth - cell.image.width) / 2
                let y = row * cellHeight + (cellHeight - cell.image.height) / 2
                context.saveGState()
                if cell.variant.style != .none {
                    context.setShadow(offset: CGSize(width: 0, height: -cell.shadow.shadowOffset),
                                      blur: CGFloat(cell.shadow.shadowRadius),
                                      color: CGColor(gray: 0, alpha: CGFloat(cell.shadow.shadowOpacity)))
                }
                context.draw(cell.image, in: CGRect(x: x, y: y, width: cell.image.width, height: cell.image.height))
                context.restoreGState()
            }
        }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor(white: 0.2, alpha: 1),
        ]
        for (column, cell) in cells.enumerated() {
            (cell.variant.name as NSString).draw(
                at: NSPoint(x: column * cellWidth + 12, y: 2 * cellHeight + 8), withAttributes: attributes)
        }
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// A new folder under the temporary directory, named after the time.
    static func defaultFolder(now: Date = Date()) -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("stickermine-gallery-\(formatter.string(from: now))", isDirectory: true)
    }

    /// Runs the gallery off the main thread, prints where it went and quits.
    @MainActor
    static func runAndQuit() {
        let subjects = defaultSubjects(maple: BundledImages.cgImage(named: BundledImages.mapleName))
        let folder = defaultFolder()
        Task.detached {
            do {
                let files = try run(subjects: subjects, into: folder)
                print("Style gallery: \(files.count) files in \(folder.path)")
                log.notice("style gallery: \(files.count) files in \(folder.path, privacy: .public)")
            } catch {
                print("Style gallery failed: \(error)")
                log.error("style gallery failed: \(String(describing: error), privacy: .public)")
            }
            await MainActor.run { NSApp.terminate(nil) }
        }
    }
}
