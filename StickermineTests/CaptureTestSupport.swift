import CoreGraphics
import CoreVideo
import Foundation
@testable import Stickermine

/// Generated captures and masks for the M4 tests.
enum CaptureImages {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func draw(width: Int, height: Int, colorSpace: CGColorSpace = sRGB,
                     _ body: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(context)
        return context.makeImage()!
    }

    /// 1200 × 800 on warm white: a red disc (280 px) lower left, centred at
    /// (300, 540) from the top-left, and a blue square (260 px) upper right,
    /// centred at (890, 250). Vision finds two subjects.
    static func twoShapes() -> CGImage {
        draw(width: 1200, height: 800) { context in
            context.setFillColor(CGColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.25, alpha: 1))
            context.fillEllipse(in: CGRect(x: 160, y: 120, width: 280, height: 280))
            context.setFillColor(CGColor(srgbRed: 0.15, green: 0.3, blue: 0.85, alpha: 1))
            context.fill(CGRect(x: 760, y: 420, width: 260, height: 260))
        }
    }

    /// The disc's and the square's centres, 0–1 from the top-left.
    static let discCentre = CGPoint(x: 300.0 / 1200, y: 540.0 / 800)
    static let squareCentre = CGPoint(x: 890.0 / 1200, y: 250.0 / 800)
    static let backgroundPoint = CGPoint(x: 600.0 / 1200, y: 400.0 / 800)

    /// 600 × 400 white: a green toggle track (300 × 120) with its white knob
    /// (100 px) on the right: the white-on-white case Fill holes exists for.
    /// The knob's centre is 3/4 across and halfway down the cutout.
    static func toggle() -> CGImage {
        draw(width: 600, height: 400) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
            context.addPath(CGPath(roundedRect: CGRect(x: 150, y: 140, width: 300, height: 120),
                                   cornerWidth: 60, cornerHeight: 60, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1))
            context.fillPath()
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 340, y: 150, width: 100, height: 100))
        }
    }

    /// One flat colour.
    static func flat(width: Int = 600, height: Int = 400, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A red-to-blue gradient (Vision throws `requestCancelled` on it on macOS 27.2).
    static func gradient() -> CGImage {
        draw(width: 600, height: 400) { context in
            let gradient = CGGradient(colorsSpace: sRGB,
                                      colors: [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                               CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)] as CFArray,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 600, y: 0), options: [])
        }
    }

    /// A window capture: a light grey rounded rect (radius 40) on transparent,
    /// with dark text-like bars; Vision finds no subject.
    static func window(width: Int = 800, height: Int = 500) -> CGImage {
        draw(width: width, height: height) { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 40, cornerHeight: 40, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1))
            context.fillPath()
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 40, y: height - 80, width: 300, height: 30))
            context.fill(CGRect(x: 40, y: height - 140, width: 500, height: 14))
            context.fill(CGRect(x: 40, y: height - 170, width: 460, height: 14))
        }
    }

    static func loaded(_ image: CGImage, pixelsPerPoint: Double = 2) -> LoadedCapture {
        LoadedCapture(image: image, pixelsPerPoint: pixelsPerPoint)
    }

    /// A OneComponent32Float buffer whose rows are `rowPadding` bytes longer
    /// than needed (so code must use the real bytes per row). `value(x, y)`
    /// gives each pixel, y = 0 being the top row.
    static func maskBuffer(width: Int = 512, height: Int = 512, rowPadding: Int = 64,
                           _ value: (Int, Int) -> Float) -> CVPixelBuffer {
        let rowBytes = width * 4 + rowPadding
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
        for y in 0..<height {
            let row = (bytes + y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width { row[x] = value(x, y) }
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreateWithBytes(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent32Float,
                                     bytes, rowBytes, { _, base in base?.deallocate() }, nil, nil, &buffer)
        return buffer!
    }

    /// Premultiplied RGBA bytes at (x, y), y = 0 the top row, read in sRGB.
    static func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        TestImages.rgba(of: image, x: x, y: y)
    }
}
