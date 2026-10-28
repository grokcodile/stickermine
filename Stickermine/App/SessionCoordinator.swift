import AppKit
import os

/// One sticker session at a time (spec section 5.2): from a trigger until the
/// sticker is placed or cancelled. A capture runs the permission check,
/// `screencapture`, the cutout, the picker and placement; re-placing from
/// history starts at the picker. While a session is active every trigger is
/// ignored. Starting one first ends any sticker's editing (discarding a
/// gesture); a capture started from Home orders Home out before screencapture
/// runs. When it ends, focus returns to the app that was frontmost before.
@MainActor
final class SessionCoordinator {
    enum Stage: Equatable {
        case idle, capturing, analyzing, picking, saving, placing
    }

    private(set) var stage: Stage = .idle
    var isActive: Bool { stage != .idle }
    /// Called with true when a session starts and false when it ends.
    var onActiveChange: ((Bool) -> Void)?
    /// A placement click of `sticker` made `placement` (M6 counts these for
    /// the support ask).
    var onPlaced: ((_ placement: UUID, _ sticker: UUID) -> Void)?
    /// The sticker this session works on, once known: the re-placed sticker,
    /// or a fresh one once it is saved. Delete from History cancels the
    /// session when it is the one being deleted (M6).
    private(set) var currentSticker: UUID?

