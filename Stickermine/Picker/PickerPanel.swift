import AppKit
import SwiftUI

/// The picker's window: borderless, floating, allowed to become key (so Esc
/// and 1–4 arrive), and never hidden or cancelled when it loses key: the
/// system's "bypass the private window picker" alert lands on it right after
/// a capture (spec sections 5.9 and 7).
@MainActor
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows a `PickerModel` in a `PickerPanel` near the cursor, activates
/// Stickermine and handles the keys. Only Esc or the × button cancel.
@MainActor
final class PickerController {
    /// Space between the cursor and the panel.
    static let cursorGap: CGFloat = 16

    let model: PickerModel
    let panel: PickerPanel
    private var keyMonitor: Any?

    /// Esc or the × button.
    var onCancel: (() -> Void)?

    init(model: PickerModel) {
        self.model = model
        panel = Self.makePanel()
        let host = NSHostingView(rootView: PickerView(model: model, onCancel: { [weak self] in self?.onCancel?() }))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
    }

    /// The panel policy (spec section 4): not released on close, never hidden
    /// on deactivation, the floating-panel flag untouched, the level last.
    /// Non-activating, so it becomes key (and Esc and 1–4 arrive) even when
    /// the system turns down `NSApp.activate()`: the last input went to
    /// `screencapture`'s crosshair, not to Stickermine. The session ignores
    /// every trigger while it is up, so neither Hide (⌘H) nor a Space switch
    /// may take it out of sight.
    static func makePanel() -> PickerPanel {
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: PickerView.width, height: 320),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.canHide = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.level = .floating  // last
        return panel
    }

    /// Below the cursor and centred on it; above it when there's no room
    /// below; centred on the display when it fits neither way. Always inside
    /// `visibleFrame`.
    static func frame(size: CGSize, near cursor: CGPoint, visibleFrame: CGRect) -> CGRect {
        var origin = CGPoint(x: cursor.x - size.width / 2, y: cursor.y - cursorGap - size.height)
        if origin.y < visibleFrame.minY {
            origin.y = cursor.y + cursorGap
        }
        if origin.y + size.height > visibleFrame.maxY || origin.y < visibleFrame.minY {
            origin = CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width))
        origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        return CGRect(origin: origin, size: size).integral
    }

    /// The style for a typed character: "1"–"4" in UI order.
    static func style(forKey characters: String?) -> StickerStyle? {
        guard let characters, characters.count == 1, let number = Int(characters),
              (1...StickerStyle.allCases.count).contains(number)
        else { return nil }
        return StickerStyle.allCases[number - 1]
    }

    /// Shows the panel near `cursor` inside `visibleFrame`, activates the app
    /// and makes the panel key.
    func show(near cursor: CGPoint, visibleFrame: CGRect) {
        panel.setFrame(Self.frame(size: panel.frame.size, near: cursor, visibleFrame: visibleFrame), display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 {  // Esc
                self.onCancel?()
                return nil
            }
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let style = Self.style(forKey: event.charactersIgnoringModifiers) {
                self.model.confirm(style)
                return nil
            }
            return event
        }
    }

    /// Removes the panel for good.
    func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel.orderOut(nil)
        panel.close()
        // The × button's action is still running inside the hosting view:
        // release it on the next turn of the run loop, not under its own feet.
        let panel = self.panel
        DispatchQueue.main.async { panel.contentView = nil }
    }
}
