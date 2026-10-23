import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct DisplayRegistryTests {
    private let frame = CGRect(x: 40_000, y: 0, width: 1920, height: 1080)

    private func display(_ uuid: String, id: UInt32, vendor: UInt32 = 7789, model: UInt32 = 23305,
                         serial: UInt32 = 848_464, builtin: Bool = false, mirrors: UInt32? = nil) -> DisplayInfo {
        Fixtures.display(uuid: uuid, id: id, frame: frame, vendor: vendor, model: model, serial: serial,
                         builtin: builtin, mirrors: mirrors)
    }

    private func record(vendor: UInt32 = 7789, model: UInt32 = 23305, serial: UInt32 = 848_464,
                        builtin: Bool = false) -> DisplayRecord {
        DisplayRecord(name: "LG UltraFine", vendor: vendor, model: model, serial: serial, builtin: builtin,
                      lastSeen: Date(timeIntervalSince1970: 0), placements: [])
    }

    @Test func theGhostDisplayIsIgnored() {
        let ghost = display("GHOST", id: 7, vendor: 0x756E6B6E, model: 0x76697274)
        #expect(ghost.isGhost)
        let real = display("REAL", id: 3)
        #expect(!real.isGhost)
        #expect(DisplayRegistry.usable([ghost, real]) == [real])
        // Only one of the two codes is not the ghost.
        #expect(!display("X", id: 8, vendor: 0x756E6B6E, model: 1).isGhost)
    }

    @Test func mirrorSecondariesAreIgnoredButThePrimaryStays() {
        let primary = Fixtures.display(uuid: "PRIMARY", id: 1, frame: frame, inMirrorSet: true)
        let secondary = Fixtures.display(uuid: "SECONDARY", id: 3, frame: frame, mirrors: 1, inMirrorSet: true)
        #expect(DisplayRegistry.usable([primary, secondary]) == [primary])
    }

    @Test func aNullDisplayIDOrMissingUUIDIsIgnored() {
        #expect(DisplayRegistry.usable([display("ZERO", id: 0), display("", id: 5)]).isEmpty)
    }

    @Test func aDuplicateUUIDKeepsTheFirstDisplay() {
        let first = display("SAME", id: 3)
        let second = display("SAME", id: 4)
        #expect(DisplayRegistry.usable([first, second]) == [first])
    }

    @Test func noUsableDisplayGivesAnEmptyList() {
        #expect(DisplayRegistry.usable([display("GHOST", id: 7, vendor: 0x756E6B6E, model: 0x76697274)]).isEmpty)
    }

    @Test func uuidStringRefusesTheNullAndUnknownIDs() {
        // CGDisplayCreateUUIDFromDisplayID(0) would answer with the main display's UUID.
        #expect(DisplayRegistry.uuidString(for: 0) == nil)
        #expect(DisplayRegistry.uuidString(for: UInt32.max) == nil)
        #expect(DisplayRegistry.uuidString(for: 0x7FFF_0001) == nil)
    }

    @Test func uuidStringOfTheMainDisplayIsUppercase() throws {
        let uuid = try #require(DisplayRegistry.uuidString(for: CGMainDisplayID()))
        #expect(uuid == uuid.uppercased())
        #expect(UUID(uuidString: uuid) != nil)
    }

    @Test func fingerprintAdoptsTheOneMatchingDisconnectedRecord() {
        let newcomer = display("NEW-UUID", id: 3)
        let records = ["OLD-UUID": record(), "OTHER": record(serial: 1234)]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == "OLD-UUID")
    }

    @Test func fingerprintRefusesSerialZero() {
        let newcomer = display("NEW-UUID", id: 3, serial: 0)
        let records = ["OLD-UUID": record(serial: 0)]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == nil)
    }

    @Test func fingerprintRefusesTheSharedSerial() {
        let newcomer = display("NEW-UUID", id: 3, serial: 0x01010101)
        let records = ["OLD-UUID": record(serial: 0x01010101)]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == nil)
    }

    @Test func fingerprintRefusesWhenAConnectedDisplaySharesIt() {
        let newcomer = display("NEW-UUID", id: 3)
        let twin = display("TWIN-UUID", id: 4)
        let records = ["OLD-UUID": record()]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer, twin]) == nil)
    }

    @Test func fingerprintRefusesTwoMatchingRecords() {
        let newcomer = display("NEW-UUID", id: 3)
        let records = ["OLD-1": record(), "OLD-2": record()]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == nil)
    }

    @Test func fingerprintNeedsEveryFieldAndADisconnectedUnknownDisplay() {
        let newcomer = display("NEW-UUID", id: 3)
        // Built-in flag differs.
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["OLD": record(builtin: true)],
                                                    connected: [newcomer]) == nil)
        // Model differs.
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["OLD": record(model: 1)],
                                                    connected: [newcomer]) == nil)
        // The display already has its own record.
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["NEW-UUID": record(), "OLD": record()],
                                                    connected: [newcomer]) == nil)
        // The only match is a record whose display is connected (under another fingerprint field set).
        let connectedOwner = display("OLD", id: 9, serial: 5)
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["OLD": record()],
                                                    connected: [newcomer, connectedOwner]) == nil)
    }

    @Test func sizeComesFromTheFrame() {
        #expect(display("A", id: 3).size == DisplaySize(width: 1920, height: 1080))
    }
}
