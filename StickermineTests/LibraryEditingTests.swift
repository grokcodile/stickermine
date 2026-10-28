import Foundation
import Testing
@testable import Stickermine

struct LibraryEditingTests {
    private let sticker = UUID()
    private let left = "LEFT-DISPLAY"
    private let right = "RIGHT-DISPLAY"

    private func placement(_ x: Double = 0.5) -> Placement {
        Placement(sticker: sticker, style: .outline, poses: ["1920x1080": Pose(x: x, y: 0.5, scale: 1)])
    }

    private func record(_ placements: [Placement]) -> DisplayRecord {
        DisplayRecord(name: "Display", vendor: 1, model: 2, serial: 3, builtin: false,
                      lastSeen: Date(timeIntervalSince1970: 0), placements: placements)
    }

    private func library(left placements: [Placement], right others: [Placement] = []) -> Library {
        Library(stickers: [Fixtures.sticker(sticker)], displays: [left: record(placements), right: record(others)])
    }

    @Test func bringingToFrontMovesThePlacementToTheEndOfItsDisplaysList() {
        let a = placement(0.1), b = placement(0.2), c = placement(0.3)
        var model = library(left: [a, b, c])
        let moved = model.bringToFront(a.id)
        #expect(moved)
        #expect(model.displays[left]?.placements.map(\.id) == [b.id, c.id, a.id])
        // Already in front, or unknown: nothing changes.
        let before = model
        let again = model.bringToFront(a.id)
        let unknown = model.bringToFront(UUID())
        #expect(!again && !unknown)
        #expect(model == before)
    }

    @Test func updatingAPlacementChangesOnlyThatPlacement() {
        let a = placement(0.1), b = placement(0.2)
        var model = library(left: [a], right: [b])
        let updated = model.updatePlacement(b.id) { $0.flipped = true }
        #expect(updated)
        #expect(model.placement(b.id)?.flipped == true)
        #expect(model.placement(a.id) == a)
        #expect(model.displays[right]?.placements.count == 1)
        let unknown = model.updatePlacement(UUID()) { $0.onTop = true }
        #expect(!unknown)
    }

    @Test func movingAPlacementPutsItOnTopOfTheOtherDisplay() {
        let a = placement(0.1), b = placement(0.2)
        var model = library(left: [a], right: [b])
        let moved = model.movePlacement(a.id, toDisplay: right)
        #expect(moved)
        #expect(model.displays[left]?.placements.isEmpty == true)
        #expect(model.displays[right]?.placements.map(\.id) == [b.id, a.id])
        // An unknown display or placement changes nothing.
        let before = model
        let nowhere = model.movePlacement(a.id, toDisplay: "NOWHERE")
        let unknown = model.movePlacement(UUID(), toDisplay: left)
        #expect(!nowhere && !unknown)
        #expect(model == before)
    }

    @Test func restylingSetsTheStickersLastStyle() {
        let a = placement()
        var model = library(left: [a])
        #expect(model.sticker(sticker)?.lastStyle == .outline)
        let restyled = model.restyle(a.id, to: .puffy)
        #expect(restyled)
        #expect(model.placement(a.id)?.style == .puffy)
        #expect(model.sticker(sticker)?.lastStyle == .puffy)
        let same = model.restyle(a.id, to: .puffy)
        let unknown = model.restyle(UUID(), to: .none)
        #expect(!same && !unknown)
    }
}
