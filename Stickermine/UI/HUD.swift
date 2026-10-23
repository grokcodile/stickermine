import AppKit

/// A brief, non-interactive pill at the top centre of the display under the
/// cursor: an SF Symbol and a short message (spec section 5.7). It never
/// takes focus, never catches clicks, and fades itself out. One reused panel,
/// so a second message replaces the first. Ported from Pullcord's HUD
/// (`showMessage`), without its morphing.
@MainActor
final class HUD {
    static let shared = HUD()

    static let controlHeldMessage = "Let go of Control before releasing the mouse"
    static let couldNotStartMessage = "Couldn’t start a capture"
    static let readOnlyMessage = "This library was saved by a newer Stickermine. Update to make changes."
    static let saveFailedMessage = "Couldn’t save the sticker"

    /// How long a message stays before fading.
    static let dwell: TimeInterval = 2.2
    static let height: CGFloat = 42
    private static let padding: CGFloat = 18
    private static let gap: CGFloat = 10
    private static let iconSize: CGFloat = 18

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Bumped by every show and hide, so a fade that finishes late never
    /// orders out a newer message.
    private var generation = 0

    /// The message last shown (tests and logs).
    private(set) var lastMessage: String?

    /// The pill's panel: the panel policy (spec section 4), click-through,
    /// on every Space and over full-screen apps; the level last.
    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = .statusBar  // last
        return panel
    }

    /// Where a pill of `width` sits: centred, 16 pt below the top of `visibleFrame`.
    static func frame(width: CGFloat, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: (visibleFrame.midX - width / 2).rounded(), y: visibleFrame.maxY - height - 16,
               width: width, height: height)
    }

    func show(_ message: String, symbol: String = "exclamationmark.triangle.fill") {
        lastMessage = message
        generation &+= 1
        hideWork?.cancel()
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let textHeight = ceil(font.ascender - font.descender)
        let width = Self.padding + Self.iconSize + Self.gap + textWidth + Self.padding

        let shell = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        shell.material = .hudWindow
        shell.blendingMode = .behindWindow
        shell.state = .active
        shell.wantsLayer = true
        shell.layer?.cornerRadius = Self.height / 2
        shell.layer?.masksToBounds = true

        let icon = NSImageView(frame: NSRect(x: Self.padding, y: (Self.height - Self.iconSize) / 2,
                                             width: Self.iconSize, height: Self.iconSize))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        shell.addSubview(icon)

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.frame = NSRect(x: Self.padding + Self.iconSize + Self.gap, y: (Self.height - textHeight) / 2,
                             width: textWidth, height: textHeight)
        shell.addSubview(label)
        panel.contentView = shell

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            panel.setFrame(Self.frame(width: width, in: visible), display: false)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut(generation: generation) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
    }

    func hide() {
        generation &+= 1
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private func fadeOut(generation: Int) {
        guard generation == self.generation, let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.generation else { return }
                panel.orderOut(nil)
            }
        })
    }
}
