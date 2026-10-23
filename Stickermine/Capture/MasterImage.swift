import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A screenshot loaded for cutting out (spec section 5.8): its pixels with the
/// embedded colour profile, and its pixels per point from the file's DPI, so
/// the sticker's natural point size is pixels / pixelsPerPoint on mixed 1×/2×
/// setups too.
struct LoadedCapture {
    let image: CGImage
    let pixelsPerPoint: Double
}

/// Master PNGs on disk (spec section 6.8): written with DPI = 72 × pixels per
/// point, so recovery can restore a sticker's natural size from the file alone.
/// Also loads screenshots (`load(url:)`) and crops cutouts to their pixels.
enum MasterImage {
    enum Failure: Error {
        case cannotEncode
        case unreadable
    }

    /// What launch repair needs from a PNG without decoding its pixels.
    struct FileInfo: Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        /// From the file's DPI; nil when the file has none.
        let pixelsPerPoint: Double?
    }

    /// The transparent border a master keeps around its pixels (spec section 6.8).
    static let cropPadding = 2

    /// PNG data for `image` (its colour profile embedded) with DPI = 72 × `pixelsPerPoint`.
    static func pngData(_ image: CGImage, pixelsPerPoint: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.cannotEncode }
        let dpi = 72 * pixelsPerPoint
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.cannotEncode }
        return data as Data
    }

    /// Pixel size and DPI-derived pixels per point; nil when the file isn't a readable image.
    static func fileInfo(at url: URL) -> FileInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        let dpi = properties[kCGImagePropertyDPIWidth] as? Double
        return FileInfo(pixelWidth: width, pixelHeight: height,
                        pixelsPerPoint: dpi.flatMap(pixelsPerPoint(fromDPI:)))
    }

    /// DPI / 72, rounded to 0.01 (PNG stores pixels per metre, so 144 DPI can
    /// come back as 143.99). nil for a DPI that isn't positive.
    static func pixelsPerPoint(fromDPI dpi: Double) -> Double? {
        guard dpi > 0 else { return nil }
        return (dpi / 72 * 100).rounded() / 100
    }

    /// The master's pixels as stored (colour profile kept). Thread-safe.
    static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Loads a screenshot with ImageIO, keeping its embedded ICC profile and
    /// decoding it at once, so the file can be deleted right after. Pixels per
    /// point come from the DPI (`LibraryStore.defaultPixelsPerPoint` when the
    /// file has none).
    static func load(url: URL) throws -> LoadedCapture {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width > 0, image.height > 0
        else { throw Failure.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double
        return LoadedCapture(image: image,
                             pixelsPerPoint: dpi.flatMap(pixelsPerPoint(fromDPI:)) ?? LibraryStore.defaultPixelsPerPoint)
    }

    /// The smallest pixel rect (top-left origin) holding every pixel whose alpha
    /// isn't 0; nil when the image is fully transparent.
    static func alphaBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        // Row 0 of the context's memory is the image's top row; alpha is byte 3.
        for y in 0..<height {
            let row = pixels + y * width * 4
            var x = 0
            while x < width, row[x * 4 + 3] == 0 { x += 1 }
            guard x < width else { continue }
            var last = width - 1
            while row[last * 4 + 3] == 0 { last -= 1 }
            minX = min(minX, x)
            maxX = max(maxX, last)
            minY = min(minY, y)
            maxY = y
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// `image` cropped to its alpha bounds plus `padding` pixels on every side
    /// (kept inside the image); nil when it is fully transparent.
    static func croppedToAlpha(_ image: CGImage, padding: Int = cropPadding) -> CGImage? {
        guard let bounds = alphaBounds(of: image) else { return nil }
        let padded = bounds.insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if padded.width == CGFloat(image.width), padded.height == CGFloat(image.height) { return image }
        // CGImage cropping takes a rect with the image's top-left as origin.
        return image.cropping(to: padded)
    }
}
