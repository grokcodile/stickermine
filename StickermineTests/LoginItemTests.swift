import Foundation
import ServiceManagement
import Testing
@testable import Stickermine

/// A fake service: the real login items are never touched.
@MainActor
struct LoginItemTests {
    final class FakeService: LoginItemService {
        var status: SMAppService.Status
        var statusAfterRegister: SMAppService.Status = .enabled
        var registers = 0
        var unregisters = 0
        var settingsOpened = 0
        var failsToRegister = false

        init(status: SMAppService.Status) { self.status = status }

        func register() throws {
            registers += 1
            if failsToRegister { throw CocoaError(.featureUnsupported) }
            status = statusAfterRegister
        }

        func unregister() throws {
            unregisters += 1
            status = .notRegistered
        }

        func openSystemSettings() { settingsOpened += 1 }
    }

    private func suite() -> (UserDefaults, String) {
        let name = "StickermineTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func launchRegistersWhenOnAndNotYetEnabled() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = FakeService(status: .notRegistered)
        let item = LoginItem(service: service, defaults: defaults)
        item.applyAtLaunch()
        #expect(service.registers == 1)
        #expect(item.state == .on)
        item.applyAtLaunch()
        #expect(service.registers == 1)
    }

    @Test func launchLeavesAnOffSettingAlone() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.launchAtLogin = false
        let service = FakeService(status: .notRegistered)
        let item = LoginItem(service: service, defaults: defaults)
        item.applyAtLaunch()
        #expect(service.registers == 0)
        #expect(service.unregisters == 0)
        #expect(item.state == .off)
    }

    @Test func turningItOffUnregistersAndOnRegisters() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = FakeService(status: .enabled)
        let item = LoginItem(service: service, defaults: defaults)
        item.setEnabled(false)
        #expect(service.unregisters == 1)
        #expect(!defaults.launchAtLogin)
        #expect(item.state == .off)
        item.setEnabled(true)
        #expect(service.registers == 1)
        #expect(defaults.launchAtLogin)
        #expect(item.state == .on)
        #expect(service.settingsOpened == 0)
    }

    @Test func approvalShowsAndOpensLoginItems() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = FakeService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let item = LoginItem(service: service, defaults: defaults)
        item.applyAtLaunch()
        // At launch it only shows; System Settings opens when the user turns it on.
        #expect(item.state == .requiresApproval)
        #expect(service.settingsOpened == 0)
        item.setEnabled(true)
        #expect(service.settingsOpened == 1)
        item.openSystemSettings()
        #expect(service.settingsOpened == 2)
    }

    @Test func aFailedRegistrationKeepsTheSetting() {
        let (defaults, name) = suite()
        defer { defaults.removePersistentDomain(forName: name) }
        let service = FakeService(status: .notRegistered)
        service.failsToRegister = true
        let item = LoginItem(service: service, defaults: defaults)
        item.setEnabled(true)
        #expect(service.registers == 1)
        #expect(defaults.launchAtLogin)
    }
}
