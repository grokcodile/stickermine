import Carbon.HIToolbox
import Testing
@testable import Stickermine

/// Registers ⌃⌥⇧⌘F19, a chord nothing else uses, and unregisters it before returning.
@MainActor
struct HotkeyCenterTests {
    static let unusual = Shortcut(keyCode: 80, modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))

    @Test func registersSuspendsAndResumes() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        center.register(Self.unusual) {}
        #expect(center.isRegistered)
        #expect(center.lastStatus == noErr)
        center.suspend()
        #expect(!center.isRegistered)
        center.resume()
        #expect(center.isRegistered)
    }

    @Test func aShortcutSetWhileSuspendedWaitsForResume() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        center.suspend()
        center.register(Self.unusual) {}
        #expect(!center.isRegistered)
        center.resume()
        #expect(center.isRegistered)
    }

    @Test func noShortcutRegistersNothing() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        center.register(Self.unusual) {}
        center.register(nil) {}
        #expect(!center.isRegistered)
        center.resume()
        #expect(!center.isRegistered)
    }

    @Test func aPressRunsTheLatestHandler() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        var presses: [String] = []
        center.register(Self.unusual) { presses.append("first") }
        center.register(Self.unusual) { presses.append("second") }
        center.fire()
        #expect(presses == ["second"])
        #expect(HotkeyCenter.signature == 0x5354_4B4D)   // 'STKM'
    }
}
