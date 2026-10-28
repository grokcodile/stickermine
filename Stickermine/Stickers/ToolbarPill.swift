import AppKit
import SwiftUI
import os

/// The pill's window: borderless, so it never becomes key; using it never
/// takes key status from the sticker being edited (spec section 10).
@MainActor
final class ToolbarPillPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// A hosting view whose controls take the first click, so a click on the pill
/// acts at once even though its window is never key.
@MainActor
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// What the pill shows and does: Style (four previews inline, in UI order),
/// Flip, Float on top and Remove for the placement being edited.
@MainActor
final class ToolbarPillModel: ObservableObject {
    /// Each style preview fits in this box (points).
    static let previewBox = CGSize(width: 40, height: 40)

    @Published private(set) var style: StickerStyle
    @Published private(set) var flipped: Bool
    @Published private(set) var onTop: Bool
    @Published private(set) var showsStyles = false
    @Published private(set) var previews: [StickerStyle: PickerModel.Preview] = [:]
    /// The order previews were rendered in (tests).
    private(set) var renderOrder: [StickerStyle] = []

    var onStyle: ((StickerStyle) -> Void)?
    var onFlip: (() -> Void)?
    var onFloatOnTop: (() -> Void)?
    var onRemove: (() -> Void)?
    /// The pill's size changed (the style row opened or closed).
    var onResize: (() -> Void)?

    let sticker: UUID
    let natural: CGSize
    let sourceLongSide: Double
    private let renderer: StyleRenderer
    private let backingScale: CGFloat
    private var previewTask: Task<Void, Never>?
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "editing")

    init(placement: Placement, natural: CGSize, sourceLongSide: Double, renderer: StyleRenderer,
         backingScale: CGFloat) {
        style = placement.style
        flipped = placement.flipped
        onTop = placement.onTop
        sticker = placement.sticker
        self.natural = natural
        self.sourceLongSide = sourceLongSide
        self.renderer = renderer
        self.backingScale = backingScale
    }

    /// Opens or closes the style row; opening renders the four previews.
    func toggleStyles() {
        showsStyles.toggle()
        if showsStyles { renderPreviews() }
        onResize?()
    }

    func choose(_ style: StickerStyle) { perform { [weak self] in self?.onStyle?(style) } }
    func flip() { perform { [weak self] in self?.onFlip?() } }
    func floatOnTop() { perform { [weak self] in self?.onFloatOnTop?() } }
    func remove() { perform { [weak self] in self?.onRemove?() } }

    /// The placement changed (a button acted, or something else wrote it).
    func update(style: StickerStyle, flipped: Bool, onTop: Bool) {
        let flipChanged = flipped != self.flipped
        if style != self.style { self.style = style }
        if flipChanged { self.flipped = flipped }
        if onTop != self.onTop { self.onTop = onTop }
        if flipChanged && showsStyles { renderPreviews() }
    }

    /// The preview request for `style`: unrotated, flipped like the
    /// placement, the natural size fitted into `previewBox`.
    func previewRequest(for style: StickerStyle) -> RenderRequest {
        let scale = natural.width > 0 && natural.height > 0
            ? min(Self.previewBox.width / natural.width, Self.previewBox.height / natural.height) : 1
        return RenderRequest(sticker: sticker, style: style, flipped: flipped, rotation: 0,
                             pointSize: CGSize(width: natural.width * scale, height: natural.height * scale),
                             backingScale: backingScale)
    }

    /// Renders the four previews in UI order through the app's renderer,
    /// skipping any that is already current.
    func renderPreviews() {
        previewTask?.cancel()
        let requests = StickerStyle.allCases.map(previewRequest(for:))
        let renderer = self.renderer
        previewTask = Task { [weak self] in
            for request in requests {
                guard let self, !Task.isCancelled else { return }
                if self.previews[request.style]?.request == request { continue }
                do {
                    let rendered = try await renderer.render(request)
                    guard !Task.isCancelled else { return }
                    let shadow = request.onScreenParameters(sourceLongSide: self.sourceLongSide)
                    self.previews[request.style] = PickerModel.Preview(request: request, rendered: rendered,
                                                                       shadow: shadow)
                    self.renderOrder.append(request.style)
                } catch {
                    self.log.error("pill preview \(request.style.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
    }

    /// Stops rendering previews (the pill closed).
    func cancel() {
        previewTask?.cancel()
        previewTask = nil
    }

    /// A pill button acts once SwiftUI has finished handling the click:
    /// Remove closes the pill's own window.
    private func perform(_ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in action() }
    }
}

/// The pill's content: an optional row of style previews above the four buttons.
struct ToolbarPillView: View {
    @ObservedObject var model: ToolbarPillModel

    var body: some View {
        VStack(spacing: 6) {
            if model.showsStyles {
                HStack(spacing: 6) {
                    ForEach(StickerStyle.allCases, id: \.self) { style in
                        StyleChoice(style: style, preview: model.previews[style], selected: model.style == style) {
                            model.choose(style)
                        }
                    }
                }
            }
            HStack(spacing: 2) {
                PillButton(title: "Style", symbol: "paintpalette", isOn: model.showsStyles,
                           action: model.toggleStyles)
                PillButton(title: "Flip", symbol: "arrow.left.and.right.righttriangle.left.righttriangle.right",
                           isOn: model.flipped, action: model.flip)
                PillButton(title: "Float on top", symbol: "pin", isOn: model.onTop, action: model.floatOnTop)
                PillButton(title: "Remove", symbol: "trash", isOn: false, action: model.remove)
            }
        }
        .padding(6)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color(nsColor: .windowBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(Color.primary.opacity(0.12)))
        .fixedSize()
    }
}

/// One of the pill's four buttons.
private struct PillButton: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .labelStyle(.titleAndIcon)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 9)
                .padding(.vertical, 6)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isOn ? Color.accentColor.opacity(0.2) : Color.clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

/// One style preview in the pill's style row.
private struct StyleChoice: View {
    let style: StickerStyle
    let preview: PickerModel.Preview?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                    if let preview {
                        PillPreview(preview: preview)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 56, height: 56)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.clear, lineWidth: 2))
                Text(style.displayName)
                    .font(.system(size: 11))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(style.displayName)
    }
}

