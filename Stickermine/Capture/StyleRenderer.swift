import CoreGraphics
import Foundation

/// Everything a sticker's bitmap depends on. Two equal requests give the same bitmap.
struct RenderRequest: Equatable {
    let sticker: UUID
    let style: StickerStyle
    let flipped: Bool
    /// Radians, counter-clockwise on screen.
    let rotation: Double
    /// The unrotated on-screen size in points (natural size × pose scale).
    let pointSize: CGSize
    let backingScale: CGFloat
}

struct RenderedSticker {
    /// A CGImage (the M2 baseline) or an IOSurface, set as `CALayer.contents`.
    let contents: Any
    /// The bitmap's size in pixels (long side at most `StyleRenderer.maxPixelLongSide`).
    let pixelSize: CGSize
    /// The rotated bounding box of the sticker in points, without shadow margin.
    let pointBounds: CGSize
    let alphaMask: AlphaMask
}

/// A coarse copy of the bitmap's alpha (long side at most 512): a cell is the
/// largest alpha among the pixels it covers, so any visible pixel marks it.
struct AlphaMask {
    let width: Int
    let height: Int
    /// Row-major, row 0 at the top.
    let bytes: [UInt8]

    /// `p` in 0–1 with the origin at the top-left of the bitmap.
    func isOpaque(atUnit p: CGPoint) -> Bool {
        guard width > 0, height > 0, bytes.count == width * height,
              p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1
        else { return false }
        let x = min(width - 1, Int(p.x * CGFloat(width)))
        let y = min(height - 1, Int(p.y * CGFloat(height)))
        return bytes[y * width + x] > 0
    }
}

/// Renders a sticker's bitmap for a request, off the main actor.
///
/// M2 baseline: every style draws the master unstyled, scaled to the on-screen
/// pixel size (capped at 2048 px on the long side; above that the layer scales
/// it up), with flip and rotation baked in and alpha below about 0.02 cleared,
/// so faint fringes never catch clicks (spec sections 8 and 9). M3 replaces the
/// per-style drawing inside `render` and adds the Puffy kernel to `prewarm`.
final class StyleRenderer {
    enum RenderError: Error, Equatable {
        case missingMaster
        case emptySize
        case contextFailed
    }

    static let maxPixelLongSide: Double = 2048
    static let maxMaskLongSide = 512
    /// Alpha below this (about 0.02 × 255) becomes 0.
    static let alphaFloor: UInt8 = 5

    private let masterProvider: (UUID) -> CGImage?

    /// `masterProvider` loads a sticker's master image. It is called off the
    /// main thread and must be thread-safe.
    init(masterProvider: @escaping (UUID) -> CGImage?) {
        self.masterProvider = masterProvider
    }

    func render(_ request: RenderRequest) async throws -> RenderedSticker {
        guard let master = masterProvider(request.sticker) else { throw RenderError.missingMaster }
        return try Self.renderBaseline(master: master, request: request)
    }

    /// The baseline has nothing to compile; M3 compiles the Puffy kernel here.
    func prewarm() {}

    /// The canvas for a request: the rotated bounding box in pixels, capped at
    /// `maxPixelLongSide`, and the size the unrotated master is drawn at.
    static func canvas(for request: RenderRequest) -> (width: Int, height: Int, drawSize: CGSize, pointBounds: CGSize) {
        let pixelSize = CGSize(width: request.pointSize.width * request.backingScale,
                               height: request.pointSize.height * request.backingScale)
        let box = StickerGeometry.boundingSize(of: pixelSize, rotation: request.rotation)
        let longSide = max(box.width, box.height)
        let cap = longSide > maxPixelLongSide ? maxPixelLongSide / longSide : 1
        // The tiny allowance keeps 100.000000001 from becoming 101 after rotation.
        let width = max(1, Int((box.width * cap - 0.001).rounded(.up)))
        let height = max(1, Int((box.height * cap - 0.001).rounded(.up)))
        let drawSize = CGSize(width: pixelSize.width * cap, height: pixelSize.height * cap)
        return (width, height, drawSize, StickerGeometry.boundingSize(of: request.pointSize, rotation: request.rotation))
    }

    static func renderBaseline(master: CGImage, request: RenderRequest) throws -> RenderedSticker {
        guard request.pointSize.width > 0, request.pointSize.height > 0, request.backingScale > 0 else {
            throw RenderError.emptySize
        }
        let canvas = canvas(for: request)
        let rgbSpace = master.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let colorSpace = rgbSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8,
                  bytesPerRow: canvas.width * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw RenderError.contextFailed }
        context.interpolationQuality = .high
        // Flip in the sticker's own frame, then rotate, around the canvas centre.
        context.translateBy(x: CGFloat(canvas.width) / 2, y: CGFloat(canvas.height) / 2)
        context.rotate(by: CGFloat(request.rotation))
        if request.flipped { context.scaleBy(x: -1, y: 1) }
        let draw = canvas.drawSize
        context.draw(master, in: CGRect(x: -draw.width / 2, y: -draw.height / 2, width: draw.width, height: draw.height))

        guard let data = context.data else { throw RenderError.contextFailed }
        let mask = clampAlphaAndBuildMask(
            pixels: data.bindMemory(to: UInt8.self, capacity: canvas.width * canvas.height * 4),
            width: canvas.width, height: canvas.height)
        guard let image = context.makeImage() else { throw RenderError.contextFailed }
        return RenderedSticker(
            contents: image,
            pixelSize: CGSize(width: canvas.width, height: canvas.height),
            pointBounds: canvas.pointBounds,
            alphaMask: mask
        )
    }

    /// One pass over premultiplied RGBA rows (row 0 at the top): clears pixels
    /// whose alpha is below `alphaFloor` and records the largest alpha per mask cell.
    static func clampAlphaAndBuildMask(pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> AlphaMask {
        let longSide = max(width, height)
        let factor = longSide > maxMaskLongSide ? Double(maxMaskLongSide) / Double(longSide) : 1
        let maskWidth = max(1, Int((Double(width) * factor).rounded(.up)))
        let maskHeight = max(1, Int((Double(height) * factor).rounded(.up)))
        var bytes = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        bytes.withUnsafeMutableBufferPointer { mask in
            for y in 0..<height {
                let maskRow = min(maskHeight - 1, y * maskHeight / height) * maskWidth
                let row = pixels + y * width * 4
                for x in 0..<width {
                    let pixel = row + x * 4
                    let alpha = pixel[3]
                    if alpha < alphaFloor {
                        if alpha != 0 { pixel[0] = 0; pixel[1] = 0; pixel[2] = 0; pixel[3] = 0 }
                        continue
                    }
                    let cell = maskRow + min(maskWidth - 1, x * maskWidth / width)
                    if alpha > mask[cell] { mask[cell] = alpha }
                }
            }
        }
        return AlphaMask(width: maskWidth, height: maskHeight, bytes: bytes)
    }
}
