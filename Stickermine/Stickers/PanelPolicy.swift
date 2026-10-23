import AppKit

/// Every window-policy constant lives here, so the sticker level, collection
/// behaviour and panel flags are decided in one place (spec sections 4 and 9).
///
/// Rules for every NSPanel the app creates:
/// - isReleasedWhenClosed is false, and hidesOnDeactivate is set explicitly (a
///   plain NSPanel defaults to true, which leaves it invisible and unclickable in
///   an accessory app that isn't active);
/// - the floating-panel flag is never touched: assigning it rewrites the level;
/// - the level is assigned last.
///
/// Sticker panels additionally never have their mouse-event flag written: left
/// untouched, the window server hit-tests by rendered alpha (alpha 0 clicks pass
/// through); writing it, with either value, switches the window to rectangle
/// hit-testing for good (spec section 9).
@MainActor
enum PanelPolicy {
    /// One level above Finder's desktop-icon window. Below it, Finder's
    /// screen-sized desktop window catches every click; above it is every app
    /// window. At exactly this level ScreenCaptureKit pickers that exclude desktop
    /// windows also leave stickers out.
    static var stickerLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    /// The level of a sticker with Float on top switched on.
    static let floatingLevel: NSWindow.Level = .floating

    /// On every desktop Space, never on full-screen Spaces, untouched by Mission
    /// Control, and skipped by window cycling.
    static let stickerBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone,
    ]

    static func level(onTop: Bool) -> NSWindow.Level {
        onTop ? floatingLevel : stickerLevel
    }

    /// The flags every panel in the app gets, whatever it is for.
    static func applyCommon(to panel: NSPanel, hidesOnDeactivate: Bool) {
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = hidesOnDeactivate
        panel.isExcludedFromWindowsMenu = true
        panel.isRestorable = false
    }

    /// The only way a sticker window is created. `hideFromSharing` is the
    /// "Hide stickers from screen sharing and screenshots" setting (default on)
    /// at creation time. A panel must start with the right value: on macOS 27.2
    /// a window that was once set to `.none` keeps reporting `.none` after a
    /// later `.readOnly`, so StickerManager recreates panels when the setting
    /// is turned off.
    static func makeStickerPanel(contentRect: NSRect, hideFromSharing: Bool = true) -> StickerPanel {
        let panel = StickerPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.canHide = false
        panel.animationBehavior = .none
        panel.sharingType = hideFromSharing ? .none : .readOnly
        panel.collectionBehavior = stickerBehavior
        panel.level = stickerLevel  // last
        return panel
    }
}
