import AppKit

/// One borderless, non-activating panel per placed sticker. Created only by
/// `PanelPolicy.makeStickerPanel(contentRect:)`.
@MainActor
final class StickerPanel: NSPanel {
    /// The placement this panel draws (nil for the M1 spike's hard-coded stickers).
    var placementID: UUID?

    /// A borderless panel can't become key by default. It may while its sticker is
    /// being edited, so Esc, Delete and trackpad gestures arrive.
    var isEditing = false

    /// Called after the panel stops being key (a click elsewhere, Esc handing focus
    /// back, the app deactivating). Editing ends here.
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { isEditing }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
