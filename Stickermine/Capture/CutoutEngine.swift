import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Metal
import Vision
import os

enum CutoutError: Error, Equatable {
    /// No subject was selected (never ask Vision for an empty set or for 0).
    case emptySelection
    /// The picker closed and the Vision handler was let go.
    case released
    /// The mask came out empty.
    case emptyMask
    case renderFailed
}

/// On-device subject cutout with Vision's foreground instance masks (spec
/// section 6). `analyze` runs pass 1 on a capture and returns a
/// `CutoutAnalysis` for the picker. Never forces the CPU (it fails there).
/// Thread-safe; call it from any task.
final class CutoutEngine: @unchecked Sendable {
    /// Runs the foreground-instance request on a handler. Tests substitute one
    /// that throws or finds nothing.
    typealias Perform = @Sendable (ImageRequestHandler) async throws -> InstanceMaskObservation?

    static let vision: Perform = { handler in
        try await handler.perform(GenerateForegroundInstanceMaskRequest())
    }

    /// The Metal-backed context every cutout renders with.
    let context: CIContext
    private let perform: Perform
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "cutout")

    init(perform: @escaping Perform = CutoutEngine.vision) {
        self.perform = perform
        let options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    /// Loads the Vision model with a throwaway request (about 100 ms cold) while
    /// the crosshair is up (spec section 5.5). Returns at once.
    func prewarm() {
        let perform = self.perform
        Task.detached(priority: .userInitiated) {
            guard let image = CutoutEngine.warmUpImage() else { return }
            _ = try? await perform(ImageRequestHandler(image))
        }
    }

    /// Pass 1 on the full capture. nil, no instances and any thrown error (Vision
    /// throws `requestCancelled` on flat colours) all mean "no subject": the
    /// analysis then has no subjects and the picker offers the whole image.
    func analyze(_ capture: LoadedCapture) async -> CutoutAnalysis {
        let handler = ImageRequestHandler(capture.image)
        var observation: InstanceMaskObservation?
        do {
            observation = try await perform(handler)
        } catch {
            log.notice("no subject: Vision threw \(String(describing: error), privacy: .public)")
        }
        var masks: [(index: Int, mask: CVPixelBuffer)] = []
        if let observation {
            // Instance 0 is the background; never ask for it.
            for index in observation.allInstances.sorted() where index > 0 {
                do {
                    masks.append((index, try observation.generateMask(for: IndexSet(integer: index))))
                } catch {
                    log.error("mask for instance \(index) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        log.notice("pass 1: \(masks.count) subjects in \(capture.image.width)x\(capture.image.height)")
        return CutoutAnalysis(capture: capture, handler: masks.isEmpty ? nil : handler,
                              observation: masks.isEmpty ? nil : observation, masks: masks,
                              context: context, perform: perform)
    }

    /// A small picture with one obvious subject, for the warm-up request.
    static func warmUpImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.94, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(CGColor(srgbRed: 0.85, green: 0.2, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: 16, y: 16, width: 32, height: 32))
        return context.makeImage()
    }
}

/// What Vision found in one capture, kept while the picker is open (spec
/// section 6). Holds the pass-1 handler and observation (about 130 MB at peak)
/// until `release()`. Thread-safe.
final class CutoutAnalysis: @unchecked Sendable {
    /// Pass 2 runs when the selection's box is under this share of the
    /// capture's long side.
    static let refineBelow = 0.6
    /// Pass 2 looks at the box plus this share of its size on every side.
    static let refineMargin = 0.08
    /// Whole image: corners rounded at 4% of the short side.
    static let cornerRadiusFraction = 0.04
    /// The picker shows the capture downsampled to this long side.
    static let displayLongSide = 1024

    let capture: LoadedCapture
    /// Vision's instance indices, ascending; empty when there is no subject.
    let subjectIndices: [Int]
    /// The capture at most `displayLongSide` pixels long, for the picker.
    let displayImage: CGImage

    private let context: CIContext
    private let perform: CutoutEngine.Perform
    private let lock = NSLock()
    private var handler: ImageRequestHandler?
    private var observation: InstanceMaskObservation?
    private var masks: [(index: Int, mask: CVPixelBuffer)]
    private var whole: CGImage?
    private var refinedCount = 0

    init(capture: LoadedCapture, handler: ImageRequestHandler?, observation: InstanceMaskObservation?,
         masks: [(index: Int, mask: CVPixelBuffer)], context: CIContext, perform: @escaping CutoutEngine.Perform) {
        self.capture = capture
        self.handler = handler
        self.observation = observation
        self.masks = masks
        self.context = context
        self.perform = perform
        subjectIndices = masks.map(\.index)
        displayImage = Self.downsampled(capture.image, longSide: Self.displayLongSide) ?? capture.image
    }

    /// The subject under `p` (0–1, top-left origin of the capture); nil is background.
    func subject(atUnitTopLeft p: CGPoint) -> Int? {
        MaskSampler.subject(atUnitTopLeft: p, masks: currentMasks())
    }

    /// A 512 × 512 white image whose alpha is the subject's coverage, for the
    /// picker's highlight (stretched over the capture).
    func highlightMask(for index: Int) -> CGImage? {
        guard let mask = currentMasks().first(where: { $0.index == index })?.mask else { return nil }
        return Self.coverageImage(mask)
    }

    /// The union of the selected subjects' boxes (0–1, top-left origin).
    func bounds(of selection: Set<Int>) -> CGRect? {
        let boxes = currentMasks().filter { selection.contains($0.index) }.compactMap { MaskSampler.bounds(of: $0.mask) }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Pass 2 is worth it when the box's long side is under 60% of the capture's.
    static func refines(_ unitBounds: CGRect, width: Int, height: Int) -> Bool {
        let longSide = max(unitBounds.width * CGFloat(width), unitBounds.height * CGFloat(height))
        return Double(longSide) < refineBelow * Double(max(width, height))
    }

    /// How many cutouts used pass 2 (diagnostics and tests).
    var refinedCutoutCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return refinedCount
    }

    /// The selected subjects cut out of the capture, cropped to their pixels
    /// plus 2 px, in the capture's colour space: the master as it will be
    /// saved. A small selection is refined with pass 2 (spec section 6.4);
    /// Fill holes closes enclosed gaps (6.6).
    func cutout(selection: Set<Int>, fillHoles: Bool) async throws -> CGImage {
        let picked = selection.filter { $0 > 0 }.sorted()
        guard !picked.isEmpty else { throw CutoutError.emptySelection }
        guard let (handler, observation) = visionState() else { throw CutoutError.released }
        let width = capture.image.width
        let height = capture.image.height
        let full = CGRect(x: 0, y: 0, width: width, height: height)

        let firstPass = Self.maskImage(try observation.generateScaledMask(
            for: IndexSet(picked), scaledToImageFrom: handler))
        var mask = firstPass
        if let unit = bounds(of: Set(picked)), Self.refines(unit, width: width, height: height),
           let refined = await refinedMask(unit: unit, firstPass: firstPass) {
            mask = refined
            countRefinement()
        }
        try Task.checkCancellation()
        if fillHoles {
            mask = try filled(mask, width: width, height: height)
        }
        // CIBlendWithMask over an empty background keeps the original's exact
        // colours (generateMaskedImage would drop the colour space).
        let blended = CIImage(cgImage: capture.image).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
        guard let space = SurfaceContents.colorSpace(for: capture.image),
              let rendered = context.createCGImage(blended, from: full, format: .RGBA8, colorSpace: space)
        else { throw CutoutError.renderFailed }
        context.clearCaches()
        try Task.checkCancellation()
        guard let cropped = MasterImage.croppedToAlpha(rendered) else { throw CutoutError.emptyMask }
        return cropped
    }

    /// The original capture with its own alpha kept (window captures have
    /// transparent corners) and corners rounded at 4% of the short side,
    /// cropped to its pixels plus 2 px (spec section 6.7). Computed once.
    func wholeImage() -> CGImage {
        lock.lock()
        if let whole {
            lock.unlock()
            return whole
        }
        lock.unlock()
        let rounded = Self.roundedCorners(capture.image) ?? capture.image
        let result = MasterImage.croppedToAlpha(rounded) ?? rounded
        lock.lock()
        whole = result
        lock.unlock()
        return result
    }

    /// Lets go of the Vision handler, observation and masks (the picker closed).
    func release() {
        lock.lock()
        handler = nil
        observation = nil
        masks = []
        lock.unlock()
    }

    // MARK: Helpers

    private func currentMasks() -> [(index: Int, mask: CVPixelBuffer)] {
        lock.lock()
        defer { lock.unlock() }
        return masks
    }

    /// The pass-1 handler and observation; nil after `release()`.
    private func visionState() -> (ImageRequestHandler, InstanceMaskObservation)? {
        lock.lock()
        defer { lock.unlock() }
        guard let handler, let observation else { return nil }
        return (handler, observation)
    }

    private func countRefinement() {
        lock.lock()
        refinedCount += 1
        lock.unlock()
    }

    /// Pass 2 on the box plus 8%: the union of what Vision finds there,
    /// intersected with a slightly dilated pass-1 mask, as a full-size mask.
    /// nil when pass 2 finds nothing (the pass-1 mask is used then).
    private func refinedMask(unit: CGRect, firstPass: CIImage) async -> CIImage? {
        let width = CGFloat(capture.image.width)
        let height = CGFloat(capture.image.height)
        let box = CGRect(x: unit.minX * width, y: unit.minY * height, width: unit.width * width,
                         height: unit.height * height)
        let marginX = max(8, box.width * CGFloat(Self.refineMargin))
        let marginY = max(8, box.height * CGFloat(Self.refineMargin))
        let region = box.insetBy(dx: -marginX, dy: -marginY).integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !region.isEmpty, let crop = capture.image.cropping(to: region) else { return nil }
        let cropHandler = ImageRequestHandler(crop)
        guard let second = try? await perform(cropHandler) else { return nil }
        let instances = IndexSet(second.allInstances.filter { $0 > 0 })
        guard !instances.isEmpty,
              let secondMask = try? second.generateScaledMask(for: instances, scaledToImageFrom: cropHandler)
        else { return nil }
        // Core Image is y-up: the crop's top-left region sits at height − maxY.
        let placedRegion = CGRect(x: region.minX, y: height - region.maxY, width: region.width, height: region.height)
        let placed = Self.maskImage(secondMask)
            .transformed(by: CGAffineTransform(translationX: placedRegion.minX, y: placedRegion.minY))
        let texel = Double(max(width, height)) / 512
        let dilated = firstPass.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: max(2, 1.5 * texel),
        ])
        let combined = placed.applyingFilter("CIMinimumCompositing", parameters: [
            kCIInputBackgroundImageKey: dilated,
        ]).cropped(to: placedRegion)
        return combined.composited(over: CIImage(color: CIColor.black)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height)))
    }

    /// `mask` rendered into a float buffer, holes filled (`HoleFiller`), and
    /// wrapped again without colour management.
    private func filled(_ mask: CIImage, width: Int, height: Int) throws -> CIImage {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent32Float,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created)
        guard let buffer = created else { throw CutoutError.renderFailed }
        context.render(mask, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: nil)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw CutoutError.renderFailed }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var alpha = [Float](repeating: 0, count: width * height)
        alpha.withUnsafeMutableBufferPointer { values in
            for y in 0..<height {
                let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in 0..<width { values[y * width + x] = row[x] }
            }
        }
        HoleFiller.fill(alpha: &alpha, width: width, height: height, edge: HoleFiller.defaultEdge)
        alpha.withUnsafeBufferPointer { values in
            for y in 0..<height {
                let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in 0..<width { row[x] = values[y * width + x] }
            }
        }
        return Self.maskImage(buffer)
    }

    /// A Vision mask as a Core Image mask. The NSNull colour space stops Core
    /// Image from treating the coverage as gamma-encoded grey and linearising
    /// it, which would shift the edge (spec section 6.5).
    static func maskImage(_ buffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    /// White, with the coverage as premultiplied alpha.
    static func coverageImage(_ buffer: CVPixelBuffer) -> CGImage? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                let value = UInt8(max(0, min(1, row[x])) * 255)
                let pixel = pixels + (y * width + x) * 4
                pixel[0] = value
                pixel[1] = value
                pixel[2] = value
                pixel[3] = value
            }
        }
        return context.makeImage()
    }

    /// `image` clipped to a rounded rect (radius 4% of the short side), its own
    /// alpha kept, in its own colour space when that is RGB.
    static func roundedCorners(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let radius = CGFloat(cornerRadiusFraction) * CGFloat(min(width, height))
        guard let space = SurfaceContents.colorSpace(for: image),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// `image` scaled down to at most `longSide` pixels (unchanged when smaller).
    static func downsampled(_ image: CGImage, longSide: Int) -> CGImage? {
        let scale = Double(longSide) / Double(max(image.width, image.height))
        guard scale < 1 else { return image }
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = SurfaceContents.colorSpace(for: image),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
