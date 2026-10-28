import AppKit
import os

/// Where editing moves keyboard focus. Tests substitute a recorder, so they
/// never activate the app or make a panel key.
@MainActor
protocol EditingFocus: AnyObject {
    /// The frontmost app, unless it is Stickermine itself.
    func frontmostOtherApp() -> NSRunningApplication?
    /// Activates Stickermine and makes `panel` key with its content view as
    /// first responder, so Esc, Delete and trackpad gestures arrive.
    func takeFocus(for panel: NSPanel)
    /// Hands focus back to `app` once editing ends, but only while
    /// Stickermine is still frontmost and none of its other windows took key:
    /// a click into another app or onto one of Stickermine's windows keeps
    /// that focus. Without `app` (Stickermine itself was frontmost), another
    /// visible Stickermine window that can be key gets it back, else
    /// Stickermine deactivates.
    func returnFocus(to app: NSRunningApplication?)
}

@MainActor
final class LiveEditingFocus: EditingFocus {
    private static let log = Logger(subsystem: "com.ethan.stickermine", category: "editing")

    init() {}

    func frontmostOtherApp() -> NSRunningApplication? {
        let front = NSWorkspace.shared.frontmostApplication
        return front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
    }

    func takeFocus(for panel: NSPanel) {
        NSApp.activate()
        panel.makeKey()
        if let view = panel.contentView { panel.makeFirstResponder(view) }
        // Activation of an accessory app is expected but unverified (spec
        // section 10); the log line says what happened.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak panel] in
            MainActor.assumeIsolated {
                Self.log.notice("editing focus +0.5s: appActive=\(NSApp.isActive) key=\(panel?.isKeyWindow ?? false)")
            }
        }
    }

    func returnFocus(to app: NSRunningApplication?) {
        // On the next turn, when a click elsewhere has finished moving key status.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                guard NSApp.isActive, NSApp.keyWindow == nil || NSApp.keyWindow is StickerPanel else {
                    let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
                    Self.log.notice("focus stays with \(front, privacy: .public)")
                    return
                }
                if let app, !app.isTerminated {
                    app.activate()
                    Self.log.notice("focus returned to \(app.bundleIdentifier ?? "?", privacy: .public)")
                } else if let window = NSApp.windows.first(where: {
                    $0.isVisible && $0.canBecomeKey && !($0 is StickerPanel)
                }) {
                    window.makeKeyAndOrderFront(nil)
                    Self.log.notice("focus returned to \(window.title, privacy: .public)")
                } else {
                    NSApp.deactivate()
                    Self.log.notice("focus released")
                }
            }
        }
    }
}

/// One sticker being edited (spec section 10): the toolbar pill and the
/// keys. `StickerManager` creates it when editing begins and drops it when
/// editing ends; every model write goes through the manager.
@MainActor
final class StickerEditor {
    let placementID: UUID
    let panel: StickerPanel
    let view: StickerView
    /// The app that was frontmost before editing began.
    let previousApp: NSRunningApplication?
    let pill: ToolbarPill
    private unowned let manager: StickerManager

    init(placementID: UUID, panel: StickerPanel, view: StickerView, previousApp: NSRunningApplication?,
         target: StickerManager.EditTarget, renderer: StyleRenderer, manager: StickerManager) {
        self.placementID = placementID
        self.panel = panel
        self.view = view
        self.previousApp = previousApp
        self.manager = manager
        let model = ToolbarPillModel(placement: target.placement, natural: target.natural,
                                     sourceLongSide: target.sourceLongSide, renderer: renderer,
                                     backingScale: target.display.backingScale)
        pill = ToolbarPill(model: model)
        let id = placementID
        model.onStyle = { [weak manager] style in manager?.setStyle(style, for: id) }
        model.onFlip = { [weak manager] in manager?.toggleFlip(for: id) }
        model.onFloatOnTop = { [weak manager] in manager?.toggleOnTop(for: id) }
        model.onRemove = { [weak manager] in manager?.remove(placement: id) }
    }

    /// Takes the view's key events and shows the pill.
    func show() {
        view.onKeyDown = { [weak self] event in self?.keyDown(event) ?? false }
        pill.attach(to: panel)
        placePill()
    }

    /// Editing ended: the view's key events are let go and the pill goes.
    func tearDown() {
        view.onKeyDown = nil
        pill.close()
    }

    // MARK: Keys

    /// Esc ends editing; Delete removes the placement (on the next turn, so
    /// the panel isn't closed inside its own key event).
    func keyDown(_ event: NSEvent) -> Bool {
        switch event.keyCode {
        case 53:
            manager.endEditing(discardGesture: true)
            return true
        case 51, 117:
            manager.scheduleRemoval(of: placementID)
            return true
        default:
            return false
        }
    }

    // MARK: Pill

    /// The shown bitmap's box; the sticker rect before the first render.
    private func shownSize(_ target: StickerManager.EditTarget) -> CGSize {
        let content = view.contentPointSize
        return content.width > 0 && content.height > 0 ? content : target.layout.stickerRect.size
    }

    /// Places the pill under (or above) the sticker's current box, on the
    /// display under the box's centre (during a drag, the one it is over).
    func placePill() {
        guard let target = manager.editTarget(for: placementID) else { return }
        let box = StickerView.boundingSize(of: shownSize(target), scale: view.contentScale,
                                           rotation: view.contentRotation)
        let frame = panel.frame
        // The outline and the knob on its bottom-right corner reach this far past
        // the box: the pill keeps its gap from them, so it never covers the knob.
        let reach = StickerView.outlineOutset + StickerView.knobRadius
        let stickerRect = CGRect(x: frame.midX - box.width / 2, y: frame.midY - box.height / 2,
                                 width: box.width, height: box.height).insetBy(dx: 0, dy: -reach)
        let display = manager.display(at: NSPoint(x: frame.midX, y: frame.midY)) ?? target.display
        pill.place(around: stickerRect, visibleFrame: display.visibleFrame)
    }

    /// The placement was written or its window changed: the pill shows its
    /// style, flip and Float on top, keeps its level, and follows it.
    func placementDidChange() {
        guard let target = manager.editTarget(for: placementID) else { return }
        pill.model.update(style: target.placement.style, flipped: target.placement.flipped,
                          onTop: target.placement.onTop)
        pill.setLevel(panel.level)
        placePill()
    }
}
