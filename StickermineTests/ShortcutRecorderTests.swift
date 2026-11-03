import AppKit
import Carbon.HIToolbox
import Testing
@testable import Stickermine

/// The recorder is driven with synthesized key events; no window is shown.
@MainActor
struct ShortcutRecorderTests {
    static func key(_ code: Int, _ flags: NSEvent.ModifierFlags = [], _ characters: String = "k") throws -> NSEvent {
        try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: 0,
                                      windowNumber: 0, context: nil, characters: characters,
                                      charactersIgnoringModifiers: characters, isARepeat: false,
                                      keyCode: UInt16(code)))
    }

    final class Recorder {
        var changes: [Shortcut?] = []
        var recording: [Bool] = []
        var rejected = 0
    }

    func makeButton(_ shortcut: Shortcut? = .defaultCapture) -> (ShortcutRecorderButton, Recorder) {
        let button = ShortcutRecorderButton(shortcut: shortcut)
        let recorder = Recorder()
        button.onChange = { recorder.changes.append($0) }
        button.onRecordingChange = { recorder.recording.append($0) }
        button.onRejected = { recorder.rejected += 1 }
        return (button, recorder)
    }

    @Test func outcomesFollowTheSpecRules() {
        typealias R = ShortcutRecording
        #expect(R.outcome(keyCode: UInt16(kVK_Escape), flags: []) == .cancel)
        #expect(R.outcome(keyCode: UInt16(kVK_Escape), flags: [.shift]) == .cancel)
        #expect(R.outcome(keyCode: UInt16(kVK_Delete), flags: []) == .clear)
        #expect(R.outcome(keyCode: UInt16(kVK_ForwardDelete), flags: []) == .clear)
        #expect(R.outcome(keyCode: 1, flags: [.control, .option, .command]) == .record(.defaultCapture))
        #expect(R.outcome(keyCode: 40, flags: [.command]) == .record(Shortcut(keyCode: 40, modifiers: UInt32(cmdKey))))
        #expect(R.outcome(keyCode: 40, flags: [.control, .shift])
                == .record(Shortcut(keyCode: 40, modifiers: UInt32(controlKey | shiftKey))))
        #expect(R.outcome(keyCode: 40, flags: [.option]) == .reject)
        #expect(R.outcome(keyCode: 40, flags: [.option, .shift]) == .reject)
        #expect(R.outcome(keyCode: 40, flags: []) == .reject)
        // F-keys may stand alone; ⌘Esc and ⌘⌫ are ordinary chords.
        #expect(R.outcome(keyCode: 96, flags: []) == .record(Shortcut(keyCode: 96, modifiers: 0)))
        #expect(R.outcome(keyCode: UInt16(kVK_Escape), flags: [.command])
                == .record(Shortcut(keyCode: UInt32(kVK_Escape), modifiers: UInt32(cmdKey))))
        #expect(R.outcome(keyCode: UInt16(kVK_Delete), flags: [.command])
                == .record(Shortcut(keyCode: UInt32(kVK_Delete), modifiers: UInt32(cmdKey))))
        // Caps Lock and Fn don't count as modifiers.
        #expect(R.outcome(keyCode: 40, flags: [.capsLock, .function]) == .reject)
    }

    @Test func recordingSuspendsTheHotkeyAndAChordReplacesTheShortcut() throws {
        let (button, recorder) = makeButton()
        defer { button.cancelRecording() }
        #expect(button.title == "⌃⌥⌘S")
        button.beginRecording()
        #expect(button.isRecording)
        #expect(ShortcutRecorderButton.active === button)
        #expect(button.title == ShortcutRecorderButton.listeningTitle)
        #expect(recorder.recording == [true])
        #expect(button.handle(try Self.key(40, [.command])))
        let chord = Shortcut(keyCode: 40, modifiers: UInt32(cmdKey))
        #expect(recorder.changes == [chord])
        #expect(recorder.recording == [true, false])
        #expect(!button.isRecording)
        #expect(ShortcutRecorderButton.active == nil)
        #expect(button.shortcut == chord)
        #expect(button.title == "⌘K")
    }

    @Test func escCancelsAndDeleteClears() throws {
        let (button, recorder) = makeButton()
        defer { button.cancelRecording() }
        button.beginRecording()
        button.handle(try Self.key(kVK_Escape, [], "\u{1b}"))
        #expect(!button.isRecording)
        #expect(recorder.changes.isEmpty)
        #expect(button.shortcut == .defaultCapture)
        button.beginRecording()
        button.handle(try Self.key(kVK_Delete, [], "\u{7f}"))
        #expect(recorder.changes == [nil])
        #expect(button.shortcut == nil)
        #expect(button.title == ShortcutRecorderButton.emptyTitle)
        #expect(recorder.recording == [true, false, true, false])
    }

    @Test func aChordWithoutCommandOrControlIsRefusedAndListeningGoesOn() throws {
        let (button, recorder) = makeButton()
        defer { button.cancelRecording() }
        button.beginRecording()
        #expect(button.handle(try Self.key(40, [.option])))
        #expect(button.isRecording)
        #expect(recorder.rejected == 1)
        #expect(recorder.changes.isEmpty)
        button.handle(try Self.key(111))   // F12 alone
        #expect(recorder.changes == [Shortcut(keyCode: 111, modifiers: 0)])
    }

    @Test func keysAreIgnoredWhenNotListening() throws {
        let (button, recorder) = makeButton()
        #expect(!button.handle(try Self.key(40, [.command])))
        #expect(recorder.changes.isEmpty)
        button.cancelRecording()
        #expect(recorder.recording.isEmpty)
    }

    @Test func onlyOneRecorderListensAtATime() {
        let (first, firstRecorder) = makeButton()
        let (second, secondRecorder) = makeButton()
        defer { first.cancelRecording(); second.cancelRecording() }
        first.beginRecording()
        second.beginRecording()
        #expect(!first.isRecording)
        #expect(second.isRecording)
        #expect(firstRecorder.recording == [true, false])
        #expect(secondRecorder.recording == [true])
        #expect(ShortcutRecorderButton.active === second)
    }

    @Test func leavingTheWindowStopsListening() {
        let window = NSWindow(contentRect: NSRect(x: 40_000, y: 0, width: 200, height: 80), styleMask: [.titled],
                              backing: .buffered, defer: true)
        window.isReleasedWhenClosed = false
        let (button, recorder) = makeButton()
        window.contentView?.addSubview(button)
        button.beginRecording()
        button.removeFromSuperview()
        #expect(!button.isRecording)
        #expect(recorder.recording == [true, false])
        window.close()
    }
}
