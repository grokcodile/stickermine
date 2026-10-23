import CoreGraphics
import Foundation
import ImageIO
@testable import Stickermine

/// Model, display and file fixtures for the M2 tests.
enum Fixtures {
    /// A display far off every real screen (x ≥ 40 000 pt), so panels ordered
    /// in by tests never appear on the developer's desktop.
    static func display(
        uuid: String, id: UInt32, frame: CGRect, visibleFrame: CGRect? = nil, scale: CGFloat = 2,
        name: String = "Test Display", vendor: UInt32 = 7789, model: UInt32 = 23305, serial: UInt32 = 848_464,
        builtin: Bool = false, mirrors: UInt32? = nil, inMirrorSet: Bool = false
    ) -> DisplayInfo {
        DisplayInfo(uuid: uuid, displayID: id, frame: frame, visibleFrame: visibleFrame ?? frame,
                    backingScale: scale, name: name, vendor: vendor, model: model, serial: serial,
                    builtin: builtin, mirrorsDisplayID: mirrors, inMirrorSet: inMirrorSet)
    }

    static let externalUUID = "25A19A46-A9B2-42B2-B1F8-389D978CBBC2"
    static let mainUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    /// 1920 × 1080 at x = 40 000.
    static func external(frame: CGRect = CGRect(x: 40_000, y: 0, width: 1920, height: 1080),
                         scale: CGFloat = 2) -> DisplayInfo {
        display(uuid: externalUUID, id: 3, frame: frame, scale: scale, name: "LG UltraFine")
    }

    /// 1512 × 982 at x = 50 000, built in.
    static func main() -> DisplayInfo {
        display(uuid: mainUUID, id: 1, frame: CGRect(x: 50_000, y: 0, width: 1512, height: 982),
                name: "Built-in Retina Display", vendor: 1552, model: 41_013, serial: 0, builtin: true)
    }

    /// A sticker record whose natural size is `width` × `height` points at 2 px/pt.
    static func sticker(_ id: UUID = UUID(), width: Int = 200, height: Int = 100, tutorial: Bool = false) -> StickerRecord {
        StickerRecord(id: id, created: Date(timeIntervalSince1970: 1_760_000_000), pixelWidth: width * 2,
                      pixelHeight: height * 2, pixelsPerPoint: 2, lastStyle: .outline, tutorial: tutorial)
    }

    static func displayRecord(for display: DisplayInfo, placements: [Placement]) -> DisplayRecord {
        DisplayRecord(name: display.name, vendor: display.vendor, model: display.model, serial: display.serial,
                      builtin: display.builtin, lastSeen: Date(timeIntervalSince1970: 1_760_000_000),
                      placements: placements)
    }

    /// A fresh, empty directory; delete it at the end of the test.
    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickermineTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An opaque sRGB image: the left half `left`, the right half `right` (RGBA, 0–255;
    /// alpha 0 makes that half transparent).
    static func image(width: Int, height: Int, left: [UInt8] = [255, 0, 0, 255],
                      right: [UInt8] = [0, 0, 255, 255], colorSpace: CGColorSpace? = nil) -> CGImage {
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ rgba: [UInt8], _ rect: CGRect) {
            let a = CGFloat(rgba[3]) / 255
            context.setFillColor(CGColor(colorSpace: space, components: [
                CGFloat(rgba[0]) / 255, CGFloat(rgba[1]) / 255, CGFloat(rgba[2]) / 255, a])!)
            context.setBlendMode(.copy)
            context.fill(rect)
        }
        fill(left, CGRect(x: 0, y: 0, width: width / 2, height: height))
        fill(right, CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    /// PNG data for a `width` × `height` px image with DPI = 72 × `pixelsPerPoint`
    /// (no DPI at all when it is nil). Written with ImageIO directly, so store
    /// tests don't depend on the app's own PNG writer.
    static func pngData(width: Int, height: Int, pixelsPerPoint: Double?) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        let properties: [CFString: Any]? = pixelsPerPoint.map {
            [kCGImagePropertyDPIWidth: 72 * $0, kCGImagePropertyDPIHeight: 72 * $0]
        }
        CGImageDestinationAddImage(destination, image(width: width, height: height), properties as CFDictionary?)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }
}
