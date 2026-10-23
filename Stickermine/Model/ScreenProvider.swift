import AppKit

/// Where StickerManager learns which displays exist. The live one reads
/// `NSScreen.screens`; tests substitute a fake to simulate unplugging,
/// mirroring and resolution changes.
@MainActor
protocol ScreenProvider: AnyObject {
    /// Connected displays, already filtered by `DisplayRegistry.usable`.
    func currentDisplays() -> [DisplayInfo]
    /// `NSScreen.screens[0]` (the menu-bar display), never `NSScreen.main`.
    var mainDisplay: DisplayInfo? { get }
}

@MainActor
final class LiveScreenProvider: ScreenProvider {
    init() {}

    /// Presence comes from `NSScreen.screens` only: a sleeping display stays in
    /// it, while `CGGetActiveDisplayList` drops it.
    func currentDisplays() -> [DisplayInfo] {
        DisplayRegistry.usable(NSScreen.screens.compactMap(Self.info(for:)))
    }

    var mainDisplay: DisplayInfo? {
        guard let first = NSScreen.screens.first, let id = first.cgDirectDisplayID else { return nil }
        return currentDisplays().first { $0.displayID == id }
    }

    /// nil for a screen without a display ID or UUID (both mean "no display").
    static func info(for screen: NSScreen) -> DisplayInfo? {
        guard let id = screen.cgDirectDisplayID, id != kCGNullDirectDisplay,
              let uuid = DisplayRegistry.uuidString(for: id)
        else { return nil }
        let mirrored = CGDisplayMirrorsDisplay(id)
        return DisplayInfo(
            uuid: uuid,
            displayID: id,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            backingScale: screen.backingScaleFactor,
            name: screen.localizedName,
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id),
            // Boolean CG calls return -1 for a vanished ID: compare with 1.
            builtin: CGDisplayIsBuiltin(id) == 1,
            mirrorsDisplayID: mirrored == kCGNullDirectDisplay ? nil : mirrored,
            inMirrorSet: CGDisplayIsInMirrorSet(id) == 1
        )
    }
}
