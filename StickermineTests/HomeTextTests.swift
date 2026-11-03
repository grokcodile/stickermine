import Carbon.HIToolbox
import Foundation
import Testing
@testable import Stickermine

/// The words and links Home shows. Pure.
struct HomeTextTests {
    @Test func theAboutLinksAreTheSpecsInItsOrder() {
        #expect(AboutLinks.rows.map(\.title) == ["Website", "Star on GitHub", "Buy me a coffee", "Report a Bug"])
        #expect(AboutLinks.rows.map(\.url.absoluteString) == [
            "https://grokcodile.github.io/stickermine/",
            "https://github.com/grokcodile/stickermine",
            "https://ko-fi.com/grokcodile",
            "https://github.com/grokcodile/stickermine/issues",
        ])
        #expect(AboutLinks.pretty(AboutLinks.website) == "grokcodile.github.io/stickermine")
        #expect(AboutLinks.tooltip(for: AboutLinks.rows[2]) == "Tips keep it going\n↗ ko-fi.com/grokcodile")
    }

    @Test func theVersionLineReportsTheCheck() {
        #expect(VersionCheck.line(version: "1.2", check: .idle) == "Version 1.2")
        #expect(VersionCheck.line(version: "1.2", check: .checking) == "Version 1.2 · Checking…")
        #expect(VersionCheck.line(version: "1.2", check: .upToDate) == "Version 1.2 · Up to date")
        #expect(VersionCheck.line(version: "1.2", check: .available) == "Version 1.2 · Update available")
        #expect(VersionCheck.line(version: "1.2", check: .failed) == "Version 1.2 · Couldn’t check")
    }

    @Test func theStripShowsOnlyWhileThereIsAnUpdate() {
        #expect(UpdateStrip.content(state: .upToDate, latest: nil) == nil)
        let available = UpdateStrip.content(state: .available, latest: "1.3")
        #expect(available?.text == "Update available: v1.3")
        #expect(available?.showsButton == true)
        #expect(UpdateStrip.content(state: .downloading, latest: "1.3")?.showsButton == false)
        #expect(UpdateStrip.content(state: .updating, latest: "1.3")?.text == "Updating to v1.3…")
        let failed = UpdateStrip.content(state: .failed, latest: "1.3")
        #expect(failed?.text == "The update to v1.3 didn’t finish")
        #expect(failed?.showsButton == true)
    }

    @Test func theShortcutHelpCoversConflictsAndTheWayBack() {
        let chord = Shortcut(keyCode: 20, modifiers: UInt32(cmdKey | shiftKey))
        #expect(SettingsText.conflict(chord).hasPrefix("⇧⌘3 is also a macOS shortcut"))
        #expect(SettingsText.noShortcut(menuBarIcon: true) == "No shortcut: click the menu bar icon to make a sticker.")
        #expect(SettingsText.noShortcut(menuBarIcon: false)
                == "No shortcut and no menu bar icon: open Stickermine again and click New Sticker.")
        #expect(SettingsText.voiceOverHelp.contains("VO-⌘-S"))
        #expect(SettingsText.sharingTitle == "Hide stickers from screen sharing and screenshots")
        #expect(SettingsText.sharingDetail.hasPrefix("Best effort"))
        #expect(SettingsText.sharingDetail.contains("your own screenshots"))
    }

    @Test func screenRecordingOffSuggestsARelaunchOnceItWasAskedFor() {
        #expect(SettingsText.screenRecordingDetail(on: true, requested: true).hasPrefix("On."))
        #expect(SettingsText.screenRecordingDetail(on: false, requested: false)
                == "Off. macOS needs it before Stickermine can open the screenshot crosshair.")
        #expect(SettingsText.screenRecordingDetail(on: false, requested: true).contains("relaunch Stickermine"))
    }
}
