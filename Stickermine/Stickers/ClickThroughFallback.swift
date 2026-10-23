import AppKit

/// The hidden fallback click-through mode (spec section 9; `defaults write
/// com.ethan.stickermine clickThroughFallback -bool true`, read at launch).
/// It exists because the window server's alpha hit-testing has regressed in
/// past releases. Every sticker panel ignores the mouse, and the one sticker
/// whose opaque pixels are under the cursor is switched to receive it, using
/// each sticker's alpha mask. This is the only file that may write the panels'
/// mouse-event flag: once written, a window never returns to alpha hit-testing,
/// which is why the mode only changes on relaunch.
@MainActor
final class ClickThroughFallback {
    struct Target {
        let panel: NSPanel
        /// The sticker bitmap's rect in screen points (the panel minus its margin).
        let contentRect: CGRect
        let mask: AlphaMask?
        /// While editing, the whole padded frame takes clicks (the hit pad).
        let wholeFrame: Bool
    }

    struct Candidate {
        let contentRect: CGRect
        let frame: CGRect
        let mask: AlphaMask?
        let wholeFrame: Bool
    }

    /// Targets front to back.
    private let targets: () -> [Target]
    private var monitors: [Any] = []
    private(set) weak var activePanel: NSPanel?

    init(targets: @escaping () -> [Target]) {
        self.targets = targets
    }

    /// Every sticker panel starts out ignoring the mouse. Its view also gets an
    /// always-active mouse-moved tracking area: once a sticker takes the mouse,
    /// moves over its own rectangle belong to this app, so the global monitor
    /// no longer sees them and only these events reach the local monitor.
    func prepare(_ panel: NSPanel) {
        panel.ignoresMouseEvents = true
        if let view = panel.contentView {
            view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                                owner: view, userInfo: nil))
        }
    }

    func forget(_ panel: NSPanel) {
        if activePanel === panel { activePanel = nil }
    }

    /// Global monitors see moves over other apps' windows (every sticker
    /// ignores the mouse until one is switched on); local ones see moves over
    /// our own. Mouse-move monitors need no permission.
    func start() {
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.update(at: NSEvent.mouseLocation) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.update(at: NSEvent.mouseLocation) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Lets the front-most sticker with an opaque pixel under `point` take the
    /// mouse, and every other sticker ignore it.
    func update(at point: NSPoint) {
        let current = targets()
        let candidates = current.map {
            Candidate(contentRect: $0.contentRect, frame: $0.panel.frame, mask: $0.mask, wholeFrame: $0.wholeFrame)
        }
        let hit = Self.hitIndex(at: point, in: candidates).map { current[$0].panel }
        guard hit !== activePanel else { return }
        activePanel?.ignoresMouseEvents = true
        hit?.ignoresMouseEvents = false
        activePanel = hit
    }

    /// The index of the first (front-most) candidate that takes a click at `p`.
    nonisolated static func hitIndex(at p: CGPoint, in candidates: [Candidate]) -> Int? {
        for (index, candidate) in candidates.enumerated() {
            if candidate.wholeFrame {
                if candidate.frame.contains(p) { return index }
                continue
            }
            let rect = candidate.contentRect
            guard let mask = candidate.mask, rect.width > 0, rect.height > 0, rect.contains(p) else { continue }
            let unit = CGPoint(x: (p.x - rect.minX) / rect.width, y: (rect.maxY - p.y) / rect.height)
            if mask.isOpaque(atUnit: unit) { return index }
        }
        return nil
    }
}
