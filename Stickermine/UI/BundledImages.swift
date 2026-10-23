import AppKit

/// Bitmaps bundled in Assets.xcassets, read at full pixel resolution.
enum BundledImages {
    /// Maple, copied from design/dog.png (620 × 910 px, stored as @2x).
    static let mapleName = "Maple"

    /// The named asset's largest representation drawn 1:1 into an sRGB,
    /// premultiplied RGBA bitmap. nil when the asset is missing.
    static func cgImage(named name: String) -> CGImage? {
        guard let image = NSImage(named: name),
              let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
              rep.pixelsWide > 0, rep.pixelsHigh > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: rep.pixelsWide, height: rep.pixelsHigh,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        rep.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
