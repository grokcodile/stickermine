import AppKit
import Testing
@testable import Stickermine

/// Never touches TCC: a fake answers the Screen Recording checks.
@MainActor
struct PermissionPanelTests {
    final class FakeAccess: ScreenRecordingAccess {
        var granted = false
        var requests = 0

        func preflight() -> Bool { granted }

        func request() -> Bool {
            requests += 1
            return granted
        }
    }

    static func defaults() -> (UserDefaults, String) {
        let name = "StickermineTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func theFirstTimeItAsksAfterwardsItOpensSettingsAndThenOffersARelaunch() {
        #expect(PermissionPanelState(didRequest: false).actions == [.requestAccess])
        #expect(PermissionPanelState(didRequest: true).actions == [.openSettings])
        #expect(PermissionPanelState(didRequest: true, cameBackWithoutAccess: true).actions == [.openSettings, .relaunch])
        // Brought up by a capture: a trigger while the panel is up, after the
        // request, is coming back too, and an offered Relaunch stays.
        let fresh = PermissionPanelState(didRequest: false)
        let asked = PermissionPanelState(didRequest: true)
        let cameBack = PermissionPanelState(didRequest: true, cameBackWithoutAccess: true)
        #expect(PermissionPanelState.whenShown(didRequest: false, panelIsUp: true, previous: fresh).actions
                == [.requestAccess])
        #expect(PermissionPanelState.whenShown(didRequest: true, panelIsUp: false, previous: asked).actions
                == [.openSettings])
        #expect(PermissionPanelState.whenShown(didRequest: true, panelIsUp: true, previous: asked).actions
                == [.openSettings, .relaunch])
        #expect(PermissionPanelState.whenShown(didRequest: true, panelIsUp: false, previous: cameBack).actions
                == [.openSettings, .relaunch])
    }

    @Test func askingRequestsOnceAndRemembersIt() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let access = FakeAccess()
        let panel = PermissionPanel(access: access, defaults: defaults, screens: FakeScreens([]))
        #expect(panel.model.state.actions == [.requestAccess])
        panel.perform(.requestAccess)
        #expect(access.requests == 1)
        #expect(defaults.bool(forKey: PermissionPanel.didRequestKey))
        #expect(panel.model.state.actions == [.openSettings])
        // A later panel starts from the remembered flag.
        let later = PermissionPanel(access: access, defaults: defaults, screens: FakeScreens([]))
        #expect(later.model.state.actions == [.openSettings])
    }

    @Test func openSystemSettingsGoesToScreenRecording() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var opened: [URL] = []
        let panel = PermissionPanel(access: FakeAccess(), defaults: defaults, screens: FakeScreens([]),
                                    openURL: { opened.append($0) })
        panel.perform(.openSettings)
        #expect(opened.map(\.absoluteString)
                == ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"])
    }

    @Test func comingBackWithoutAccessOffersARelaunchAndWithAccessCloses() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: PermissionPanel.didRequestKey)
        let access = FakeAccess()
        let panel = PermissionPanel(access: access, defaults: defaults, screens: FakeScreens([]))
        var granted = 0
        panel.onGranted = { granted += 1 }
        panel.recheck()
        #expect(panel.model.state.actions == [.openSettings, .relaunch])
        #expect(granted == 0)
        access.granted = true
        panel.recheck()
        #expect(granted == 1)
        #expect(!panel.isVisible)
    }

    @Test func thePanelStaysWhileTheUserIsInSystemSettings() {
        let panel = PermissionPanel.makePanel()
        defer { panel.close() }
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.closable))
        #expect(panel.canBecomeKey)
        #expect(!panel.isVisible)
    }
}
