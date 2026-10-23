import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation
import os

/// Puffy (spec section 8): the cutout over its white rim, shaded as an
/// inflated dome lit from the top-left in screen space.
///
/// The dome's height is the mean of three Gaussian blurs of the rim mask
/// (σ = R/3, 2R/3, R), averaged inside a Metal Core Image kernel that also
/// computes the normals (central differences, ±1.5 px) and applies Lambert +
/// Blinn-Phong light. The kernel source is a Swift string compiled at runtime
/// with `CIKernel.kernels(withMetalString:)`: a `.metal` file in the target
/// would need the separately downloaded Metal Toolchain. It is compiled once,
/// off the main thread (`StyleRenderer.prewarm()` reads `compiled` on the
/// render queue). If compiling throws, Puffy falls back to built-in filters
/// (Sobel gradients, a Lambert colour matrix and a screen-blended specular),
/// and if even those give no image, to the plain rim (Outline's look).
enum PuffyKernel {
    enum Path: String, Equatable {
        case kernel
        case builtIn
        case rimOnly
    }

    struct Compiled {
        let kernel: CIKernel?
        let error: Error?
        let seconds: TimeInterval
        let onMainThread: Bool
    }

    static let functionName = "puffyShade"
    static let ambient = 0.35
    static let diffuse = 0.65
    static let shininess = 40.0
    static let specular = 0.55
    /// Light from the top-left: 135° in Core Image's y-up space.
    static let lightAngle = 135.0 * Double.pi / 180
    static let lightPlanar = 0.55
    static let lightZ = 0.63
    /// Central-difference step for the normals, in pixels.
    static let normalStep = 1.5

    static var light: (x: Double, y: Double, z: Double) {
        (lightPlanar * cos(lightAngle), lightPlanar * sin(lightAngle), lightZ)
    }

    static let source = """
    #include <metal_stdlib>
    using namespace metal;
    #include <CoreImage/CoreImage.h>

    namespace stickermine {
        // The dome's height at p: the mean of the three blurred rim masks.
        inline float domeHeight(coreimage::sampler h1, coreimage::sampler h2, coreimage::sampler h3, float2 p) {
            return (h1.sample(h1.transform(p)).a + h2.sample(h2.transform(p)).a + h3.sample(h3.transform(p)).a) / 3.0;
        }
    }

    extern "C" {
    namespace coreimage {

    [[stitchable]] float4 puffyShade(sampler base, sampler h1, sampler h2, sampler h3,
                                     float3 light, float heightPx, float step, float ambient, float diffuse,
                                     float shininess, float specular, destination dest) {
        float2 p = dest.coord();
        float4 c = base.sample(base.transform(p));
        if (c.a <= 0.0) {
            return float4(0.0);
        }
        float dx = stickermine::domeHeight(h1, h2, h3, p + float2(step, 0.0))
                 - stickermine::domeHeight(h1, h2, h3, p - float2(step, 0.0));
        float dy = stickermine::domeHeight(h1, h2, h3, p + float2(0.0, step))
                 - stickermine::domeHeight(h1, h2, h3, p - float2(0.0, step));
        float slope = heightPx / (2.0 * step);
        float3 n = normalize(float3(-dx * slope, -dy * slope, 1.0));
        float lambert = max(dot(n, light), 0.0);
        float shade = (ambient + diffuse * lambert) / (ambient + diffuse * light.z);
        float3 halfway = normalize(light + float3(0.0, 0.0, 1.0));
        float highlight = specular * pow(max(dot(n, halfway), 0.0), shininess);
        float3 rgb = c.rgb * shade + highlight * c.a;
        return float4(min(rgb, float3(c.a)), c.a);
    }

    }
    }
    """

    private static let log = Logger(subsystem: "com.ethan.stickermine", category: "render")

    /// The kernel, compiled the first time anything reads this (thread-safe,
    /// exactly once per process).
    static let compiled: Compiled = compile(source)

    /// Compiles `source` and logs how long it took or why it failed.
    static func compile(_ source: String) -> Compiled {
        let start = Date()
        let onMain = Thread.isMainThread
        do {
            let kernels = try CIKernel.kernels(withMetalString: source)
            guard let kernel = kernels.first(where: { $0.name == functionName }) else {
                throw CocoaError(.featureUnsupported)
            }
            let seconds = Date().timeIntervalSince(start)
            log.notice("Puffy kernel compiled in \(Int(seconds * 1000)) ms")
            return Compiled(kernel: kernel, error: nil, seconds: seconds, onMainThread: onMain)
        } catch {
            log.error("Puffy kernel failed to compile, using built-in filters: \(String(describing: error), privacy: .public)")
            return Compiled(kernel: nil, error: error, seconds: Date().timeIntervalSince(start), onMainThread: onMain)
        }
    }

