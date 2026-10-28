import AppKit
import os

/// Where editing moves keyboard focus. Tests substitute a recorder, so they
/// never activate the app or make a panel key.
@MainActor
protocol EditingFocus: AnyObject {
    /// The frontmost app, unless it is Stickermine itself.
    func frontmostOtherApp() -> NSRunningApplication?
    /// Activates Stickermine and makes `panel` key with its content view as
    /// first responder, so Esc, Delete and trackpad gestures arrive.
    func takeFocus(for panel: NSPanel)
    /// Hands focus back to `app` once editing ends, but only while
    /// Stickermine is still frontmost and none of its other windows took key:
    /// a click into another app or onto one of Stickermine's windows keeps
    /// that focus. Without `app` (Stickermine itself was frontmost), another
    /// visible Stickermine window that can be key gets it back, else
    /// Stickermine deactivates.
    func returnFocus(to app: NSRunningApplication?)
}

@MainActor
final class LiveEditingFocus: EditingFocus {
    private static let log = Logger(subsystem: "com.ethan.stickermine", category: "editing")

    init() {}

    func frontmostOtherApp() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        return front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    }

    func takeFocus(for panel: NSPanel) {
        NSApp.activate()
        panel.makeKey()
        if let view = panel.contentView { panel.makeFirstResponder(view) }
        // Activation of an accessory app is expected but unverified (spec
        // section 10); the log line says what happened.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak panel] in
            MainActor.assumeIsolated {
                Self.log.notice("editing focus +0.5s: appActive=\(NSApp.isActive) key=\(panel?.isKeyWindow ?? false)")
            }
        }
    }

    func returnFocus(to app: NSRunningApplication?) {
        // On the next turn, when a click elsewhere has finished moving key status.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard NSApp.isActive, NSApp.keyWindow == nil || NSApp.keyWindow is StickerPanel else {
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
                    Self.log.notice("focus stays with \(front, privacy: .public)")
                    return
                }
                if let app, !app.isTerminated {
                    app.activate()
                    Self.log.notice("focus returned to \(app.bundleIdentifier ?? "?", privacy: .public)")
                } else if let window = NSApp.windows.first(where: {
                    $0.isVisible && $0.canBecomeKey && !($0 is StickerPanel)
                }) {
                    window.makeKeyAndOrderFront(nil)
                    Self.log.notice("focus returned to \(window.title, privacy: .public)")
                } else {
                    NSApp.deactivate()
                    Self.log.notice("focus released")
                }
            }
        }
    }
}

/// One sticker being edited (spec section 10): the toolbar pill, keys, the
/// drag, the corner knob and trackpad pinch and rotate. `StickerManager`
/// creates it when editing begins and drops it when editing ends; every
/// model write goes through the manager.
///
/// Gesture lifecycle: the first gesture to begin grows the window once to a
/// square that fits the sticker turned any way at up to twice its size
/// (`EditGeometry.gestureSide`), and the manager holds the frame. Every event
/// only changes the content layer's transform (scale and rotation around the
/// centre). When the last gesture ends, the manager writes the new pose and
/// rotation, renders the bitmap with them baked in, and then shrinks the
/// window and resets the transform in one step.
@MainActor
final class StickerEditor {
    enum Gesture: Hashable {
        case knob, magnify, rotate
    }

    /// What the current gesture started from.
    struct GestureBase: Equatable {
        /// The window's centre: the gesture scales and rotates around it.
        let center: CGPoint
        /// The shown bitmap's box (rotated, rim included) at the start.
        let contentSize: CGSize
        let margin: CGFloat
        /// The pose scale on this display at the start.
        let poseScale: Double
        /// The placement's rotation at the start.
        let rotation: Double
        let limits: ClosedRange<Double>
    }

