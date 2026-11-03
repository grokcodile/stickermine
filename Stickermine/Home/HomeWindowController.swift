import AppKit
import SwiftUI

/// Home's window. ⌘W closes it: the app's main menu has no Close item.
@MainActor
final class HomeWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if Self.isClose(event) {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    /// ⌘W and nothing else (Caps Lock, Fn and the keypad flag don't count).
    nonisolated static func isClose(_ event: NSEvent) -> Bool {
        event.type == .keyDown
            && event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "w"
    }
}

/// The Home window (spec section 13), an AppKit window hosting `HomeView`.
/// Created once and kept: closing only orders it out. The first time it
/// shows, it is centred on the main display's visible frame at the size
/// `TutorialLayout.homeSize` gives (smaller on a small display), which is
/// where the first-run tutorial stickers keep clear of
/// (`TutorialLayout.homeFrame`); after that it stays wherever the user moved it. Becoming key re-reads the
/// settings and the Screen Recording state (spec section 14); resigning key
/// or closing stops the shortcut recorder, so the hotkey always comes back.
@MainActor
final class HomeWindowController: NSObject, NSWindowDelegate {
    static let initialSize = CGSize(width: 640, height: 640)
    static let minimumSize = CGSize(width: 560, height: 480)

    let window: HomeWindow
    let model: HomeModel
    private let mainVisibleFrame: () -> CGRect?
    private var hasShown = false

    init(model: HomeModel, mainVisibleFrame: @escaping () -> CGRect?,
         openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.model = model
        self.mainVisibleFrame = mainVisibleFrame
        window = Self.makeWindow()
        super.init()
        let host = NSHostingView(rootView: HomeView(model: model, updater: model.updater, openURL: openURL))
        // SwiftUI sets only the minimum size; the window keeps the size it is
        // given, so its first frame is exactly the one the tutorials avoid.
        host.sizingOptions = [.minSize]
        window.contentView = host
        window.setContentSize(Self.initialSize)
        window.delegate = self
    }

    static func makeWindow() -> HomeWindow {
        let window = HomeWindow(contentRect: NSRect(origin: .zero, size: initialSize),
                                styleMask: [.titled, .closable, .resizable, .fullSizeContentView],
                                backing: .buffered, defer: false)
        window.title = "Stickermine"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.minSize = minimumSize
        // Opening Stickermine brings Home to the Space the user is on.
        window.collectionBehavior = [.moveToActiveSpace]
        return window
    }

    var isVisible: Bool { window.isVisible }

    /// Shows Home in front and activates Stickermine.
    func show() {
        if !hasShown {
            hasShown = true
            if let visible = mainVisibleFrame() {
                // Narrowed and shortened on a small display, so it fits and the
                // first-run tutorials' column beside it keeps its minimum width.
                let size = TutorialLayout.homeSize(preferred: Self.initialSize, minimum: Self.minimumSize, in: visible)
                window.setFrame(TutorialLayout.homeFrame(size: size, in: visible), display: false)
            } else {
                window.center()
            }
        }
        model.refresh()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        // NSApp.activate() is cooperative (macOS 14+): with no user input behind
        // it (the update check 6 s after a login launch) the system may decline,
        // and an inactive app's window would stay behind the active app's.
        window.orderFrontRegardless()
    }

    func close() {
        window.performClose(nil)
    }

    // MARK: NSWindowDelegate

    func windowDidBecomeKey(_ notification: Notification) {
        model.refresh()
    }

    func windowDidResignKey(_ notification: Notification) {
        ShortcutRecorderButton.active?.cancelRecording()
    }

    func windowWillClose(_ notification: Notification) {
        ShortcutRecorderButton.active?.cancelRecording()
        model.cancelDelete()
    }
}
