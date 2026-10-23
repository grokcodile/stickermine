import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

/// The Core Image recipes behind Outline, Shadow and None, and the pieces
/// Puffy shares with Outline (spec section 8). Everything works in bitmap
/// pixels with Core Image's y-up coordinates on premultiplied images; nothing
/// here renders, so `StyleRenderer` decides which context runs the graph.
/// Filters are created per call: `CIFilter` isn't thread-safe.
enum StyleRecipes {
    /// None's choke ramp: alpha × clamp((blurred alpha − 0.7) / 0.35 + 0.5).
    static let chokeCenter = 0.7
    static let chokeWidth = 0.35
    /// The SDF's maximum distance is the distance asked for plus this.
    static let distanceHeadroom = 4.0

    /// `master` scaled to `size` (high-quality downsampling), flipped
    /// horizontally in its own frame when `flipped`, then rotated
    /// counter-clockwise by `rotation` radians, centred on `canvas` and cropped
    /// to it. Outside the master everything stays transparent.
    static func placed(_ master: CIImage, size: CGSize, flipped: Bool, rotation: Double, canvas: CGRect) -> CIImage {
        let extent = master.extent
        guard extent.width > 0, extent.height > 0, size.width > 0, size.height > 0 else { return .empty() }
        // Read bottom-up: centre the master on the origin, scale, flip, rotate, move to the canvas centre.
        var transform = CGAffineTransform(translationX: canvas.midX, y: canvas.midY)
        transform = transform.rotated(by: CGFloat(rotation))
        if flipped { transform = transform.scaledBy(x: -1, y: 1) }
        transform = transform.scaledBy(x: size.width / extent.width, y: size.height / extent.height)
        transform = transform.translatedBy(x: -extent.midX, y: -extent.midY)
        return master.transformed(by: transform, highQualityDownsample: true).cropped(to: canvas)
    }

    /// Premultiplied white with `image`'s alpha, so red equals coverage: the
    /// mask the signed-distance filter reads (never the coloured cutout).
    static func silhouette(of image: CIImage) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 1, y: 1, z: 1, w: 0)
        return matrix.outputImage ?? .empty()
    }

    /// Everything within `radius` px of `mask`'s opaque area, as premultiplied
    /// white with alpha = clamp(r + 0.5 − d), d from
    /// `CIFilter.signedDistanceGradientFromRedMask()` with D = r + 4 (spec
    /// section 8). Cropped to `canvas` (the distance field itself is infinite).
    static func grown(_ mask: CIImage, by radius: Double, canvas: CGRect) -> CIImage {
        let maxDistance = max(radius, 0) + distanceHeadroom
        let field = CIFilter.signedDistanceGradientFromRedMask()
        field.inputImage = mask
        field.maximumDistance = Float(maxDistance)
        return coverage(field.outputImage, slope: -maxDistance, offset: max(radius, 0) + 0.5, canvas: canvas)
    }

    /// `mask`'s opaque area shrunk by `distance` px: alpha = clamp(0.5 − s − d).
    static func shrunk(_ mask: CIImage, by distance: Double, canvas: CGRect) -> CIImage {
        let maxDistance = max(distance, 0) + distanceHeadroom
        let field = CIFilter.signedDistanceGradientFromRedMask()
        field.inputImage = mask
        field.maximumDistance = Float(maxDistance)
        return coverage(field.outputImage, slope: -maxDistance, offset: 0.5 - max(distance, 0), canvas: canvas)
    }

    /// White with alpha = clamp(slope × red + offset) for an opaque distance
    /// field whose red channel is the signed distance / D.
    private static func coverage(_ field: CIImage?, slope: Double, offset: Double, canvas: CGRect) -> CIImage {
        guard let field else { return .empty() }
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = field
        matrix.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.aVector = CIVector(x: CGFloat(slope), y: 0, z: 0, w: 0)
        matrix.biasVector = CIVector(x: 1, y: 1, z: 1, w: CGFloat(offset))
        return clamped(matrix.outputImage).cropped(to: canvas)
    }

    /// Every component clamped to 0–1.
    static func clamped(_ image: CIImage?) -> CIImage {
        guard let image else { return .empty() }
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = image
        clamp.minComponents = CIVector(x: 0, y: 0, z: 0, w: 0)
        clamp.maxComponents = CIVector(x: 1, y: 1, z: 1, w: 1)
        return clamp.outputImage ?? .empty()
    }

    /// The white die-cut rim around `subject` (alpha = coverage, the subject's
    /// own area included). With `closing` s > 0 the mask grows by r + s and
    /// shrinks back by s, which bridges notches narrower than about 2s for a
    /// smoother line; the intermediate keeps s + 2 px beyond the canvas, so the
    /// shrink never starts from the canvas edge.
    static func rim(around subject: CIImage, radius: Double, closing: Double, canvas: CGRect) -> CIImage {
        let mask = silhouette(of: subject)
        guard closing > 0 else { return grown(mask, by: radius, canvas: canvas) }
        let room = canvas.insetBy(dx: -CGFloat(closing + 2), dy: -CGFloat(closing + 2))
        return shrunk(grown(mask, by: radius + closing, canvas: room), by: closing, canvas: canvas)
    }

    /// Outline: the cutout over its white rim (the layer adds the drop shadow).
    static func outline(subject: CIImage, rim: CIImage, canvas: CGRect) -> CIImage {
        subject.composited(over: rim).cropped(to: canvas)
    }

    /// None's (and Shadow's) edge choke: the alpha is multiplied by
    /// clamp((a − 0.7) / 0.35 + 0.5) of the alpha blurred with σ = `sigma` px,
    /// which removes the light halo a 512 px Vision mask leaves around a cutout.
    static func choked(_ image: CIImage, sigma: Double, canvas: CGRect) -> CIImage {
        let blurred = sigma > 0 ? image.applyingGaussianBlur(sigma: sigma) : image
        let ramp = CIFilter.colorMatrix()
        ramp.inputImage = blurred
        ramp.rVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        ramp.gVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        ramp.bVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        ramp.aVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(1 / chokeWidth))
        ramp.biasVector = CIVector(x: 0, y: 0, z: 0, w: CGFloat(0.5 - chokeCenter / chokeWidth))
        let blend = CIFilter.blendWithAlphaMask()
        blend.inputImage = image
        blend.backgroundImage = CIImage.empty()
        blend.maskImage = clamped(ramp.outputImage)
        return (blend.outputImage ?? .empty()).cropped(to: canvas)
    }
}
