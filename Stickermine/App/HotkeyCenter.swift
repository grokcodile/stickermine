import Carbon.HIToolbox
import Foundation
import os

/// The capture shortcut as a Carbon global hotkey (spec section 5.1): no
/// Accessibility or Input Monitoring permission is needed. One shortcut per
/// center. `suspend()` unregisters it while the shortcut recorder (M6) listens
/// and `resume()` registers it again. Ported from Pullcord's installHandler and
/// syncHotkeys, with its own signature 'STKM'.
@MainActor
final class HotkeyCenter {
    /// 'STKM'
    static let signature: OSType = 0x5354_4B4D

    /// Carbon IDs are per center, so several centers (tests) never answer
    /// each other's presses.
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var shortcut: Shortcut?
    private var handler: (() -> Void)?
    private var isSuspended = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "hotkey")

    /// The status of the last `RegisterEventHotKey` call (noErr when none ran).
    /// Carbon hotkeys aren't exclusive, so noErr doesn't prove no other app
    /// uses the chord.
    private(set) var lastStatus: OSStatus = noErr

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    var isRegistered: Bool { hotKey != nil }

    /// Replaces the shortcut (nil: none) and what a press does. While suspended
    /// it is registered on `resume()`.
    func register(_ shortcut: Shortcut?, handler: @escaping () -> Void) {
        unregisterHotKey()
        self.shortcut = shortcut
        self.handler = handler
        installEventHandlerIfNeeded()
        if !isSuspended { registerHotKey() }
    }

    func suspend() {
        isSuspended = true
        unregisterHotKey()
    }

    func resume() {
        isSuspended = false
        if !isRegistered { registerHotKey() }
    }

    /// Unregisters the shortcut and removes the Carbon handler (tests; the app's
    /// center lives as long as the app).
    func invalidate() {
        unregisterHotKey()
        handler = nil
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Runs the handler, as a press of the shortcut does.
    func fire() {
        handler?()
    }

    private func registerHotKey() {
        guard let shortcut, hotKey == nil else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        lastStatus = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &ref)
        if lastStatus == noErr, let ref {
            hotKey = ref
        } else {
            log.error("registering \(shortcut.label, privacy: .public) failed: \(self.lastStatus)")
        }
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            guard pressedID.signature == HotkeyCenter.signature, pressedID.id == center.id else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.fire() }
            }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr {
            log.error("InstallEventHandler failed: \(status)")
        }
    }
}
