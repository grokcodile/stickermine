import Combine
import CoreGraphics
import Foundation
import os

/// Where a preview's pixels, and the confirmed sticker's master, come from.
enum CutoutSource: Hashable {
    /// The whole capture, alpha kept, corners rounded.
    case wholeImage
    /// The selected subjects, with or without Fill holes.
    case subjects(Set<Int>, fillHoles: Bool)
    /// Re-placing from history: the sticker's own master in the library.
    case stored
}

/// The picker's selection and Fill holes rules (spec section 7), as a value.
/// Pure: the panel and the tests drive it the same way.
struct PickerState: Equatable {
    /// What the Fill holes control shows.
    enum FillHolesDisplay: Equatable {
        case auto, on, off
    }

    /// Vision's subject indices, ascending.
    let subjects: [Int]
    private(set) var selected: Set<Int>
    private(set) var wholeImage: Bool
    /// nil until the user touches Fill holes; then it applies to every preview.
    private(set) var fillHolesChoice: Bool?
    /// The style preview under the mouse.
    private(set) var hovered: StickerStyle?

    /// With subjects, all start selected and Whole image starts off; with none,
    /// Whole image is on and locked.
    init(subjects: [Int]) {
        self.subjects = subjects
        selected = Set(subjects)
        wholeImage = subjects.isEmpty
    }

    var wholeImageLocked: Bool { subjects.isEmpty }
    /// Fill holes is disabled while Whole image is on.
    var fillHolesEnabled: Bool { !wholeImage }

    /// Turning Whole image on deselects every subject; turning it off selects
    /// them all again (a selection can't be empty with Whole image off).
    mutating func setWholeImage(_ on: Bool) {
        guard !wholeImageLocked, on != wholeImage else { return }
        wholeImage = on
        selected = on ? [] : Set(subjects)
    }

    /// A click on the capture. While Whole image is on, a subject turns it off
    /// and becomes the only selection; otherwise it toggles, and deselecting
    /// the last subject turns Whole image on. nil (background) does nothing.
    mutating func click(subject: Int?) {
        guard let subject, subjects.contains(subject) else { return }
        if wholeImage {
            wholeImage = false
            selected = [subject]
        } else if selected.contains(subject) {
            selected.remove(subject)
            if selected.isEmpty { wholeImage = true }
        } else {
            selected.insert(subject)
        }
    }

    /// The first touch turns Fill holes on (out of Auto); later touches flip it.
    mutating func toggleFillHoles() {
        guard fillHolesEnabled else { return }
        fillHolesChoice = !(fillHolesChoice ?? false)
    }

    /// The mouse entered (`inside`) or left a style's preview.
    mutating func hover(_ style: StickerStyle, inside: Bool) {
        if inside {
            hovered = style
        } else if hovered == style {
            hovered = nil
        }
    }

    /// Until touched, each style uses its own default (on for Puffy and
    /// Outline, off for Shadow and None); once touched, the choice.
    func fillHoles(for style: StickerStyle) -> Bool {
        fillHolesChoice ?? style.defaultFillHoles
    }

    /// The choice once touched; until then the hovered preview's default, or Auto.
    var fillHolesDisplay: FillHolesDisplay {
        if let choice = fillHolesChoice { return choice ? .on : .off }
        if let hovered { return hovered.defaultFillHoles ? .on : .off }
        return .auto
    }

    /// The cutout a style's preview (and that style's result) uses.
    func source(for style: StickerStyle) -> CutoutSource {
        wholeImage ? .wholeImage : .subjects(selected, fillHoles: fillHoles(for: style))
    }
}

/// The picker's model: the rules above plus the cutouts and the four live
/// previews, rendered in UI order through the app's StyleRenderer (spec
/// section 7). A capture's cutouts get in-flight IDs (`StyleRenderer.
/// setInFlightMaster`); the confirmed one's ID becomes the sticker's ID, so the
/// preview is exactly what gets placed. Selection changes are debounced 100 ms.
@MainActor
final class PickerModel: ObservableObject {
    enum Mode: Equatable {
        /// A fresh capture: the capture, subjects, Whole image, Fill holes, styles.
        case capture
        /// Re-placing a sticker from history: only the style row, `highlight`
        /// (its `lastStyle`) highlighted.
        case restyle(sticker: UUID, highlight: StickerStyle)
    }

    /// One rendered preview and the shadow parameters to show it with.
    struct Preview {
        let request: RenderRequest
        let rendered: RenderedSticker
        let shadow: StyleParameters
    }

    /// What confirming a style hands to the session.
    struct Confirmation {
        /// The master's ID: the cutout's in-flight ID for a capture (the new
        /// sticker's ID), the sticker's own ID when re-placing.
        let sticker: UUID
        let style: StickerStyle
        /// The master to save; nil when re-placing.
        let image: CGImage?
        let pixelsPerPoint: Double
    }

