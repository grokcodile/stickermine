import AppKit
import SwiftUI
import Testing
@testable import Stickermine

/// The Home window is built but never shown here.
@MainActor
struct HomeWindowControllerTests {
    @Test func theWindowIsBuiltButNotShown() throws {
        let h = try HomeModelTests.harness()
        defer { h.finish() }
        let home = HomeWindowController(model: h.model, mainVisibleFrame: { nil })
        defer { home.window.close() }
        let window = home.window
        #expect(!window.isVisible)
        #expect(!home.isVisible)
        #expect(window.styleMask == [.titled, .closable, .resizable, .fullSizeContentView])
        #expect(window.titlebarAppearsTransparent)
        #expect(!window.isReleasedWhenClosed)
        #expect(!window.isRestorable)
        #expect(window.minSize == HomeWindowController.minimumSize)
        #expect(window.collectionBehavior.contains(.moveToActiveSpace))
        #expect(window.contentView is NSHostingView<HomeView>)
        #expect(window.delegate === home)
        #expect(window.frame.size == HomeWindowController.initialSize)
        // The first-run tutorials keep clear of exactly this size (on a small
        // display, of the smaller one TutorialLayout.homeSize gives both).
        #expect(HomeWindowController.initialSize == TutorialStickersTests.homeSize)
    }

    @Test func commandWClosesHomeAndNothingElseDoes() throws {
        func key(_ characters: String, _ flags: NSEvent.ModifierFlags) throws -> NSEvent {
            try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                          windowNumber: 0, context: nil, characters: characters,
                                          charactersIgnoringModifiers: characters, isARepeat: false, keyCode: 13))
        }
        #expect(HomeWindow.isClose(try key("w", [.command])))
        // Caps Lock (and Fn) aren't modifiers here.
        #expect(HomeWindow.isClose(try key("w", [.command, .capsLock])))
        #expect(!HomeWindow.isClose(try key("w", [.command, .shift])))
        #expect(!HomeWindow.isClose(try key("w", [])))
        #expect(!HomeWindow.isClose(try key("q", [.command])))
    }

    @Test func resigningKeyOrClosingStopsTheRecorder() throws {
        let h = try HomeModelTests.harness()
        defer { h.finish() }
        let home = HomeWindowController(model: h.model, mainVisibleFrame: { nil })
        defer { home.window.close() }
        let recorder = ShortcutRecorderButton(shortcut: .defaultCapture)
        var states: [Bool] = []
        recorder.onRecordingChange = { states.append($0) }
        recorder.beginRecording()
        home.windowDidResignKey(Notification(name: NSWindow.didResignKeyNotification, object: home.window))
        #expect(!recorder.isRecording)
        recorder.beginRecording()
        home.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: home.window))
        #expect(!recorder.isRecording)
        #expect(states == [true, false, true, false])
    }

    @Test func becomingKeyReadsTheSettingsAgain() throws {
        let h = try HomeModelTests.harness()
        defer { h.finish() }
        let home = HomeWindowController(model: h.model, mainVisibleFrame: { nil })
        defer { home.window.close() }
        h.access.granted = true
        h.defaults.showMenuBarIcon = false
        home.windowDidBecomeKey(Notification(name: NSWindow.didBecomeKeyNotification, object: home.window))
        #expect(h.model.screenRecordingOn)
        #expect(!h.model.showMenuBarIcon)
    }
}
