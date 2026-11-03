import AppKit
import SwiftUI

/// What Home shows and does (spec section 13): the history, the settings,
/// the read-only notice and the session state. Writes the settings to
/// `UserDefaults` and asks the rest of the app to act through `Actions`, so
/// tests drive it without a window, a session or the real defaults.
@MainActor
final class HomeModel: ObservableObject {
    /// What Home asks the app to do. AppDelegate fills these in.
    struct Actions {
        var newSticker: () -> Void = {}
        var replace: (UUID) -> Void = { _ in }
        var delete: (UUID) -> Void = { _ in }
        /// After the new shortcut is stored: re-register the hotkey, update
        /// the menu and re-render tutorial 1.
        var shortcutChanged: (Shortcut?) -> Void = { _ in }
        /// The recorder started (true) or stopped listening: suspend or resume the hotkey.
        var recordingChanged: (Bool) -> Void = { _ in }
        var menuBarIconChanged: (Bool) -> Void = { _ in }
        var sharingHiddenChanged: (Bool) -> Void = { _ in }
        /// The permission panel (spec section 14).
        var fixScreenRecording: () -> Void = {}
        /// Quit and reopen, in case the in-process Screen Recording check is stale.
        var relaunch: () -> Void = {}
        var quit: () -> Void = {}
    }

    /// A Delete from History waiting for its confirmation.
    struct PendingDelete: Equatable, Identifiable {
        let id: UUID
        let message: String
    }

    static let emptyHistoryText = "Stickers you make show up here. Click one to place it again."

    @Published private(set) var history: [StickerRecord] = []
    /// A library saved by a newer Stickermine: shown, never changed (spec section 12).
    @Published private(set) var isReadOnly = false
    /// A session runs: New Sticker and the grid are ignored (spec section 5.2).
    @Published var sessionActive = false
    @Published private(set) var shortcut: Shortcut?
    /// The shortcut is one of macOS's own enabled shortcuts.
    @Published private(set) var shortcutConflicts = false
    /// The last chord typed into the recorder had no ⌘ or ⌃.
    @Published private(set) var chordRejected = false
    @Published private(set) var showMenuBarIcon = true
    @Published private(set) var loginState: LoginItem.State = .on
    @Published private(set) var hideFromSharing = true
    @Published private(set) var screenRecordingOn = false
    /// Access was asked for once already (`didRequestScreenCapture`).
    @Published private(set) var screenRecordingRequested = false
    @Published var pendingDelete: PendingDelete?

    let library: LibraryController
    let thumbnails: ThumbnailCache
    let updater: Updater
    private let defaults: UserDefaults
    private let loginItem: LoginItem
    private let access: ScreenRecordingAccess
    private let conflicts: (Shortcut) -> Bool
    private let actions: Actions

    init(library: LibraryController, defaults: UserDefaults, loginItem: LoginItem, access: ScreenRecordingAccess,
         thumbnails: ThumbnailCache, updater: Updater,
         conflicts: @escaping (Shortcut) -> Bool = { SystemShortcuts.conflicts(with: $0) },
         actions: Actions) {
        self.library = library
        self.defaults = defaults
        self.loginItem = loginItem
        self.access = access
        self.thumbnails = thumbnails
        self.updater = updater
        self.conflicts = conflicts
        self.actions = actions
        refresh()
    }

    // MARK: Reading

    /// Re-reads everything: on creation and whenever Home becomes key, so a
    /// Screen Recording grant, a Login Items approval or a change made
    /// elsewhere shows at once (spec section 14).
    func refresh() {
        libraryChanged()
        shortcut = defaults.captureShortcut
        shortcutConflicts = shortcut.map(conflicts) ?? false
        showMenuBarIcon = defaults.showMenuBarIcon
        loginState = loginItem.state
        hideFromSharing = defaults.hideFromSharing
        screenRecordingOn = access.preflight()
        screenRecordingRequested = defaults.didRequestScreenCapture
    }

    /// The library changed (`LibraryController.onChange`).
    func libraryChanged() {
        isReadOnly = library.isReadOnly
        let items = HistoryList.items(in: library.library)
        if items != history { history = items }
        if let pending = pendingDelete, library.library.sticker(pending.id) == nil { pendingDelete = nil }
    }

    func pngURL(for sticker: UUID) -> URL {
        library.store.pngURL(for: sticker)
    }

    // MARK: History

    func newSticker() {
        guard !isReadOnly, !sessionActive else { return }
        actions.newSticker()
    }

    func replace(_ sticker: UUID) {
        guard !isReadOnly, !sessionActive else { return }
        actions.replace(sticker)
    }

    func requestDelete(_ sticker: UUID) {
        guard !isReadOnly, library.library.sticker(sticker) != nil else { return }
        pendingDelete = PendingDelete(
            id: sticker, message: HistoryList.deleteMessage(placementCount: library.library.placementCount(of: sticker)))
    }

    func confirmDelete() {
        guard let pending = pendingDelete else { return }
        pendingDelete = nil
        actions.delete(pending.id)
        libraryChanged()
    }

    func cancelDelete() {
        pendingDelete = nil
    }

    // MARK: Settings

    /// A recorded (or, with nil, cleared) shortcut.
    func setShortcut(_ shortcut: Shortcut?) {
        chordRejected = false
        defaults.captureShortcut = shortcut
        self.shortcut = shortcut
        shortcutConflicts = shortcut.map(conflicts) ?? false
        actions.shortcutChanged(shortcut)
    }

    func recordingChanged(_ recording: Bool) {
        if recording { chordRejected = false }
        actions.recordingChanged(recording)
    }

    func rejectChord() {
        chordRejected = true
    }

    func setShowMenuBarIcon(_ on: Bool) {
        defaults.showMenuBarIcon = on
        showMenuBarIcon = on
        actions.menuBarIconChanged(on)
    }

    func setLaunchAtLogin(_ on: Bool) {
        loginItem.setEnabled(on)
        loginState = loginItem.state
    }

    func openLoginItems() {
        loginItem.openSystemSettings()
    }

    func setHideFromSharing(_ on: Bool) {
        defaults.hideFromSharing = on
        hideFromSharing = on
        actions.sharingHiddenChanged(on)
    }

    func fixScreenRecording() {
        actions.fixScreenRecording()
    }

    func relaunch() {
        actions.relaunch()
    }

    func quit() {
        actions.quit()
    }
}
