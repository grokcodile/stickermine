import CoreGraphics
import CoreVideo

/// Maps a click to a subject on Vision's per-instance coverage masks (spec
/// section 6.2): `generateMask(for: [i])` returns a 512 × 512
/// OneComponent32Float buffer with rows top-down, whatever the image's aspect
/// ratio. Pure: no AppKit, no Vision.
enum MaskSampler {
    /// Coverage above this counts as the subject.
    static let threshold: Float = 0.5

    /// The instance whose coverage at `p` (0–1, top-left origin) is above 0.5,
    /// the highest when masks overlap; nil means background.
    static func subject(atUnitTopLeft p: CGPoint, masks: [(index: Int, mask: CVPixelBuffer)]) -> Int? {
        var best: (index: Int, value: Float)?
        for entry in masks {
            guard let value = value(in: entry.mask, atUnitTopLeft: p), value > threshold else { continue }
            if best == nil || value > best!.value { best = (entry.index, value) }
        }
        return best?.index
    }

    /// The coverage at `p` (0–1, top-left origin): row = Int(v × height),
    /// col = Int(u × width), read with the buffer's own bytes per row. nil for
    /// a point outside 0–1 or a buffer that isn't OneComponent32Float.
    static func value(in buffer: CVPixelBuffer, atUnitTopLeft p: CGPoint) -> Float? {
        guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
        else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let row = min(height - 1, Int(p.y * CGFloat(height)))
        let col = min(width - 1, Int(p.x * CGFloat(width)))
        let rowStart = base + row * CVPixelBufferGetBytesPerRow(buffer)
        return rowStart.assumingMemoryBound(to: Float.self)[col]
    }

    /// The unit rect (top-left origin) of the pixels above the threshold; nil
    /// when there are none.
    static func bounds(of buffer: CVPixelBuffer) -> CGRect? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width where row[x] > threshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width),
                      height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }
}