    /// The three height fields: the rim mask blurred at σ = R/3, 2R/3 and R.
    static func heightFields(rim: CIImage, domeRadius: Double) -> [CIImage] {
        [domeRadius / 3, 2 * domeRadius / 3, domeRadius].map { heightField(rim: rim, sigma: $0) }
    }

    /// One height field: the rim mask blurred at `sigma`, as three box blurs.
    /// Not CIGaussianBlur: it keeps its horizontal pass at half precision even
    /// in an RGBAf context, so a large blur's height steps by 2^-11 along x,
    /// and the normals' differences turn that into vertical streaks under the
    /// specular. Three box blurs approximate the Gaussian (central limit) and
    /// stay at full precision in both directions. CIBoxBlur's radius is the
    /// box's width w (σ² ≈ w²/12 per pass), so three passes of w = 2σ give σ;
    /// measured within about 1% of CIGaussianBlur on a 600 px disc.
    static func heightField(rim: CIImage, sigma: Double) -> CIImage {
        var image = rim
        for _ in 0..<3 {
            image = image.applyingFilter("CIBoxBlur", parameters: [kCIInputRadiusKey: 2 * sigma])
        }
        return image
    }

    /// Shades `base` (the cutout over its rim) with a dome of radius
    /// `domeRadius` px built from `rim`, trying the kernel first (when
    /// `useKernel` and it compiled), then the built-in filters, then nothing.
    static func shade(base: CIImage, rim: CIImage, domeRadius: Double, canvas: CGRect,
                      useKernel: Bool) -> (image: CIImage, path: Path) {
        if useKernel, let kernel = compiled.kernel,
           let image = shadeWithKernel(kernel, base: base, rim: rim, domeRadius: domeRadius, canvas: canvas) {
            return (image, .kernel)
        }
        if let image = shadeWithBuiltInFilters(base: base, rim: rim, domeRadius: domeRadius, canvas: canvas) {
            return (image, .builtIn)
        }
        return (base.cropped(to: canvas), .rimOnly)
    }

    static func shadeWithKernel(_ kernel: CIKernel, base: CIImage, rim: CIImage, domeRadius: Double,
                                canvas: CGRect) -> CIImage? {
        let heights = heightFields(rim: rim, domeRadius: domeRadius)
        let margin = CGFloat(normalStep + 2)
        let light = light
        return kernel.apply(
            extent: canvas,
            roiCallback: { index, rect in index == 0 ? rect : rect.insetBy(dx: -margin, dy: -margin) },
            arguments: [
                base, heights[0], heights[1], heights[2],
                CIVector(x: CGFloat(light.x), y: CGFloat(light.y), z: CGFloat(light.z)),
                StyleParameters.domeHeightPerRadius * domeRadius, normalStep,
                ambient, diffuse, shininess, specular,
            ])
    }

    /// The fallback, built-in filters only. One blur (σ = 2R/3) is the height,
    /// so nothing is summed. `CISobelGradients` gives 8 × the slope per pixel
    /// (red: x, green: y upwards), lightly blurred against the bands a large
    /// blur's interpolation leaves. A colour matrix turns the gradients into a
    /// linearised Lambert factor that multiplies the colours, and into u, the
    /// slope towards the light. The specular is a tent in u that peaks where
    /// the surface faces the halfway vector and is gone at u = 0 and u = 1,
    /// squared and screened on: less glossy than the kernel, never a flat wash.
    static func shadeWithBuiltInFilters(base: CIImage, rim: CIImage, domeRadius: Double, canvas: CGRect) -> CIImage? {
        let height = heightField(rim: rim, sigma: 2 * domeRadius / 3)
        let sobel = CIFilter.sobelGradients()
        sobel.inputImage = height
        guard let raw = sobel.outputImage else { return nil }
        let gradients = raw.clampedToExtent().applyingGaussianBlur(sigma: 1.5).cropped(to: canvas)
        let slope = StyleParameters.domeHeightPerRadius * domeRadius / 8
        let light = light
        let flat = ambient + diffuse * light.z

        // Lambert: (ambient + diffuse × N·L) / (ambient + diffuse × Lz), with
        // N·L ≈ Lz − Lx·sx − Ly·sy for the slopes sx, sy.
        let lx = -diffuse * light.x * slope / flat
        let ly = -diffuse * light.y * slope / flat
        let factor = gray(gradients, x: lx, y: ly, bias: 1, min: 0, max: 2)
        let opaqueBase = base.unpremultiplyingAlpha().settingAlphaOne(in: canvas)
        let lit = CIFilter.multiplyCompositing()
        lit.inputImage = factor
        lit.backgroundImage = opaqueBase

        // u = −slope × (d · gradient) for the light's planar direction d; the
        // halfway vector's tilt puts the tent's peak at u0 = |Hxy| / Hz.
        let ux = -slope * cos(lightAngle)
        let uy = -slope * sin(lightAngle)
        let hz = light.z + 1
        let peak = (light.x * light.x + light.y * light.y).squareRoot() / hz
        let rising = gray(gradients, x: ux / peak, y: uy / peak, bias: 0, min: 0, max: 1)
        let falling = gray(gradients, x: -ux / (1 - peak), y: -uy / (1 - peak), bias: 1 / (1 - peak), min: 0, max: 1)
        let tent = CIFilter.minimumCompositing()
        tent.inputImage = rising
        tent.backgroundImage = falling
        let sharpen = CIFilter.gammaAdjust()
        sharpen.inputImage = tent.outputImage
        sharpen.power = 2
        let amount = CIFilter.colorMatrix()
        amount.inputImage = sharpen.outputImage
        amount.rVector = CIVector(x: CGFloat(specular), y: 0, z: 0, w: 0)
        amount.gVector = CIVector(x: 0, y: CGFloat(specular), z: 0, w: 0)
        amount.bVector = CIVector(x: 0, y: 0, z: CGFloat(specular), w: 0)
        amount.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)

