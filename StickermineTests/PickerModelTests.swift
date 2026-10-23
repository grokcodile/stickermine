import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

/// The picker's rules (spec section 7) and its previews.
@MainActor
struct PickerModelTests {
    // MARK: Selection

    @Test func subjectsStartSelectedWithWholeImageOff() {
        let state = PickerState(subjects: [1, 2, 3])
        #expect(state.selected == [1, 2, 3])
        #expect(!state.wholeImage)
        #expect(!state.wholeImageLocked)
    }

    @Test func withoutSubjectsWholeImageIsOnAndLocked() {
        var state = PickerState(subjects: [])
        #expect(state.wholeImage)
        #expect(state.wholeImageLocked)
        state.setWholeImage(false)
        #expect(state.wholeImage)
        state.click(subject: 1)
        #expect(state.wholeImage)
        #expect(state.selected.isEmpty)
    }

    @Test func turningWholeImageOnDeselectsEverySubject() {
        var state = PickerState(subjects: [1, 2])
        state.setWholeImage(true)
        #expect(state.wholeImage)
        #expect(state.selected.isEmpty)
    }

    @Test func turningWholeImageOffSelectsEverySubjectAgain() {
        var state = PickerState(subjects: [1, 2])
        state.setWholeImage(true)
        state.setWholeImage(false)
        #expect(!state.wholeImage)
        #expect(state.selected == [1, 2])
    }

    @Test func clickingASubjectWhileWholeImageIsOnSelectsOnlyThatSubject() {
        var state = PickerState(subjects: [1, 2, 3])
        state.setWholeImage(true)
        state.click(subject: 2)
        #expect(!state.wholeImage)
        #expect(state.selected == [2])
    }

    @Test func clickingTogglesAndDeselectingTheLastTurnsWholeImageOn() {
        var state = PickerState(subjects: [1, 2])
        state.click(subject: 1)
        #expect(state.selected == [2])
        state.click(subject: 1)
        #expect(state.selected == [1, 2])
        state.click(subject: 1)
        state.click(subject: 2)
        #expect(state.selected.isEmpty)
        #expect(state.wholeImage)
    }

    @Test func backgroundAndUnknownClicksChangeNothing() {
        var state = PickerState(subjects: [1, 2])
        state.click(subject: nil)
        state.click(subject: 7)
        #expect(state == PickerState(subjects: [1, 2]))
    }

    // MARK: Fill holes

    @Test func untouchedFillHolesUsesEachStylesDefault() {
        let state = PickerState(subjects: [1])
        #expect(state.fillHolesChoice == nil)
        #expect(state.fillHoles(for: .puffy))
        #expect(state.fillHoles(for: .outline))
        #expect(!state.fillHoles(for: .shadow))
        #expect(!state.fillHoles(for: .none))
        #expect(state.source(for: .puffy) == .subjects([1], fillHoles: true))
        #expect(state.source(for: .none) == .subjects([1], fillHoles: false))
    }

    @Test func theToggleShowsAutoOrTheHoveredPreviewsDefault() {
        var state = PickerState(subjects: [1])
        #expect(state.fillHolesDisplay == .auto)
        state.hover(.outline, inside: true)
        #expect(state.fillHolesDisplay == .on)
        state.hover(.shadow, inside: true)
        #expect(state.fillHolesDisplay == .off)
        state.hover(.outline, inside: false)     // a late exit from another preview
        #expect(state.fillHolesDisplay == .off)
        state.hover(.shadow, inside: false)
        #expect(state.fillHolesDisplay == .auto)
    }

    @Test func onceTouchedFillHolesAppliesToEveryStyle() {
        var state = PickerState(subjects: [1])
        state.toggleFillHoles()
        #expect(state.fillHolesChoice == true)
        #expect(StickerStyle.allCases.allSatisfy { state.fillHoles(for: $0) })
        state.hover(.none, inside: true)
        #expect(state.fillHolesDisplay == .on)
        state.toggleFillHoles()
        #expect(StickerStyle.allCases.allSatisfy { !state.fillHoles(for: $0) })
        #expect(state.fillHolesDisplay == .off)
    }

