import AppKit
import QuartzCore

/// The content view of a StickerPanel: a layer-hosting view whose root layer
/// holds three sublayers we own, back to front:
/// - `hitPadLayer`: alpha 1/255 over the whole padded frame while editing, so the
///   transparent parts of the box and the corner knob can be grabbed; hidden
///   otherwise, so transparent pixels click through.
/// - `contentLayer`: the sticker bitmap (CGImage or IOSurface), centred, with the
///   layer shadow. Gesture transforms go on this layer, never on the root.
/// - `outlineLayer`: the subtle editing outline, with the corner knob
///   (`knobLayer`) as its sublayer, so both show and hide together.
@MainActor
final class StickerView: NSView {
    /// A drag's steps: the mouse-down, each move, the mouse-up.
    enum DragPhase: Equatable {
        case began, moved, ended
    }

    /// What a drag that started while editing is doing.
    enum DragKind: Equatable {
        /// Started on the corner knob: scale and rotate.
        case knob
        /// Started anywhere else in the frame: move the sticker.
        case move
    }

    let contentLayer = CALayer()
    let hitPadLayer = CALayer()
    let outlineLayer = CAShapeLayer()
    let knobLayer = CAShapeLayer()

    /// A double-click on an inactive (not editing) sticker.
    var onDoubleClick: (() -> Void)?
    /// Every mouse-down on a sticker that isn't being edited (before
    /// `onDoubleClick` for the second click of a double-click).
    var onInactiveMouseDown: (() -> Void)?
    /// Key presses while the panel is key. Return true when handled.
    var onKeyDown: ((NSEvent) -> Bool)?
    /// Trackpad pinch and rotate, delivered whatever the editing state.
    var onMagnify: ((NSEvent) -> Void)?
    var onRotate: ((NSEvent) -> Void)?
    /// A drag that started away from the knob while editing (moving the
    /// sticker): the phase and the cursor in screen coordinates.
    var onMoveDrag: ((DragPhase, CGPoint) -> Void)?
    /// A drag that started on the corner knob while editing: the phase, the
    /// cursor in screen coordinates, and whether Shift is held.
    var onKnobDrag: ((DragPhase, CGPoint, Bool) -> Void)?
    /// The window's backing scale after it changed (moved to a display with
    /// another scale, or the display's scale changed): the bitmap must be
    /// re-rendered at the new scale (spec section 11).
    var onBackingScaleChange: ((CGFloat) -> Void)?

    /// The sticker's unrotated, unscaled size in points (the bitmap's bounds).
    private(set) var contentPointSize: CGSize = .zero
    private(set) var layerShadow: LayerShadow?
    /// The transparent padding the window keeps on every side of the shown
    /// bitmap's box, in points: `StyleParameters.shadowMargin(for:)` rounded up
    /// to whole pixels, over the backing scale, for a rendered sticker;
    /// `LayerShadow.margin` for raw contents; 0 without a shadow (spec section 9).
    private(set) var frameMargin: CGFloat = 0
    private(set) var contentScale: CGFloat = 1
    private(set) var contentRotation: CGFloat = 0
    private(set) var isShowingEditingChrome = false
    /// The knob's centre in this view's coordinates: the bottom-right corner
    /// of the (transformed) outline.
    private(set) var knobCenter: CGPoint = .zero
    /// The drag in progress, from its mouse-down to its mouse-up.
    private(set) var trackedDrag: DragKind?

    static let hitPadAlpha: CGFloat = 1.0 / 255.0
    /// The outline sits this far outside the bitmap's box.
    static let outlineOutset: CGFloat = 2
    static let knobRadius: CGFloat = 7
    /// A mouse-down this close to the knob's centre grabs the knob.
    static let knobHitRadius: CGFloat = 12
    /// While editing, the window keeps at least this much room on every side
    /// of the bitmap's box, so the knob is never clipped and can be grabbed
    /// (a None sticker has no shadow margin).
    static let editingMargin: CGFloat = 14

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.isOpaque = false
        // Assigning the layer before wantsLayer makes this a layer-hosting view:
        // AppKit leaves the layer tree to us.
        layer = root
        wantsLayer = true

        hitPadLayer.backgroundColor = NSColor(white: 0, alpha: Self.hitPadAlpha).cgColor
        hitPadLayer.isHidden = true

        contentLayer.contentsGravity = .resize
        contentLayer.minificationFilter = .trilinear

        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        outlineLayer.lineWidth = 1.5
        outlineLayer.lineDashPattern = [5, 4]
        outlineLayer.isHidden = true

