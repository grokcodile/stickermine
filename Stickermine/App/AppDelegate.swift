import AppKit
import os

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is hosting the unit-test bundle. Every startup step
    /// (single-instance check, hotkey, status item, sticker restore, launch repair,
    /// SMAppService, updater) must be skipped then, so tests never show a window
    /// or touch system state (spec section 18).
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Set right after the test-host guard, so a test can prove the guard returned
    /// early.
    private(set) static var didRunStartup = false

    /// From design/spike-results.md, Decisions: "Alpha click-through works, or
    /// the fallback mode becomes the default?" (keep the value M2 chose). The
    /// hidden `clickThroughFallback` setting (spec section 12) overrides it either
    /// way.
    static let clickThroughFallbackByDefault = false

    private let log = Logger(subsystem: "com.ethan.stickermine", category: "app")
    private var library: LibraryController?
    private var stickers: StickerManager?
    private var session: SessionCoordinator?
    private var statusItem: StatusItemController?
    private var hotkeys: HotkeyCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.arguments.contains(StyleGallery.launchArgument) {
            // Debug: render the style gallery and quit, without touching the library.
            StyleGallery.runAndQuit()
            return
        }
        startStickers()
        startCapture()
    }

    /// SIGTERM skips this, so nothing may depend on it; the debounced save has
    /// usually run already. A running screencapture is terminated and its
    /// temporary file deleted first (spec section 5.10).
    func applicationWillTerminate(_ notification: Notification) {
        session?.cancel()
        library?.flush()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Loads the library (with launch repair) and restores every sticker on the
    /// connected displays. Every launch does this (spec section 13).
    private func startStickers() {
        let root: URL
        do {
            root = try LibraryStore.defaultRoot()
        } catch {
            log.error("no Application Support folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        let store = LibraryStore(root: root)
        let library = LibraryController(store: store)
        let renderer = StyleRenderer(masterProvider: { id in MasterImage.image(at: store.pngURL(for: id)) })
        let screens = LiveScreenProvider()
        let stickers = StickerManager(library: library, screens: screens, renderer: renderer)
        let defaults = UserDefaults.standard
        // Keys from spec section 12; M6's Settings enum takes these over.
        stickers.setSharingHidden(defaults.object(forKey: "hideFromSharing") as? Bool ?? true)
        if defaults.object(forKey: "clickThroughFallback") as? Bool ?? Self.clickThroughFallbackByDefault {
            stickers.enableClickThroughFallback()
        }
        stickers.startObservingDisplayChanges()
        stickers.restoreAll()
        renderer.prewarm()
        self.library = library
        self.stickers = stickers
        log.notice("library \(Self.describe(library.loadResult), privacy: .public): \(library.library.stickers.count) stickers")

        let session = SessionCoordinator(capture: CaptureService(), cutout: CutoutEngine(), stickers: stickers,
                                         library: library, store: store, renderer: renderer, screens: screens)
        // Double-clicks don't enter editing while a session runs (spec section 5.2).
        stickers.isSessionActive = { [weak session] in session?.isActive ?? false }
        self.session = session
    }

    /// The capture triggers: the menu bar icon and the global shortcut
    /// (default ⌃⌥⌘S; M6 reads the stored one and adds the recorder).
    private func startCapture() {
        // Leftovers from a run that was killed mid-capture (spec section 5.10).
        CaptureService.deleteLeftovers()
        guard let session else { return }
        let shortcut = Shortcut.defaultCapture
        let statusItem = StatusItemController(shortcut: shortcut)
        statusItem.onCapture = { [weak session] in session?.startCapture() }
        statusItem.onQuit = { [weak self] in self?.quit() }
        session.onActiveChange = { [weak statusItem] active in statusItem?.sessionActive = active }
        let hotkeys = HotkeyCenter()
        hotkeys.register(shortcut) { [weak session] in session?.startCapture() }
        self.statusItem = statusItem
        self.hotkeys = hotkeys
    }

    /// The menu's Quit: cancel the session, then quit (spec section 5.2).
    private func quit() {
        session?.cancel()
        NSApp.terminate(nil)
    }

    private static func describe(_ result: LibraryStore.LoadResult) -> String {
        switch result {
        case .fresh: return "fresh"
        case .loaded: return "loaded"
        case .readOnlyNewer: return "read-only (saved by a newer Stickermine)"
        case .recoveredFromCorrupt: return "recovered from a corrupt library.json"
        }
    }
}
