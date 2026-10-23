import CoreGraphics
import Foundation
import Testing
import Vision
@testable import Stickermine

/// Vision on generated captures (spec sections 6 and 18).
struct CutoutEngineTests {
    @Test func twoShapesAreTwoSubjectsFoundWhereTheyAre() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        #expect(analysis.subjectIndices.count == 2)
        #expect(!analysis.subjectIndices.contains(0))
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        let square = try #require(analysis.subject(atUnitTopLeft: CaptureImages.squareCentre))
        #expect(disc != square)
        #expect(analysis.subject(atUnitTopLeft: CaptureImages.backgroundPoint) == nil)
        #expect(analysis.displayImage.width == 1024)
    }

    @Test func aSmallSelectionIsRefinedCutOutAndCroppedWithItsColours() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        let cutout = try await analysis.cutout(selection: [disc], fillHoles: false)
        #expect(analysis.refinedCutoutCount == 1)
        // The 280 px disc plus 2 px on each side, give or take Vision's edge.
        #expect(abs(cutout.width - 284) <= 8)
        #expect(abs(cutout.height - 284) <= 8)
        let centre = CaptureImages.rgba(cutout, x: cutout.width / 2, y: cutout.height / 2)
        #expect(centre[3] == 255)
        #expect(abs(Int(centre[0]) - 230) <= 2 && abs(Int(centre[1]) - 51) <= 2 && abs(Int(centre[2]) - 64) <= 2)
        // The disc's box corner is background: cut away.
        #expect(CaptureImages.rgba(cutout, x: 3, y: 3)[3] == 0)
        #expect(cutout.colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test func aLargeSelectionSkipsPassTwo() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        let cutout = try await analysis.cutout(selection: Set(analysis.subjectIndices), fillHoles: false)
        #expect(analysis.refinedCutoutCount == 0)
        // Both shapes: x 160–1020, y 120–680 from the top, plus 2 px, plus the
        // soft edge of a 512 px mask stretched over 1200 px.
        #expect(abs(cutout.width - 864) <= 16)
        #expect(abs(cutout.height - 564) <= 16)
    }

    @Test func fillHolesClosesAWhiteKnobOnAWhiteBackground() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.toggle()))
        let selection = Set(analysis.subjectIndices)
        #expect(!selection.isEmpty)
        let plain = try await analysis.cutout(selection: selection, fillHoles: false)
        let filled = try await analysis.cutout(selection: selection, fillHoles: true)
        #expect(filled.width == plain.width && filled.height == plain.height)
        let knob = (x: plain.width * 3 / 4, y: plain.height / 2)
        #expect(CaptureImages.rgba(plain, x: knob.x, y: knob.y)[3] == 0)      // Vision cut the knob out
        #expect(CaptureImages.rgba(filled, x: knob.x, y: knob.y)[3] == 255)   // Fill holes put it back
        #expect(CaptureImages.rgba(filled, x: 0, y: 0)[3] == 0)               // the outside stays clear
    }

    @Test func flatColoursHaveNoSubject() async {
        let engine = CutoutEngine()
        for image in [CaptureImages.flat(red: 0.1, green: 0.3, blue: 0.9),
                      CaptureImages.flat(red: 1, green: 1, blue: 1),
                      CaptureImages.gradient()] {
            let analysis = await engine.analyze(CaptureImages.loaded(image))
            #expect(analysis.subjectIndices.isEmpty)
        }
    }

    @Test func aThrownErrorOrNilMeansNoSubject() async {
        let throwing = CutoutEngine(perform: { _ in throw VisionError.requestCancelled("test") })
        #expect(await throwing.analyze(CaptureImages.loaded(CaptureImages.twoShapes())).subjectIndices.isEmpty)
        let empty = CutoutEngine(perform: { _ in nil })
        let analysis = await empty.analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        #expect(analysis.subjectIndices.isEmpty)
        // With no subject, a cutout is refused and the whole image still works.
        await #expect(throws: CutoutError.self) { try await analysis.cutout(selection: [1], fillHoles: false) }
        #expect(analysis.wholeImage().width == 1200)
    }

    @Test func theWholeImageKeepsItsAlphaAndRoundsItsCorners() {
        let window = CaptureImages.window()
        let whole = CutoutAnalysis(capture: CaptureImages.loaded(window), handler: nil, observation: nil, masks: [],
                                   context: CutoutEngine().context, perform: CutoutEngine.vision).wholeImage()
        #expect(whole.width == 800)
        #expect(whole.height == 500)
        #expect(CaptureImages.rgba(whole, x: 2, y: 2)[3] == 0)          // the window's own transparent corner
        #expect(CaptureImages.rgba(whole, x: 400, y: 250)[3] == 255)
        #expect(CaptureImages.rgba(whole, x: 1, y: 250)[3] == 255)      // 4% of 500 = 20 < the window's 40

        let opaque = CaptureImages.flat(red: 0.5, green: 0.5, blue: 0.5)   // 600 × 400: radius 16
        let rounded = CutoutAnalysis(capture: CaptureImages.loaded(opaque), handler: nil, observation: nil, masks: [],
                                     context: CutoutEngine().context, perform: CutoutEngine.vision).wholeImage()
        #expect(CaptureImages.rgba(rounded, x: 1, y: 1)[3] == 0)
        #expect(CaptureImages.rgba(rounded, x: 16, y: 16)[3] == 255)
        #expect(CaptureImages.rgba(rounded, x: 0, y: 200)[3] == 255)
    }

    @Test func emptySelectionsTheBackgroundAndReleasedAnalysesAreRefused() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        await #expect(throws: CutoutError.emptySelection) { try await analysis.cutout(selection: [], fillHoles: false) }
        await #expect(throws: CutoutError.emptySelection) { try await analysis.cutout(selection: [0], fillHoles: true) }
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        analysis.release()
        await #expect(throws: CutoutError.released) { try await analysis.cutout(selection: [disc], fillHoles: false) }
        #expect(analysis.subject(atUnitTopLeft: CaptureImages.discCentre) == nil)
    }

    @Test func highlightMasksShowEachSubjectsCoverage() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        let mask = try #require(analysis.highlightMask(for: disc))
        #expect(mask.width == 512 && mask.height == 512)
        #expect(CaptureImages.rgba(mask, x: Int(CaptureImages.discCentre.x * 512), y: Int(CaptureImages.discCentre.y * 512))[3] > 200)
        #expect(CaptureImages.rgba(mask, x: Int(CaptureImages.squareCentre.x * 512), y: Int(CaptureImages.squareCentre.y * 512))[3] == 0)
    }

    @Test func passTwoIsForBoxesUnderSixtyPercentOfTheLongSide() {
        #expect(CutoutAnalysis.refines(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), width: 1000, height: 1000))
        #expect(!CutoutAnalysis.refines(CGRect(x: 0, y: 0, width: 0.6, height: 0.1), width: 1000, height: 1000))
        // A tall box on a wide capture: 0.9 × 500 = 450 px < 0.6 × 1000.
        #expect(CutoutAnalysis.refines(CGRect(x: 0, y: 0, width: 0.1, height: 0.9), width: 1000, height: 500))
    }
}
