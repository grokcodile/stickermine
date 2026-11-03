import AppKit
import Carbon

/// One copy of Stickermine at a time (spec section 13), ported from
/// Pullcord's `yieldToRunningInstance`. Two copies would put every sticker on
/// the desktop twice and fight over ⌃⌥⌘S.
///
/// It asks which processes run with this bundle ID rather than setting
/// `LSMultipleInstancesProhibited`: LaunchServices keys that on the bundle on
/// disk, and a rebuilt bundle looks like a different app to it, while the old
/// copy still answers to the bundle ID.
@MainActor
enum SingleInstance {
    /// A duplicate launched by the user posts this on its way out; the copy
    /// that stays opens Home, so opening the app never looks like nothing happened.
    nonisolated static let showHomeNotification = Notification.Name("com.ethan.stickermine.showHome")

    /// A running copy: its process ID and launch date (nil when unknown).
    struct Copy: Equatable {
        let pid: Int32
        let launchDate: Date?
    }

    /// The copy this one yields to, or nil when this one stays. The earliest
    /// launch wins and an identical date goes to the lower pid, so two copies
    /// launched together reach the same answer. Both unknowns lean towards
    /// yielding: an unknown own date counts as "just now", an unknown other
    /// date as "long ago".
    nonisolated static func incumbent(among others: [Copy], mine: Copy, now: Date = Date()) -> Copy? {
        let launched = mine.launchDate ?? now
        return others.first { other in
            let theirs = other.launchDate ?? .distantPast
            return theirs == launched ? other.pid < mine.pid : theirs < launched
        }
    }

    /// The running copy this launch must hand over to, read in
    /// `applicationWillFinishLaunching`, before anything is registered.
    static func runningIncumbent() -> NSRunningApplication? {
        guard let bundleID = Bundle.main.bundleIdentifier else { return nil }
        let mine = ProcessInfo.processInfo.processIdentifier
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .filter { $0.processIdentifier != mine && !$0.isTerminated }
        guard !others.isEmpty else { return nil }
        let copies = others.map { Copy(pid: $0.processIdentifier, launchDate: $0.launchDate) }
        guard let chosen = incumbent(among: copies, mine: Copy(pid: mine, launchDate: NSRunningApplication.current.launchDate))
        else { return nil }
        return others.first { $0.processIdentifier == chosen.pid }
    }

    /// Hands over and exits. A launch the user asked for means they wanted a
    /// window, so the running copy is told to open Home and brought forward; a
    /// login launch just goes. `exit` rather than `terminate`: nothing is
    /// registered yet, so there is nothing to unwind.
    static func yield(to incumbent: NSRunningApplication, userLaunch: Bool) -> Never {
        if userLaunch {
            DistributedNotificationCenter.default().postNotificationName(
                showHomeNotification, object: nil, userInfo: nil, deliverImmediately: true)
            incumbent.activate()
        }
        exit(0)
    }

    /// Whether launchd started this copy as a login item: the launch Apple
    /// event (`kAEOpenApplication`) carries `keyAELaunchedAsLogInItem` only
    /// then (spec section 13). Only readable inside
    /// `applicationDidFinishLaunching`; `currentAppleEvent` is nil earlier.
    nonisolated static func isLoginLaunch(_ event: NSAppleEventDescriptor?) -> Bool {
        guard let event, event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}
