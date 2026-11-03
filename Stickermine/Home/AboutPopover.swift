import AppKit
import SwiftUI

/// The About popover's links, in the spec's order (section 13): Website,
/// Star on GitHub, Buy me a coffee, Report a Bug. The Website is the GitHub
/// Pages address until stickermine.app is bought and resolves (section 15).
enum AboutLinks {
    struct Row: Equatable, Identifiable {
        let title: String
        let symbol: String
        let help: String
        let url: URL
        var id: String { title }
    }

    static let website = URL(string: "https://grokcodile.github.io/stickermine/")!
    static let repo = URL(string: "https://github.com/grokcodile/stickermine")!
    static let kofi = URL(string: "https://ko-fi.com/grokcodile")!
    static let issues = URL(string: "https://github.com/grokcodile/stickermine/issues")!

    static let rows: [Row] = [
        Row(title: "Website", symbol: "globe", help: "Learn more about Stickermine", url: website),
        Row(title: "Star on GitHub", symbol: "star", help: "A star helps others find it", url: repo),
        Row(title: "Buy me a coffee", symbol: "mug", help: "Tips keep it going", url: kofi),
        Row(title: "Report a Bug", symbol: "ladybug", help: "Open an issue on GitHub", url: issues),
    ]

    /// The address as you'd say it: no scheme, no trailing slash.
    static func pretty(_ url: URL) -> String {
        var text = url.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) { text.removeFirst(scheme.count) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// A row's tooltip: what it is for, then where it goes.
    static func tooltip(for row: Row) -> String {
        "\(row.help)\n↗ \(pretty(row.url))"
    }
}

/// The version line, which doubles as Check for Updates (Pullcord's).
enum VersionCheck: Equatable {
    case idle, checking, upToDate, available, failed

    static func line(version: String, check: VersionCheck) -> String {
        switch check {
        case .idle: return "Version \(version)"
        case .checking: return "Version \(version) · Checking…"
        case .upToDate: return "Version \(version) · Up to date"
        case .available: return "Version \(version) · Update available"
        case .failed: return "Version \(version) · Couldn’t check"
        }
    }
}

/// Hung from the ⓘ in Home's footer: icon, name, the version line (a click
/// checks for updates; Home's strip then offers the update) and the links.
struct AboutPopover: View {
    @ObservedObject var updater: Updater
    let open: (URL) -> Void

    @State private var check: VersionCheck = .idle

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 64, height: 64)
            Text("Stickermine")
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Button(VersionCheck.line(version: updater.appVersion, check: check)) { checkNow() }
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("Check for updates")
            VStack(spacing: 6) {
                ForEach(AboutLinks.rows) { row in
                    Button { open(row.url) } label: {
                        Label(row.title, systemImage: row.symbol)
                            .frame(maxWidth: .infinity)
                    }
                    .controlSize(.large)
                    .help(AboutLinks.tooltip(for: row))
                }
            }
            .padding(.top, 6)
        }
        .padding(16)
        .frame(width: 268)
    }

    private func checkNow() {
        check = .checking
        updater.check { reachable in
            guard reachable else {
                check = .failed
                return
            }
            check = updater.state == .upToDate ? .upToDate : .available
        }
    }
}
