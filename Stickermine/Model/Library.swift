import CoreGraphics
import Foundation

/// The four sticker styles, in UI order (spec section 8). Stored as their raw
/// strings; a string this build doesn't know (written by a newer build)
/// decodes as `.puffy` instead of failing the whole library (spec section 12).
enum StickerStyle: String, Codable, CaseIterable {
    case puffy, outline, shadow, none

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StickerStyle(rawValue: raw) ?? .puffy
    }

    /// The picker's Fill holes default for this style (spec section 7).
    var defaultFillHoles: Bool {
        switch self {
        case .puffy, .outline: return true
        case .shadow, .none: return false
        }
    }
}

/// Where a placement sits at one display size: its centre as 0–1 of the
/// display's frame (Cocoa, y up) and a multiplier on the sticker's natural
/// point size (spec section 11).
struct Pose: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double
}

/// One sticker on one display. Rotation (radians, counter-clockwise), style,
/// flip and Float on top are shared by every size; only the pose is per size.
struct Placement: Codable, Equatable, Identifiable {
    let id: UUID
    var sticker: UUID
    var style: StickerStyle
    var flipped: Bool
    var onTop: Bool
    var rotation: Double
    /// Keyed by `DisplaySize.key`, e.g. "1920x1080".
    var poses: [String: Pose]

    init(id: UUID = UUID(), sticker: UUID, style: StickerStyle, flipped: Bool = false,
         onTop: Bool = false, rotation: Double = 0, poses: [String: Pose]) {
        self.id = id
        self.sticker = sticker
        self.style = style
        self.flipped = flipped
        self.onTop = onTop
        self.rotation = rotation
        self.poses = poses
    }

    private enum CodingKeys: String, CodingKey {
        case id, sticker, style, flipped, onTop, rotation, poses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sticker = try c.decode(UUID.self, forKey: .sticker)
        style = try c.decodeIfPresent(StickerStyle.self, forKey: .style) ?? .puffy
        flipped = try c.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
        onTop = try c.decodeIfPresent(Bool.self, forKey: .onTop) ?? false
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        poses = try c.decodeIfPresent([String: Pose].self, forKey: .poses) ?? [:]
    }
}

/// One entry in the history: a master PNG in `stickers/<id>.png`.
struct StickerRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var created: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var pixelsPerPoint: Double
    var lastStyle: StickerStyle
    var tutorial: Bool

    init(id: UUID, created: Date, pixelWidth: Int, pixelHeight: Int, pixelsPerPoint: Double,
         lastStyle: StickerStyle, tutorial: Bool = false) {
        self.id = id
        self.created = created
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pixelsPerPoint = pixelsPerPoint
        self.lastStyle = lastStyle
        self.tutorial = tutorial
    }

    /// The size the sticker had on screen when it was captured: pixels divided
    /// by the capture's pixels per point (spec section 5.8).
    var naturalPointSize: CGSize {
        let ppp = pixelsPerPoint > 0 ? pixelsPerPoint : 1
        return CGSize(width: Double(pixelWidth) / ppp, height: Double(pixelHeight) / ppp)
    }

    private enum CodingKeys: String, CodingKey {
        case id, created, pixelWidth, pixelHeight, pixelsPerPoint, lastStyle, tutorial
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        pixelWidth = try c.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
        pixelsPerPoint = try c.decodeIfPresent(Double.self, forKey: .pixelsPerPoint) ?? 2
        lastStyle = try c.decodeIfPresent(StickerStyle.self, forKey: .lastStyle) ?? .puffy
        tutorial = try c.decodeIfPresent(Bool.self, forKey: .tutorial) ?? false
    }
}

/// Everything known about one display (keyed by its UUID in `Library.displays`),
/// with its placements in z-order, back to front.
struct DisplayRecord: Codable, Equatable {
    var name: String
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var builtin: Bool
    var lastSeen: Date
    var placements: [Placement]

    init(name: String, vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool,
         lastSeen: Date, placements: [Placement]) {
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.builtin = builtin
        self.lastSeen = lastSeen
        self.placements = placements
    }

    private enum CodingKeys: String, CodingKey {
        case name, vendor, model, serial, builtin, lastSeen, placements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        vendor = try c.decodeIfPresent(UInt32.self, forKey: .vendor) ?? 0
        model = try c.decodeIfPresent(UInt32.self, forKey: .model) ?? 0
        serial = try c.decodeIfPresent(UInt32.self, forKey: .serial) ?? 0
        builtin = try c.decodeIfPresent(Bool.self, forKey: .builtin) ?? false
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date(timeIntervalSince1970: 0)
        placements = try c.decodeIfPresent([Placement].self, forKey: .placements) ?? []
    }
}

/// The whole of `library.json` (spec section 12).
struct Library: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var stickers: [StickerRecord]
    /// Keyed by display UUID (uppercase).
    var displays: [String: DisplayRecord]

    init(version: Int = Library.currentVersion, stickers: [StickerRecord], displays: [String: DisplayRecord]) {
        self.version = version
        self.stickers = stickers
        self.displays = displays
    }

    static var empty: Library { Library(stickers: [], displays: [:]) }

    private enum CodingKeys: String, CodingKey {
        case version, stickers, displays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        stickers = try c.decodeIfPresent([StickerRecord].self, forKey: .stickers) ?? []
        displays = try c.decodeIfPresent([String: DisplayRecord].self, forKey: .displays) ?? [:]
    }
}

extension Library {
    func sticker(_ id: UUID) -> StickerRecord? {
        stickers.first { $0.id == id }
    }

    func placement(_ id: UUID) -> Placement? {
        for record in displays.values {
            if let placement = record.placements.first(where: { $0.id == id }) { return placement }
        }
        return nil
    }

    /// The display record (key) that holds the placement.
    func displayKey(containing placement: UUID) -> String? {
        displays.first { $0.value.placements.contains { $0.id == placement } }?.key
    }

    /// Placements of `sticker` on every display, connected or not (the
    /// delete-from-history confirmation states this number).
    func placementCount(of sticker: UUID) -> Int {
        displays.values.reduce(0) { $0 + $1.placements.filter { $0.sticker == sticker }.count }
    }

    @discardableResult
    mutating func removePlacement(_ id: UUID) -> Placement? {
        guard let key = displayKey(containing: id),
              let index = displays[key]?.placements.firstIndex(where: { $0.id == id })
        else { return nil }
        return displays[key]?.placements.remove(at: index)
    }

    /// Removes the sticker and every placement of it on every display.
    mutating func removeSticker(_ id: UUID) {
        stickers.removeAll { $0.id == id }
        for key in Array(displays.keys) {
            displays[key]?.placements.removeAll { $0.sticker == id }
        }
    }

    /// Re-keys a display record (the fingerprint fallback, spec section 11).
    /// The record keeps its placements; an existing record at `newKey` is replaced.
    mutating func moveDisplayRecord(from oldKey: String, to newKey: String) {
        guard oldKey != newKey, let record = displays.removeValue(forKey: oldKey) else { return }
        displays[newKey] = record
    }
}

/// The JSON coders for `library.json`: ISO-8601 dates (whole seconds are
/// written; fractional seconds are accepted when reading), sorted keys.
enum LibraryCoding {
    private static let plainDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(plainDates.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = plainDates.date(from: text) ?? fractionalDates.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
        }
        return decoder
    }
}
