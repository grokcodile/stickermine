import ColorSync
import CoreGraphics
import Foundation

/// One connected display as Stickermine sees it (built by `LiveScreenProvider`
/// from an `NSScreen`, or by tests). Frames are Cocoa global coordinates.
struct DisplayInfo: Equatable {
    /// Uppercase `CGDisplayCreateUUIDFromDisplayID` string: the only identity
    /// that is persisted.
    let uuid: String
    /// Runtime handle only; never persisted (spec section 11).
    let displayID: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScale: CGFloat
    let name: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let builtin: Bool
    /// The display this one mirrors; nil when it is not a mirror secondary.
    let mirrorsDisplayID: UInt32?
    /// True for every member of a mirror set, the primary included.
    let inMirrorSet: Bool

    init(uuid: String, displayID: UInt32, frame: CGRect, visibleFrame: CGRect, backingScale: CGFloat,
         name: String, vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool,
         mirrorsDisplayID: UInt32?, inMirrorSet: Bool = false) {
        self.uuid = uuid
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScale = backingScale
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.builtin = builtin
        self.mirrorsDisplayID = mirrorsDisplayID
        self.inMirrorSet = inMirrorSet
    }

    var size: DisplaySize { DisplaySize(frame.size) }

    /// The placeholder display macOS adds around wake and while a display is
    /// off: vendor 'unkn', model 'virt' (spec section 11).
    var isGhost: Bool {
        vendor == DisplayRegistry.ghostVendor && model == DisplayRegistry.ghostModel
    }
}

/// Display identity rules (spec section 11). Pure, except `uuidString`, which
/// asks Core Graphics.
enum DisplayRegistry {
    static let ghostVendor: UInt32 = 0x756E6B6E   // 'unkn'
    static let ghostModel: UInt32 = 0x76697274    // 'virt'
    /// A serial some vendors flash onto every unit; it identifies nothing.
    static let sharedSerial: UInt32 = 0x01010101

    /// The displays stickers may use: no null IDs, no ghost, no mirror
    /// secondaries, one entry per UUID (the first one wins).
    static func usable(_ all: [DisplayInfo]) -> [DisplayInfo] {
        var seen = Set<String>()
        return all.filter { display in
            guard display.displayID != kCGNullDirectDisplay, !display.uuid.isEmpty,
                  !display.isGhost, display.mirrorsDisplayID == nil
            else { return false }
            return seen.insert(display.uuid).inserted
        }
    }

    /// The fingerprint fallback: the key of the one disconnected record whose
    /// vendor, model, serial and built-in flag match `display`, when `display`
    /// has no record of its own, its serial means something, and no other
    /// connected display shares that fingerprint. nil otherwise (it starts empty).
    static func fingerprintAdoption(for display: DisplayInfo, records: [String: DisplayRecord],
                                    connected: [DisplayInfo]) -> String? {
        guard records[display.uuid] == nil,
              display.serial != 0, display.serial != sharedSerial
        else { return nil }
        let twinConnected = connected.contains {
            $0.uuid != display.uuid && $0.vendor == display.vendor && $0.model == display.model
                && $0.serial == display.serial && $0.builtin == display.builtin
        }
        guard !twinConnected else { return nil }
        let connectedUUIDs = Set(connected.map(\.uuid))
        let matches = records.filter { key, record in
            !connectedUUIDs.contains(key) && record.vendor == display.vendor && record.model == display.model
                && record.serial == display.serial && record.builtin == display.builtin
        }
        guard matches.count == 1 else { return nil }
        return matches.first?.key
    }

    /// The uppercase UUID string for a live display ID. nil for 0
    /// (`kCGNullDirectDisplay`, which Core Graphics would silently answer with
    /// the main display's UUID), for 0xFFFFFFFF, and for IDs that aren't online.
    static func uuidString(for displayID: UInt32) -> String? {
        guard displayID != kCGNullDirectDisplay, displayID != UInt32.max,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string.uppercased()
    }
}
