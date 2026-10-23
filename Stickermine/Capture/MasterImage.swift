import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Master PNGs on disk (spec section 6.8): written with DPI = 72 × pixels per
/// point, so recovery can restore a sticker's natural size from the file alone.
/// M4 adds `load(url:)` and `LoadedCapture` for screenshots.
enum MasterImage {
    enum Failure: Error {
        case cannotEncode
    }

    /// What launch repair needs from a PNG without decoding its pixels.
    struct FileInfo: Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        /// From the file's DPI; nil when the file has none.
        let pixelsPerPoint: Double?
    }

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
}
