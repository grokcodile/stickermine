import SwiftUI

/// The words the settings section uses (spec section 13). Pure.
enum SettingsText {
    static let shortcutTitle = "Capture shortcut"
    static let shortcutHelp = "Click to record. Esc cancels, Delete clears. A shortcut needs ⌘ or ⌃ (F-keys can stand alone)."
    static let voiceOverHelp = "VoiceOver users: ⌃⌥⌘S is also VO-⌘-S, so you may want to record another shortcut."
    static let rejected = "That one needs ⌘ or ⌃ (F-keys can stand alone). Try another."
    static let menuBarTitle = "Show menu bar icon"
    static let loginTitle = "Launch at login"
    static let loginDetail = "Stickers only stay on your desktop while Stickermine runs."
    static let loginNeedsApproval = "macOS is waiting for your OK in System Settings › General › Login Items."
    static let sharingTitle = "Hide stickers from screen sharing and screenshots"
    static let sharingDetail = "Best effort: screen sharing, recording and screenshot apps usually leave stickers out. This also keeps them out of your own screenshots."
    static let screenRecordingTitle = "Screen Recording"

    /// The macOS-shortcut warning; Stickermine can't see other apps' shortcuts.
    static func conflict(_ shortcut: Shortcut) -> String {
        "\(shortcut.label) is also a macOS shortcut (System Settings › Keyboard › Keyboard Shortcuts), so it may not reach Stickermine."
    }

    /// What making a sticker takes without a shortcut (Review Focus 5: the
    /// way back to Home is always opening the app again).
    static func noShortcut(menuBarIcon: Bool) -> String {
        menuBarIcon
            ? "No shortcut: click the menu bar icon to make a sticker."
            : "No shortcut and no menu bar icon: open Stickermine again and click New Sticker."
    }

    static func menuBarDetail(on: Bool) -> String {
        on ? "Click it to make a sticker; right-click it for the menu."
            : "Without it, use the shortcut, or open Stickermine again to come back here."
    }

    /// Once access was asked for and is still off, the check may be stale
    /// (spec section 14), so Home also offers a relaunch.
    static func screenRecordingDetail(on: Bool, requested: Bool) -> String {
        if on { return "On. macOS will ask you to confirm it from time to time." }
        return requested
            ? "Off. If you just turned it on in System Settings, relaunch Stickermine so it sees the change."
            : "Off. macOS needs it before Stickermine can open the screenshot crosshair."
    }
}

/// Home's settings (spec section 13): the capture shortcut, the menu bar
/// icon, launch at login, hiding from screen sharing, and Screen Recording.
struct SettingsSection: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Settings")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
            shortcutRow
            toggle(SettingsText.menuBarTitle, isOn: model.showMenuBarIcon, set: model.setShowMenuBarIcon,
                   detail: SettingsText.menuBarDetail(on: model.showMenuBarIcon))
            loginRow
            toggle(SettingsText.sharingTitle, isOn: model.hideFromSharing, set: model.setHideFromSharing,
                   detail: SettingsText.sharingDetail)
            screenRecordingRow
        }
    }

    private var shortcutRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(SettingsText.shortcutTitle)
                Spacer()
                ShortcutRecorder(shortcut: model.shortcut, onChange: model.setShortcut,
                                 onRecordingChange: model.recordingChanged, onRejected: model.rejectChord)
                    .frame(width: 170)
            }
            if model.chordRejected {
                detail(SettingsText.rejected, warning: true)
            } else if let shortcut = model.shortcut, model.shortcutConflicts {
                detail(SettingsText.conflict(shortcut), warning: true)
            } else if model.shortcut == nil {
                detail(SettingsText.noShortcut(menuBarIcon: model.showMenuBarIcon), warning: false)
            }
            detail(SettingsText.shortcutHelp, warning: false)
            detail(SettingsText.voiceOverHelp, warning: false)
        }
    }

    private var loginRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(SettingsText.loginTitle, isOn: Binding(get: { model.loginState != .off },
                                                          set: { model.setLaunchAtLogin($0) }))
            if model.loginState == .requiresApproval {
                HStack(spacing: 8) {
                    detail(SettingsText.loginNeedsApproval, warning: true)
                    Button("Open Login Items") { model.openLoginItems() }
                        .controlSize(.small)
                }
            } else {
                detail(SettingsText.loginDetail, warning: false)
            }
        }
    }

    private var screenRecordingRow: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(SettingsText.screenRecordingTitle,
                      systemImage: model.screenRecordingOn ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(model.screenRecordingOn ? Color.green : Color.orange)
                Spacer()
                if !model.screenRecordingOn {
                    if model.screenRecordingRequested {
                        Button("Relaunch Stickermine") { model.relaunch() }
                    }
                    Button("Turn On…") { model.fixScreenRecording() }
                }
            }
            detail(SettingsText.screenRecordingDetail(on: model.screenRecordingOn,
                                                      requested: model.screenRecordingRequested), warning: false)
        }
    }

    private func toggle(_ title: String, isOn: Bool, set: @escaping (Bool) -> Void, detail text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(title, isOn: Binding(get: { isOn }, set: set))
            detail(text, warning: false)
        }
    }

    private func detail(_ text: String, warning: Bool) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(warning ? Color.orange : Color.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
