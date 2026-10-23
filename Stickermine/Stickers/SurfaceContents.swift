import CoreGraphics
import CoreImage
import CoreVideo
import IOSurface

/// IOSurfaces for `CALayer.contents`. An IOSurface costs about 1× the bitmap's
/// bytes in the app; a CGImage as layer contents costs about 2× (spec section 9).
/// `StyleRenderer` renders into `blank(width:height:)` surfaces and tags them;
/// `make(from:)` converts an existing image.
enum SurfaceContents {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// An empty BGRA, premultiplied surface (rows padded as IOSurface prefers;
    /// read `bytesPerRow`). nil for an empty size or when allocation fails.
    static func blank(width: Int, height: Int) -> IOSurface? {
        guard width > 0, height > 0 else { return nil }
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * 4),
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]
        return IOSurface(properties: properties)
    }

    /// Tags `surface` with `colorSpace` (`kIOSurfaceColorSpace`), so Core
    /// Animation shows its pixels in that space instead of assuming sRGB.
    static func tag(_ surface: IOSurface, with colorSpace: CGColorSpace) {
        if let serialized = colorSpace.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, serialized)
        }
    }

    /// The colour space a BGRA surface of `image` uses: the image's own when it
    /// is RGB, sRGB otherwise (a BGRA surface can only hold RGB).
    static func colorSpace(for image: CGImage) -> CGColorSpace? {
        image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil } ?? CGColorSpace(name: CGColorSpace.sRGB)
    }

    /// A BGRA, premultiplied surface holding `image` upright (row 0 = top row),
    /// rendered in the image's own colour space when that is RGB (sRGB otherwise)
    /// and tagged with it.
    static func make(from image: CGImage) -> IOSurface? {
        let width = image.width
        let height = image.height
        guard let colorSpace = colorSpace(for: image),
              let surface = blank(width: width, height: height)
        else { return nil }
        // Core Image puts the image's (0,0) at the surface's lower-left corner,
        // which is the last row in memory, so the surface reads top-down.
        context.render(
            CIImage(cgImage: image),
            to: surface,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace
        )
        tag(surface, with: colorSpace)
        return surface
    }
}
