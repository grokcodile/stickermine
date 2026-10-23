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

    @Test func theSpikeIsGoneAndOnlyTheDebugMaplePathRemains() throws {
        let spike = SourceFiles.appRoot.appendingPathComponent("Stickers/SpikeController.swift")
        #expect(!FileManager.default.fileExists(atPath: spike.path))
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(!delegate.contains("SpikeController"))
        #expect(delegate.contains("DebugMaple.launchArgument"))
        #expect(DebugMaple.launchArgument == "-debugPlaceMaple")
    }
}