        let r = Self.knobRadius
        knobLayer.path = CGPath(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r), transform: nil)
        knobLayer.fillColor = NSColor.white.cgColor
        knobLayer.strokeColor = NSColor.controlAccentColor.cgColor
        knobLayer.lineWidth = 1.5
        knobLayer.shadowColor = NSColor.black.cgColor
        knobLayer.shadowOpacity = 0.3
        knobLayer.shadowRadius = 1.5
        knobLayer.shadowOffset = CGSize(width: 0, height: -0.5)
        outlineLayer.addSublayer(knobLayer)

        root.addSublayer(hitPadLayer)
        root.addSublayer(contentLayer)
        root.addSublayer(outlineLayer)
        layoutStickerLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("StickerView is only created in code")
    }

    /// The window size for a sticker of `pointSize` with `shadow`: the sticker
    /// rect plus the shadow margin on every side (zero margin without a shadow).
    static func frameSize(pointSize: CGSize, shadow: LayerShadow?) -> CGSize {
        let margin = shadow?.margin ?? 0
        return CGSize(width: pointSize.width + 2 * margin, height: pointSize.height + 2 * margin)
    }

    /// The axis-aligned bounding box of `size` scaled by `scale` and rotated by
    /// `rotation` radians. The rotation math lives in one place,
    /// `StickerGeometry.boundingSize(of:rotation:)` (M2); this only scales it.
    static func boundingSize(of size: CGSize, scale: CGFloat, rotation: CGFloat) -> CGSize {
        let box = StickerGeometry.boundingSize(of: size, rotation: Double(rotation))
        return CGSize(width: box.width * scale, height: box.height * scale)
    }

    /// The room the window keeps around the bitmap's box: the shadow margin,
    /// and at least `editingMargin` while the editing chrome shows.
    var windowMargin: CGFloat {
        isShowingEditingChrome ? max(frameMargin, Self.editingMargin) : frameMargin
    }

    /// Shows `contents` (a CGImage or an IOSurface, as accepted by
    /// `CALayer.contents`) at `pointSize`, with an optional layer shadow.
    /// `frameMargin` defaults to the shadow's own margin (0 without one);
    /// `show(_:shadow:style:)` passes `StyleParameters.shadowMargin` in points.
    func showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?, frameMargin: CGFloat? = nil) {
        contentPointSize = pointSize
        layerShadow = shadow
        self.frameMargin = frameMargin ?? shadow?.margin ?? 0
        withoutAnimation {
            contentLayer.contents = contents
            if let shadow {
                contentLayer.shadowColor = NSColor.black.cgColor
                contentLayer.shadowOpacity = shadow.opacity
                contentLayer.shadowRadius = shadow.radius
                // Layer-hosting views aren't flipped: negative y points down.
                contentLayer.shadowOffset = CGSize(width: 0, height: -shadow.offset)
            } else {
                contentLayer.shadowOpacity = 0
            }
        }
        layoutStickerLayers()
    }

    /// Shows a rendered sticker at its point bounds with its drop shadow:
    /// `shadow` holds the style parameters for the sticker's on-screen pixel
    /// size (`RenderRequest.onScreenParameters(sourceLongSide:)`), which become
    /// points through the backing scale the bitmap was rendered for. None, or
    /// a nil `shadow`, shows no shadow and needs no margin (spec sections 8–9).
    /// The shadow stays unrasterized: the content is static between gestures.
    func show(_ rendered: RenderedSticker, shadow: StyleParameters?, style: StickerStyle) {
        let layer = Self.layerShadow(for: shadow, style: style, backingScale: rendered.backingScale)
        // Whole device pixels, so the bitmap stays on the pixel grid inside the
        // backing-aligned frame (spec section 9).
        let pixels = CGFloat(shadow?.shadowMargin(for: style) ?? 0).rounded(.up)
        let margin = layer == nil ? 0 : pixels / rendered.backingScale
        showContents(rendered.contents, pointSize: rendered.pointBounds, shadow: layer, frameMargin: margin)
    }

    /// The layer shadow for pixel `parameters` at `backingScale`: black at the
    /// parameters' opacity, radius and downward offset in points. nil for None,
    /// without parameters, or when the radius is zero.
    static func layerShadow(for parameters: StyleParameters?, style: StickerStyle,
                            backingScale: CGFloat) -> LayerShadow? {
        guard let parameters, style != .none, backingScale > 0, parameters.shadowRadius > 0 else { return nil }
        return LayerShadow(radius: CGFloat(parameters.shadowRadius) / backingScale,
                           opacity: Float(parameters.shadowOpacity),
                           offset: CGFloat(parameters.shadowOffset) / backingScale)
    }

    /// Drops the bitmap. Call before ordering out and closing a panel for good:
    /// a closed window keeps its contents alive until the next event otherwise.
    func clearContents() {
        withoutAnimation { contentLayer.contents = nil }
    }

    /// Scales and rotates the content around its centre (a live gesture
    /// preview); the outline and the knob follow it.
    func setContentTransform(scale: CGFloat, rotation: CGFloat) {
        contentScale = scale
        contentRotation = rotation
        withoutAnimation {
            contentLayer.transform = CATransform3DScale(
                CATransform3DMakeRotation(rotation, 0, 0, 1), scale, scale, 1)
            updateOutlinePath()
        }
    }

    /// The hit pad, outline and knob shown while the sticker is being edited.
    /// Hiding them also forgets a drag in progress.
    func setEditingChrome(_ visible: Bool) {
        isShowingEditingChrome = visible
        if !visible { trackedDrag = nil }
        withoutAnimation {
            hitPadLayer.isHidden = !visible
            outlineLayer.isHidden = !visible
        }
    }

    /// Whether a mouse-down at `point` (this view's coordinates) grabs the knob.
    func isOnKnob(_ point: CGPoint) -> Bool {
        isShowingEditingChrome && hypot(point.x - knobCenter.x, point.y - knobCenter.y) <= Self.knobHitRadius
    }

    /// Layer-hosting views don't pass the backing scale to their sublayers, so the
    /// dashed outline and the knob (the layers that draw vector content) get it
    /// here: when the view joins a window and whenever that window's scale changes.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        matchOutlineToBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        matchOutlineToBackingScale()
        if let scale = window?.backingScaleFactor { onBackingScaleChange?(scale) }
    }

    private func matchOutlineToBackingScale() {
        guard let scale = window?.backingScaleFactor else { return }
        withoutAnimation {
            outlineLayer.contentsScale = scale
            knobLayer.contentsScale = scale
        }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutStickerLayers()
    }

    private func layoutStickerLayers() {
        withoutAnimation {
            hitPadLayer.frame = bounds
            outlineLayer.frame = bounds
            contentLayer.bounds = CGRect(origin: .zero, size: contentPointSize)
            contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            updateOutlinePath()
        }
    }

    /// The outline is the bitmap's box, scaled and turned with the content
    /// and set `outlineOutset` outside it; the knob sits on its bottom-right
    /// corner.
    private func updateOutlinePath() {
        let width = contentPointSize.width * contentScale + 2 * Self.outlineOutset
        let height = contentPointSize.height * contentScale + 2 * Self.outlineOutset
        var transform = CGAffineTransform(translationX: bounds.midX, y: bounds.midY).rotated(by: contentRotation)
        let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
        outlineLayer.path = CGPath(rect: rect, transform: &transform)
        knobCenter = CGPoint(x: width / 2, y: -height / 2).applying(transform)
        knobLayer.position = knobCenter
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: Events

    /// The first click on a sticker of an inactive app must reach us.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let editing = (window as? StickerPanel)?.isEditing ?? false
        guard editing else {
            // Inactive stickers absorb single clicks; a double-click starts editing.
            onInactiveMouseDown?()
            if event.clickCount == 2 { onDoubleClick?() }
            return
        }
        // The window follows the mouse here, event by event (not the window
        // server's performDrag), so the drag's end is the mouse-up and the pill
        // can follow every step.
        let kind: DragKind = isOnKnob(convert(event.locationInWindow, from: nil)) ? .knob : .move
        trackedDrag = kind
        report(kind, .began, event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let kind = trackedDrag else { return }
        report(kind, .moved, event)
    }

    override func mouseUp(with event: NSEvent) {
        guard let kind = trackedDrag else { return }
        trackedDrag = nil
        report(kind, .ended, event)
    }

    private func report(_ kind: DragKind, _ phase: DragPhase, _ event: NSEvent) {
        let point = screenLocation(of: event)
        switch kind {
        case .knob: onKnobDrag?(phase, point, event.modifierFlags.contains(.shift))
        case .move: onMoveDrag?(phase, point)
        }
    }

    private func screenLocation(of event: NSEvent) -> CGPoint {
        window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event)
    }

    override func rotate(with event: NSEvent) {
        onRotate?(event)
    }
}