    private let capture: CaptureService
    private let cutout: CutoutEngine
    private let stickers: StickerManager
    private let library: LibraryController
    private let store: LibraryStore
    private let renderer: StyleRenderer
    private let screens: ScreenProvider
    private let access: ScreenRecordingAccess
    private let showMessage: (String) -> Void
    private let permissionOverride: (() -> Void)?
    private let pickerOverride: ((PickerController) -> Void)?
    private let placementOverride: ((PlacementSession) -> Void)?
    private let restoresFocus: Bool
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "session")

    /// Bumped by every start and end, so late async results of an ended
    /// session are dropped.
    private var sessionID = 0
    private var previousApp: NSRunningApplication?
    private var analysis: CutoutAnalysis?
    private var picker: PickerController?
    private var placement: PlacementSession?
    private var inFlightSticker: UUID?
    private var permissionPanel: PermissionPanel?

    /// `screens` defaults to the live screens, `showMessage` to the HUD,
    /// `presentPermission` to the permission panel, `presentPicker` to showing
    /// the picker near the cursor and `presentPlacement` to starting the
    /// placement; tests replace them and turn `restoresFocus` off, so a test
    /// never shows a window or activates another app.
    init(capture: CaptureService, cutout: CutoutEngine, stickers: StickerManager, library: LibraryController,
         store: LibraryStore, renderer: StyleRenderer, screens: ScreenProvider? = nil,
         access: ScreenRecordingAccess = LiveScreenRecordingAccess(),
         showMessage: ((String) -> Void)? = nil, presentPermission: (() -> Void)? = nil,
         presentPicker: ((PickerController) -> Void)? = nil,
         presentPlacement: ((PlacementSession) -> Void)? = nil,
         restoresFocus: Bool = true) {
        self.capture = capture
        self.cutout = cutout
        self.stickers = stickers
        self.library = library
        self.store = store
        self.renderer = renderer
        self.screens = screens ?? LiveScreenProvider()
        self.access = access
        self.showMessage = showMessage ?? { HUD.shared.show($0) }
        permissionOverride = presentPermission
        pickerOverride = presentPicker
        placementOverride = presentPlacement
        self.restoresFocus = restoresFocus
    }

    // MARK: Triggers

    /// The shortcut, a left-click on the menu bar icon, New Sticker. `window`
    /// (Home, when started from there) is ordered out just before screencapture
    /// runs and isn't shown again.
    func startCapture(orderingOut window: NSWindow? = nil) {
        guard !isActive else {
            log.notice("capture ignored: a session is active")
            return
        }
        guard !library.isReadOnly else {
            showMessage(HUD.readOnlyMessage)
            return
        }
        guard access.preflight() else {
            // Never start screencapture without Screen Recording (spec 5.3).
            presentPermission()
            return
        }
        permissionPanel?.close()
        begin(.capturing)
        window?.orderOut(nil)
        cutout.prewarm()
        renderer.prewarm()
        let id = sessionID
        capture.capture { [weak self] outcome in
            self?.captureFinished(outcome, session: id)
        }
    }

    /// Re-placing a sticker from history: the style-only picker, then placement.
    func startReplace(sticker: UUID) {
        guard !isActive else {
            log.notice("re-place ignored: a session is active")
            return
        }
        guard !library.isReadOnly else {
            showMessage(HUD.readOnlyMessage)
            return
        }
        guard let record = library.library.sticker(sticker) else { return }
        begin(.picking)
        currentSticker = sticker
        let model = PickerModel.forRestyle(record, renderer: renderer, backingScale: cursorDisplay()?.backingScale ?? 2)
        showPicker(model, session: sessionID)
    }

    /// Ends the session wherever it is: terminates screencapture (deleting its
    /// file), closes the picker or the placement panel. Saves nothing new; a
    /// sticker already saved stays in history. Quit calls this first.
    func cancel() {
        guard isActive else { return }
        log.notice("session cancelled at \(String(describing: self.stage), privacy: .public)")
        capture.cancelRunning()
        end()
    }

    // MARK: Steps

    private func captureFinished(_ outcome: CaptureOutcome, session: Int) {
        guard session == sessionID, stage == .capturing else { return }
        switch outcome {
        case .success(let url):
            stage = .analyzing
            analyze(url, session: session)
        case .controlHeldToClipboard:
            showMessage(HUD.controlHeldMessage)
            end()
        case .busyOrBlocked:
            showMessage(HUD.couldNotStartMessage)
            end()
        case .cancelled:
            end()
        }
    }

    /// Loads the PNG and deletes it at once, then runs pass 1, off the main actor.
    private func analyze(_ url: URL, session: Int) {
        let engine = cutout
        Task { [weak self] in
            guard let loaded = await Self.load(url) else {
                self?.analysisFailed(session: session)
                return
            }
            let analysis = await engine.analyze(loaded)
            self?.analyzed(analysis, session: session)
        }
    }

    /// The capture with its colour profile and DPI; the temporary file is
    /// deleted right after (spec section 5.8). Runs off the main actor.
    nonisolated private static func load(_ url: URL) async -> LoadedCapture? {
        defer { try? FileManager.default.removeItem(at: url) }
        return try? MasterImage.load(url: url)
    }

    private func analysisFailed(session: Int) {
        guard session == sessionID else { return }
        log.error("the capture couldn't be read")
        showMessage(HUD.couldNotStartMessage)
        end()
    }

    private func analyzed(_ analysis: CutoutAnalysis, session: Int) {
        guard session == sessionID, stage == .analyzing else {
            analysis.release()
            return
        }
        stage = .picking
        self.analysis = analysis
        let model = PickerModel.forCapture(analysis, renderer: renderer,
                                           backingScale: cursorDisplay()?.backingScale ?? 2)
        showPicker(model, session: session)
    }

    private func showPicker(_ model: PickerModel, session: Int) {
        let picker = PickerController(model: model)
        picker.onCancel = { [weak self] in self?.cancel() }
        model.onConfirm = { [weak self] confirmation in self?.confirmed(confirmation, session: session) }
        self.picker = picker
        if let pickerOverride {
            pickerOverride(picker)
            return
        }
        let mouse = NSEvent.mouseLocation
        let visible = cursorDisplay()?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        picker.show(near: mouse, visibleFrame: visible)
    }

    private func confirmed(_ confirmation: PickerModel.Confirmation, session: Int) {
        guard session == sessionID, stage == .picking else { return }
        closePicker()
        guard let image = confirmation.image else {
            // Re-placing: the master is already in the library.
            startPlacement(sticker: confirmation.sticker, style: confirmation.style)
            return
        }
        // A fresh capture: PNG first (off the main actor), then the index.
        stage = .saving
        inFlightSticker = confirmation.sticker
        currentSticker = confirmation.sticker
        let store = self.store
        Task { [weak self] in
            let succeeded = await Self.write(image, pixelsPerPoint: confirmation.pixelsPerPoint,
                                             as: confirmation.sticker, in: store)
            self?.saved(confirmation, image: image, succeeded: succeeded, session: session)
        }
    }

    /// The master PNG with its DPI, written atomically. Runs off the main actor.
    nonisolated private static func write(_ image: CGImage, pixelsPerPoint: Double, as sticker: UUID,
                                          in store: LibraryStore) async -> Bool {
        do {
            try store.writePNG(try MasterImage.pngData(image, pixelsPerPoint: pixelsPerPoint), for: sticker)
            return true
        } catch {
            return false
        }
    }

    private func saved(_ confirmation: PickerModel.Confirmation, image: CGImage, succeeded: Bool, session: Int) {
        guard session == sessionID, stage == .saving else {
            // Cancelled while the PNG was written: nothing was indexed, so the
            // PNG goes too (launch repair would adopt it otherwise).
            if succeeded { try? store.deletePNG(for: confirmation.sticker) }
            return
        }
        guard succeeded else {
            log.error("saving the master PNG failed")
            showMessage(HUD.saveFailedMessage)
            end()
            return
        }
        let record = StickerRecord(id: confirmation.sticker, created: Date(), pixelWidth: image.width,
                                   pixelHeight: image.height, pixelsPerPoint: confirmation.pixelsPerPoint,
                                   lastStyle: confirmation.style)
        library.mutate { $0.stickers.append(record) }
        startPlacement(sticker: record.id, style: confirmation.style)
    }

    private func startPlacement(sticker: UUID, style: StickerStyle) {
        guard let record = library.library.sticker(sticker) else {
            end()
            return
        }
        stage = .placing
        let session = PlacementSession(
            sticker: sticker, style: style, natural: record.naturalPointSize,
            sourceLongSide: Double(max(record.pixelWidth, record.pixelHeight)),
            renderer: renderer, stickers: stickers, screens: screens)
        let id = sessionID
        session.onEnd = { [weak self] outcome in
            guard let self, id == self.sessionID else { return }
            if case .placed(let placement) = outcome {
                self.onPlaced?(placement, sticker)
            }
            self.placement = nil
            self.end()
        }
        placement = session
        if let placementOverride {
            placementOverride(session)
        } else {
            session.start()
        }
    }

    // MARK: Start and end

    private func begin(_ stage: Stage) {
        sessionID += 1
        self.stage = stage
        // Editing ends (discarding a gesture) without handing focus back: the
        // session takes over the app editing would have returned it to, and
        // hands focus back itself when it ends.
        let beforeEditing = stickers.endEditing(discardGesture: true, returningFocus: false)
        let frontmost = restoresFocus ? (beforeEditing ?? NSWorkspace.shared.frontmostApplication) : nil
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        onActiveChange?(true)
    }

    private func end() {
        sessionID += 1
        closePicker()
        if let placement {
            self.placement = nil
            placement.onEnd = nil
            placement.cancel()
        }
        if let inFlightSticker {
            renderer.setInFlightMaster(nil, for: inFlightSticker)
            self.inFlightSticker = nil
        }
        currentSticker = nil
        stage = .idle
        if let previousApp, !previousApp.isTerminated, NSApp.isActive {
            previousApp.activate()
        }
        previousApp = nil
        onActiveChange?(false)
    }

    private func closePicker() {
        picker?.model.finish()
        picker?.close()
        picker = nil
        analysis?.release()
        analysis = nil
    }

    /// The permission panel (spec section 14), or the tests' stand-in.
    private func presentPermission() {
        if let permissionOverride {
            permissionOverride()
            return
        }
        let panel = permissionPanel ?? PermissionPanel(access: access, screens: screens)
        permissionPanel = panel
        panel.show()
    }

    private func cursorDisplay() -> DisplayInfo? {
        StickerManager.display(containing: NSEvent.mouseLocation, in: screens.currentDisplays())
    }
}
