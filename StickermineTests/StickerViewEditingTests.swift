import AppKit
import Testing
@testable import Stickermine

/// The editing chrome (knob, outline, margin) and the mouse while editing. No window is ordered in.
@MainActor
struct StickerViewEditingTests {
    /// A 300 × 200 pt view showing a 100 × 50 pt bitmap without a shadow.
    private func makeView() -> StickerView {
        let view = StickerView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        view.showContents(TestImages.bands(width: 200, height: 100, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: CGSize(width: 100, height: 50), shadow: nil)
        return view
    }

    private func near(_ a: CGPoint, _ b: CGPoint) -> Bool {
        abs(a.x - b.x) < 1e-9 && abs(a.y - b.y) < 1e-9
    }

    @Test func theKnobSitsOnTheOutlinesBottomRightCorner() {
        let view = makeView()
        // The outline is the 100 × 50 box plus 2 pt, centred at (150, 100).
        #expect(near(view.knobCenter, CGPoint(x: 202, y: 73)))
        #expect(view.knobLayer.superlayer === view.outlineLayer)
        #expect(near(view.knobLayer.position, view.knobCenter))
    }

    @Test func theKnobAndOutlineFollowTheGestureTransform() throws {
        let view = makeView()
        view.setContentTransform(scale: 2, rotation: 0)
        #expect(near(view.knobCenter, CGPoint(x: 252, y: 48)))
        // A quarter turn counter-clockwise takes the corner (52, −27) to (27, 52).
        view.setContentTransform(scale: 1, rotation: .pi / 2)
        #expect(near(view.knobCenter, CGPoint(x: 177, y: 152)))
        // The outline turns with the content: its box is the turned 104 × 54 rect.
        let box = try #require(view.outlineLayer.path?.boundingBox)
        #expect(abs(box.width - 54) < 1e-9 && abs(box.height - 104) < 1e-9)
        #expect(abs(box.midX - 150) < 1e-9 && abs(box.midY - 100) < 1e-9)
    }

    @Test func onlyTheKnobsNeighbourhoodGrabsItAndOnlyWhileEditing() {
        let view = makeView()
        #expect(!view.isOnKnob(view.knobCenter))
        view.setEditingChrome(true)
        #expect(view.isOnKnob(view.knobCenter))
        #expect(view.isOnKnob(CGPoint(x: view.knobCenter.x - 8, y: view.knobCenter.y + 8)))
        #expect(!view.isOnKnob(CGPoint(x: view.knobCenter.x - 12, y: view.knobCenter.y + 12)))
        #expect(!view.isOnKnob(CGPoint(x: 150, y: 100)))
        view.setEditingChrome(false)
        #expect(!view.isOnKnob(view.knobCenter))
    }

    @Test func editingKeepsRoomForTheKnob() {
        let view = makeView()
        #expect(view.frameMargin == 0)
        #expect(view.windowMargin == 0)
        view.setEditingChrome(true)
        #expect(view.windowMargin == StickerView.editingMargin)
        // A shadow margin larger than the editing margin wins.
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: CGSize(width: 100, height: 50), shadow: nil, frameMargin: 18)
        #expect(view.windowMargin == 18)
        view.setEditingChrome(false)
        #expect(view.windowMargin == 18)
    }

    private func mouse(_ type: NSEvent.EventType, at point: NSPoint, in window: NSWindow, clicks: Int = 1,
                       shift: Bool = false) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(with: type, location: point, modifierFlags: shift ? [.shift] : [],
                                        timestamp: 0, windowNumber: window.windowNumber, context: nil,
                                        eventNumber: 0, clickCount: clicks, pressure: 1))
    }

    @Test func aDragOnTheKnobIsReportedInScreenCoordinates() throws {
        let view = makeView()
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 40_000, y: 100, width: 300, height: 200))
        defer { panel.close() }
        panel.contentView = view
        panel.isEditing = true
        view.setEditingChrome(true)
        var reports: [(StickerView.DragPhase, CGPoint, Bool)] = []
        var moves = 0
        view.onKnobDrag = { reports.append(($0, $1, $2)) }
        view.onMoveDrag = { _, _ in moves += 1 }
        let knob = view.knobCenter
        view.mouseDown(with: try mouse(.leftMouseDown, at: knob, in: panel))
        #expect(view.trackedDrag == .knob)
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: NSPoint(x: knob.x + 10, y: knob.y - 5), in: panel,
                                          shift: true))
        view.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: knob.x + 20, y: knob.y), in: panel))
        #expect(view.trackedDrag == nil)
        #expect(reports.map(\.0) == [.began, .moved, .ended])
        #expect(near(reports[0].1, CGPoint(x: 40_202, y: 173)))
        #expect(near(reports[1].1, CGPoint(x: 40_212, y: 168)))
        #expect(reports.map(\.2) == [false, true, false])
        #expect(moves == 0)
        // Moves without a mouse-down in this view aren't reported.
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: knob, in: panel))
        #expect(reports.count == 3 && moves == 0)
    }

    @Test func aDragAwayFromTheKnobMovesAndIsReportedInScreenCoordinates() throws {
        let view = makeView()
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 40_000, y: 100, width: 300, height: 200))
        defer { panel.close() }
        panel.contentView = view
        panel.isEditing = true
        view.setEditingChrome(true)
        var reports: [(StickerView.DragPhase, CGPoint)] = []
        view.onMoveDrag = { reports.append(($0, $1)) }
        view.onKnobDrag = { _, _, _ in Issue.record("not a knob drag") }
        // A transparent spot of the padded frame: the hit pad takes it.
        view.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 20, y: 180), in: panel))
        #expect(view.trackedDrag == .move)
        view.mouseDragged(with: try mouse(.leftMouseDragged, at: NSPoint(x: 60, y: 150), in: panel))
        view.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: 70, y: 150), in: panel))
        #expect(view.trackedDrag == nil)
        #expect(reports.map(\.0) == [.began, .moved, .ended])
        #expect(near(reports[0].1, CGPoint(x: 40_020, y: 280)))
        #expect(near(reports[1].1, CGPoint(x: 40_060, y: 250)))
        #expect(near(reports[2].1, CGPoint(x: 40_070, y: 250)))
        // Hiding the chrome (editing ended) forgets the drag: a late mouse-up isn't reported.
        view.mouseDown(with: try mouse(.leftMouseDown, at: NSPoint(x: 20, y: 180), in: panel))
        view.setEditingChrome(false)
        view.mouseUp(with: try mouse(.leftMouseUp, at: NSPoint(x: 30, y: 180), in: panel))
        #expect(reports.count == 4)
    }

    @Test func clicksOnAStickerThatIsntEditingAreReported() throws {
        let view = makeView()
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 40_000, y: 100, width: 300, height: 200))
        defer { panel.close() }
        panel.contentView = view
        var events: [String] = []
        view.onInactiveMouseDown = { events.append("down") }
        view.onDoubleClick = { events.append("double") }
        view.onKnobDrag = { _, _, _ in events.append("knob") }
        view.mouseDown(with: try mouse(.leftMouseDown, at: view.knobCenter, in: panel))
        view.mouseDown(with: try mouse(.leftMouseDown, at: view.knobCenter, in: panel, clicks: 2))
        #expect(events == ["down", "down", "double"])
    }
}
