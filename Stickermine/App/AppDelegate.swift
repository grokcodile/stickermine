import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is hosting the unit-test bundle. Every startup step
    /// (single-instance check, hotkey, status item, sticker restore, launch repair,
    /// SMAppService, updater) must be skipped then, so tests never show a window
    /// or touch system state (spec section 18).
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Set right after the test-host guard, so a test can prove the guard returned
    /// early (nothing in M1's startup is visible enough to test otherwise).
    private(set) static var didRunStartup = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
