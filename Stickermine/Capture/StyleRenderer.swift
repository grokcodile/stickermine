import CoreGraphics
import CoreImage
import Foundation
import IOSurface
import Metal
import os

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

extension RenderRequest {
    /// The style parameters for the sticker's on-screen size (unrotated long
    /// side in points × backing scale): what the layer shadow and the window's
    /// margin use. The bitmap's own rim and dome use the parameters of its
    /// possibly capped pixel size instead.
    func onScreenParameters(sourceLongSide: Double) -> StyleParameters {
        StyleParameters.forStickerPixels(
            longSide: Double(max(pointSize.width, pointSize.height) * backingScale),
            sourceLongSide: sourceLongSide)
    }
}

struct RenderedSticker {
    /// An IOSurface or a CGImage (`StyleRenderer.Options.contents`), set as `CALayer.contents`.
    let contents: Any
    /// The bitmap's size in pixels (long side at most `StyleRenderer.maxPixelLongSide`).
    let pixelSize: CGSize
    /// The rotated bounding box of the sticker in points, without shadow margin.
    let pointBounds: CGSize
    let alphaMask: AlphaMask
    /// The backing scale the bitmap was rendered for; the layer shadow turns
    /// its pixel parameters into points with it.
    let backingScale: CGFloat
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

/// Renders a sticker's styled bitmap (spec sections 8 and 9).
///
/// One serial queue does every render off the main thread, with one shared
/// Metal-backed `CIContext` (half-float working format) for Outline, Shadow and
/// None and one RGBAf context for Puffy; caches are cleared after each bake.
/// The bitmap is the rotated box of the sticker (plus its rim for Outline and
/// Puffy, so the subject keeps its size in every style) at the on-screen pixel
/// size, capped at 2048 px on the long side (the layer scales it up beyond
/// that), with flip and rotation baked in, so the Puffy light stays top-left
/// on screen. Alpha
/// below about 0.02 is cleared so faint fringes never catch clicks; the drop
/// shadow is never baked (`StickerView` draws it as a layer shadow).
///
/// Thread-safe: its mutable state is behind `lock`, `CIContext` is thread-safe,
/// and every `CIFilter` is created per render.
final class StyleRenderer: @unchecked Sendable {
    enum RenderError: Error, Equatable {
        case missingMaster
        case emptySize
        case contextFailed
    }

    /// What `RenderedSticker.contents` holds.
    enum Contents: Equatable {
        case surface
        case image
    }

    struct Options: Equatable {
        var contents: Contents
        /// Outline and Puffy close the rim (grow by r + s, shrink by s).
        var closesRim: Bool
        /// False forces Puffy's built-in-filter fallback (tests, the gallery).
        var usesPuffyKernel: Bool

        static let standard = Options(contents: StyleRenderer.defaultContents, closesRim: true, usesPuffyKernel: true)
    }

    /// From design/spike-results.md, Decisions: "Contents type for M3: IOSurface
    /// or CGImage?" IOSurface contents cost about half the memory of a CGImage.
    static let defaultContents: Contents = .surface
    static let maxPixelLongSide: Double = 2048
    static let maxMaskLongSide = 512
    /// Alpha below this (about 0.02 × 255) becomes 0.
    static let alphaFloor: UInt8 = 5

    let options: Options
    private let masterProvider: (UUID) -> CGImage?
    private let queue = DispatchQueue(label: "com.ethan.stickermine.render", qos: .userInitiated)
    private let standardContext: CIContext
    private let puffyContext: CIContext
    private let hasMetal: Bool
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "render")

    private struct Inscribed {
        let width: Int
        let height: Int
        let radius: Double
    }

    private let lock = NSLock()
    private var inscribed: [UUID: Inscribed] = [:]
    private var measurements = 0
    private var puffyPath: PuffyKernel.Path?

    /// `masterProvider` loads a sticker's master image. It is called off the
    /// main thread and must be thread-safe.
    init(masterProvider: @escaping (UUID) -> CGImage?, options: Options = .standard) {
        self.masterProvider = masterProvider
        self.options = options
        let device = MTLCreateSystemDefaultDevice()
        // Kernels from a Metal string run only on a Metal-backed context whose
        // device supports dynamic libraries (CIKernel.h).
        hasMetal = device?.supportsDynamicLibraries == true
        standardContext = Self.makeContext(device: device, workingFormat: nil)
        puffyContext = Self.makeContext(device: device, workingFormat: .RGBAf)
    }

