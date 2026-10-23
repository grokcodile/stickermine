import Foundation

/// Style parameters in pixels, scaled linearly with the sticker's pixel size
/// from the spec's values per 800 px (spec section 8). Pure math: M3's style
/// rendering and the layer shadow read these.
struct StyleParameters: Equatable {
    /// Outline/Puffy white rim radius r (12 px per 800).
    let rimRadius: Double
    /// SDF closing distance s for a smoother die-cut line (10 px per 800).
    let closing: Double
    /// Layer-shadow blur radius (10 px per 800).
    let shadowRadius: Double
    /// Downward layer-shadow offset (0.6 × the radius).
    let shadowOffset: Double
    /// Layer-shadow opacity (0.35 at every size).
    let shadowOpacity: Double
    /// None's edge choke blur σ = 0.5 × (source long side / 512).
    let chokeSigma: Double

    static let referenceLongSide = 800.0
    static let rimRadiusPerReference = 12.0
    static let closingPerReference = 10.0
    static let shadowRadiusPerReference = 10.0
    static let shadowOffsetPerRadius = 0.6
    static let shadowOpacityValue = 0.35
    static let chokeSigmaPer512 = 0.5

    /// `longSide`: the sticker's on-screen long side in pixels (points × scale ×
    /// backing scale). `sourceLongSide`: the master's long side in pixels.
    static func forStickerPixels(longSide: Double, sourceLongSide: Double) -> StyleParameters {
        let factor = max(longSide, 0) / referenceLongSide
        let shadowRadius = shadowRadiusPerReference * factor
        return StyleParameters(
            rimRadius: rimRadiusPerReference * factor,
            closing: closingPerReference * factor,
            shadowRadius: shadowRadius,
            shadowOffset: shadowOffsetPerRadius * shadowRadius,
            shadowOpacity: shadowOpacityValue,
            chokeSigma: chokeSigmaPer512 * max(sourceLongSide, 0) / 512
        )
    }

    /// The transparent padding on every side of the sticker's window, in
    /// pixels: ceil(3 × shadow radius) + |offset|, and 0 for None, which has no
    /// shadow (spec section 9).
    func shadowMargin(for style: StickerStyle) -> Double {
        switch style {
        case .none:
            return 0
        case .puffy, .outline, .shadow:
            return (3 * shadowRadius).rounded(.up) + abs(shadowOffset)
        }
    }
}
