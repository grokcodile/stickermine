import Carbon.HIToolbox
import Foundation
import Testing
@testable import Stickermine

/// Every test uses its own suite, never `.standard`.
@MainActor
struct SettingsTests {
    private func suite() -> (UserDefaults, String) {
        let name = "StickermineTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func registersTheSpecDefaultsWithoutWritingThem() throws {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        Settings.register(in: defaults)
        #expect(defaults.captureShortcut == .defaultCapture)
        #expect(defaults.showMenuBarIcon)
        #expect(defaults.launchAtLogin)
        #expect(defaults.hideFromSharing)
        #expect(!defaults.didFirstRun)
        #expect(!defaults.didRequestScreenCapture)
        #expect(defaults.ownPlacementsCount == 0)
        #expect(!defaults.supportAskShown)
        // The spike's decision, whichever way M2 recorded it (false unless the
        // fallback became the default).
        #expect(defaults.clickThroughFallback == Settings.clickThroughFallbackByDefault)
        #expect(defaults.object(forKey: Settings.Key.clickThroughFallback) as? Bool == Settings.clickThroughFallbackByDefault)
        #expect(AppDelegate.clickThroughFallbackByDefault == Settings.clickThroughFallbackByDefault)
        // Settings is pure (spec section 4): it never reads the AppKit app
        // delegate, which the import scan in LibraryModelTests can't see.
        #expect(!(try SourceFiles.contents(of: "App/Settings.swift")).contains("AppDelegate"))
        // Registered defaults live in memory only.
        #expect(defaults.persistentDomain(forName: name)?.isEmpty ?? true)
    }

    @Test func theKeysAreTheSpecNames() {
        #expect(Settings.Key.captureShortcut == "captureShortcut")
        #expect(Settings.Key.showMenuBarIcon == "showMenuBarIcon")
        #expect(Settings.Key.launchAtLogin == "launchAtLogin")
        #expect(Settings.Key.hideFromSharing == "hideFromSharing")
        #expect(Settings.Key.didFirstRun == "didFirstRun")
        #expect(Settings.Key.didRequestScreenCapture == "didRequestScreenCapture")
        #expect(Settings.Key.ownPlacementsCount == "ownPlacementsCount")
        #expect(Settings.Key.supportAskShown == "supportAskShown")
        #expect(Settings.Key.clickThroughFallback == "clickThroughFallback")
        #expect(PermissionPanel.didRequestKey == Settings.Key.didRequestScreenCapture)
    }

    @Test func aShortcutIsStoredAsKAndM() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        Settings.register(in: defaults)
        let chord = Shortcut(keyCode: 40, modifiers: UInt32(cmdKey | shiftKey))
        defaults.captureShortcut = chord
        #expect(defaults.dictionary(forKey: Settings.Key.captureShortcut) as? [String: Int] == ["k": 40, "m": 768])
        #expect(defaults.captureShortcut == chord)
        let reopened = UserDefaults(suiteName: name)!
        #expect(reopened.captureShortcut == chord)
    }

    @Test func aClearedShortcutStaysClearedAndNeverFallsBackToTheDefault() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        Settings.register(in: defaults)
        defaults.captureShortcut = nil
        #expect(defaults.captureShortcut == nil)
        #expect(defaults.dictionary(forKey: Settings.Key.captureShortcut)?.isEmpty == true)
        Settings.register(in: defaults)
        #expect(defaults.captureShortcut == nil)
        // Recording the default again stores it explicitly.
        defaults.captureShortcut = .defaultCapture
        #expect(defaults.captureShortcut == .defaultCapture)
    }

    @Test func anUnreadableShortcutReadsAsNone() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set("⌃⌥⌘S", forKey: Settings.Key.captureShortcut)
        #expect(defaults.captureShortcut == nil)
        defaults.set(["k": 1], forKey: Settings.Key.captureShortcut)
        #expect(defaults.captureShortcut == nil)
        defaults.set(["k": 1, "m": -5], forKey: Settings.Key.captureShortcut)
        #expect(defaults.captureShortcut == nil)
        #expect(Settings.shortcut(fromStored: ["k": 1, "m": 6400]) == .defaultCapture)
        #expect(Settings.storedValue(for: nil).isEmpty)
    }

    @Test func gettersFallBackToTheDefaultsBeforeRegistration() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(defaults.captureShortcut == .defaultCapture)
        #expect(defaults.showMenuBarIcon)
        #expect(defaults.launchAtLogin)
        #expect(defaults.hideFromSharing)
        #expect(defaults.clickThroughFallback == Settings.clickThroughFallbackByDefault)
        #expect(defaults.ownPlacementsCount == 0)
    }

    @Test func theSettersWriteTheirKeys() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.showMenuBarIcon = false
        defaults.launchAtLogin = false
        defaults.hideFromSharing = false
        defaults.didFirstRun = true
        defaults.didRequestScreenCapture = true
        defaults.ownPlacementsCount = 4
        defaults.supportAskShown = true
        defaults.clickThroughFallback = true
        #expect(defaults.object(forKey: "showMenuBarIcon") as? Bool == false)
        #expect(defaults.object(forKey: "launchAtLogin") as? Bool == false)
        #expect(defaults.object(forKey: "hideFromSharing") as? Bool == false)
        #expect(defaults.bool(forKey: "didFirstRun"))
        #expect(defaults.bool(forKey: PermissionPanel.didRequestKey))
        #expect(defaults.integer(forKey: "ownPlacementsCount") == 4)
        #expect(defaults.bool(forKey: "supportAskShown"))
        #expect(defaults.bool(forKey: "clickThroughFallback"))
    }
}
