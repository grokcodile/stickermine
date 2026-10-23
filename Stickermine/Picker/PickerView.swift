import AppKit
import SwiftUI

extension StickerStyle {
    /// The name the UI shows.
    var displayName: String {
        switch self {
        case .puffy: return "Puffy"
        case .outline: return "Outline"
        case .shadow: return "Shadow"
        case .none: return "None"
        }
    }
}

/// The picker's content (spec section 7): the capture with its subjects
/// highlighted, Whole image and Fill holes, and the four style previews in UI
/// order, each numbered for its key. Re-placing shows only the style row.
struct PickerView: View {
    @ObservedObject var model: PickerModel
    let onCancel: () -> Void

    static let width: CGFloat = 476
    static let captureMaxSize = CGSize(width: 440, height: 300)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.mode == .capture {
                captureArea
                controls
            }
            styleRow
        }
        .padding(18)
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
    }

    private var header: some View {
        HStack {
            Text(model.mode == .capture ? "New Sticker" : "Place Sticker")
                .font(.headline)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        }
    }

    @ViewBuilder
    private var captureArea: some View {
        if let image = model.displayImage {
            let size = Self.fitted(CGSize(width: image.width, height: image.height), in: Self.captureMaxSize)
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                // Every subject stays visible (spec section 7: "each subject
                // highlighted"); selected ones are tinted more strongly.
                ForEach(model.state.subjects, id: \.self) { index in
                    if let mask = model.highlightMasks[index] {
                        Color.accentColor.opacity(model.state.selected.contains(index) ? 0.35 : 0.12)
                            .mask(Image(decorative: mask, scale: 1).resizable())
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                model.clickSubject(atUnitTopLeft: CGPoint(x: value.location.x / size.width,
                                                          y: value.location.y / size.height))
            })
            .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Toggle("Whole image", isOn: Binding(get: { model.state.wholeImage },
                                                set: { model.setWholeImage($0) }))
                .toggleStyle(.checkbox)
                .disabled(model.state.wholeImageLocked)
            Button(action: model.toggleFillHoles) {
                HStack(spacing: 5) {
                    Image(systemName: fillHolesSymbol)
                    Text("Fill holes: \(fillHolesText)")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!model.state.fillHolesEnabled)
            Spacer()
            if model.state.wholeImageLocked {
                Text("No subject found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fillHolesText: String {
        switch model.state.fillHolesDisplay {
        case .auto: return "Auto"
        case .on: return "On"
        case .off: return "Off"
        }
    }

    private var fillHolesSymbol: String {
        switch model.state.fillHolesDisplay {
        case .auto: return "a.square"
        case .on: return "checkmark.square.fill"
        case .off: return "square"
        }
    }

    private var styleRow: some View {
        HStack(spacing: 10) {
            ForEach(Array(StickerStyle.allCases.enumerated()), id: \.element) { offset, style in
                StylePreviewButton(style: style, number: offset + 1, preview: model.previews[style],
                                   highlighted: model.highlightedStyle == style,
                                   action: { model.confirm(style) })
                    .onHover { model.hover(style, inside: $0) }
            }
        }
        .disabled(model.isConfirming)
    }

    static func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height, 1)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

/// One style's live preview, its number and name.
private struct StylePreviewButton: View {
    let style: StickerStyle
    let number: Int
    let preview: PickerModel.Preview?
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(highlighted ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                    if let preview {
                        StickerPreview(preview: preview)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 104, height: 104)
                .overlay(alignment: .topLeading) {
                    Text("\(number)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor : Color.clear, lineWidth: 2))
                Text(style.displayName)
                    .font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(style.displayName) (\(number))")
    }
}

/// A rendered preview shown through a StickerView, the same view a placed
/// sticker uses, so the preview is exactly what gets placed (layer shadow
/// included). Clicks pass through to the SwiftUI button around it.
private struct StickerPreview: NSViewRepresentable {
    let preview: PickerModel.Preview

    func makeNSView(context: Context) -> PreviewHost {
        PreviewHost()
    }

    func updateNSView(_ view: PreviewHost, context: Context) {
        view.show(preview)
    }
}

@MainActor
final class PreviewHost: NSView {
    private let sticker = StickerView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        sticker.autoresizingMask = [.width, .height]
        sticker.frame = bounds
        addSubview(sticker)
    }

    required init?(coder: NSCoder) {
        fatalError("PreviewHost is only created in code")
    }

    func show(_ preview: PickerModel.Preview) {
        sticker.show(preview.rendered, shadow: preview.shadow, style: preview.request.style)
    }

    /// The preview never takes a click: the button around it does.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
