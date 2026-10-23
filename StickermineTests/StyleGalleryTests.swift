import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Stickermine

struct StyleGalleryTests {
    @Test func writesEveryVariantASheetAndTheTimings() throws {
        let folder = Fixtures.temporaryDirectory().appendingPathComponent("gallery", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) }
        let disc = StyleGallery.image(of: .disc, longSide: 120)
        let subject = StyleGallery.Subject(name: "disc", image: disc, pointSize: CGSize(width: 60, height: 60))
        let files = try StyleGallery.run(subjects: [subject], into: folder)
        let names = files.map(\.lastPathComponent)
        #expect(names == StyleGallery.variants.map { "disc-\($0.name).png" } + ["disc-sheet.png", "timings.txt"])
        for (variant, file) in zip(StyleGallery.variants, files) {
            let info = try #require(MasterImage.fileInfo(at: file))
            // 120 px; Outline and Puffy add a rim of ceil(1.8) + 1 = 3 px on every side.
            let side = variant.style == .puffy || variant.style == .outline ? 126 : 120
            #expect(info.pixelWidth == side && info.pixelHeight == side, "\(file.lastPathComponent)")
        }
        let timings = try String(contentsOf: folder.appendingPathComponent("timings.txt"), encoding: .utf8)
        let lines = timings.split(separator: "\n")
        #expect(lines.count == 2 + StyleGallery.variants.count)
        #expect(lines[0].hasPrefix("# Puffy kernel compiled in "))
        #expect(lines.contains { $0.hasPrefix("disc\tpuffy\t126x126\t") && $0.hasSuffix("\tkernel") })
        #expect(lines.contains { $0.hasPrefix("disc\tpuffy-builtin\t") && $0.hasSuffix("\tbuiltIn") })
    }

    @Test(arguments: StyleGallery.Shape.allCases)
    func everyShapeIsDrawnAtItsSize(_ shape: StyleGallery.Shape) {
        let image = StyleGallery.image(of: shape, longSide: 200)
        #expect(max(image.width, image.height) == 200)
        #expect(TestImages.rgba(of: image, x: 0, y: 0)[3] == 0)   // the 2 px border is transparent
        let centre = TestImages.rgba(of: image, x: image.width / 2, y: image.height / 2)
        #expect(centre[3] == (shape == .ring ? 0 : 255), "the ring has a hole")
        #expect((image.colorSpace?.name == CGColorSpace.displayP3) == (shape == .p3))
    }

    @Test func theDefaultSubjectsAreMapleTwiceThenEveryShape() {
        let maple = Fixtures.image(width: 62, height: 91)
        let names = StyleGallery.defaultSubjects(maple: maple).map(\.name)
        #expect(names == ["maple", "maple-turned"] + StyleGallery.Shape.allCases.map(\.rawValue))
        #expect(StyleGallery.defaultSubjects(maple: nil).count == StyleGallery.Shape.allCases.count)
        let turned = StyleGallery.defaultSubjects(maple: maple)[1]
        #expect(turned.flipped && turned.rotation == .pi / 6)
        #expect(turned.pointSize == CGSize(width: 31, height: 45.5))
    }

    @Test func theFolderIsANewOneUnderTheTemporaryDirectory() throws {
        let folder = StyleGallery.defaultFolder(now: Date(timeIntervalSince1970: 0))
        #expect(folder.deletingLastPathComponent().standardizedFileURL
                == FileManager.default.temporaryDirectory.standardizedFileURL)
        #expect(folder.lastPathComponent.hasPrefix("stickermine-gallery-"))
        #expect(folder.lastPathComponent.count == "stickermine-gallery-yyyyMMdd-HHmmss".count)
    }

    @Test func theGalleryNeverTouchesTheLibrary() throws {
        let text = try SourceFiles.contents(of: "App/StyleGallery.swift")
        for forbidden in ["LibraryStore", "LibraryController", "StickerManager", "writePNG"] {
            #expect(!text.contains(forbidden), "StyleGallery mentions \(forbidden)")
        }
        #expect(StyleGallery.launchArgument == "-styleGallery")
    }
}