    let placementID: UUID
    let panel: StickerPanel
    let view: StickerView
    /// The app that was frontmost before editing began.
    let previousApp: NSRunningApplication?
    let pill: ToolbarPill
    private unowned let manager: StickerManager
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "editing")

    private(set) var activeGestures: Set<Gesture> = []
    private(set) var base: GestureBase?
    /// The live change: a factor on `base.poseScale` and a rotation to add.
    private(set) var scaleFactor: Double = 1
    private(set) var rotationDelta: Double = 0
    /// Window resizes since the current gesture began (one, unless the
    /// sticker outgrows the square).
    private(set) var gestureResizeCount = 0
    private var knobStart: (vector: CGVector, scale: Double, rotation: Double)?

    init(placementID: UUID, panel: StickerPanel, view: StickerView, previousApp: NSRunningApplication?,
         target: StickerManager.EditTarget, renderer: StyleRenderer, manager: StickerManager) {
        self.placementID = placementID
        self.panel = panel
        self.view = view
        self.previousApp = previousApp
        self.manager = manager
        let model = ToolbarPillModel(placement: target.placement, natural: target.natural,
                                     sourceLongSide: target.sourceLongSide, renderer: renderer,
                                     backingScale: target.display.backingScale)
        pill = ToolbarPill(model: model)
        let id = placementID
        model.onStyle = { [weak manager] style in manager?.setStyle(style, for: id) }
        model.onFlip = { [weak manager] in manager?.toggleFlip(for: id) }
        model.onFloatOnTop = { [weak manager] in manager?.toggleOnTop(for: id) }
        model.onRemove = { [weak manager] in manager?.remove(placement: id) }
    }

    var isGestureActive: Bool { !activeGestures.isEmpty }

    /// Takes the view's editing events (keys, gestures, the knob) and shows
    /// the pill.
    func show() {
        view.onKeyDown = { [weak self] event in self?.keyDown(event) ?? false }
        view.onMagnify = { [weak self] event in
            self?.magnify(by: Double(event.magnification), phase: event.phase)
        }
        view.onRotate = { [weak self] event in
            self?.rotate(byDegrees: Double(event.rotation), phase: event.phase)
        }
        view.onKnobDrag = { [weak self] phase, point, shift in self?.knob(phase, at: point, snapping: shift) }
        pill.attach(to: panel)
        placePill()
    }

    /// Editing ended: the view's editing events are let go, the pill goes and
    /// any gesture is forgotten (the manager resets the transform and frame).
    func tearDown() {
        view.onKeyDown = nil
        view.onMagnify = nil
        view.onRotate = nil
        view.onKnobDrag = nil
        activeGestures = []
        base = nil
        knobStart = nil
        pill.close()
    }

    // MARK: Keys

    /// Esc ends editing; Delete removes the placement (on the next turn, so
    /// the panel isn't closed inside its own key event).
    func keyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            manager.endEditing(discardGesture: true)
            return true
        case 51, 117:
            manager.scheduleRemoval(of: placementID)
            return true
        default:
            return false
        }
    }

    // MARK: Gestures

    /// A trackpad pinch: `amount` is the event's magnification (1 + amount
    /// multiplies the size).
    func magnify(by amount: Double, phase: NSEvent.Phase) {
        handle(.magnify, phase: phase) { (scaleFactor * (1 + amount), rotationDelta) }
    }

    /// A trackpad rotation: `degrees` counter-clockwise.
    func rotate(byDegrees degrees: Double, phase: NSEvent.Phase) {
        handle(.rotate, phase: phase) { (scaleFactor, rotationDelta + degrees * Double.pi / 180) }
    }

    /// A drag on the corner knob: scale and rotate around the centre so the
    /// knob follows the cursor (`point`, screen coordinates); Shift snaps the
    /// rotation to 15°.
    func knob(_ phase: StickerView.DragPhase, at point: CGPoint, snapping: Bool) {
        switch phase {
        case .began:
            guard beginGesture(.knob), let base else { return }
            knobStart = (CGVector(dx: point.x - base.center.x, dy: point.y - base.center.y), scaleFactor, rotationDelta)
        case .moved:
            followKnob(to: point, snapping: snapping)
        case .ended:
            followKnob(to: point, snapping: snapping)
            endGesture(.knob)
        }
    }

    private func followKnob(to point: CGPoint, snapping: Bool) {
        guard activeGestures.contains(.knob), let base, let start = knobStart else { return }
        let change = EditGeometry.knobChange(
            from: start.vector, to: CGVector(dx: point.x - base.center.x, dy: point.y - base.center.y),
            baseRotation: base.rotation + start.rotation, snap: snapping)
        apply(scale: start.scale * change.scale, rotation: start.rotation + change.rotation)
    }

    private func handle(_ kind: Gesture, phase: NSEvent.Phase, change: () -> (Double, Double)) {
        if phase.contains(.ended) || phase.contains(.cancelled) {
            endGesture(kind)
            return
        }
        guard beginGesture(kind) else { return }
        let (scale, rotation) = change()
        apply(scale: scale, rotation: rotation)
        // An event without phases is a whole gesture on its own.
        if phase.isEmpty { endGesture(kind) }
    }

    /// The first gesture grows the window once; later ones join it.
    private func beginGesture(_ kind: Gesture) -> Bool {
        if activeGestures.contains(kind) { return true }
        if activeGestures.isEmpty {
            guard let target = manager.editTarget(for: placementID), target.layout.pose.scale > 0,
                  manager.holdFrame(for: placementID)
            else { return false }
            let start = GestureBase(
                center: CGPoint(x: panel.frame.midX, y: panel.frame.midY), contentSize: shownSize(target),
                margin: view.windowMargin, poseScale: target.layout.pose.scale, rotation: target.placement.rotation,
                limits: EditGeometry.scaleLimits(natural: target.natural, displaySize: target.display.frame.size))
            base = start
            scaleFactor = 1
            rotationDelta = 0
            gestureResizeCount = 0
            resizeWindow(factor: max(1, min(EditGeometry.gestureHeadroom, maximumFactor(start))))
        }
        activeGestures.insert(kind)
        return true
    }

    /// The largest factor the limits allow from the gesture's start.
    private func maximumFactor(_ base: GestureBase) -> Double {
        max(base.limits.upperBound, base.poseScale) / base.poseScale
    }

    private func apply(scale proposed: Double, rotation: Double) {
        guard let base else { return }
        let total = EditGeometry.clampedScale(base.poseScale * proposed, current: base.poseScale, limits: base.limits)
        scaleFactor = total / base.poseScale
        rotationDelta = EditGeometry.normalized(rotation)
        let needed = EditGeometry.gestureSide(contentSize: base.contentSize, factor: scaleFactor, margin: base.margin)
        if needed > panel.frame.width {
            // Outgrew the square: grow again, with room to spare.
            resizeWindow(factor: min(maximumFactor(base), scaleFactor * 1.5))
        }
        view.setContentTransform(scale: CGFloat(scaleFactor), rotation: CGFloat(rotationDelta))
        placePill()
    }

    private func resizeWindow(factor: Double) {
        guard let base else { return }
        let side = EditGeometry.gestureSide(contentSize: base.contentSize, factor: factor, margin: base.margin)
        let square = NSRect(x: base.center.x - side / 2, y: base.center.y - side / 2, width: side, height: side)
        panel.setFrame(panel.backingAlignedRect(square, options: .alignAllEdgesOutward), display: true)
        gestureResizeCount += 1
    }

    private func endGesture(_ kind: Gesture) {
        guard activeGestures.remove(kind) != nil else { return }
        if kind == .knob { knobStart = nil }
        guard activeGestures.isEmpty else { return }
        base = nil
        log.notice("gesture end: scale ×\(self.scaleFactor) rotation \(self.rotationDelta)")
        manager.commitGesture(placement: placementID, scaleFactor: scaleFactor, rotationDelta: rotationDelta)
    }

    // MARK: Pill

    /// The shown bitmap's box; the sticker rect before the first render.
    private func shownSize(_ target: StickerManager.EditTarget) -> CGSize {
        let content = view.contentPointSize
        return content.width > 0 && content.height > 0 ? content : target.layout.stickerRect.size
    }

    /// Places the pill under (or above) the sticker's current box, on the
    /// display under the box's centre (during a drag, the one it is over).
    func placePill() {
        guard let target = manager.editTarget(for: placementID) else { return }
        let box = StickerView.boundingSize(of: shownSize(target), scale: view.contentScale,
                                           rotation: view.contentRotation)
        let frame = panel.frame
        // The outline and the knob on its bottom-right corner reach this far past
        // the box: the pill keeps its gap from them, so it never covers the knob.
        let reach = StickerView.outlineOutset + StickerView.knobRadius
        let stickerRect = CGRect(x: frame.midX - box.width / 2, y: frame.midY - box.height / 2,
                                 width: box.width, height: box.height).insetBy(dx: 0, dy: -reach)
        let display = manager.display(at: NSPoint(x: frame.midX, y: frame.midY)) ?? target.display
        pill.place(around: stickerRect, visibleFrame: display.visibleFrame)
    }

    /// The placement was written or its window changed: the pill shows its
    /// style, flip and Float on top, keeps its level, and follows it.
    func placementDidChange() {
        guard let target = manager.editTarget(for: placementID) else { return }
        pill.model.update(style: target.placement.style, flipped: target.placement.flipped,
                          onTop: target.placement.onTop)
        pill.setLevel(panel.level)
        placePill()
    }
}
