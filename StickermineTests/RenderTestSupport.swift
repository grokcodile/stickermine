import CoreGraphics
import CoreImage
import Foundation
import IOSurface
@testable import Stickermine

/// Full-bleed test masters: the shape touches the image's edges, so where it
/// lands in a rendered bitmap follows directly from the subject scale.
enum Masters {
    /// A `diameter` px disc of one opaque sRGB colour (0–255) on transparent.
    static func disc(diameter: Int, rgb: (UInt8, UInt8, UInt8) = (20, 140, 130)) -> CGImage {
        draw(width: diameter, height: diameter) { context, rect in
            context.setFillColor(CGColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255,
                                         blue: CGFloat(rgb.2) / 255, alpha: 1))
            context.fillEllipse(in: rect)
        }
    }

    /// A `side` px opaque square of one sRGB colour.
    static func square(side: Int, rgb: (UInt8, UInt8, UInt8) = (128, 128, 128)) -> CGImage {
        draw(width: side, height: side) { context, rect in
            context.setFillColor(CGColor(srgbRed: CGFloat(rgb.0) / 255, green: CGFloat(rgb.1) / 255,
                                         blue: CGFloat(rgb.2) / 255, alpha: 1))
            context.fill(rect)
        }
    }

    /// A `diameter` px opaque disc whose outer 4 px are a light ring at alpha
    /// 0.3: the halo a 512 px Vision mask leaves around a cutout.
    static func fringe(diameter: Int) -> CGImage {
        draw(width: diameter, height: diameter) { context, rect in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.3))
            context.fillEllipse(in: rect)
            context.setFillColor(CGColor(srgbRed: 0.1, green: 0.55, blue: 0.5, alpha: 1))
            context.fillEllipse(in: rect.insetBy(dx: 4, dy: 4))
        }
    }

    static func draw(width: Int, height: Int, _ body: (CGContext, CGRect) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(context, CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
}

/// Reads `RenderedSticker.contents`, whichever kind it is.
enum RenderedPixels {
    static func isSurface(_ contents: Any) -> Bool {
        CFGetTypeID(contents as AnyObject) == IOSurfaceGetTypeID()
    }

    static func isImage(_ contents: Any) -> Bool {
        CFGetTypeID(contents as AnyObject) == CGImage.typeID
    }

    static func size(_ contents: Any) -> CGSize? {
        if isSurface(contents), let surface = contents as? IOSurface {
            return CGSize(width: surface.width, height: surface.height)
        }
        if isImage(contents) {
            let image = contents as! CGImage
            return CGSize(width: image.width, height: image.height)
        }
        return nil
    }

    /// The colour space the pixels are in: a CGImage's own, an IOSurface's tag.
    static func colorSpace(_ contents: Any) -> CGColorSpace? {
        if isSurface(contents), let surface = contents as? IOSurface,
           let tag = IOSurfaceCopyValue(surface, kIOSurfaceColorSpace) {
            return CGColorSpace(propertyListPlist: tag)
        }
        if isImage(contents) { return (contents as! CGImage).colorSpace }
        return nil
    }

    /// Premultiplied RGBA bytes, rows top first: an IOSurface's raw BGRA bytes
    /// reordered, a CGImage drawn into sRGB.
    static func rgbaRows(_ contents: Any) -> (width: Int, height: Int, bytes: [UInt8])? {
        if isSurface(contents), let surface = contents as? IOSurface {
            _ = surface.lock(options: .readOnly, seed: nil)
            defer { _ = surface.unlock(options: .readOnly, seed: nil) }
            let base = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
            var bytes = [UInt8](repeating: 0, count: surface.width * surface.height * 4)
            for y in 0..<surface.height {
                for x in 0..<surface.width {
                    let source = base + y * surface.bytesPerRow + x * 4
                    let target = (y * surface.width + x) * 4
                    bytes[target] = source[2]
                    bytes[target + 1] = source[1]
                    bytes[target + 2] = source[0]
                    bytes[target + 3] = source[3]
                }
            }
            return (surface.width, surface.height, bytes)
        }
        if isImage(contents) {
            let image = contents as! CGImage
            let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                    bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setBlendMode(.copy)
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            let data = context.data!.assumingMemoryBound(to: UInt8.self)
            return (image.width, image.height, Array(UnsafeBufferPointer(start: data, count: image.width * image.height * 4)))
        }
        return nil
    }

    /// RGBA at (`x`, `y`), y = 0 being the top row.
    static func rgba(_ contents: Any, x: Int, y: Int) -> [UInt8] {
        guard let rows = rgbaRows(contents) else { return [] }
        let offset = (y * rows.width + x) * 4
        return Array(rows.bytes[offset..<offset + 4])
    }

    /// Every pixel's alpha.
    static func alphas(_ contents: Any) -> [UInt8] {
        guard let rows = rgbaRows(contents) else { return [] }
        return stride(from: 3, to: rows.bytes.count, by: 4).map { rows.bytes[$0] }
    }

    /// Rec. 709 luma of the premultiplied colour at (`x`, `y`).
    static func luma(_ contents: Any, x: Int, y: Int) -> Double {
        let p = rgba(contents, x: x, y: y)
        guard p.count == 4 else { return 0 }
        return 0.2126 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.0722 * Double(p[2])
    }
}

/// Renders a Core Image graph into premultiplied sRGB RGBA bytes, rows top first.
enum CIRender {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    static func rgba(_ image: CIImage, width: Int, height: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        context.render(image, toBitmap: &bytes, rowBytes: width * 4,
                       bounds: CGRect(x: 0, y: 0, width: width, height: height),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        return bytes
    }

    /// The pixel at (`x`, `y`) of `bytes`, y = 0 being the top row.
    static func pixel(_ bytes: [UInt8], width: Int, x: Int, y: Int) -> [UInt8] {
        let offset = (y * width + x) * 4
        return Array(bytes[offset..<offset + 4])
    }
}
