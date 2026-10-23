import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Stickermine

struct MasterImageTests {
    @Test func dpiSurvivesARoundTrip() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = Fixtures.image(width: 120, height: 80)
        for pixelsPerPoint in [1.0, 2.0, 3.0] {
            let url = folder.appendingPathComponent("\(pixelsPerPoint).png")
            try MasterImage.pngData(image, pixelsPerPoint: pixelsPerPoint).write(to: url)
            let loaded = try MasterImage.load(url: url)
            #expect(loaded.pixelsPerPoint == pixelsPerPoint)
            #expect(loaded.image.width == 120)
            #expect(loaded.image.height == 80)
            #expect(MasterImage.fileInfo(at: url)?.pixelsPerPoint == pixelsPerPoint)
        }
    }

    @Test func aFileWithoutDPIGetsTheDefault() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("plain.png")
        try Fixtures.pngData(width: 40, height: 20, pixelsPerPoint: nil).write(to: url)
        #expect(try MasterImage.load(url: url).pixelsPerPoint == LibraryStore.defaultPixelsPerPoint)
    }

    @Test func theEmbeddedProfileIsKept() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = Fixtures.image(width: 32, height: 32, colorSpace: p3)
        let url = folder.appendingPathComponent("p3.png")
        try MasterImage.pngData(image, pixelsPerPoint: 2).write(to: url)
        let loaded = try MasterImage.load(url: url)
        #expect(loaded.image.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func theFileCanGoRightAfterLoading() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("gone.png")
        try MasterImage.pngData(Fixtures.image(width: 50, height: 50), pixelsPerPoint: 2).write(to: url)
        let loaded = try MasterImage.load(url: url)
        try FileManager.default.removeItem(at: url)
        #expect(TestImages.rgba(of: loaded.image, x: 10, y: 10) == [255, 0, 0, 255])
    }

    @Test func anUnreadableFileThrows() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("junk.png")
        try Data("not a png".utf8).write(to: url)
        #expect(throws: (any Error).self) { try MasterImage.load(url: url) }
    }

    @Test func croppingKeepsTheVisiblePixelsPlusTwo() throws {
        // 100 × 60, transparent except a 10 × 8 block at x 30, y 20 from the top.
        let image = CaptureImages.draw(width: 100, height: 60) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1))
            context.fill(CGRect(x: 30, y: 60 - 20 - 8, width: 10, height: 8))
        }
        #expect(MasterImage.alphaBounds(of: image) == CGRect(x: 30, y: 20, width: 10, height: 8))
        let cropped = try #require(MasterImage.croppedToAlpha(image))
        #expect(cropped.width == 14)
        #expect(cropped.height == 12)
        #expect(TestImages.rgba(of: cropped, x: 1, y: 1)[3] == 0)
        #expect(TestImages.rgba(of: cropped, x: 2, y: 2)[3] == 255)
        #expect(TestImages.rgba(of: cropped, x: 11, y: 9)[3] == 255)
        #expect(TestImages.rgba(of: cropped, x: 12, y: 10)[3] == 0)
    }

    @Test func croppingStaysInsideTheImage() throws {
        let opaque = Fixtures.image(width: 40, height: 30)
        let cropped = try #require(MasterImage.croppedToAlpha(opaque))
        #expect(cropped.width == 40)
        #expect(cropped.height == 30)
        let empty = CaptureImages.draw(width: 20, height: 20) { _ in }
        #expect(MasterImage.croppedToAlpha(empty) == nil)
    }
}
