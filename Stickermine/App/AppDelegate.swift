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
    /// the fallback mode becomes the default?", kept in the pure `Settings`
    /// since M6 Task 1. The hidden `clickThroughFallback` setting (spec
    /// section 12) overrides it either way.
    nonisolated static let clickThroughFallbackByDefault = Settings.clickThroughFallbackByDefault

    private let log = Logger(subsystem: "com.ethan.stickermine", category: "app")
    private let defaults = UserDefaults.standard
    private var library: LibraryController?
    private var stickers: StickerManager?
    private var session: SessionCoordinator?
    private var screens: ScreenProvider?
    private var statusItem: StatusItemController?
    private var hotkeys: HotkeyCenter?
    private var loginItem: LoginItem?
    private var updater: Updater?
    private var tutorials: TutorialStickers?
    private var supportAsk: SupportAsk?
    private var home: HomeWindowController?
    private let thumbnails = ThumbnailCache()
    private var showHomeObserver: NSObjectProtocol?
    /// Another copy was already running when this one started (spec section 13).
    private var incumbent: NSRunningApplication?

    /// The single-instance check runs before anything can appear or register.
    /// Whether this is a login launch can only be read in
    /// `applicationDidFinishLaunching`, so the hand-over itself waits for that.
    func applicationWillFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        incumbent = SingleInstance.runningIncumbent()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        if ProcessInfo.processInfo.arguments.contains(StyleGallery.launchArgument) {
            // Debug: render the style gallery and quit, without touching the
            // library. Before the hand-over, so it runs while another copy does.
            NSApp.setActivationPolicy(.accessory)
            StyleGallery.runAndQuit()
            return
        }
        let loginLaunch = SingleInstance.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)
        if let incumbent {
            log.notice("another copy (pid \(incumbent.processIdentifier)) is running; handing over")
            SingleInstance.yield(to: incumbent, userLaunch: !loginLaunch)
        }
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
        Settings.register(in: defaults)
        startStickers()
        startCapture()
        startShell(loginLaunch: loginLaunch)
    }

    /// SIGTERM skips this, so nothing may depend on it; the debounced save has
    /// usually run already.
    func applicationWillTerminate(_ notification: Notification) {
        terminationCleanup()
    }

    /// Opening the app again (Finder, Spotlight, the Dock) while it runs.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showHome()
        return true
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
        stickers.setSharingHidden(defaults.hideFromSharing)
        if defaults.clickThroughFallback {
            stickers.enableClickThroughFallback()
        }
        stickers.startObservingDisplayChanges()
        stickers.restoreAll()
        renderer.prewarm()
        self.library = library
        self.stickers = stickers
        self.screens = screens
        log.notice("library \(Self.describe(library.loadResult), privacy: .public): \(library.library.stickers.count) stickers")

        let session = SessionCoordinator(capture: CaptureService(), cutout: CutoutEngine(), stickers: stickers,
                                         library: library, store: store, renderer: renderer, screens: screens)
        // Double-clicks don't enter editing while a session runs (spec section 5.2).
        stickers.isSessionActive = { [weak session] in session?.isActive ?? false }
        self.session = session
        tutorials = TutorialStickers(library: library, stickers: stickers, screens: screens, defaults: defaults)
        library.onChange = { [weak self] in self?.home?.model.libraryChanged() }
    }

    /// The capture triggers: the menu bar icon and the stored global shortcut
    /// (none once the user cleared it).
    private func startCapture() {
        // Leftovers from a run that was killed mid-capture (spec section 5.10).
        CaptureService.deleteLeftovers()
        guard let session else { return }
        let shortcut = defaults.captureShortcut
        let statusItem = StatusItemController(shortcut: shortcut)
        statusItem.isVisible = defaults.showMenuBarIcon
        statusItem.onCapture = { [weak session] in session?.startCapture() }
        statusItem.onOpenHome = { [weak self] in self?.showHome() }
        statusItem.onQuit = { [weak self] in self?.quit() }
        session.onActiveChange = { [weak self] active in self?.sessionActiveChanged(active) }
        session.onPlaced = { [weak self] _, sticker in self?.placementClicked(sticker) }
        let hotkeys = HotkeyCenter()
        hotkeys.register(shortcut) { [weak session] in session?.startCapture() }
        self.statusItem = statusItem
        self.hotkeys = hotkeys
        supportAsk = SupportAsk(defaults: defaults,
                                anchor: { [weak statusItem] in statusItem?.buttonScreenFrame },
                                fallbackArea: { [weak self] in self?.screens?.mainDisplay?.visibleFrame })
    }

    /// Launch at login, the updater, the hand-over notification and what this
    /// launch opens (spec section 13).
    private func startShell(loginLaunch: Bool) {
        let loginItem = LoginItem(defaults: defaults)
        loginItem.applyAtLaunch()
        self.loginItem = loginItem
        let updater = Updater(beforeHelper: { [weak self] in self?.terminationCleanup() })
        self.updater = updater
        showHomeObserver = DistributedNotificationCenter.default().addObserver(
            forName: SingleInstance.showHomeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showHome() }
        }
        guard let library else { return }
        let plan = LaunchPlan.decide(loginLaunch: loginLaunch, didFirstRun: defaults.didFirstRun,
                                     libraryIsEmpty: library.library.stickers.isEmpty, readOnly: library.isReadOnly)
        log.notice("launch: login=\(loginLaunch) home=\(plan.opensHome) tutorials=\(plan.placesTutorials)")
        if plan.placesTutorials {
            // The size Home's first show() gives it on this display, so the
            // tutorials keep clear of it there too.
            let homeSize = screens?.mainDisplay.map {
                TutorialLayout.homeSize(preferred: HomeWindowController.initialSize,
                                        minimum: HomeWindowController.minimumSize, in: $0.visibleFrame)
            } ?? HomeWindowController.initialSize
            tutorials?.placeFirstRun(shortcut: defaults.captureShortcut, homeSize: homeSize)
        }
        if plan.opensHome {
            showHome()
        }
        if plan.checksForUpdateAfterLogin {
            DispatchQueue.main.asyncAfter(deadline: .now() + LaunchPlan.loginUpdateCheckDelay) { [weak self] in
                MainActor.assumeIsolated {
                    updater.check { [weak self] _ in
                        guard updater.state != .upToDate else { return }
                        self?.showHome(checkingForUpdate: false)
                    }
                }
            }
        }
    }

    // MARK: Home

    /// Opens Home (reopen, the hand-over notification, the menu's Open
    /// Stickermine…, ⌘,). Opening it checks for an update, unless the caller
    /// has just checked.
    func showHome(checkingForUpdate: Bool = true) {
        guard let home = home ?? makeHome() else { return }
        home.show()
        if checkingForUpdate { updater?.check() }
    }

    private func makeHome() -> HomeWindowController? {
        guard let library, let stickers, let session, let loginItem, let updater else { return nil }
        var actions = HomeModel.Actions()
        actions.newSticker = { [weak self, weak session] in session?.startCapture(orderingOut: self?.home?.window) }
        actions.replace = { [weak session] sticker in session?.startReplace(sticker: sticker) }
        actions.delete = { [weak self, weak session, weak stickers] sticker in
            guard let stickers else { return }
            HistoryDeletion.delete(sticker, session: session, stickers: stickers, thumbnails: self?.thumbnails)
        }
        actions.shortcutChanged = { [weak self] shortcut in self?.shortcutChanged(shortcut) }
        actions.recordingChanged = { [weak self] recording in
            if recording { self?.hotkeys?.suspend() } else { self?.hotkeys?.resume() }
        }
        actions.menuBarIconChanged = { [weak self] visible in self?.statusItem?.isVisible = visible }
        actions.sharingHiddenChanged = { [weak stickers] hidden in stickers?.setSharingHidden(hidden) }
        actions.fixScreenRecording = { [weak session] in session?.showPermissionPanel() }
        actions.relaunch = { PermissionPanel.relaunch() }
        actions.quit = { [weak self] in self?.quit() }
        let model = HomeModel(library: library, defaults: defaults, loginItem: loginItem,
                              access: LiveScreenRecordingAccess(), thumbnails: thumbnails, updater: updater,
                              actions: actions)
        model.sessionActive = session.isActive
        let home = HomeWindowController(model: model,
                                        mainVisibleFrame: { [weak self] in self?.screens?.mainDisplay?.visibleFrame })
        self.home = home
        return home
    }

    // MARK: Events

    private func sessionActiveChanged(_ active: Bool) {
        statusItem?.sessionActive = active
        home?.model.sessionActive = active
    }

    /// A placement click (fresh or re-placed); cross-display drags never come here.
    private func placementClicked(_ sticker: UUID) {
        let isTutorial = library?.library.sticker(sticker)?.tutorial ?? false
        supportAsk?.placementClicked(isTutorial: isTutorial)
    }

    /// Home stored the new shortcut: register it (or nothing), show it in the
    /// menu, and redraw tutorial 1 if it still exists.
    private func shortcutChanged(_ shortcut: Shortcut?) {
        hotkeys?.register(shortcut) { [weak session] in session?.startCapture() }
        statusItem?.setShortcut(shortcut)
        tutorials?.shortcutChanged(to: shortcut)
    }

    /// The menu's and Home's Quit: clean up, then quit (spec section 5.2).
    private func quit() {
        terminationCleanup()
        NSApp.terminate(nil)
    }

    /// Spec section 5.10, run by `applicationWillTerminate`, Quit and the
    /// updater before its helper: cancel the session (terminating a running
    /// screencapture and deleting its temporary file), decline a support ask
    /// that is up, and flush the pending library save.
    private func terminationCleanup() {
        session?.cancel()
        supportAsk?.dismiss()
        library?.flush()
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