        let screen = CIFilter.screenBlendMode()
        screen.inputImage = amount.outputImage
        screen.backgroundImage = lit.outputImage
        let masked = CIFilter.blendWithAlphaMask()
        masked.inputImage = StyleRecipes.clamped(screen.outputImage)
        masked.backgroundImage = CIImage.empty()
        masked.maskImage = base
        return masked.outputImage?.cropped(to: canvas)
    }

    /// Opaque gray = clamp(x × red + y × green + bias) of an opaque image.
    private static func gray(_ image: CIImage, x: Double, y: Double, bias: Double, min: Double, max: Double) -> CIImage {
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = image
        let row = CIVector(x: CGFloat(x), y: CGFloat(y), z: 0, w: 0)
        matrix.rVector = row
        matrix.gVector = row
        matrix.bVector = row
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 0)
        matrix.biasVector = CIVector(x: CGFloat(bias), y: CGFloat(bias), z: CGFloat(bias), w: 1)
        let clamp = CIFilter.colorClamp()
        clamp.inputImage = matrix.outputImage
        clamp.minComponents = CIVector(x: CGFloat(min), y: CGFloat(min), z: CGFloat(min), w: 1)
        clamp.maxComponents = CIVector(x: CGFloat(max), y: CGFloat(max), z: CGFloat(max), w: 1)
        return clamp.outputImage ?? CIImage(color: CIColor(red: CGFloat(bias), green: CGFloat(bias), blue: CGFloat(bias)))
    }

    /// The longest side of the copy `inscribedRadius(of:context:)` measures.
    static let inscribedProxyLongSide = 1024.0

    /// The radius of the largest circle inside `master`'s opaque area, in the
    /// master's pixels. Measured once per sticker on a copy at most 1024 px
    /// long (the distance field's maximum distance is 1000), with
    /// `CIAreaMinimum` and a 1×1 float readback; `StyleRenderer` caches it.
    static func inscribedRadius(of master: CGImage, context: CIContext) -> Double {
        let longSide = Double(max(master.width, master.height))
        guard longSide > 0 else { return 0 }
        let scale = min(1, inscribedProxyLongSide / longSide)
        let proxy = CIImage(cgImage: master).transformed(
            by: CGAffineTransform(scaleX: CGFloat(scale), y: CGFloat(scale)), highQualityDownsample: true)
        let field = CIFilter.signedDistanceGradientFromRedMask()
        field.inputImage = StyleRecipes.silhouette(of: proxy)
        field.maximumDistance = 1000
        let minimum = CIFilter.areaMinimum()
        minimum.inputImage = field.outputImage
        minimum.extent = proxy.extent
        guard let pixel = minimum.outputImage else { return 0 }
        var rgba = [Float](repeating: 0, count: 4)
        context.render(pixel, toBitmap: &rgba, rowBytes: 16,
                       bounds: CGRect(origin: pixel.extent.origin, size: CGSize(width: 1, height: 1)),
                       format: .RGBAf, colorSpace: nil)
        // The field measures between pixel centres, half a pixel past the edge.
        let inside = Double(-rgba[0]) * 1000 - 0.5
        return max(0, inside) / scale
    }
}
