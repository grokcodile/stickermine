import SwiftUI

/// The band across the bottom of Home while an update is available, under
/// way or failed (spec section 13; Pullcord's strip, in the brand blue).
struct UpdateStrip: View {
    @ObservedObject var updater: Updater

    static let blue = Color(red: 0x3D / 255.0, green: 0x4B / 255.0, blue: 0xE0 / 255.0)

    /// What the strip says, and whether it offers Update; nil hides it.
    static func content(state: UpdateState, latest: String?) -> (text: String, showsButton: Bool)? {
        switch state {
        case .upToDate:
            return nil
        case .available:
            return (latest.map { "Update available: v\($0)" } ?? "Update available", true)
        case .downloading:
            return ("Downloading the update…", false)
        case .updating:
            return (latest.map { "Updating to v\($0)…" } ?? "Updating…", false)
        case .failed:
            return (latest.map { "The update to v\($0) didn’t finish" } ?? "The update didn’t finish", true)
        }
    }

    var body: some View {
        if let content = Self.content(state: updater.state, latest: updater.latestVersion) {
            HStack(spacing: 10) {
                Text(content.text)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white)
                if content.showsButton {
                    Button { updater.performUpdate() } label: {
                        Text("Update")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Self.blue)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.white.opacity(0.94)))
                    }
                    .buttonStyle(.plain)
                    .help(updater.isHomebrewManaged ? "Upgrade through Homebrew and reopen."
                                                    : "Download the new version and open it.")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .background(Self.blue)
        }
    }
}
