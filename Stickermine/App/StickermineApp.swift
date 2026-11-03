import SwiftUI

/// The SwiftUI entry point. Its only scene is an empty Settings scene, so SwiftUI
/// never opens a window of its own: every window in Stickermine is an AppKit
/// window or panel owned by a controller that AppDelegate holds (spec section 4).
/// (`SwiftUI.Settings`, because the app's own `Settings` enum holds its
/// UserDefaults keys.)
///
/// The main menu is never shown (Stickermine is an agent app), but its key
/// equivalents work while Stickermine is active: ⌘, opens Home, which holds
/// the settings, instead of the empty Settings window, and there is no ⌘Q,
/// because quitting takes every sticker off the desktop and so is only ever
/// a deliberate click (Home's Quit, the menu bar menu's Quit), as in Key54.
/// Home closes itself on ⌘W (`HomeWindow`).
@main
struct StickermineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        SwiftUI.Settings {
            EmptyView()
        }
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { appDelegate.showHome() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .appTermination) {}
        }
    }
}
