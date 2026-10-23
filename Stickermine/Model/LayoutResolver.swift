import CoreGraphics
import Foundation

/// A display's size in points, from `NSScreen.frame.size`. Its `key`
/// ("1920x1080") is how poses are stored (spec section 11).
struct DisplaySize: Hashable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Parses "WxH"; nil for anything else (including zero or negative sides).
    init?(key: String) {
        let parts = key.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]),
              width > 0, height > 0
        else { return nil }
        self.init(width: width, height: height)
    }

    /// `Int(w)` × `Int(h)`, exactly as the spec writes the key.
    init(_ size: CGSize) {
        self.init(width: Int(size.width), height: Int(size.height))
    }

    var key: String { "\(width)x\(height)" }

    /// Square sizes count as landscape.
    var isLandscape: Bool { width >= height }

    var area: Double { Double(width) * Double(height) }
}

/// The pose-for-current-size rule (spec section 11). Pure: it never writes;
/// a borrowed pose is only saved when a user edit writes it.
enum LayoutResolver {
    /// Distances closer than this are a tie.
    static let tieTolerance = 1e-9

    /// `poses[size]` when stored; otherwise the pose of the closest stored size
    /// (same orientation first, then the smallest |ln(wB/wA)| + |ln(hB/hA)|; on a
    /// tie the larger area, then the lexicographically smaller key), keeping x and
    /// y and multiplying scale by min(wB/wA, hB/hA). nil when nothing is stored.
    static func pose(for placement: Placement, at size: DisplaySize) -> Pose? {
        if let exact = placement.poses[size.key] { return exact }
        guard let source = closestStoredSize(in: placement.poses, to: size),
              let pose = placement.poses[source.key]
        else { return nil }
        let factor = min(Double(size.width) / Double(source.width),
                         Double(size.height) / Double(source.height))
        return Pose(x: pose.x, y: pose.y, scale: pose.scale * factor)
    }

    /// The stored size `pose(for:at:)` borrows from (unparsable keys are ignored).
    /// Candidates are sorted by key first, so dictionary order never matters.
    static func closestStoredSize(in poses: [String: Pose], to size: DisplaySize) -> DisplaySize? {
        let candidates = poses.keys.sorted().compactMap(DisplaySize.init(key:))
        let sameOrientation = candidates.filter { $0.isLandscape == size.isLandscape }
        let pool = sameOrientation.isEmpty ? candidates : sameOrientation
        return pool.min { isCloser($0, than: $1, to: size) }
    }

    /// |ln(wB/wA)| + |ln(hB/hA)|.
    static func distance(from source: DisplaySize, to target: DisplaySize) -> Double {
        abs(log(Double(target.width) / Double(source.width)))
            + abs(log(Double(target.height) / Double(source.height)))
    }

    static func isCloser(_ a: DisplaySize, than b: DisplaySize, to target: DisplaySize) -> Bool {
        let da = distance(from: a, to: target)
        let db = distance(from: b, to: target)
        if abs(da - db) >= tieTolerance { return da < db }
        if a.area != b.area { return a.area > b.area }
        return a.key < b.key
    }

    /// A move or scale at `size`: writes only `poses[size]` (creating it when
    /// the pose was borrowed).
    static func writing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement {
        // A NaN or infinity in library.json makes every later save throw, so a
        // non-finite pose leaves the placement as it was.
        guard pose.isFinite else { return placement }
        var result = placement
        result.poses[size.key] = pose
        return result
    }

    /// A placement (fresh, re-placed or dropped on another display): `poses = [size: pose]`.
    static func placing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement {
        // A NaN or infinity in library.json makes every later save throw, so a
        // non-finite pose leaves the placement as it was.
        guard pose.isFinite else { return placement }
        var result = placement
        result.poses = [size.key: pose]
        return result
    }
}

extension Pose {
    /// All three values are finite numbers (JSON can't store NaN or infinity).
    var isFinite: Bool { x.isFinite && y.isFinite && scale.isFinite }
}
