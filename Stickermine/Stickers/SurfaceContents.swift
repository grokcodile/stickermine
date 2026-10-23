import CoreGraphics
import CoreImage
import CoreVideo
import IOSurface

/// Turns a bitmap into an IOSurface for `CALayer.contents`. An IOSurface costs
/// about 1× the bitmap's bytes in the app; a CGImage as layer contents costs
/// about 2× (spec section 9). The M1 spike checks colour and alpha hit-testing
/// with these surfaces before M3 commits to them.
enum SurfaceContents {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// A BGRA, premultiplied surface holding `image` upright (row 0 = top row),
    /// rendered in the image's own colour space when that is RGB (sRGB otherwise)
    /// and tagged with it.
    static func make(from image: CGImage) -> IOSurface? {
        let width = image.width
        let height = image.height
        // A BGRA surface can only hold RGB: gray, CMYK or indexed images are
        // rendered (and tagged) as sRGB instead.
        let rgbSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard width > 0, height > 0,
              let colorSpace = rgbSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * 4),
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]
        guard let surface = IOSurface(properties: properties) else { return nil }
        // Core Image puts the image's (0,0) at the surface's lower-left corner,
        // which is the last row in memory, so the surface reads top-down.
        context.render(
            CIImage(cgImage: image),
            to: surface,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace
        )
        if let serialized = colorSpace.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, serialized)
        }
        return surface
    }
}
