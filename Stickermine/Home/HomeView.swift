import AppKit
import SwiftUI

/// Home's content (spec section 13): New Sticker at the top, the read-only
/// notice when the library came from a newer build, the history grid, the
/// settings, and a footer with the ⓘ About popover and Quit; the update
/// strip runs along the bottom while there is an update.
struct HomeView: View {
    @ObservedObject var model: HomeModel
    @ObservedObject var updater: Updater
    let openURL: (URL) -> Void

    @State private var showsAbout = false

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if model.isReadOnly { readOnlyNotice }
                    HistoryGrid(model: model)
                    Divider()
                    SettingsSection(model: model)
                }
                .padding(.horizontal, 24)
                // Room for the window buttons: the content runs under the transparent titlebar.
                .padding(.top, 34)
                .padding(.bottom, 20)
            }
            Divider()
            footer
            UpdateStrip(updater: updater)
        }
        .frame(minWidth: HomeWindowController.minimumSize.width, minHeight: HomeWindowController.minimumSize.height)
        .alert(HistoryList.deleteTitle,
               isPresented: Binding(get: { model.pendingDelete != nil }, set: { if !$0 { model.cancelDelete() } }),
               presenting: model.pendingDelete) { _ in
            Button("Delete", role: .destructive) { model.confirmDelete() }
            Button("Cancel", role: .cancel) { model.cancelDelete() }
        } message: { pending in
            Text(pending.message)
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("Stickermine")
                .font(.system(size: 26, weight: .semibold, design: .rounded))
            Spacer()
            Button { model.newSticker() } label: {
                Label("New Sticker", systemImage: "plus")
            }
            .controlSize(.large)
            .keyboardShortcut("n", modifiers: .command)
            .disabled(model.isReadOnly || model.sessionActive)
        }
    }

    private var readOnlyNotice: some View {
        Label(HUD.readOnlyMessage, systemImage: "lock.fill")
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.orange.opacity(0.15)))
    }

    private var footer: some View {
        HStack {
            Button { showsAbout.toggle() } label: {
                Image(systemName: "info.circle")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("About Stickermine")
            .popover(isPresented: $showsAbout, arrowEdge: .top) {
                AboutPopover(updater: updater) { url in
                    showsAbout = false
                    openURL(url)
                }
            }
            Spacer()
            Button("Quit Stickermine") { model.quit() }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}
