import Foundation
import ServiceManagement

/// What `LoginItem` needs from `SMAppService.mainApp`, so tests never touch
/// the real login items.
@MainActor
protocol LoginItemService: AnyObject {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
    /// System Settings › General › Login Items.
    func openSystemSettings()
}

@MainActor
final class LiveLoginItemService: LoginItemService {
    init() {}

    var status: SMAppService.Status { SMAppService.mainApp.status }
    func register() throws { try SMAppService.mainApp.register() }
    func unregister() throws { try SMAppService.mainApp.unregister() }
    func openSystemSettings() { SMAppService.openSystemSettingsLoginItems() }
}

/// Launch at login (spec section 13): `SMAppService.mainApp`, on by default,
/// because stickers only exist while the app runs. The `launchAtLogin`
/// setting is the switch; registering happens when it is on and the service
/// isn't enabled, unregistering when it is turned off. When macOS wants the
/// user's approval first, the setting says so and System Settings opens.
@MainActor
final class LoginItem {
    enum State: Equatable {
        case on
        case off
        /// On, but macOS waits for the user to allow it in Login Items.
        case requiresApproval
    }

    private let service: LoginItemService
    private let defaults: UserDefaults

    init(service: LoginItemService? = nil, defaults: UserDefaults = .standard) {
        self.service = service ?? LiveLoginItemService()
        self.defaults = defaults
    }

    var state: State {
        guard defaults.launchAtLogin else { return .off }
        return service.status == .requiresApproval ? .requiresApproval : .on
    }

    /// Every launch (outside the test host): register when the setting is on
    /// and the service isn't enabled yet. An off setting is left alone.
    func applyAtLaunch() {
        guard defaults.launchAtLogin, service.status != .enabled else { return }
        try? service.register()
    }

    /// The Home toggle. Turning it on registers and, if macOS asks for
    /// approval, opens Login Items; turning it off unregisters.
    func setEnabled(_ on: Bool) {
        defaults.launchAtLogin = on
        if on {
            if service.status != .enabled { try? service.register() }
            if service.status == .requiresApproval { service.openSystemSettings() }
        } else {
            try? service.unregister()
        }
    }

    func openSystemSettings() {
        service.openSystemSettings()
    }
}
