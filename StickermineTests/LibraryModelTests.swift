import Foundation
import Testing
@testable import Stickermine

struct LibraryModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try LibraryCoding.decoder().decode(type, from: Data(json.utf8))
    }

    @Test func stylesAreInTheUIOrder() {
        #expect(StickerStyle.allCases == [.puffy, .outline, .shadow, .none])
        #expect(StickerStyle.allCases.map(\.rawValue) == ["puffy", "outline", "shadow", "none"])
    }

    @Test func fillHolesDefaultsOnOnlyForTheRimmedStyles() {
        #expect(StickerStyle.puffy.defaultFillHoles)
        #expect(StickerStyle.outline.defaultFillHoles)
        #expect(!StickerStyle.shadow.defaultFillHoles)
        #expect(!StickerStyle.none.defaultFillHoles)
    }

    @Test func anUnknownStyleDecodesAsPuffy() throws {
        #expect(try decode([StickerStyle].self, #"["glitter", "none", "outline"]"#) == [.puffy, .none, .outline])
    }

    @Test func missingOptionalFieldsTakeTheirDefaults() throws {
        let placement = try decode(Placement.self, """
            {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "sticker": "7F9619FF-8B86-D011-B42D-00C04FC964FF"}
            """)
        #expect(placement.style == .puffy)
        #expect(!placement.flipped)
        #expect(!placement.onTop)
        #expect(placement.rotation == 0)
        #expect(placement.poses.isEmpty)

        let sticker = try decode(StickerRecord.self, """
            {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "pixelWidth": 840, "pixelHeight": 620, "future": 1}
            """)
        #expect(sticker.pixelsPerPoint == 2)
        #expect(sticker.lastStyle == .puffy)
        #expect(!sticker.tutorial)

        let display = try decode(DisplayRecord.self, "{}")
        #expect(display.placements.isEmpty)
        #expect(display.serial == 0)

        let library = try decode(Library.self, #"{"version": 1}"#)
        #expect(library == .empty)
    }

    @Test func encodesTheSpecFieldNames() throws {
        let sticker = UUID()
        let placement = Placement(sticker: sticker, style: .puffy, poses: ["1920x1080": Pose(x: 0.81, y: 0.22, scale: 1)])
        let library = Library(
            stickers: [StickerRecord(id: sticker, created: Date(timeIntervalSince1970: 1_760_000_000),
                                     pixelWidth: 840, pixelHeight: 620, pixelsPerPoint: 2, lastStyle: .outline)],
            displays: ["25A19A46-A9B2-42B2-B1F8-389D978CBBC2": DisplayRecord(
                name: "LG UltraFine", vendor: 7789, model: 23305, serial: 0, builtin: false,
                lastSeen: Date(timeIntervalSince1970: 1_760_000_000), placements: [placement])])
        let data = try LibraryCoding.encoder().encode(library)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        let stickerJSON = try #require((json["stickers"] as? [[String: Any]])?.first)
        #expect(Set(stickerJSON.keys) == ["id", "created", "pixelWidth", "pixelHeight", "pixelsPerPoint", "lastStyle", "tutorial"])
        #expect(stickerJSON["created"] as? String == "2025-10-09T08:53:20Z")
        #expect(stickerJSON["lastStyle"] as? String == "outline")
        let displays = try #require(json["displays"] as? [String: [String: Any]])
        let display = try #require(displays["25A19A46-A9B2-42B2-B1F8-389D978CBBC2"])
        #expect(Set(display.keys) == ["name", "vendor", "model", "serial", "builtin", "lastSeen", "placements"])
        let placementJSON = try #require((display["placements"] as? [[String: Any]])?.first)
        #expect(Set(placementJSON.keys) == ["id", "sticker", "style", "flipped", "onTop", "rotation", "poses"])
        let poses = try #require(placementJSON["poses"] as? [String: [String: Double]])
        #expect(poses["1920x1080"] == ["x": 0.81, "y": 0.22, "scale": 1])
        #expect(try LibraryCoding.decoder().decode(Library.self, from: data) == library)
    }

    @Test func datesWithFractionalSecondsAreAccepted() throws {
        let record = try decode(DisplayRecord.self, #"{"lastSeen": "2026-10-12T09:30:00.250Z"}"#)
        #expect(record.lastSeen == Date(timeIntervalSince1970: 1_791_797_400.25))
    }

    @Test func naturalPointSizeIsPixelsOverPixelsPerPoint() {
        let record = StickerRecord(id: UUID(), created: Date(), pixelWidth: 840, pixelHeight: 620,
                                   pixelsPerPoint: 2, lastStyle: .none)
        #expect(record.naturalPointSize == CGSize(width: 420, height: 310))
    }

    @Test func libraryHelpersFindMoveAndRemove() {
        let kept = UUID()
        let deleted = UUID()
        let a = Placement(sticker: kept, style: .puffy, poses: [:])
        let b = Placement(sticker: deleted, style: .shadow, poses: [:])
        let c = Placement(sticker: deleted, style: .none, poses: [:])
        func record(_ placements: [Placement]) -> DisplayRecord {
            DisplayRecord(name: "", vendor: 1, model: 2, serial: 3, builtin: false, lastSeen: Date(), placements: placements)
        }
        func sticker(_ id: UUID) -> StickerRecord {
            StickerRecord(id: id, created: Date(), pixelWidth: 10, pixelHeight: 10, pixelsPerPoint: 1, lastStyle: .puffy)
        }
        var library = Library(stickers: [sticker(kept), sticker(deleted)],
                              displays: ["A": record([a, b]), "B": record([c])])
        #expect(library.placement(b.id) == b)
        #expect(library.displayKey(containing: c.id) == "B")
        #expect(library.placementCount(of: deleted) == 2)
        #expect(library.removePlacement(a.id) == a)
        #expect(library.displays["A"]?.placements == [b])
        library.removeSticker(deleted)
        #expect(library.stickers.map(\.id) == [kept])
        #expect(library.displays["A"]?.placements.isEmpty == true)
        #expect(library.displays["B"]?.placements.isEmpty == true)
        library.moveDisplayRecord(from: "B", to: "C")
        #expect(library.displays["B"] == nil)
        #expect(library.displays["C"] != nil)
    }

    @Test func pureLogicFilesStayFreeOfAppKit() throws {
        // Spec section 4: the pure logic has no AppKit dependency, so it is
        // tested without windows. Files that later tasks add are covered as
        // soon as they exist.
        let pure: Set<String> = ["Library.swift", "LayoutResolver.swift", "DisplayRegistry.swift",
                                 "LibraryStore.swift", "LibraryController.swift", "StyleParameters.swift",
                                 "StyleRenderer.swift", "MasterImage.swift", "StickerGeometry.swift",
                                 "StyleRecipes.swift", "PuffyKernel.swift", "SurfaceContents.swift"]
        let files = SourceFiles.swiftFiles().filter { pure.contains($0.lastPathComponent) }
        #expect(!files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("import AppKit"), "\(url.lastPathComponent) imports AppKit")
            #expect(!text.contains("import SwiftUI"), "\(url.lastPathComponent) imports SwiftUI")
        }
    }
}
