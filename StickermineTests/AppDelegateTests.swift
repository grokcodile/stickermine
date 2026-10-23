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

    @Test func theSpikeAndTheDebugMaplePathAreGone() throws {
        for file in ["Stickers/SpikeController.swift", "App/DebugMaple.swift"] {
            #expect(!FileManager.default.fileExists(atPath: SourceFiles.appRoot.appendingPathComponent(file).path))
        }
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(!delegate.contains("SpikeController"))
        #expect(!delegate.contains("DebugMaple"))
    }

    @Test func theStyleGalleryRunsInsteadOfTheStickers() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        let gallery = try #require(delegate.range(of: "StyleGallery.launchArgument"))
        let stickers = try #require(delegate.range(of: "startStickers()\n"))
        #expect(gallery.lowerBound < stickers.lowerBound)
        #expect(delegate.contains("StyleGallery.runAndQuit()"))
    }

    @Test func launchWiresTheCaptureTriggersAndCleansUp() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(delegate.contains("CaptureService.deleteLeftovers()"))
        #expect(delegate.contains("StatusItemController(shortcut: shortcut)"))
        #expect(delegate.contains("hotkeys.register(shortcut)"))
        #expect(delegate.contains("let shortcut = Shortcut.defaultCapture"))
        // Quit and termination cancel the session (terminating screencapture)
        // before the library is flushed.
        let terminate = try #require(delegate.range(of: "func applicationWillTerminate"))
        let cancel = try #require(delegate.range(of: "session?.cancel()", range: terminate.upperBound..<delegate.endIndex))
        let flush = try #require(delegate.range(of: "library?.flush()", range: terminate.upperBound..<delegate.endIndex))
        #expect(cancel.lowerBound < flush.lowerBound)
    }
}