    @Test func fillHolesIsDisabledWhileWholeImageIsOn() {
        var state = PickerState(subjects: [1])
        state.setWholeImage(true)
        #expect(!state.fillHolesEnabled)
        state.toggleFillHoles()
        #expect(state.fillHolesChoice == nil)
        #expect(StickerStyle.allCases.allSatisfy { state.source(for: $0) == .wholeImage })
    }

    // MARK: Previews

    /// Records which cutouts were asked for.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [CutoutSource] = []

        func add(_ source: CutoutSource) {
            lock.lock()
            list.append(source)
            lock.unlock()
        }

        var sources: [CutoutSource] {
            lock.lock()
            defer { lock.unlock() }
            return list
        }
    }

    static func model(subjects: [Int] = [1, 2], calls: Calls, renderer: StyleRenderer) -> PickerModel {
        PickerModel(mode: .capture, subjects: subjects, pixelsPerPoint: 2, renderer: renderer, backingScale: 2,
                    subjectAt: { $0.x < 0.5 ? 1 : 2 },
                    makeCutout: { source in
                        calls.add(source)
                        return Masters.disc(diameter: 200)
                    })
    }

    static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    @Test func previewsRenderInUIOrderFromOneCutoutPerFillHolesValue() async {
        let calls = Calls()
        let model = Self.model(calls: calls, renderer: StyleRenderer(masterProvider: { _ in nil }))
        defer { model.finish() }
        #expect(await Self.waitUntil { model.previews.count == 4 })
        #expect(model.renderOrder == StickerStyle.allCases)
        #expect(Set(calls.sources) == [.subjects([1, 2], fillHoles: true), .subjects([1, 2], fillHoles: false)])
        #expect(calls.sources.count == 2)
        // Puffy and Outline share one cutout, Shadow and None the other.
        let ids = StickerStyle.allCases.map { model.previews[$0]?.request.sticker }
        #expect(ids[0] == ids[1] && ids[2] == ids[3] && ids[0] != ids[2])
        // 200 px at 2 px/pt is 100 pt, fitted into the 84 pt box.
        #expect(model.previews[.none]?.request.pointSize == CGSize(width: 84, height: 84))
    }

    @Test func confirmingUsesThatStylesCutoutAndID() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls, renderer: StyleRenderer(masterProvider: { _ in nil }))
        defer { model.finish() }
        #expect(await Self.waitUntil { model.previews.count == 4 })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        model.confirm(.shadow)
        #expect(await Self.waitUntil { confirmed != nil })
        let confirmation = try #require(confirmed)
        #expect(confirmation.style == .shadow)
        #expect(confirmation.sticker == model.previews[.shadow]?.request.sticker)
        #expect(confirmation.image?.width == 200)
        #expect(confirmation.pixelsPerPoint == 2)
        #expect(model.isConfirming)
        model.confirm(.puffy)   // ignored: already confirming
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(confirmed?.style == .shadow)
    }

    @Test func selectionChangesAreDebounced() async {
        let calls = Calls()
        let model = Self.model(calls: calls, renderer: StyleRenderer(masterProvider: { _ in nil }))
        defer { model.finish() }
        #expect(await Self.waitUntil { model.previews.count == 4 })
        let before = calls.sources.count
        model.clickSubject(atUnitTopLeft: CGPoint(x: 0.2, y: 0.5))   // deselect 1
        model.clickSubject(atUnitTopLeft: CGPoint(x: 0.2, y: 0.5))   // select 1 again
        model.clickSubject(atUnitTopLeft: CGPoint(x: 0.8, y: 0.5))   // deselect 2
        #expect(model.state.selected == [1])
        #expect(await Self.waitUntil { model.previews[.none]?.request.sticker != nil && calls.sources.count == before + 2 })
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Only the final selection was cut out, once per Fill holes value.
        #expect(Array(calls.sources.dropFirst(before)).allSatisfy {
            $0 == .subjects([1], fillHoles: true) || $0 == .subjects([1], fillHoles: false)
        })
        #expect(calls.sources.count == before + 2)
    }

    @Test func finishingLetsGoOfEveryCutoutButTheConfirmedOne() async throws {
        let calls = Calls()
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let model = Self.model(calls: calls, renderer: renderer)
        #expect(await Self.waitUntil { model.previews.count == 4 })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        model.confirm(.outline)
        #expect(await Self.waitUntil { confirmed != nil })
        model.finish()
        let kept = try #require(confirmed?.sticker)
        let dropped = try #require(model.previews[.none]?.request.sticker)
        let size = CGSize(width: 20, height: 20)
        _ = try await renderer.render(RenderRequest(sticker: kept, style: .none, flipped: false, rotation: 0,
                                                    pointSize: size, backingScale: 1))
        await #expect(throws: StyleRenderer.RenderError.missingMaster) {
            _ = try await renderer.render(RenderRequest(sticker: dropped, style: .none, flipped: false, rotation: 0,
                                                        pointSize: size, backingScale: 1))
        }
        renderer.setInFlightMaster(nil, for: kept)
    }

    @Test func aCutoutThatFinishesAfterThePickerClosedIsNotKept() async {
        let calls = Calls()
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let model = PickerModel(mode: .capture, subjects: [1], pixelsPerPoint: 2, renderer: renderer, backingScale: 2,
                                makeCutout: { source in
                                    calls.add(source)
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    return Masters.disc(diameter: 200)
                                })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        #expect(await Self.waitUntil { !calls.sources.isEmpty })
        model.confirm(.puffy)   // waits for the cutout still being computed
        model.finish()          // Esc before it is ready
        try? await Task.sleep(nanoseconds: 600_000_000)
        // Neither the preview's cutout nor the confirmed one stays registered,
        // and the session never hears of a confirmation after it ended.
        #expect(renderer.inFlightMasterCount == 0)
        #expect(confirmed == nil)

        // Pressing 1 while Shadow and None's cutout (Fill holes off) is still
        // computing: the session closes the picker on confirm, and only the
        // confirmed cutout stays registered.
        let slow = Calls()
        let otherRenderer = StyleRenderer(masterProvider: { _ in nil })
        let other = PickerModel(mode: .capture, subjects: [1], pixelsPerPoint: 2, renderer: otherRenderer, backingScale: 2,
                                makeCutout: { source in
                                    slow.add(source)
                                    if source == .subjects([1], fillHoles: false) {
                                        try? await Task.sleep(nanoseconds: 300_000_000)
                                    }
                                    return Masters.disc(diameter: 200)
                                })
        var placed: PickerModel.Confirmation?
        other.onConfirm = { [weak other] confirmation in
            placed = confirmation
            other?.finish()   // what SessionCoordinator's closePicker() does
        }
        #expect(await Self.waitUntil { slow.sources.contains(.subjects([1], fillHoles: false)) })
        other.confirm(.puffy)
        #expect(await Self.waitUntil { placed != nil })
        try? await Task.sleep(nanoseconds: 600_000_000)
        #expect(otherRenderer.inFlightMasterCount == 1)
        if let placed { otherRenderer.setInFlightMaster(nil, for: placed.sticker) }
        #expect(otherRenderer.inFlightMasterCount == 0)
    }

    @Test func rePlacingRendersTheStoredMasterUnderTheStickersID() async throws {
        let record = Fixtures.sticker(width: 50, height: 50)
        let renderer = StyleRenderer(masterProvider: { $0 == record.id ? Masters.square(side: 100) : nil })
        let model = PickerModel.forRestyle(record, renderer: renderer, backingScale: 2)
        defer { model.finish() }
        #expect(model.highlightedStyle == .outline)
        #expect(model.displayImage == nil)
        #expect(await Self.waitUntil { model.previews.count == 4 })
        #expect(StickerStyle.allCases.allSatisfy { model.previews[$0]?.request.sticker == record.id })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        model.confirm(.none)
        #expect(await Self.waitUntil { confirmed != nil })
        #expect(confirmed?.sticker == record.id)
        #expect(confirmed?.image == nil)
    }
}
