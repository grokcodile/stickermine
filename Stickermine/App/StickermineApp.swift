import SwiftUI

/// The SwiftUI entry point. Its only scene is an empty Settings scene, so SwiftUI
/// never opens a window of its own: every window in Stickermine is an AppKit
/// window or panel owned by a controller that AppDelegate holds (spec section 4).
@main
struct StickermineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
