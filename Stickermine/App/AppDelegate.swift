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
    /// the fallback mode becomes the default?". The hidden `clickThroughFallback`
    /// setting (spec section 12) overrides it either way.
    static let clickThroughFallbackByDefault = false

    private let log = Logger(subsystem: "com.ethan.stickermine", category: "app")
    private var library: LibraryController?
    private var stickers: StickerManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
        startStickers()
    }

    /// SIGTERM skips this, so nothing may depend on it; the debounced save has
    /// usually run already.
    func applicationWillTerminate(_ notification: Notification) {
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

        if ProcessInfo.processInfo.arguments.contains(DebugMaple.launchArgument) {
            DebugMaple.place(library: library, stickers: stickers, screens: screens)
        }
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
