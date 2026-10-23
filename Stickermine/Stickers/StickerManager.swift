import AppKit
import os

/// Core Graphics calls this for every display reconfiguration pass (a global
/// function, so it carries no actor isolation into the C callback).
private func stickerDisplayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                        _ userInfo: UnsafeMutableRawPointer?) {
    StickerManager.displayReconfigured(display, flags: flags)
}

/// Owns every sticker panel and keeps them in step with the library and the
/// connected displays (spec sections 9 and 11).
///
/// - The model is the only source of truth. Every reconcile re-applies
///   visibility and frames from it to every panel; a snapshot diff of the
///   displays only decides whether poses are re-resolved.
/// - Panels of a display that is gone are ordered out and kept, and ordered in
///   again when it returns. A display event never writes the library.
/// - Only `place`, `remove` and `deleteSticker` (user actions) write, plus the
///   spec's exceptions: a returning display's lastSeen and name (quietly, with
///   the next save) and a fingerprint re-key on the next user edit.
@MainActor
final class StickerManager {
    /// Set from design/spike-results.md, Decisions: "Do panels go stale, and
    /// does a rebuild fix it?". When true, every panel is closed and recreated
    /// from the model 1.5 s after wake, unlock and display changes.
    static let rebuildsPanelsAfterSystemEvents = false
    /// Wake and unlock are checked again this long after the event.
    static let systemEventRecheckDelay: TimeInterval = 1.5

    /// What a display change must alter to re-resolve poses (spec section 11).
    struct DisplaySnapshot: Equatable {
        let frame: CGRect
        let backingScale: CGFloat
        let inMirrorSet: Bool

        init(_ display: DisplayInfo) {
            frame = display.frame
            backingScale = display.backingScale
            inMirrorSet = display.inMirrorSet
        }
    }

    private final class Entry {
        let panel: StickerPanel
        let view: StickerView
        /// The display the cached layout was resolved for.
        var displayUUID: String?
        var layout: StickerGeometry.Layout?
        /// The newest render asked for; a result for any other request is dropped.
        var request: RenderRequest?
        var alphaMask: AlphaMask?

        init(panel: StickerPanel, view: StickerView) {
            self.panel = panel
            self.view = view
        }
    }

