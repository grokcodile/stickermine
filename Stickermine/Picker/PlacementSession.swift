import AppKit
import os

/// The transient panel that carries a new sticker under the cursor. It may
/// become key, so Esc arrives.
@MainActor
final class PlacementPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The placement panel's content: the styled sticker (a StickerView, exactly
/// as it will look once placed) under a view that takes every mouse-down.
@MainActor
final class PlacementView: NSView {
    let sticker = StickerView(frame: .zero)
    var onPlace: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        sticker.autoresizingMask = [.width, .height]
        sticker.frame = bounds
        addSubview(sticker)
    }

    required init?(coder: NSCoder) {
        fatalError("PlacementView is only created in code")
    }

    /// The sticker view below never sees a click: this view takes them all.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onPlace?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The sticker following the cursor until a click places it (spec section 7).
///
/// Every new placement starts at rotation 0, unflipped, Float on top off, in
/// the chosen style, at its natural point size scaled down to fit within half
/// the width and height of the display under the cursor (recomputed when the
/// cursor moves to another display). A mouse-down on the panel places it on
/// that display, on top of its z-order, through `StickerManager.place`; clicks
/// on other windows are ignored; Esc or a right-click cancels.
@MainActor
final class PlacementSession {
    enum Outcome: Equatable {
        case placed(UUID)
        case cancelled
    }

    /// The sticker fits within this share of the display's width and height.
    static let fitFraction: CGFloat = 0.5
    /// After placing, the panel stays until the new sticker shows, at most this long.
    static let handOverTimeout: TimeInterval = 0.5

    let sticker: UUID
    let style: StickerStyle
    let natural: CGSize
    let sourceLongSide: Double
    var onEnd: ((Outcome) -> Void)?

    private let renderer: StyleRenderer
    private let stickers: StickerManager
    private let screens: ScreenProvider
    private let mouseLocation: () -> NSPoint
    private var panel: PlacementPanel?
    private var view: PlacementView?
    private var monitors: [Any] = []
    private var display: DisplayInfo?
    private var request: RenderRequest?
    private var ended = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "placement")

    /// The unrotated size the sticker is placed at, in points.
    private(set) var pointSize: CGSize = .zero

    init(sticker: UUID, style: StickerStyle, natural: CGSize, sourceLongSide: Double, renderer: StyleRenderer,
         stickers: StickerManager, screens: ScreenProvider,
         mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.sticker = sticker
        self.style = style
        self.natural = natural
        self.sourceLongSide = sourceLongSide
        self.renderer = renderer
        self.stickers = stickers
        self.screens = screens
        self.mouseLocation = mouseLocation
    }

    /// `natural` scaled down (never up) to fit within half of `frame`.
    static func fittedSize(natural: CGSize, in frame: CGRect) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return natural }
        let scale = min(1, frame.width * fitFraction / natural.width, frame.height * fitFraction / natural.height)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    /// The panel policy (spec section 4), plus the explicit
    /// `ignoresMouseEvents = false` this transient panel is allowed: its whole
    /// rectangle takes the click, transparent pixels included (spec section 7).
    static func makePanel() -> PlacementPanel {
        let panel = PlacementPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .floating  // last
        return panel
    }

    /// Creates the panel and starts following the cursor. The panel appears
    /// with the first render.
    func start() {
        let panel = Self.makePanel()
        let view = PlacementView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        panel.contentView = view
        view.onPlace = { [weak self] in self?.place() }
        view.onCancel = { [weak self] in self?.cancel() }
        self.panel = panel
        self.view = view
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.follow()
            return event
        }) {
            monitors.append(local)
        }
        // Global monitors don't see events sent to this app; the local one does.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.follow()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, !self.ended else { return event }
            self.cancel()
            return nil
        }) {
            monitors.append(local)
        }
        follow()
    }

    /// Centres the panel on the cursor; on another display, re-fits and re-renders.
    func follow() {
        guard !ended else { return }
        let point = mouseLocation()
        guard let current = StickerManager.display(containing: point, in: screens.currentDisplays()) else { return }
        if current != display {
            display = current
            pointSize = Self.fittedSize(natural: natural, in: current.frame)
            render(backingScale: current.backingScale)
        }
        guard let panel else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded()))
    }

    /// Esc, a right-click, or the session being cancelled: nothing is placed;
    /// a fresh sticker stays in history.
    func cancel() {
        end(.cancelled)
    }

    private func render(backingScale: CGFloat) {
        let request = RenderRequest(sticker: sticker, style: style, flipped: false, rotation: 0,
                                    pointSize: pointSize, backingScale: backingScale)
        guard request != self.request else { return }
        self.request = request
        let renderer = self.renderer
        Task { [weak self] in
            do {
                let rendered = try await renderer.render(request)
                self?.show(rendered, for: request)
            } catch {
                self?.log.error("placement render failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func show(_ rendered: RenderedSticker, for request: RenderRequest) {
        guard !ended, request == self.request, let panel, let view else { return }
        view.sticker.show(rendered, shadow: request.onScreenParameters(sourceLongSide: sourceLongSide), style: style)
        let margin = view.sticker.frameMargin
        let size = CGSize(width: rendered.pointBounds.width + 2 * margin,
                          height: rendered.pointBounds.height + 2 * margin)
        let point = mouseLocation()
        panel.setFrame(NSRect(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    /// A mouse-down on the panel (internal so tests can place without a click).
    func place() {
        guard !ended, let panel else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let placement = stickers.place(sticker: sticker, style: style, centerOnScreen: center,
                                             pointSize: pointSize)
        else {
            log.error("placing \(self.sticker.uuidString, privacy: .public) failed")
            end(.cancelled)
            return
        }
        end(.placed(placement))
    }

    private func end(_ outcome: Outcome) {
        guard !ended else { return }
        ended = true
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let panel, let view {
            if case .placed(let placement) = outcome {
                Self.close(panel, view: view, whenStickerShows: placement, in: stickers,
                           deadline: Date().addingTimeInterval(Self.handOverTimeout))
            } else {
                Self.close(panel, view: view)
            }
        }
        panel = nil
        view = nil
        onEnd?(outcome)
    }

    /// Keeps the panel until the placed sticker's own panel has its bitmap (or
    /// the deadline passes), so the sticker never blinks out between the two.
    private static func close(_ panel: PlacementPanel, view: PlacementView, whenStickerShows placement: UUID,
                              in stickers: StickerManager, deadline: Date) {
        let shown = (stickers.panel(for: placement)?.contentView as? StickerView)?.contentLayer.contents != nil
        guard shown || Date() >= deadline else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) {
                MainActor.assumeIsolated {
                    close(panel, view: view, whenStickerShows: placement, in: stickers, deadline: deadline)
                }
            }
            return
        }
        close(panel, view: view)
    }

    private static func close(_ panel: PlacementPanel, view: PlacementView) {
        view.sticker.clearContents()
        panel.orderOut(nil)
        panel.close()
    }
}
