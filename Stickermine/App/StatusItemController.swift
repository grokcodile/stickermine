import AppKit
import Carbon.HIToolbox

/// The menu bar icon (spec section 13): the pickaxe glyph from
/// `design/menubar-glyph.svg` (asset `MenuBarGlyph`, a template image drawn
/// white or black to match the menu bar). A left-click starts a capture; a
/// right-click or Control-click shows the menu: New Sticker (with the
/// shortcut; disabled during a session) and Quit. M6 adds Open Stickermine…
/// and hiding the icon. `MenuBarExtra` isn't used: it can't act on a plain click.
@MainActor
final class StatusItemController: NSObject {
    static let glyphName = "MenuBarGlyph"
    /// The SVG reports 200 × 200 pt; the menu bar wants 18 × 18.
    static let glyphSize = NSSize(width: 18, height: 18)

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let newStickerItem: NSMenuItem

    /// A left-click or the menu's New Sticker.
    var onCapture: (() -> Void)?
    /// The menu's Quit.
    var onQuit: (() -> Void)?

    /// While a session runs, New Sticker is disabled (spec section 5.2).
    var sessionActive = false {
        didSet { Self.applySessionState(sessionActive, to: newStickerItem) }
    }

    init(shortcut: Shortcut?) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let built = Self.makeMenu(shortcut: shortcut)
        menu = built.menu
        newStickerItem = built.newSticker
        super.init()
        newStickerItem.target = self
        newStickerItem.action = #selector(newSticker(_:))
        built.quit.target = self
        built.quit.action = #selector(quit(_:))
        if let button = statusItem.button {
            button.image = Self.glyph()
            button.toolTip = "Stickermine"
            button.setAccessibilityLabel("Stickermine")
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Shows the shortcut in the menu (nil: none).
    func setShortcut(_ shortcut: Shortcut?) {
        Self.applyShortcut(shortcut, to: newStickerItem)
    }

    /// The glyph from the asset catalog, as an 18 × 18 pt template image.
    static func glyph() -> NSImage? {
        guard let named = NSImage(named: glyphName), let image = named.copy() as? NSImage else { return nil }
        image.size = glyphSize
        image.isTemplate = true
        return image
    }

    /// The menu: New Sticker (with the shortcut), a separator, Quit Stickermine.
    static func makeMenu(shortcut: Shortcut?) -> (menu: NSMenu, newSticker: NSMenuItem, quit: NSMenuItem) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let newSticker = NSMenuItem(title: "New Sticker", action: nil, keyEquivalent: "")
        applyShortcut(shortcut, to: newSticker)
        menu.addItem(newSticker)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Stickermine", action: nil, keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        return (menu, newSticker, quit)
    }

    /// The item shows `shortcut` as its key equivalent (nothing when there is
    /// none or the key can't be shown in a menu).
    static func applyShortcut(_ shortcut: Shortcut?, to item: NSMenuItem) {
        guard let shortcut, let key = shortcut.menuKeyEquivalent else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifierFlags(carbon: shortcut.modifiers)
    }

    static func applySessionState(_ active: Bool, to item: NSMenuItem) {
        item.isEnabled = !active
    }

    /// A Carbon modifier mask as AppKit modifier flags.
    static func modifierFlags(carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// A right-click or Control-click opens the menu; any other click captures.
    static func opensMenu(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseUp || type == .rightMouseDown || modifiers.contains(.control)
    }

    @objc private func buttonClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if let event, Self.opensMenu(type: event.type, modifiers: event.modifierFlags) {
            showMenu()
        } else {
            onCapture?()
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func newSticker(_ sender: Any?) {
        onCapture?()
    }

    @objc private func quit(_ sender: Any?) {
        onQuit?()
    }
}
