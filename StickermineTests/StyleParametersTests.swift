import Testing
@testable import Stickermine

struct StyleParametersTests {
    @Test func theSpecValuesAt800Pixels() {
        let p = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 512)
        #expect(p.rimRadius == 12)
        #expect(p.closing == 10)
        #expect(p.shadowRadius == 10)
        #expect(p.shadowOffset == 6)
        #expect(p.shadowOpacity == 0.35)
        #expect(p.chokeSigma == 0.5)
    }

    @Test func sizesScaleLinearlyWithThePixelSize() {
        let base = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 1000)
        let double = StyleParameters.forStickerPixels(longSide: 1600, sourceLongSide: 1000)
        let half = StyleParameters.forStickerPixels(longSide: 400, sourceLongSide: 1000)
        #expect(double.rimRadius == 2 * base.rimRadius)
        #expect(double.closing == 2 * base.closing)
        #expect(double.shadowRadius == 2 * base.shadowRadius)
        #expect(double.shadowOffset == 2 * base.shadowOffset)
        #expect(half.rimRadius == base.rimRadius / 2)
        #expect(half.shadowRadius == base.shadowRadius / 2)
        // Opacity and the choke (which follows the source) don't change with on-screen size.
        #expect(double.shadowOpacity == base.shadowOpacity)
        #expect(double.chokeSigma == base.chokeSigma)
    }

    @Test func theChokeFollowsTheSourceLongSide() {
        #expect(StyleParameters.forStickerPixels(longSide: 300, sourceLongSide: 1024).chokeSigma == 1)
        #expect(StyleParameters.forStickerPixels(longSide: 300, sourceLongSide: 2048).chokeSigma == 2)
    }

    @Test func shadowMarginIsCeilThreeRadiiPlusTheOffsetExceptForNone() {
        let at800 = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 512)
        #expect(at800.shadowMargin(for: .puffy) == 36)        // ceil(30) + 6
        #expect(at800.shadowMargin(for: .outline) == 36)
        #expect(at800.shadowMargin(for: .shadow) == 36)
        #expect(at800.shadowMargin(for: .none) == 0)
        let at1000 = StyleParameters.forStickerPixels(longSide: 1000, sourceLongSide: 512)
        #expect(at1000.shadowMargin(for: .shadow) == 45.5)    // ceil(37.5) + 7.5
    }

    @Test func aZeroSizedStickerHasZeroParameters() {
        let p = StyleParameters.forStickerPixels(longSide: 0, sourceLongSide: 0)
        #expect(p.rimRadius == 0)
        #expect(p.shadowMargin(for: .puffy) == 0)
    }

    @Test func theRimReachesItsRadiusRoundedUpPlusAPixelForRimmedStylesOnly() {
        let at800 = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 512)
        #expect(at800.rimReach(for: .puffy) == 13)
        #expect(at800.rimReach(for: .outline) == 13)
        #expect(at800.rimReach(for: .shadow) == 0)
        #expect(at800.rimReach(for: .none) == 0)
        let at100 = StyleParameters.forStickerPixels(longSide: 100, sourceLongSide: 512)
        #expect(at100.rimReach(for: .outline) == 3)          // ceil(1.5) + 1
    }

    @Test func theDomeRadiusIsHalfTheInscribedRadiusClampedPer800Pixels() {
        #expect(StyleParameters.domeRadius(inscribedRadius: 100, longSide: 800) == 50)
        #expect(StyleParameters.domeRadius(inscribedRadius: 4, longSide: 800) == 6)       // at least 6 per 800
        #expect(StyleParameters.domeRadius(inscribedRadius: 1000, longSide: 800) == 300)  // at most 300 per 800
        #expect(StyleParameters.domeRadius(inscribedRadius: 4, longSide: 1600) == 12)
        // Linear in size: twice the sticker, twice the dome.
        for inscribed in [2.0, 60, 250, 900] {
            #expect(StyleParameters.domeRadius(inscribedRadius: 2 * inscribed, longSide: 1600)
                    == 2 * StyleParameters.domeRadius(inscribedRadius: inscribed, longSide: 800))
        }
        #expect(StyleParameters.domeHeightPerRadius == 0.9)
    }
}