/// A preview drawn by a StickerView (through the picker's `PreviewHost`), so
/// it looks exactly like the sticker will.
private struct PillPreview: NSViewRepresentable {
    let preview: PickerModel.Preview

    func makeNSView(context: Context) -> PreviewHost {
        PreviewHost()
    }

    func updateNSView(_ view: PreviewHost, context: Context) {
        view.show(preview)
    }
}

/// The toolbar pill (spec section 10): a child panel of the sticker being
/// edited, at the sticker's level and with its collection behaviour, centred
/// under the sticker with an 8 pt gap, or above it when there's no room
/// below on the sticker's display. It follows the sticker (a child window
/// moves with its parent) and never becomes key.
@MainActor
final class ToolbarPill {
    nonisolated static let gap: CGFloat = 8

    let panel: ToolbarPillPanel
    let model: ToolbarPillModel
    private let host: FirstClickHostingView<ToolbarPillView>
    private var lastPlacement: (stickerRect: CGRect, visibleFrame: CGRect)?

    init(model: ToolbarPillModel) {
        self.model = model
        panel = Self.makePanel()
        host = FirstClickHostingView(rootView: ToolbarPillView(model: model))
        panel.contentView = host
        panel.setContentSize(size)
        model.onResize = { [weak self] in self?.refit() }
    }

    /// The panel policy (spec section 4): not released on close, never hidden
    /// on deactivation, the floating-panel flag untouched, the level last.
    static func makePanel() -> ToolbarPillPanel {
        let panel = ToolbarPillPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 40),
                                     styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.canHide = false
        panel.animationBehavior = .none
        panel.collectionBehavior = PanelPolicy.stickerBehavior
        panel.level = PanelPolicy.stickerLevel  // last
        return panel
    }

    /// Where a pill of `size` goes for a sticker whose box is `stickerRect`:
    /// centred under it with `gap`; above it when that leaves `visibleFrame`;
    /// over the sticker's lower edge when neither fits. Always inside
    /// `visibleFrame`, on whole points.
    nonisolated static func frame(size: CGSize, stickerRect: CGRect, visibleFrame: CGRect,
                                  gap: CGFloat = gap) -> CGRect {
        let size = CGSize(width: size.width.rounded(.up), height: size.height.rounded(.up))
        var origin = CGPoint(x: stickerRect.midX - size.width / 2, y: stickerRect.minY - gap - size.height)
        if origin.y < visibleFrame.minY {
            origin.y = stickerRect.maxY + gap
            if origin.y + size.height > visibleFrame.maxY {
                origin.y = stickerRect.minY + gap
            }
        }
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width))
        origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    /// The pill's size for its current content. SwiftUI applies a model
    /// change at the next layout pass, so lay out first.
    var size: CGSize {
        host.layoutSubtreeIfNeeded()
        return host.fittingSize
    }

    /// Joins `parent` as a child window with its sharing type, collection
    /// behaviour and level, which orders the pill in with it.
    func attach(to parent: NSWindow) {
        panel.sharingType = parent.sharingType
        panel.collectionBehavior = parent.collectionBehavior
        panel.level = parent.level  // last
        parent.addChildWindow(panel, ordered: .above)
    }

    /// Keeps the pill at its sticker's level (Float on top switched).
    func setLevel(_ level: NSWindow.Level) {
        if panel.level != level { panel.level = level }
    }

    /// Places the pill for a sticker whose box is `stickerRect` on a display
    /// whose visible frame is `visibleFrame`.
    func place(around stickerRect: CGRect, visibleFrame: CGRect) {
        lastPlacement = (stickerRect, visibleFrame)
        let target = Self.frame(size: size, stickerRect: stickerRect, visibleFrame: visibleFrame)
        if panel.frame != target { panel.setFrame(target, display: true) }
    }

    /// Places the pill again after its size changed.
    func refit() {
        guard let lastPlacement else { return }
        place(around: lastPlacement.stickerRect, visibleFrame: lastPlacement.visibleFrame)
    }

    /// Removes the pill for good.
    func close() {
        model.cancel()
        model.onResize = nil
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        panel.close()
        panel.contentView = nil
    }
}
