import CoreGraphics
import Foundation

/// Small bitmaps built in code, and a pixel reader.
enum TestImages {
    /// A `width` × `height` image whose top half is `top` and bottom half is
    /// `bottom` (opaque RGB, 0–255), with its right-most column fully transparent.
    static func bands(
        width: Int, height: Int,
        top: (UInt8, UInt8, UInt8), bottom: (UInt8, UInt8, UInt8),
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ rgb: (UInt8, UInt8, UInt8), _ rect: CGRect) {
            context.setFillColor(CGColor(
                colorSpace: colorSpace,
                components: [CGFloat(rgb.0) / 255, CGFloat(rgb.1) / 255, CGFloat(rgb.2) / 255, 1])!)
            context.fill(rect)
        }
        // Core Graphics' origin is bottom-left, so the top half starts at height / 2.
        fill(bottom, CGRect(x: 0, y: 0, width: width, height: height / 2))
        fill(top, CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        context.clear(CGRect(x: width - 1, y: 0, width: 1, height: height))
        return context.makeImage()!
    }

    /// Premultiplied sRGB RGBA bytes of the pixel at (`x`, `y`), y = 0 being the top row.
    static func rgba(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * image.width * 4 + x * 4
        return (0..<4).map { bytes[offset + $0] }
    }
}

/// The repository's own files, for tests that guard rules no runtime check can see.
enum SourceFiles {
    /// The repository root, found from this file's location in `<repo>/StickermineTests`.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// `<repo>/Stickermine`, the app target's synchronized folder.
    static var appRoot: URL {
        repoRoot.appendingPathComponent("Stickermine")
    }

    static func contents(of relativePath: String) throws -> String {
        try String(contentsOf: appRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func swiftFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
}
