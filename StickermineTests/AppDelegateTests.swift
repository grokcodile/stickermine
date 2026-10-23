import AppKit
import Testing
@testable import Stickermine

@MainActor
struct AppDelegateTests {
    @Test func detectsTheTestHost() {
        #expect(AppDelegate.isRunningTests)
    }

    @Test func startupWorkIsSkippedInTheTestHost() {
        #expect(!AppDelegate.didRunStartup)
    }

    @Test func testHostShowsNoWindows() {
        #expect(NSApp.windows.filter(\.isVisible).isEmpty)
    }
}