    private let library: LibraryController
    private let screens: ScreenProvider
    private let renderer: StyleRenderer
    private let reconcileDelay: TimeInterval
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "stickers")

    private var entries: [UUID: Entry] = [:]
    private var lastSnapshot: [String: DisplaySnapshot] = [:]
    /// Rebuilt on every reconcile; display IDs are never persisted.
    private var displayIDToUUID: [UInt32: String] = [:]
    private var presentDisplays: [String: DisplayInfo] = [:]
    /// Connected display UUID → the record it shows (itself, or a fingerprint adoption).
    private var recordForDisplay: [String: String] = [:]
    private var reconcileWork: DispatchWorkItem?
    private var rebuildWork: DispatchWorkItem?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var sharingHidden = true
    private var fallback: ClickThroughFallback?

    /// The instance the Core Graphics callback reaches (the app has one).
    private static weak var observing: StickerManager?

    /// The placement being edited (M5's StickerEditor sets it; nothing does in M2).
    private(set) var editingPlacement: UUID?
    /// Diagnostics for logs and tests.
    private(set) var reconcileCount = 0
    private(set) var renderRequestsIssued = 0

    init(library: LibraryController, screens: ScreenProvider, renderer: StyleRenderer,
         reconcileDelay: TimeInterval = 0.45) {
        self.library = library
        self.screens = screens
        self.renderer = renderer
        self.reconcileDelay = reconcileDelay
    }

    // MARK: Panels from the model

    /// Creates panels for every placement on a connected display (launch).
    func restoreAll() {
        lastSnapshot = [:]
        reconcileNow()
    }

    /// Every display event restarts one timer; the reconcile runs when it fires.
    func scheduleReconcile() {
        reconcileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reconcileNow() }
        }
        reconcileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reconcileDelay, execute: work)
    }

    func reconcileNow() {
        reconcileWork?.cancel()
        reconcileWork = nil
        reconcileCount += 1
        let displays = screens.currentDisplays()
        guard !displays.isEmpty else {
            // No real display (only a ghost, or a moment mid-change): change nothing.
            log.notice("reconcile #\(self.reconcileCount): no usable display; nothing changed")
            return
        }
        let model = library.library
        let previouslyPresent = Set(presentDisplays.keys)
        displayIDToUUID = Dictionary(displays.map { ($0.displayID, $0.uuid) }, uniquingKeysWith: { first, _ in first })
        presentDisplays = Dictionary(displays.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        recordForDisplay = Self.recordAssignments(displays: displays, records: model.displays)
        let snapshot = presentDisplays.mapValues(DisplaySnapshot.init)
        let changed = Set(snapshot.keys.filter { lastSnapshot[$0] != snapshot[$0] })
        // A display was added, changed or removed (the count drops). lastSnapshot is
        // empty after launch, closeAllPanels() and rebuildAllPanels(): those never
        // schedule a rebuild, so a rebuild can't loop.
        let displaysChanged = !lastSnapshot.isEmpty && (!changed.isEmpty || lastSnapshot.count != snapshot.count)
        lastSnapshot = snapshot
        if Self.rebuildsPanelsAfterSystemEvents, displaysChanged { scheduleRebuild() }

        var displayForRecord: [String: DisplayInfo] = [:]
        for (displayUUID, recordKey) in recordForDisplay {
            displayForRecord[recordKey] = presentDisplays[displayUUID]
        }

        let livePlacements = Set(model.displays.values.flatMap { $0.placements.map(\.id) })
        for id in Array(entries.keys) where !livePlacements.contains(id) {
            tearDown(id)
        }

        for (recordKey, record) in model.displays {
            guard let display = displayForRecord[recordKey] else {
                // Its display is gone: order out, keep the panels for its return.
                for placement in record.placements {
                    if let entry = entries[placement.id], entry.panel.isVisible {
                        entry.panel.orderOut(nil)
                        log.notice("ordered out \(Self.short(placement.id), privacy: .public): display \(recordKey, privacy: .public) is gone")
                    }
                }
                continue
            }
            var needsOrdering = false
            for placement in record.placements {
                guard let sticker = model.sticker(placement.sticker) else { continue }
                let entry = entries[placement.id] ?? makeEntry(for: placement)
                if entry.layout == nil || entry.displayUUID != display.uuid || changed.contains(display.uuid) {
                    entry.layout = StickerGeometry.layout(for: placement, natural: sticker.naturalPointSize, on: display)
                    entry.displayUUID = display.uuid
                }
                guard let layout = entry.layout else {
                    if entry.panel.isVisible { entry.panel.orderOut(nil) }
                    continue
                }
                let level = PanelPolicy.level(onTop: placement.onTop)
                if entry.panel.level != level { entry.panel.level = level }
                applyFrame(entry, layout: layout)
                requestRender(entry, placement: placement, layout: layout, backingScale: display.backingScale)
                if !entry.panel.isVisible { needsOrdering = true }
            }
            if needsOrdering {
                // Back to front, so the record's order is the z-order.
                for placement in record.placements {
                    if let entry = entries[placement.id], entry.layout != nil {
                        entry.panel.orderFrontRegardless()
                        log.notice("ordered in \(Self.short(placement.id), privacy: .public) at \(NSStringFromRect(entry.panel.frame), privacy: .public)")
                    }
                }
            }
        }

        refreshDisplayMetadata(newlyPresent: Set(presentDisplays.keys).subtracting(previouslyPresent))
        log.notice("reconcile #\(self.reconcileCount): \(displays.count) displays, \(changed.count) changed, \(self.entries.count) panels")
    }

    func panel(for placement: UUID) -> StickerPanel? {
        entries[placement]?.panel
    }

    /// Placements that currently have a panel (visible or ordered out).
    var placementsWithPanels: Set<UUID> {
        Set(entries.keys)
    }

    /// Re-resolves one placement from the model after a change to it.
    func refreshPanel(for placement: UUID) {
        entries[placement]?.layout = nil
        reconcileNow()
    }

    /// Closes every panel; the next reconcile recreates them from the model.
    func closeAllPanels() {
        for id in Array(entries.keys) { tearDown(id) }
        lastSnapshot = [:]
    }

    /// Closes and recreates every panel from the model (the stale-window fix,
    /// spec section 9), ending any editing first.
    func rebuildAllPanels() {
        endEditing(discardGesture: true)
        closeAllPanels()
        reconcileNow()
    }

    /// Shows a finished render if it is still the newest one asked for and its
    /// placement still exists.
    func commitRender(_ rendered: RenderedSticker, for request: RenderRequest, placement id: UUID) {
        guard let entry = entries[id], entry.request == request, library.library.placement(id) != nil else { return }
        entry.view.show(rendered, shadow: nil, style: request.style)
        entry.alphaMask = rendered.alphaMask
        if let layout = entry.layout { applyFrame(entry, layout: layout) }
    }

    // MARK: User actions

    /// A user placement on the display under `centerOnScreen`, on top of its
    /// z-order: `poses = [size: pose]`, rotation 0, unflipped, not on top.
    /// Returns the new placement's ID (nil when read-only or the sticker is unknown).
    @discardableResult
    func place(sticker: UUID, style: StickerStyle, centerOnScreen: NSPoint, pointSize: CGSize) -> UUID? {
        guard !library.isReadOnly, let record = library.library.sticker(sticker) else { return nil }
        let natural = record.naturalPointSize
        guard natural.width > 0, pointSize.width > 0,
              let display = Self.display(containing: centerOnScreen, in: screens.currentDisplays())
        else { return nil }
        let center = StickerGeometry.reachableCenter(centerOnScreen, visibleFrame: display.visibleFrame)
        let pose = StickerGeometry.pose(center: center, scale: Double(pointSize.width / natural.width),
                                        in: display.frame)
        let placement = LayoutResolver.placing(pose, to: Placement(sticker: sticker, style: style, poses: [:]),
                                               at: display.size)
        let key = recordKeyForUserEdit(on: display)
        library.mutate { $0.displays[key]?.placements.append(placement) }
        reconcileNow()
        return placement.id
    }

    /// Removes one placement; the sticker stays in history. A tutorial sticker
    /// is deleted outright (spec section 13).
    func remove(placement id: UUID) {
        guard !library.isReadOnly else { return }
        let model = library.library
        guard let key = model.displayKey(containing: id), let placement = model.placement(id) else { return }
        if editingPlacement == id { endEditing(discardGesture: true) }
        if model.sticker(placement.sticker)?.tutorial == true {
            deleteSticker(placement.sticker)
            return
        }
        if let adopter = recordForDisplay.first(where: { $0.value == key && $0.key != key }),
           let display = presentDisplays[adopter.key] {
            _ = recordKeyForUserEdit(on: display)
        }
        tearDown(id)
        library.mutate { _ = $0.removePlacement(id) }
    }

    /// Delete from history: every placement on every display (connected or
    /// not), the PNG, then the entry (spec section 12).
    func deleteSticker(_ sticker: UUID) {
        guard !library.isReadOnly, library.library.sticker(sticker) != nil else { return }
        let placementIDs = library.library.displays.values.flatMap { record in
            record.placements.filter { $0.sticker == sticker }.map(\.id)
        }
        if let editing = editingPlacement, placementIDs.contains(editing) { endEditing(discardGesture: true) }
        placementIDs.forEach(tearDown)
        do {
            try library.store.deletePNG(for: sticker)
        } catch {
            log.error("deleting the PNG of \(sticker.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        library.mutate { $0.removeSticker(sticker) }
    }

    /// The record key a user edit on `display` writes to. Creates the record on
    /// the first placement; saves a fingerprint adoption as a re-key (spec section 11).
    func recordKeyForUserEdit(on display: DisplayInfo) -> String {
        let model = library.library
        if model.displays[display.uuid] != nil { return display.uuid }
        if let adopted = DisplayRegistry.fingerprintAdoption(
            for: display, records: model.displays, connected: screens.currentDisplays()) {
            library.mutate { library in
                library.moveDisplayRecord(from: adopted, to: display.uuid)
                library.displays[display.uuid]?.name = display.name
                library.displays[display.uuid]?.lastSeen = Date()
            }
            log.notice("re-keyed display record \(adopted, privacy: .public) as \(display.uuid, privacy: .public)")
        } else {
            library.mutate { library in
                library.displays[display.uuid] = DisplayRecord(
                    name: display.name, vendor: display.vendor, model: display.model, serial: display.serial,
                    builtin: display.builtin, lastSeen: Date(), placements: [])
            }
        }
        recordForDisplay[display.uuid] = display.uuid
        return display.uuid
    }

    // MARK: Settings

    /// "Hide stickers from screen sharing and screenshots", applied live.
    /// Hiding is set on each panel. A panel that keeps reporting `.none` after
    /// `.readOnly` (macOS 27.2, on a window once set to `.none`) is replaced by
    /// a new panel created with the new setting, which takes over the old one's
    /// bitmap, layout and render request, so the sticker never shows empty while
    /// a render runs.
    func setSharingHidden(_ hidden: Bool) {
        sharingHidden = hidden
        let wanted: NSWindow.SharingType = hidden ? .none : .readOnly
        var stuck: [UUID] = []
        for (id, entry) in entries {
            entry.panel.sharingType = wanted
            if entry.panel.sharingType != wanted { stuck.append(id) }
        }
        guard !stuck.isEmpty else { return }
        if let editing = editingPlacement, stuck.contains(editing) { endEditing(discardGesture: true) }
        let model = library.library
        for id in stuck {
            guard let old = entries[id], let placement = model.placement(id) else {
                tearDown(id)
                continue
            }
            let contents = old.view.contentLayer.contents
            let pointSize = old.view.contentPointSize
            let shadow = old.view.layerShadow
            let frame = old.panel.frame
            tearDown(id)
            let fresh = makeEntry(for: placement)
            fresh.displayUUID = old.displayUUID
            fresh.layout = old.layout
            fresh.request = old.request
            fresh.alphaMask = old.alphaMask
            if let contents { fresh.view.showContents(contents, pointSize: pointSize, shadow: shadow) }
            fresh.panel.setFrame(frame, display: false)
        }
        log.notice("recreated \(stuck.count) panels to change their sharing type")
        // Orders the new panels in, back to front; nothing is re-resolved or re-rendered.
        reconcileNow()
    }

    /// The hidden `clickThroughFallback` setting, read at launch (spec section 9).
    func enableClickThroughFallback() {
        guard fallback == nil else { return }
        let fallback = ClickThroughFallback(targets: { [weak self] in self?.fallbackTargets() ?? [] })
        for entry in entries.values { fallback.prepare(entry.panel) }
        fallback.start()
        self.fallback = fallback
    }

    var isClickThroughFallbackEnabled: Bool { fallback != nil }

    // MARK: Editing (M5 owns entering it)

    /// Ends editing, if any. M2 never enters editing (M5 adds StickerEditor);
    /// this clears the state so delete, remove and rebuild already end editing first.
    func endEditing(discardGesture: Bool) {
        guard let id = editingPlacement else { return }
        editingPlacement = nil
        guard let entry = entries[id] else { return }
        entry.panel.isEditing = false
        entry.view.setEditingChrome(false)
        entry.view.setContentTransform(scale: 1, rotation: 0)
        if let layout = entry.layout { applyFrame(entry, layout: layout) }
    }

    // MARK: System events

    /// Observes screen changes, wake, unlock and the Core Graphics display
    /// callback. The app calls it once; tests drive `reconcileNow()` directly.
    func startObservingDisplayChanges() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, recheckLater: false)
        observe(workspace, NSWorkspace.didWakeNotification, recheckLater: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, recheckLater: true)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"),
                recheckLater: true)
        Self.observing = self
        let status = CGDisplayRegisterReconfigurationCallback(stickerDisplayReconfigured, nil)
        if status != .success {
            log.error("CGDisplayRegisterReconfigurationCallback failed: \(status.rawValue)")
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, recheckLater: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemEvent(recheckLater: recheckLater) }
        }
        observers.append((center, token))
    }

    /// A screen change, wake or unlock: restart the reconcile timer. After wake
    /// and unlock, check again 1.5 s later and, if the spike said so, rebuild.
    /// A screen-parameters notification alone never rebuilds: the Dock and EDR
    /// headroom changes post it too. The reconcile schedules the rebuild when it
    /// finds a display added, removed or changed.
    func systemEvent(recheckLater: Bool) {
        scheduleReconcile()
        guard recheckLater else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.systemEventRecheckDelay) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReconcile() }
        }
        if Self.rebuildsPanelsAfterSystemEvents { scheduleRebuild() }
    }

    /// Closes and recreates every panel 1.5 s from now (restarted by each call).
    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuildAllPanels() }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.systemEventRecheckDelay, execute: work)
    }

    /// Only an after-pass with the Remove flag acts: the Begin pass fires for
    /// every online display and says nothing about which one is leaving.
    nonisolated static func ordersOutImmediately(for flags: CGDisplayChangeSummaryFlags) -> Bool {
        !flags.contains(.beginConfigurationFlag) && flags.contains(.removeFlag)
    }

    nonisolated static func displayReconfigured(_ displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        guard ordersOutImmediately(for: flags) else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { observing?.handleDisplayRemoved(displayID: displayID) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { observing?.handleDisplayRemoved(displayID: displayID) }
            }
        }
    }

    /// Orders out the removed display's panels at once (looked up in the
    /// in-memory ID map), then lets the debounced reconcile settle the rest.
    func handleDisplayRemoved(displayID: UInt32) {
        guard let uuid = displayIDToUUID[displayID] else { return }
        if let recordKey = recordForDisplay[uuid], let record = library.library.displays[recordKey] {
            for placement in record.placements {
                entries[placement.id]?.panel.orderOut(nil)
            }
        }
        log.notice("display \(uuid, privacy: .public) removed; its stickers are ordered out")
        scheduleReconcile()
    }

    // MARK: Helpers

    /// The first 8 characters of an ID, for log lines.
    private static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    /// Which record each connected display shows: its own, else the one the
    /// fingerprint fallback adopts (in memory only).
    static func recordAssignments(displays: [DisplayInfo], records: [String: DisplayRecord]) -> [String: String] {
        var result: [String: String] = [:]
        for display in displays {
            if records[display.uuid] != nil {
                result[display.uuid] = display.uuid
            } else if let adopted = DisplayRegistry.fingerprintAdoption(for: display, records: records, connected: displays) {
                result[display.uuid] = adopted
            }
        }
        return result
    }

    /// The display containing `point` (`NSMouseInRect`), else the nearest one.
    static func display(containing point: NSPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let hit = displays.first(where: { NSMouseInRect(point, $0.frame, false) }) { return hit }
        func distance(_ rect: CGRect) -> CGFloat {
            hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
        }
        return displays.min { distance($0.frame) < distance($1.frame) }
    }

    private func makeEntry(for placement: Placement) -> Entry {
        let start = NSRect(x: 0, y: 0, width: 1, height: 1)
        let panel = PanelPolicy.makeStickerPanel(contentRect: start, hideFromSharing: sharingHidden)
        let view = StickerView(frame: start)
        panel.contentView = view
        panel.placementID = placement.id
        fallback?.prepare(panel)
        panel.level = PanelPolicy.level(onTop: placement.onTop)  // last
        let entry = Entry(panel: panel, view: view)
        entries[placement.id] = entry
        return entry
    }

    private func applyFrame(_ entry: Entry, layout: StickerGeometry.Layout) {
        let margin = entry.view.layerShadow?.margin ?? 0
        let rect = layout.stickerRect.insetBy(dx: -margin, dy: -margin)
        let target = entry.panel.backingAlignedRect(rect, options: .alignAllEdgesNearest)
        if entry.panel.frame != target {
            entry.panel.setFrame(target, display: false)
        }
    }

    private func requestRender(_ entry: Entry, placement: Placement, layout: StickerGeometry.Layout,
                               backingScale: CGFloat) {
        let request = RenderRequest(sticker: placement.sticker, style: placement.style, flipped: placement.flipped,
                                    rotation: placement.rotation, pointSize: layout.pointSize,
                                    backingScale: backingScale)
        guard request != entry.request else { return }
        entry.request = request
        renderRequestsIssued += 1
        let renderer = self.renderer
        let placementID = placement.id
        Task { [weak self] in
            do {
                let rendered = try await renderer.render(request)
                self?.commitRender(rendered, for: request, placement: placementID)
            } catch {
                self?.log.error("render of \(placementID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A returning recorded display refreshes its lastSeen and name in memory;
    /// they are written with the next save, never on their own.
    private func refreshDisplayMetadata(newlyPresent: Set<String>) {
        let model = library.library
        let returning = newlyPresent.compactMap { uuid in model.displays[uuid] != nil ? presentDisplays[uuid] : nil }
        guard !returning.isEmpty else { return }
        let now = Date()
        library.refreshMetadata { library in
            for display in returning {
                library.displays[display.uuid]?.lastSeen = now
                library.displays[display.uuid]?.name = display.name
            }
        }
    }

    private func tearDown(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        fallback?.forget(entry.panel)
        entry.view.clearContents()
        entry.panel.orderOut(nil)
        entry.panel.close()
    }

    /// Visible stickers front to back, for the fallback click-through mode.
    private func fallbackTargets() -> [ClickThroughFallback.Target] {
        let order = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue)
        var rank: [Int: Int] = [:]
        for (index, number) in order.enumerated() where rank[number] == nil { rank[number] = index }
        return entries.values
            .filter { $0.panel.isVisible }
            .sorted { (rank[$0.panel.windowNumber] ?? Int.max) < (rank[$1.panel.windowNumber] ?? Int.max) }
            .map { entry in
                let size = entry.view.contentPointSize
                let frame = entry.panel.frame
                let content = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                     width: size.width, height: size.height)
                return ClickThroughFallback.Target(panel: entry.panel, contentRect: content,
                                                   mask: entry.alphaMask, wholeFrame: entry.panel.isEditing)
            }
    }
}
