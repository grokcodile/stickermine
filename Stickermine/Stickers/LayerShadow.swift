import CoreGraphics

/// A drop shadow drawn by Core Animation on the sticker's content layer, never
/// baked into the bitmap: a baked blur would catch clicks across its whole faint
/// tail, a layer shadow doesn't (spec section 8). All values are in points.
struct LayerShadow: Equatable {
    var radius: CGFloat
    var opacity: Float
    /// Downward offset on screen.
    var offset: CGFloat

    /// Transparent padding on every side of the sticker rect so the shadow is
    /// never clipped by the window (spec section 9).
    var margin: CGFloat { ceil(3 * radius) + abs(offset) }
}
