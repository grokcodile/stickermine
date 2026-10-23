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

    /// How often `ignoresMouseEvents` has been written on this panel. Writing it at
    /// all, even `false`, switches the window to rectangle hit-testing for good, and
    /// the getter reads `false` either way, so this count is the only runtime sign.
    /// Flow tests expect it to stay 0 unless the hidden fallback mode is on.
    private(set) var mouseFlagWrites = 0

    /// How often `isFloatingPanel` has been written. Setting it rewrites the level.
    private(set) var floatingFlagWrites = 0

    override var ignoresMouseEvents: Bool {
        get { super.ignoresMouseEvents }
        set {
            mouseFlagWrites += 1
            super.ignoresMouseEvents = newValue
        }
    }

    override var isFloatingPanel: Bool {
        get { super.isFloatingPanel }
        set {
            floatingFlagWrites += 1
            super.isFloatingPanel = newValue
        }
    }

    override var canBecomeKey: Bool { isEditing }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
