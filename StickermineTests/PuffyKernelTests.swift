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
}
