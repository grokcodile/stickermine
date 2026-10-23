import Foundation
import os

/// The in-memory library and its debounced saves (spec section 12): every
/// change schedules one save 0.5 s after the last change; `flush()` saves now
/// (applicationWillTerminate, and M6's updater before its helper runs). JSON is
/// encoded and written on the main actor.
@MainActor
final class LibraryController {
    let store: LibraryStore
    /// How the library was loaded (M6 shows the read-only notice for `.readOnlyNewer`).
    let loadResult: LibraryStore.LoadResult
    private(set) var library: Library
    /// Called after every change made through `mutate`.
    var onChange: (() -> Void)?
    /// A save is scheduled.
    private(set) var hasPendingSave = false
    /// Memory differs from what was last written.
    private(set) var hasUnsavedChanges = false

    private let saveDelay: TimeInterval
    private var saveWork: DispatchWorkItem?
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "library")

    init(store: LibraryStore, saveDelay: TimeInterval = 0.5) {
        self.store = store
        self.saveDelay = saveDelay
        let result = store.load()
        loadResult = result
        library = result.library
    }

    /// A library written by a newer Stickermine: shown, never changed.
    var isReadOnly: Bool { store.isReadOnly }

    /// Applies a user change and schedules a save. Ignored while read-only;
    /// a change that changes nothing schedules nothing.
    func mutate(_ change: (inout Library) -> Void) {
        guard !isReadOnly else {
            log.notice("change ignored: the library is read-only")
            return
        }
        var updated = library
        change(&updated)
        guard updated != library else { return }
        library = updated
        hasUnsavedChanges = true
        scheduleSave()
        onChange?()
    }

    /// For the spec's write exceptions that aren't user actions (a recorded
    /// display's `lastSeen` and `name`): kept in memory and written with the
    /// next save or flush, never scheduling one, so display events never write.
    func refreshMetadata(_ change: (inout Library) -> Void) {
        guard !isReadOnly else { return }
        var updated = library
        change(&updated)
        guard updated != library else { return }
        library = updated
        hasUnsavedChanges = true
    }

    /// Saves now if anything is unsaved, cancelling the scheduled save.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        hasPendingSave = false
        guard hasUnsavedChanges, !isReadOnly else { return }
        do {
            try store.save(library)
            hasUnsavedChanges = false
        } catch {
            log.error("saving library.json failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        saveWork = work
        hasPendingSave = true
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }
}