    /// A computed cutout under its ID.
    struct Cut {
        let id: UUID
        let pixelSize: CGSize
        let image: CGImage?
    }

    typealias MakeCutout = @Sendable (CutoutSource) async throws -> CGImage

    static let debounce: TimeInterval = 0.1
    /// Previews fit in this box (points), enlarged or reduced.
    static let previewBox = CGSize(width: 84, height: 84)

    let mode: Mode
    let pixelsPerPoint: Double
    /// The capture as shown in the picker (capture mode only).
    let displayImage: CGImage?
    /// Each subject's coverage, for the highlight overlay.
    let highlightMasks: [Int: CGImage]

    @Published private(set) var state: PickerState
    @Published private(set) var previews: [StickerStyle: Preview] = [:]
    @Published private(set) var isConfirming = false
    /// The order previews were rendered in (tests).
    private(set) var renderOrder: [StickerStyle] = []

    var onConfirm: ((Confirmation) -> Void)?

    private let renderer: StyleRenderer
    private let backingScale: CGFloat
    private let storedPixelSize: CGSize
    private let makeCutout: MakeCutout
    private let subjectAt: (CGPoint) -> Int?
    private var cutouts: [CutoutSource: Cut] = [:]
    private var inProgress: [CutoutSource: Task<CGImage?, Never>] = [:]
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var confirmedID: UUID?
    /// Set by `finish()`: a cutout that completes afterwards is dropped, never
    /// registered with the renderer (nothing would clear it again).
    private var isFinished = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "picker")

    init(mode: Mode, subjects: [Int], pixelsPerPoint: Double, storedPixelSize: CGSize = .zero,
         displayImage: CGImage? = nil, highlightMasks: [Int: CGImage] = [:],
         renderer: StyleRenderer, backingScale: CGFloat,
         subjectAt: @escaping (CGPoint) -> Int? = { _ in nil },
         makeCutout: @escaping MakeCutout) {
        self.mode = mode
        self.pixelsPerPoint = pixelsPerPoint
        self.storedPixelSize = storedPixelSize
        self.displayImage = displayImage
        self.highlightMasks = highlightMasks
        self.renderer = renderer
        self.backingScale = backingScale
        self.subjectAt = subjectAt
        self.makeCutout = makeCutout
        state = PickerState(subjects: subjects)
        scheduleRefresh(debounced: false)
    }

    /// The picker for a fresh capture.
    static func forCapture(_ analysis: CutoutAnalysis, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel {
        var masks: [Int: CGImage] = [:]
        for index in analysis.subjectIndices {
            masks[index] = analysis.highlightMask(for: index)
        }
        return PickerModel(
            mode: .capture, subjects: analysis.subjectIndices, pixelsPerPoint: analysis.capture.pixelsPerPoint,
            displayImage: analysis.displayImage, highlightMasks: masks, renderer: renderer,
            backingScale: backingScale, subjectAt: { analysis.subject(atUnitTopLeft: $0) },
            makeCutout: { source in
                switch source {
                case .wholeImage:
                    return analysis.wholeImage()
                case .subjects(let selection, let fillHoles):
                    return try await analysis.cutout(selection: selection, fillHoles: fillHoles)
                case .stored:
                    throw CutoutError.emptySelection
                }
            })
    }

    /// The style-only picker for re-placing `record` from history.
    static func forRestyle(_ record: StickerRecord, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel {
        PickerModel(mode: .restyle(sticker: record.id, highlight: record.lastStyle), subjects: [],
                    pixelsPerPoint: record.pixelsPerPoint,
                    storedPixelSize: CGSize(width: record.pixelWidth, height: record.pixelHeight),
                    renderer: renderer, backingScale: backingScale,
                    makeCutout: { _ in throw CutoutError.emptySelection })
    }

    /// The style highlighted in the style row (re-placing only).
    var highlightedStyle: StickerStyle? {
        if case .restyle(_, let highlight) = mode { return highlight }
        return nil
    }

    // MARK: User actions

    /// A click on the capture at `p` (0–1, top-left origin).
    func clickSubject(atUnitTopLeft p: CGPoint) {
        let before = state
        state.click(subject: subjectAt(p))
        if state != before { scheduleRefresh(debounced: true) }
    }

    func setWholeImage(_ on: Bool) {
        let before = state
        state.setWholeImage(on)
        if state != before { scheduleRefresh(debounced: true) }
    }

    func toggleFillHoles() {
        let before = state
        state.toggleFillHoles()
        if state != before { scheduleRefresh(debounced: false) }
    }

    func hover(_ style: StickerStyle, inside: Bool) {
        state.hover(style, inside: inside)
    }

    /// Clicking a preview or pressing 1–4: hands the style's cutout to
    /// `onConfirm` once it is ready (at once when the preview showed it).
    func confirm(_ style: StickerStyle) {
        guard !isConfirming, !isFinished else { return }
        isConfirming = true
        let source = currentSource(for: style)
        Task { [weak self] in
            guard let self else { return }
            let cut = await self.cutout(for: source)
            // The picker closed (Esc or ×) while the cutout was computed.
            guard !self.isFinished else { return }
            guard let cut else {
                self.log.error("no cutout to confirm for \(style.rawValue, privacy: .public)")
                self.isConfirming = false
                return
            }
            self.confirmedID = cut.id
            self.onConfirm?(Confirmation(sticker: cut.id, style: style, image: cut.image,
                                         pixelsPerPoint: self.pixelsPerPoint))
        }
    }

    /// The picker closed: stops work and lets go of every in-flight master
    /// except the confirmed one (the session clears that after placement).
    /// Cutouts still computing are dropped when they complete.
    func finish() {
        isFinished = true
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        for task in inProgress.values { task.cancel() }
        inProgress = [:]
        for cut in cutouts.values where cut.image != nil && cut.id != confirmedID {
            renderer.setInFlightMaster(nil, for: cut.id)
        }
        cutouts = [:]
    }

    // MARK: Previews

    private func currentSource(for style: StickerStyle) -> CutoutSource {
        if case .restyle = mode { return .stored }
        return state.source(for: style)
    }

    private func scheduleRefresh(debounced: Bool) {
        generation += 1
        let generation = self.generation
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(nanoseconds: UInt64(Self.debounce * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.refresh(generation: generation)
        }
    }

    /// Renders the four previews in UI order, computing each cutout once, and
    /// lets go of cutouts no preview uses any more.
    private func refresh(generation: Int) async {
        let wanted = StickerStyle.allCases.map { ($0, currentSource(for: $0)) }
        let used = Set(wanted.map(\.1))
        for (source, cut) in cutouts where !used.contains(source) {
            if cut.image != nil { renderer.setInFlightMaster(nil, for: cut.id) }
            cutouts[source] = nil
        }
        for (style, source) in wanted {
            guard let cut = await cutout(for: source), generation == self.generation else { return }
            let request = previewRequest(for: cut, style: style)
            if previews[style]?.request == request { continue }
            do {
                let rendered = try await renderer.render(request)
                guard generation == self.generation else { return }
                let shadow = request.onScreenParameters(
                    sourceLongSide: Double(max(cut.pixelSize.width, cut.pixelSize.height)))
                previews[style] = Preview(request: request, rendered: rendered, shadow: shadow)
                renderOrder.append(style)
            } catch {
                log.error("preview \(style.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A source's cutout, computed once (off the main actor) and registered
    /// with the renderer under a new in-flight ID. nil once the picker closed.
    private func cutout(for source: CutoutSource) async -> Cut? {
        guard !isFinished else { return nil }
        if let cut = cutouts[source] { return cut }
        if source == .stored, case .restyle(let sticker, _) = mode {
            let cut = Cut(id: sticker, pixelSize: storedPixelSize, image: nil)
            cutouts[source] = cut
            return cut
        }
        let task: Task<CGImage?, Never>
        if let running = inProgress[source] {
            task = running
        } else {
            let make = makeCutout
            task = Task.detached(priority: .userInitiated) { try? await make(source) }
            inProgress[source] = task
        }
        let image = await task.value
        // finish() ran while this cutout was computed (cancelling can't stop the
        // whole image, or a cutout past its last cancellation check): it has
        // already let go of every in-flight master, so this one must not be
        // registered.
        guard !isFinished else { return nil }
        inProgress[source] = nil
        if let cut = cutouts[source] { return cut }
        guard let image else { return nil }
        let cut = Cut(id: UUID(), pixelSize: CGSize(width: image.width, height: image.height), image: image)
        renderer.setInFlightMaster(image, for: cut.id)
        cutouts[source] = cut
        return cut
    }

    /// The preview's request: the cutout's natural size fitted into `previewBox`.
    private func previewRequest(for cut: Cut, style: StickerStyle) -> RenderRequest {
        let ppp = pixelsPerPoint > 0 ? pixelsPerPoint : 1
        let natural = CGSize(width: cut.pixelSize.width / ppp, height: cut.pixelSize.height / ppp)
        let scale = natural.width > 0 && natural.height > 0
            ? min(Self.previewBox.width / natural.width, Self.previewBox.height / natural.height) : 1
        return RenderRequest(sticker: cut.id, style: style, flipped: false, rotation: 0,
                             pointSize: CGSize(width: natural.width * scale, height: natural.height * scale),
                             backingScale: backingScale)
    }
}
