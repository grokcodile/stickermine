import AppKit
import Testing
@testable import Stickermine

@MainActor
struct LiveScreenProviderTests {
    @Test func everyRealScreenIsReportedWithItsUUID() throws {
        let displays = LiveScreenProvider().currentDisplays()
        try #require(!displays.isEmpty)
        for display in displays {
            #expect(display.uuid == display.uuid.uppercased())
            #expect(display.uuid == DisplayRegistry.uuidString(for: display.displayID))
            #expect(!display.isGhost)
            #expect(display.mirrorsDisplayID == nil)
            let screen = try #require(NSScreen.screens.first { $0.cgDirectDisplayID == display.displayID })
            #expect(display.frame == screen.frame)
            #expect(display.visibleFrame == screen.visibleFrame)
            #expect(display.backingScale == screen.backingScaleFactor)
            #expect(display.name == screen.localizedName)
        }
        #expect(Set(displays.map(\.uuid)).count == displays.count)
    }

    @Test func theMainDisplayIsTheMenuBarScreen() throws {
        let main = try #require(LiveScreenProvider().mainDisplay)
        #expect(main.frame == NSScreen.screens[0].frame)
        #expect(main.frame.origin == .zero)
    }
}
