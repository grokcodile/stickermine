import AppKit
import QuartzCore

/// The content view of a StickerPanel: a layer-hosting view whose root layer
/// holds three sublayers we own, back to front:
/// - `hitPadLayer`: alpha 1/255 over the whole padded frame while editing, so the
///   transparent parts of the box (and later the corner knob) can be grabbed;
///   hidden otherwise, so transparent pixels click through.
/// - `contentLayer`: the sticker bitmap (CGImage or IOSurface), centred, with the
///   layer shadow. Gesture transforms go on this layer, never on the root.
/// - `outlineLayer`: the subtle editing outline.
@MainActor
final class StickerView: NSView {
    let contentLayer = CALayer()
    let hitPadLayer = CALayer()
    let outlineLayer = CAShapeLayer()

    /// A double-click on an inactive (not editing) sticker.
    var onDoubleClick: (() -> Void)?
    /// Key presses while the panel is key. Return true when handled.
    var onKeyDown: ((NSEvent) -> Bool)?
    /// Trackpad pinch and rotate, delivered whatever the editing state.
    var onMagnify: ((NSEvent) -> Void)?
    var onRotate: ((NSEvent) -> Void)?
    /// Called right after `performDrag(with:)` returns for a drag started while editing.
    var onDragEnded: (() -> Void)?

    /// The sticker's unrotated, unscaled size in points (the bitmap's bounds).
    private(set) var contentPointSize: CGSize = .zero
    private(set) var layerShadow: LayerShadow?
    private(set) var contentScale: CGFloat = 1
    private(set) var contentRotation: CGFloat = 0
    private(set) var isShowingEditingChrome = false

    static let hitPadAlpha: CGFloat = 1.0 / 255.0

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
    /// `rotation` radians.
    static func boundingSize(of size: CGSize, scale: CGFloat, rotation: CGFloat) -> CGSize {
        let c = abs(cos(rotation))
        let s = abs(sin(rotation))
        return CGSize(
            width: (size.width * c + size.height * s) * scale,
            height: (size.width * s + size.height * c) * scale
        )
    }

    /// Shows `contents` (a CGImage or an IOSurface, as accepted by
    /// `CALayer.contents`) at `pointSize`, with an optional layer shadow.
    /// M2 adds `show(_:shadow:style:)` on top of this.
    func showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?) {
        contentPointSize = pointSize
        layerShadow = shadow
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

    /// Drops the bitmap. Call before ordering out and closing a panel for good:
    /// a closed window keeps its contents alive until the next event otherwise.
    func clearContents() {
        withoutAnimation { contentLayer.contents = nil }
    }

    /// Scales and rotates the content around its centre (a live gesture preview).
    func setContentTransform(scale: CGFloat, rotation: CGFloat) {
        contentScale = scale
        contentRotation = rotation
        withoutAnimation {
            contentLayer.transform = CATransform3DScale(
                CATransform3DMakeRotation(rotation, 0, 0, 1), scale, scale, 1)
            updateOutlinePath()
        }
    }

    /// The hit pad and outline shown while the sticker is being edited.
    func setEditingChrome(_ visible: Bool) {
        isShowingEditingChrome = visible
        withoutAnimation {
            hitPadLayer.isHidden = !visible
            outlineLayer.isHidden = !visible
        }
    }

    /// Layer-hosting views don't pass the backing scale to their sublayers, so the
    /// dashed outline (the only layer that draws vector content) gets it here:
    /// when the view joins a window and whenever that window's scale changes.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        matchOutlineToBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        matchOutlineToBackingScale()
    }

    private func matchOutlineToBackingScale() {
        guard let scale = window?.backingScaleFactor else { return }
        withoutAnimation { outlineLayer.contentsScale = scale }
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

    private func updateOutlinePath() {
        let box = Self.boundingSize(of: contentPointSize, scale: contentScale, rotation: contentRotation)
        let rect = CGRect(x: bounds.midX - box.width / 2, y: bounds.midY - box.height / 2,
                          width: box.width, height: box.height).insetBy(dx: -2, dy: -2)
        outlineLayer.path = CGPath(rect: rect, transform: nil)
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
            if event.clickCount == 2 { onDoubleClick?() }
            return
        }
        window?.performDrag(with: event)
        onDragEnded?()
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
