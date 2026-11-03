import AppKit
import SwiftUI

/// When the one-time support ask appears (spec section 13). Pure.
enum SupportAskRule {
    static let threshold = 5

    /// After a placement click: the new `ownPlacementsCount` and whether the
    /// ask shows now. Tutorial stickers don't count; nothing decrements it.
    static func afterPlacement(count: Int, alreadyShown: Bool, isTutorial: Bool) -> (count: Int, show: Bool) {
        guard !isTutorial else { return (count, false) }
        let next = count + 1
        return (next, !alreadyShown && next >= threshold)
    }
}

/// The card's panel. Never made key when it appears (the frontmost app keeps
/// focus); a click into it makes it key without activating Stickermine, so
/// Esc works then.
@MainActor
final class SupportAskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The one-time support ask (spec section 13): the first time
/// `ownPlacementsCount` reaches 5 and `supportAskShown` is false, a small
/// sticker-styled card appears below the menu bar icon (top-right of the main
/// display while the icon is hidden), without activating Stickermine or
/// taking focus from the frontmost app. `supportAskShown` is set when it
/// appears; every way it goes (either button, Esc, a click anywhere else,
/// quitting) counts as declined, and it never appears again.
@MainActor
final class SupportAsk {
    nonisolated static let message = "Enjoying Stickermine? It’s free and open source. If it made you smile, you can buy me a coffee."
    nonisolated static let coffeeTitle = "☕️ Buy me a coffee"
    nonisolated static let laterTitle = "Maybe later"
    nonisolated static let kofiURL = URL(string: "https://ko-fi.com/grokcodile")!
    /// After the placement click, so its own mouse-up is over.
    nonisolated static let showDelay: TimeInterval = 0.5
    nonisolated static let gap: CGFloat = 4
    nonisolated static let edgeInset: CGFloat = 8
    /// Transparent room around the card for its shadow; the frame lets it
    /// overhang, so the card itself lines up with the icon.
    nonisolated static let shadowPadding: CGFloat = 18

    private let defaults: UserDefaults
    private let openURL: (URL) -> Void
    private let anchor: () -> CGRect?
    private let fallbackArea: () -> CGRect?
    private let showDelay: TimeInterval
    /// The card's panel while it is up.
    private(set) var panel: SupportAskPanel?
    private var monitors: [Any] = []
    private var showPending = false

