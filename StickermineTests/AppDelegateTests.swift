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
        // Before the single-instance hand-over, so the debug gallery still
        // runs while the installed copy does (it never touches the library).
        let startup = try #require(delegate.range(of: "Self.didRunStartup = true"))
        let handOver = try #require(delegate.range(of: "SingleInstance.yield(to: incumbent, userLaunch: !loginLaunch)"))
        #expect(startup.lowerBound < gallery.lowerBound)
        #expect(gallery.lowerBound < handOver.lowerBound)
    }

    @Test func launchWiresTheStoredShortcutAndTheSettings() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(delegate.contains("CaptureService.deleteLeftovers()"))
        #expect(delegate.contains("let shortcut = defaults.captureShortcut"))
        #expect(delegate.contains("StatusItemController(shortcut: shortcut)"))
        #expect(delegate.contains("hotkeys.register(shortcut)"))
        #expect(delegate.contains("statusItem.isVisible = defaults.showMenuBarIcon"))
        #expect(delegate.contains("stickers.setSharingHidden(defaults.hideFromSharing)"))
        #expect(delegate.contains("if defaults.clickThroughFallback {"))
        // The defaults are registered before anything reads them.
        let register = try #require(delegate.range(of: "Settings.register(in: defaults)"))
        let stickers = try #require(delegate.range(of: "startStickers()\n"))
        #expect(register.lowerBound < stickers.lowerBound)
    }

    @Test func aSecondCopyHandsOverBeforeAnythingStarts() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        let willFinish = try #require(delegate.range(of: "func applicationWillFinishLaunching"))
        let check = try #require(delegate.range(of: "SingleInstance.runningIncumbent()"))
        #expect(willFinish.lowerBound < check.lowerBound)
        let startup = try #require(delegate.range(of: "Self.didRunStartup = true"))
        let yield = try #require(delegate.range(of: "SingleInstance.yield(to: incumbent, userLaunch: !loginLaunch)"))
        let stickers = try #require(delegate.range(of: "startStickers()\n"))
        #expect(startup.lowerBound < yield.lowerBound)
        #expect(yield.lowerBound < stickers.lowerBound)
        #expect(delegate.contains("SingleInstance.isLoginLaunch(NSAppleEventManager.shared().currentAppleEvent)"))
        #expect(delegate.contains("forName: SingleInstance.showHomeNotification"))
    }

    @Test func quitTerminationAndTheUpdaterRunTheSameCleanup() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        let cleanup = try #require(delegate.range(of: "private func terminationCleanup() {"))
        let body = delegate[cleanup.upperBound...]
        let cancel = try #require(body.range(of: "session?.cancel()"))
        let flush = try #require(body.range(of: "library?.flush()"))
        #expect(cancel.lowerBound < flush.lowerBound)
        let terminate = try #require(delegate.range(of: "func applicationWillTerminate"))
        #expect(delegate[terminate.upperBound...].hasPrefix("(_ notification: Notification) {\n        terminationCleanup()"))
        let quit = try #require(delegate.range(of: "private func quit() {"))
        #expect(delegate[quit.upperBound...].hasPrefix("\n        terminationCleanup()\n        NSApp.terminate(nil)"))
        #expect(delegate.contains("Updater(beforeHelper: { [weak self] in self?.terminationCleanup() })"))
    }

    @Test func reopeningOpensHome() {
        let delegate = AppDelegate()
        // Before startup there is no library, so this only proves it answers true.
        #expect(delegate.applicationShouldHandleReopen(NSApp, hasVisibleWindows: false))
        #expect(NSApp.windows.filter(\.isVisible).isEmpty)
    }

    @Test func theMainMenuOpensHomeOnCommandCommaAndHasNoQuit() throws {
        let app = try SourceFiles.contents(of: "App/StickermineApp.swift")
        #expect(app.contains("SwiftUI.Settings {"))
        #expect(app.contains("CommandGroup(replacing: .appSettings)"))
        #expect(app.contains("appDelegate.showHome()"))
        #expect(app.contains("CommandGroup(replacing: .appTermination) {}"))
    }
}
