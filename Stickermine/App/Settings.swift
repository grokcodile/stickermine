import Foundation

/// The settings Stickermine keeps in `UserDefaults` (spec section 12): their
/// key names, their defaults and typed accessors on `UserDefaults`. The app
/// calls `register(in: .standard)` first thing at launch; tests pass
/// `UserDefaults(suiteName:)`, never `.standard`.
enum Settings {
    /// From design/spike-results.md, Decisions: "Alpha click-through works, or
    /// the fallback mode becomes the default?". `defaults write
    /// com.ethan.stickermine clickThroughFallback -bool …` overrides it.
    /// (Here rather than in the app delegate, so this pure file never depends
    /// on the AppKit shell; the delegate's constant of the same name reads it.)
    static let clickThroughFallbackByDefault = false

    /// The key names, exactly as `defaults read com.ethan.stickermine` shows them.
    enum Key {
        /// `{k, m}`: the Carbon key code and modifier mask; `{}` once cleared.
        static let captureShortcut = "captureShortcut"
        static let showMenuBarIcon = "showMenuBarIcon"
        static let launchAtLogin = "launchAtLogin"
        static let hideFromSharing = "hideFromSharing"
        static let didFirstRun = "didFirstRun"
        /// The key `PermissionPanel.didRequestKey` names.
        static let didRequestScreenCapture = "didRequestScreenCapture"
        static let ownPlacementsCount = "ownPlacementsCount"
        static let supportAskShown = "supportAskShown"
        /// Hidden: never shown in Home. `defaults write com.ethan.stickermine
        /// clickThroughFallback -bool true`, read at launch (spec section 9).
        static let clickThroughFallback = "clickThroughFallback"
    }

    /// Every key's default. Registered defaults are never written to disk, so
    /// `defaults read com.ethan.stickermine` shows only what was changed.
    static func register(in defaults: UserDefaults) {
        defaults.register(defaults: [
            Key.captureShortcut: storedValue(for: .defaultCapture),
            Key.showMenuBarIcon: true,
            Key.launchAtLogin: true,
            Key.hideFromSharing: true,
            Key.didFirstRun: false,
            Key.didRequestScreenCapture: false,
            Key.ownPlacementsCount: 0,
            Key.supportAskShown: false,
            Key.clickThroughFallback: clickThroughFallbackByDefault,
        ])
    }

    /// How a shortcut is stored: `{"k": keyCode, "m": modifiers}`, or an empty
    /// dictionary for "no shortcut", so a cleared shortcut never falls back to
    /// the registered ⌃⌥⌘S.
    static func storedValue(for shortcut: Shortcut?) -> [String: Int] {
        guard let shortcut else { return [:] }
        return ["k": Int(shortcut.keyCode), "m": Int(shortcut.modifiers)]
    }

    /// The shortcut a stored value stands for: nil for a cleared one and for
    /// anything this build can't read.
    static func shortcut(fromStored value: Any?) -> Shortcut? {
        guard let dictionary = value as? [String: Any],
              let keyCode = dictionary["k"] as? Int, let modifiers = dictionary["m"] as? Int,
              (0...0xFFFF).contains(keyCode), (0...0xFFFF).contains(modifiers)
        else { return nil }
        return Shortcut(keyCode: UInt32(keyCode), modifiers: UInt32(modifiers))
    }
}

/// Typed accessors. Each getter falls back to the spec's default when the key
/// is missing, so a read before `Settings.register(in:)` still gets it.
extension UserDefaults {
    /// The capture shortcut; nil once the user cleared it.
    var captureShortcut: Shortcut? {
        get {
            guard let value = object(forKey: Settings.Key.captureShortcut) else { return .defaultCapture }
            return Settings.shortcut(fromStored: value)
        }
        set { set(Settings.storedValue(for: newValue), forKey: Settings.Key.captureShortcut) }
    }

    var showMenuBarIcon: Bool {
        get { object(forKey: Settings.Key.showMenuBarIcon) as? Bool ?? true }
        set { set(newValue, forKey: Settings.Key.showMenuBarIcon) }
    }

    var launchAtLogin: Bool {
        get { object(forKey: Settings.Key.launchAtLogin) as? Bool ?? true }
        set { set(newValue, forKey: Settings.Key.launchAtLogin) }
    }

    var hideFromSharing: Bool {
        get { object(forKey: Settings.Key.hideFromSharing) as? Bool ?? true }
        set { set(newValue, forKey: Settings.Key.hideFromSharing) }
    }

    var didFirstRun: Bool {
        get { bool(forKey: Settings.Key.didFirstRun) }
        set { set(newValue, forKey: Settings.Key.didFirstRun) }
    }

    var didRequestScreenCapture: Bool {
        get { bool(forKey: Settings.Key.didRequestScreenCapture) }
        set { set(newValue, forKey: Settings.Key.didRequestScreenCapture) }
    }

    var ownPlacementsCount: Int {
        get { integer(forKey: Settings.Key.ownPlacementsCount) }
        set { set(newValue, forKey: Settings.Key.ownPlacementsCount) }
    }

    var supportAskShown: Bool {
        get { bool(forKey: Settings.Key.supportAskShown) }
        set { set(newValue, forKey: Settings.Key.supportAskShown) }
    }

    /// Read once at launch; a change takes effect on the next launch.
    var clickThroughFallback: Bool {
        get { object(forKey: Settings.Key.clickThroughFallback) as? Bool ?? Settings.clickThroughFallbackByDefault }
        set { set(newValue, forKey: Settings.Key.clickThroughFallback) }
    }
}