    /// `anchor` is the menu bar icon's frame on screen (nil while hidden);
    /// `fallbackArea` the main display's visible frame.
    init(defaults: UserDefaults = .standard, openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) },
         anchor: @escaping () -> CGRect?, fallbackArea: @escaping () -> CGRect?,
         showDelay: TimeInterval = SupportAsk.showDelay) {
        self.defaults = defaults
        self.openURL = openURL
        self.anchor = anchor
        self.fallbackArea = fallbackArea
        self.showDelay = showDelay
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// A placement click (`SessionCoordinator.onPlaced`); cross-display drags
    /// never get here.
    func placementClicked(isTutorial: Bool) {
        let result = SupportAskRule.afterPlacement(count: defaults.ownPlacementsCount,
                                                   alreadyShown: defaults.supportAskShown, isTutorial: isTutorial)
        guard !isTutorial else { return }
        defaults.ownPlacementsCount = result.count
        guard result.show, !showPending, panel == nil else { return }
        if showDelay > 0 {
            showPending = true
            DispatchQueue.main.asyncAfter(deadline: .now() + showDelay) { [weak self] in
                MainActor.assumeIsolated {
                    self?.showPending = false
                    self?.show()
                }
            }
        } else {
            show()
        }
    }

    /// Shows the card (once) and marks the ask as shown.
    func show() {
        guard panel == nil else { return }
        defaults.supportAskShown = true
        let panel = Self.makePanel()
        let host = FirstClickHostingView(rootView: SupportAskView(
            coffee: { [weak self] in self?.buyCoffee() },
            later: { [weak self] in self?.dismiss() }))
        panel.contentView = host
        let anchorRect = anchor()
        let area = anchorRect.flatMap(Self.visibleFrame(containing:)) ?? fallbackArea() ?? .zero
        panel.setFrame(Self.frame(size: host.fittingSize, anchor: anchorRect, visibleFrame: area), display: false)
        panel.orderFrontRegardless()
        self.panel = panel
        installMonitors(for: panel)
    }

    /// Declines: the card goes and never comes back.
    func dismiss() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        guard let panel else { return }
        self.panel = nil
        panel.orderOut(nil)
        panel.close()
    }

    private func buyCoffee() {
        openURL(Self.kofiURL)
        dismiss()
    }

    /// The panel policy (spec section 4): non-activating, never hidden on
    /// deactivation, transparent around the card, the level last.
    static func makePanel() -> SupportAskPanel {
        let panel = SupportAskPanel(contentRect: NSRect(x: 0, y: 0, width: 332, height: 150),
                                    styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .statusBar  // last
        return panel
    }

    /// The panel's frame for a card view of `size` (its shadow padding
    /// included): the card's top-right corner just below the icon's
    /// bottom-right corner; without the icon, `edgeInset` from the top-right
    /// corner of `visibleFrame`. The card always stays inside `visibleFrame`.
    nonisolated static func frame(size: CGSize, anchor: CGRect?, visibleFrame: CGRect) -> CGRect {
        let card = CGSize(width: size.width - 2 * shadowPadding, height: size.height - 2 * shadowPadding)
        var right: CGFloat
        var top: CGFloat
        if let anchor {
            right = anchor.maxX
            top = anchor.minY - gap
        } else {
            right = visibleFrame.maxX - edgeInset
            top = visibleFrame.maxY - edgeInset
        }
        right = max(min(right, visibleFrame.maxX - edgeInset), visibleFrame.minX + edgeInset + card.width)
        top = max(min(top, visibleFrame.maxY), visibleFrame.minY + edgeInset + card.height)
        return CGRect(x: (right - card.width - shadowPadding).rounded(), y: (top - card.height - shadowPadding).rounded(),
                      width: size.width, height: size.height)
    }

    /// The visible frame of the screen the icon is on.
    private static func visibleFrame(containing rect: CGRect) -> CGRect? {
        NSScreen.screens.first { $0.frame.intersects(rect) }?.visibleFrame
    }

    /// A click anywhere else declines: in other apps (global monitor, no
    /// permission needed for mouse events) and in Stickermine's own windows
    /// (local monitor).
    private func installMonitors(for panel: NSPanel) {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self, weak panel] event in
            if event.window !== panel {
                MainActor.assumeIsolated { self?.dismiss() }
            }
            return event
        }) {
            monitors.append(local)
        }
    }
}

/// The card: yellow (the website's coffee colour) with a white border.
private struct SupportAskView: View {
    let coffee: () -> Void
    let later: () -> Void

    private static let yellow = Color(red: 0xFF / 255.0, green: 0xD8 / 255.0, blue: 0x4D / 255.0)
    private static let ink = Color(red: 0x1F / 255.0, green: 0x23 / 255.0, blue: 0x40 / 255.0)

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(SupportAsk.message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Self.ink)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 14) {
                Button(action: coffee) {
                    Text(SupportAsk.coffeeTitle)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 7)
                        .background(Capsule().fill(Self.ink))
                }
                .buttonStyle(.plain)
                Button(action: later) {
                    Text(SupportAsk.laterTitle)
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(Self.ink.opacity(0.75))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .frame(width: 280, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Self.yellow))
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 32, style: .continuous).fill(Color.white))
        .shadow(color: Self.ink.opacity(0.22), radius: 12, x: 0, y: 6)
        .padding(SupportAsk.shadowPadding)
    }
}