    private static func makeContext(device: MTLDevice?, workingFormat: CIFormat?) -> CIContext {
        var contextOptions: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let workingFormat { contextOptions[.workingFormat] = workingFormat }
        if let device { return CIContext(mtlDevice: device, options: contextOptions) }
        return CIContext(options: contextOptions)
    }

    func render(_ request: RenderRequest) async throws -> RenderedSticker {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                continuation.resume(with: Result { try self.renderNow(request) })
            }
        }
    }

    /// Compiles the Puffy kernel on the render queue (off the main thread) and
    /// returns at once; a render queued afterwards waits for it.
    func prewarm() {
        queue.async { [log] in
            let compiled = PuffyKernel.compiled
            if compiled.kernel != nil {
                log.notice("Puffy kernel ready (\(Int(compiled.seconds * 1000)) ms)")
            }
        }
    }

    /// How many inscribed radii were measured (each sticker once), for tests.
    var inscribedMeasurementCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return measurements
    }

    /// Where Puffy's kernel comes from; tests substitute a kernel that draws nothing.
    var puffyKernelProvider: () -> CIKernel? = { PuffyKernel.compiled.kernel }

    /// True once the kernel drew nothing for a sticker that has pixels: every
    /// later Puffy uses the built-in filters for the rest of the session.
    var isPuffyKernelDisabled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return kernelDisabled
    }
    private var kernelDisabled = false
    /// The path of the bitmap this thread just drew (guarded by `lock`).
    private var lastDrawnPath: PuffyKernel.Path?

    /// Which Puffy recipe drew the latest Puffy bitmap.
    var lastPuffyPath: PuffyKernel.Path? {
        lock.lock()
        defer { lock.unlock() }
        return puffyPath
    }

    /// Forgets what was measured for `sticker`; call it if a sticker's master
    /// ever changes under the same ID.
    func invalidateCache(for sticker: UUID) {
        lock.lock()
        inscribed[sticker] = nil
        lock.unlock()
    }

    /// Renders on the calling thread. The app only reaches it through `render`
    /// (the render queue); the gallery and tests call it from background tasks.
    func renderNow(_ request: RenderRequest) throws -> RenderedSticker {
        guard let master = masterProvider(request.sticker) else { throw RenderError.missingMaster }
        guard request.pointSize.width > 0, request.pointSize.height > 0, request.backingScale > 0,
              master.width > 0, master.height > 0
        else { throw RenderError.emptySize }
        let canvas = Self.canvas(for: request)
        let bounds = CGRect(x: 0, y: 0, width: canvas.width, height: canvas.height)
        guard let colorSpace = SurfaceContents.colorSpace(for: master) else { throw RenderError.contextFailed }
        let (image, context) = styled(master: master, request: request, drawSize: canvas.drawSize, bounds: bounds)
        defer { context.clearCaches() }
        let rendered: RenderedSticker
        if options.contents == .surface,
           let surface = renderSurface(image, context: context, bounds: bounds, colorSpace: colorSpace) {
            rendered = RenderedSticker(contents: surface.surface, pixelSize: bounds.size, pointBounds: canvas.pointBounds,
                                       alphaMask: surface.mask, backingScale: request.backingScale)
        } else {
            let bitmap = try renderImage(image, context: context, bounds: bounds, colorSpace: colorSpace)
            rendered = RenderedSticker(contents: bitmap.image, pixelSize: bounds.size, pointBounds: canvas.pointBounds,
                                       alphaMask: bitmap.mask, backingScale: request.backingScale)
        }
        return try guardAgainstABlankKernel(rendered, request: request)
    }

    /// A Puffy drawn by the kernel with no opaque pixel at all means either an
    /// empty master or a kernel that compiles but draws nothing (a stitched
    /// kernel failing at render time on some Mac would leave an invisible,
    /// unclickable sticker). Re-render once with the built-in filters: if that
    /// has pixels, the kernel is broken, so it stays off for the session.
    private func guardAgainstABlankKernel(_ rendered: RenderedSticker, request: RenderRequest) throws -> RenderedSticker {
        lock.lock()
        let drewWithKernel = request.style == .puffy && lastDrawnPath == .kernel && !kernelDisabled
        lock.unlock()
        guard drewWithKernel, !rendered.alphaMask.bytes.contains(where: { $0 > 0 }) else { return rendered }
        lock.lock()
        kernelDisabled = true
        lock.unlock()
        let fallback = try renderNow(request)
        if fallback.alphaMask.bytes.contains(where: { $0 > 0 }) {
            log.error("Puffy kernel drew nothing; using the built-in filters for the rest of the session")
            return fallback
        }
        lock.lock()
        kernelDisabled = false
        lock.unlock()
        return rendered
    }

    /// The canvas for a request: the rotated bounding box in pixels of the
    /// sticker plus its rim (Outline and Puffy reach `rimReach` beyond the
    /// subject on every side), capped at `maxPixelLongSide`; the size the
    /// unrotated master is drawn at; and the bitmap's box in points (its whole
    /// pixels over the backing scale, or the full on-screen box when capped).
    static func canvas(for request: RenderRequest) -> (width: Int, height: Int, drawSize: CGSize, pointBounds: CGSize) {
        let reach = CGFloat(request.onScreenParameters(sourceLongSide: 0).rimReach(for: request.style))
        let pixelSize = CGSize(width: request.pointSize.width * request.backingScale,
                               height: request.pointSize.height * request.backingScale)
        let outer = CGSize(width: pixelSize.width + 2 * reach, height: pixelSize.height + 2 * reach)
        let box = StickerGeometry.boundingSize(of: outer, rotation: request.rotation)
        let longSide = max(box.width, box.height)
        let cap = longSide > maxPixelLongSide ? maxPixelLongSide / longSide : 1
        // The tiny allowance keeps 100.000000001 from becoming 101 after rotation.
        let width = max(1, Int((box.width * cap - 0.001).rounded(.up)))
        let height = max(1, Int((box.height * cap - 0.001).rounded(.up)))
        let drawSize = CGSize(width: pixelSize.width * cap, height: pixelSize.height * cap)
        // Uncapped, the box in points is the bitmap's own whole-pixel box, so the
        // layer shows it 1:1 on device pixels. Capped, it is the full on-screen
        // box and the layer scales the bitmap up to it.
        let pointBounds: CGSize
        if cap < 1 {
            let reachPoints = reach / request.backingScale
            let outerPoints = CGSize(width: request.pointSize.width + 2 * reachPoints,
                                     height: request.pointSize.height + 2 * reachPoints)
            pointBounds = StickerGeometry.boundingSize(of: outerPoints, rotation: request.rotation)
        } else {
            pointBounds = CGSize(width: CGFloat(width) / request.backingScale,
                                 height: CGFloat(height) / request.backingScale)
        }
        return (width, height, drawSize, pointBounds)
    }

    /// The styled image for `request` on a canvas of `bounds`, and the context
    /// to render it with. `drawSize` is the unrotated master in bitmap pixels;
    /// a rim is drawn around it, inside the canvas's room for it.
    private func styled(master: CGImage, request: RenderRequest, drawSize: CGSize,
                        bounds: CGRect) -> (CIImage, CIContext) {
        let source = CIImage(cgImage: master)
        let longSide = Double(max(drawSize.width, drawSize.height))
        let parameters = StyleParameters.forStickerPixels(
            longSide: longSide, sourceLongSide: Double(max(master.width, master.height)))
        // Bitmap pixels per master pixel.
        let pixelRatio = Double(drawSize.width) / Double(master.width)
        let subject = StyleRecipes.placed(source, size: drawSize, flipped: request.flipped,
                                          rotation: request.rotation, canvas: bounds)
        let closing = options.closesRim ? parameters.closing : 0
        switch request.style {
        case .none, .shadow:
            return (StyleRecipes.choked(subject, sigma: parameters.chokeSigma * pixelRatio, canvas: bounds),
                    standardContext)
        case .outline:
            let rim = StyleRecipes.rim(around: subject, radius: parameters.rimRadius, closing: closing, canvas: bounds)
            return (StyleRecipes.outline(subject: subject, rim: rim, canvas: bounds), standardContext)
        case .puffy:
            let rim = StyleRecipes.rim(around: subject, radius: parameters.rimRadius, closing: closing, canvas: bounds)
            let base = StyleRecipes.outline(subject: subject, rim: rim, canvas: bounds)
            let inscribedRadius = inscribedRadius(for: request.sticker, master: master) * pixelRatio
                + parameters.rimRadius
            let domeRadius = StyleParameters.domeRadius(inscribedRadius: inscribedRadius, longSide: longSide)
            lock.lock()
            let kernelOff = kernelDisabled
            lock.unlock()
            let shaded = PuffyKernel.shade(base: base, rim: rim, domeRadius: domeRadius, canvas: bounds,
                                           useKernel: options.usesPuffyKernel && hasMetal && !kernelOff,
                                           kernel: puffyKernelProvider())
            lock.lock()
            puffyPath = shaded.path
            lastDrawnPath = shaded.path
            lock.unlock()
            return (shaded.image, puffyContext)
        }
    }

    /// The master's inscribed radius in master pixels, measured once per sticker.
    private func inscribedRadius(for sticker: UUID, master: CGImage) -> Double {
        lock.lock()
        if let cached = inscribed[sticker], cached.width == master.width, cached.height == master.height {
            lock.unlock()
            return cached.radius
        }
        lock.unlock()
        let radius = PuffyKernel.inscribedRadius(of: master, context: puffyContext)
        lock.lock()
        inscribed[sticker] = Inscribed(width: master.width, height: master.height, radius: radius)
        measurements += 1
        lock.unlock()
        return radius
    }

    /// Renders into a new IOSurface tagged with `colorSpace`, clearing faint
    /// alpha in place. nil when the surface can't be made.
    private func renderSurface(_ image: CIImage, context: CIContext, bounds: CGRect,
                               colorSpace: CGColorSpace) -> (surface: IOSurface, mask: AlphaMask)? {
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard let surface = SurfaceContents.blank(width: width, height: height) else { return nil }
        // Core Image's y-up origin lands on the last row, so memory row 0 is the top.
        context.render(image, to: surface, bounds: bounds, colorSpace: colorSpace)
        _ = surface.lock(options: [], seed: nil)
        let mask = Self.clampAlphaAndBuildMask(
            pixels: surface.baseAddress.assumingMemoryBound(to: UInt8.self),
            width: width, height: height, rowBytes: surface.bytesPerRow)
        _ = surface.unlock(options: [], seed: nil)
        SurfaceContents.tag(surface, with: colorSpace)
        return (surface, mask)
    }

    /// Renders into an RGBA8 premultiplied bitmap in `colorSpace` and makes a CGImage.
    private func renderImage(_ image: CIImage, context: CIContext, bounds: CGRect,
                             colorSpace: CGColorSpace) throws -> (image: CGImage, mask: AlphaMask) {
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        guard let bitmap = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8,
                  bytesPerRow: width * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = bitmap.data
        else { throw RenderError.contextFailed }
        context.render(image, toBitmap: data, rowBytes: width * 4, bounds: bounds, format: .RGBA8,
                       colorSpace: colorSpace)
        let mask = Self.clampAlphaAndBuildMask(
            pixels: data.bindMemory(to: UInt8.self, capacity: width * height * 4),
            width: width, height: height, rowBytes: width * 4)
        guard let cgImage = bitmap.makeImage() else { throw RenderError.contextFailed }
        return (cgImage, mask)
    }

    /// One pass over premultiplied 4-byte pixels (RGBA or BGRA: alpha is the
    /// fourth byte) with rows `rowBytes` apart, row 0 at the top: clears pixels
    /// whose alpha is below `alphaFloor` and records the largest alpha per mask cell.
    static func clampAlphaAndBuildMask(pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int,
                                       rowBytes: Int) -> AlphaMask {
        let longSide = max(width, height)
        let factor = longSide > maxMaskLongSide ? Double(maxMaskLongSide) / Double(longSide) : 1
        let maskWidth = max(1, Int((Double(width) * factor).rounded(.up)))
        let maskHeight = max(1, Int((Double(height) * factor).rounded(.up)))
        var bytes = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        bytes.withUnsafeMutableBufferPointer { mask in
            for y in 0..<height {
                let maskRow = min(maskHeight - 1, y * maskHeight / height) * maskWidth
                let row = pixels + y * rowBytes
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

    /// Tightly packed rows (`rowBytes` = width × 4), as M2's baseline used.
    static func clampAlphaAndBuildMask(pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> AlphaMask {
        clampAlphaAndBuildMask(pixels: pixels, width: width, height: height, rowBytes: width * 4)
    }
}
