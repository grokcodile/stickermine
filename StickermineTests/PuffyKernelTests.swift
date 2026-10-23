import CoreImage
import Foundation
import Testing
@testable import Stickermine

struct PuffyKernelTests {
    @Test func theKernelSourceCompilesOnThisMac() {
        let compiled = PuffyKernel.compile(PuffyKernel.source)
        #expect(compiled.error == nil)
        #expect(compiled.kernel?.name == PuffyKernel.functionName)
    }

    @Test func aBrokenSourceFailsWithoutAKernel() {
        let compiled = PuffyKernel.compile("this is not Metal")
        #expect(compiled.kernel == nil)
        #expect((compiled.error as NSError?)?.domain == "CIKernel")
    }

    @Test func theKernelLivesInASwiftStringNotAMetalFile() throws {
        let enumerator = FileManager.default.enumerator(at: SourceFiles.appRoot, includingPropertiesForKeys: nil)
        var metalFiles: [String] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "metal" { metalFiles.append(url.lastPathComponent) }
        }
        #expect(metalFiles.isEmpty)
        let text = try SourceFiles.contents(of: "Capture/PuffyKernel.swift")
        #expect(text.contains("CIKernel.kernels(withMetalString:"))
    }

    @Test func theLightComesFromTheTopLeft() {
        let light = PuffyKernel.light
        #expect(light.x < 0)   // left
        #expect(light.y > 0)   // up, in Core Image's y-up space
        #expect(abs(light.x + light.y) < 1e-9)
        #expect(light.z == 0.63)
    }

    @Test func theInscribedRadiusOfADiscIsItsRadius() {
        let context = CIContext()
        let small = PuffyKernel.inscribedRadius(of: Masters.disc(diameter: 200), context: context)
        #expect(abs(small - 100) <= 2)
        // Above 1024 px it is measured on a smaller copy and scaled back.
        let large = PuffyKernel.inscribedRadius(of: Masters.disc(diameter: 2048), context: context)
        #expect(abs(large - 1024) <= 8)
    }

    @Test func theFallbackShadesWithBuiltInFiltersOnly() {
        let canvas = CGRect(x: 0, y: 0, width: 64, height: 64)
        let base = CIImage(color: CIColor(red: 0.5, green: 0.5, blue: 0.5)).cropped(to: canvas.insetBy(dx: 8, dy: 8))
        let rim = StyleRecipes.silhouette(of: base)
        let shaded = PuffyKernel.shade(base: base, rim: rim, domeRadius: 12, canvas: canvas, useKernel: false)
        #expect(shaded.path == .builtIn)
        #expect(!shaded.image.extent.isEmpty && canvas.contains(shaded.image.extent))
    }

    /// A 600 px white disc on clear, like the rim silhouette of a big round sticker.
    private func discRim() -> CIImage {
        let side = 600
        let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        context.fillEllipse(in: CGRect(x: 10, y: 10, width: 580, height: 580))
        return CIImage(cgImage: context.makeImage()!)
    }

    /// The largest second difference of a height field's alpha along a row and
    /// along a column through the disc's upper-left quarter, rendered in float.
    private func roughness(_ field: CIImage) -> (x: Float, y: Float) {
        let side = 600
        let context = CIContext(options: [.workingFormat: CIFormat.RGBAf.rawValue, .workingColorSpace: NSNull()])
        var pixels = [Float](repeating: 0, count: side * side * 4)
        pixels.withUnsafeMutableBytes {
            context.render(field, toBitmap: $0.baseAddress!, rowBytes: side * 16,
                           bounds: CGRect(x: 0, y: 0, width: side, height: side), format: .RGBAf, colorSpace: nil)
        }
        func alpha(_ x: Int, _ y: Int) -> Float { pixels[(y * side + x) * 4 + 3] }
        var x: Float = 0, y: Float = 0
        for i in 100..<300 {
            x = max(x, abs(alpha(i + 1, 150) - 2 * alpha(i, 150) + alpha(i - 1, 150)))
            y = max(y, abs(alpha(150, i + 1) - 2 * alpha(150, i) + alpha(150, i - 1)))
        }
        return (x, y)
    }

    @Test func theHeightFieldsAreSmoothAlongBothAxes() {
        // CIGaussianBlur keeps its horizontal pass at half precision even in an
        // RGBAf context, so a big blur's height steps by 2^-11 along x. Puffy's
        // normals come from differences of the height, and its specular turns
        // those steps into vertical streaks. Every height field must stay below
        // half a half-float step along x, as it is along y.
        for field in PuffyKernel.heightFields(rim: discRim(), domeRadius: 150) {
            let r = roughness(field)
            #expect(r.x < 2.5e-4, "x roughness \(r.x) (y \(r.y))")
            #expect(r.y < 2.5e-4, "y roughness \(r.y)")
        }
    }

    @Test func theFallbackReadsTheSameSmoothHeight() {
        let r = roughness(PuffyKernel.heightField(rim: discRim(), sigma: 100))
        #expect(r.x < 2.5e-4 && r.y < 2.5e-4, "roughness \(r)")
        let text = (try? SourceFiles.contents(of: "Capture/PuffyKernel.swift")) ?? ""
        #expect(!text.contains("applyingGaussianBlur(sigma: 2 * domeRadius / 3)"),
                "the built-in Puffy must use heightField(rim:sigma:), not CIGaussianBlur")
    }
}
