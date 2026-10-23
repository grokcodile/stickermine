import AppKit
import Testing
@testable import Stickermine

@MainActor
struct PanelPolicyTests {
    @Test func stickerLevelIsOneAboveTheDesktopIcons() {
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        #expect(PanelPolicy.stickerLevel.rawValue == icons + 1)
        #expect(PanelPolicy.stickerLevel.rawValue > Int(CGWindowLevelForKey(.desktopWindow)))
        #expect(PanelPolicy.stickerLevel < .normal)
    }

    @Test func floatOnTopUsesTheFloatingLevel() {
        #expect(PanelPolicy.level(onTop: true) == .floating)
        #expect(PanelPolicy.level(onTop: false) == PanelPolicy.stickerLevel)
    }

    @Test func stickerBehaviorIsExactlyTheSpecSet() {
        #expect(PanelPolicy.stickerBehavior == [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone])
        #expect(!PanelPolicy.stickerBehavior.contains(.fullScreenAuxiliary))
        #expect(!PanelPolicy.stickerBehavior.contains(.canJoinAllApplications))
        #expect(!PanelPolicy.stickerBehavior.contains(.moveToActiveSpace))
        #expect(!PanelPolicy.stickerBehavior.contains(.transient))
    }

    @Test func stickerPanelHasEveryPolicyFlag() {
        let rect = NSRect(x: 100, y: 100, width: 200, height: 150)
        let panel = PanelPolicy.makeStickerPanel(contentRect: rect)
        defer { panel.close() }
        #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
        #expect(panel.backingType == .buffered)
        #expect(panel.level == PanelPolicy.stickerLevel)
        #expect(panel.collectionBehavior == PanelPolicy.stickerBehavior)
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.hasShadow)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.canHide)
        #expect(panel.isExcludedFromWindowsMenu)
        #expect(panel.animationBehavior == .none)
        #expect(!panel.isRestorable)
        #expect(panel.sharingType == .none)
        #expect(!panel.isFloatingPanel)
        #expect(panel.frame == rect)
        #expect(!panel.isVisible)
    }

    @Test func stickerPanelBecomesKeyOnlyWhileEditing() {
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50))
        defer { panel.close() }
        #expect(!panel.canBecomeKey)
        panel.isEditing = true
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        panel.isEditing = false
        #expect(!panel.canBecomeKey)
    }

    @Test func applyCommonOverridesPlainPanelDefaults() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless], backing: .buffered, defer: true)
        // The trap the policy exists for: a plain NSPanel hides whenever the app
        // isn't active, which in an accessory app is almost always.
        #expect(panel.hidesOnDeactivate)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.isExcludedFromWindowsMenu)
        #expect(!panel.isRestorable)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: true)
        #expect(panel.hidesOnDeactivate)
    }

    /// Matches any write to `ignoresMouseEvents`: an assignment (but not `==`),
    /// `.toggle()`, or key-value coding by name. Writing the flag at all switches a
    /// window to rectangle hit-testing for good (spec section 9).
    static let mouseFlagWrite = #"ignoresMouseEvents\s*=(?!=)|ignoresMouseEvents\.toggle|"ignoresMouseEvents""#

    /// The only app files allowed to write the flag, by path under `Stickermine/`:
    /// the hidden click-through fallback, the placement session's and the HUD's own
    /// transient panels, and `StickerPanel`'s counting override.
    static let mouseFlagWriters: Set<String> = [
        "Stickers/ClickThroughFallback.swift",
        "Picker/PlacementSession.swift",
        "UI/HUD.swift",
        "Stickers/StickerPanel.swift",
    ]

    @Test func theMouseFlagPatternCatchesEveryWayOfWritingIt() {
        let writes = ["panel.ignoresMouseEvents = true", "p.ignoresMouseEvents=false",
                      "panel.ignoresMouseEvents.toggle()", #"panel.setValue(true, forKey: "ignoresMouseEvents")"#]
        let reads = ["if panel.ignoresMouseEvents == false", "let x = panel.ignoresMouseEvents"]
        for line in writes {
            #expect(line.range(of: Self.mouseFlagWrite, options: .regularExpression) != nil, "\(line)")
        }
        for line in reads {
            #expect(line.range(of: Self.mouseFlagWrite, options: .regularExpression) == nil, "\(line)")
        }
    }

    @Test func stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag() throws {
        // Every app file is scanned, in every folder: sticker panels are handed to
        // code outside Stickers/ (StickerManager.panel(for:)). Only the files in
        // mouseFlagWriters may write the flag, each for its own panels.
        let files = SourceFiles.swiftFiles()
        let root = SourceFiles.appRoot.path + "/"
        let scanned = files.filter { !Self.mouseFlagWriters.contains($0.path.replacingOccurrences(of: root, with: "")) }
        #expect(scanned.contains { $0.path.hasSuffix("App/AppDelegate.swift") })
        #expect(scanned.contains { $0.path.hasSuffix("Stickers/StickerView.swift") })
        for url in scanned {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: Self.mouseFlagWrite, options: .regularExpression) == nil,
                    "\(url.lastPathComponent) writes ignoresMouseEvents")
        }
        #expect(!files.isEmpty)
        for url in files where !url.path.hasSuffix("Stickers/StickerPanel.swift") {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: #"isFloatingPanel\s*=(?!=)"#, options: .regularExpression) == nil,
                    "\(url.lastPathComponent) assigns isFloatingPanel, which rewrites the level")
        }
    }

    @Test func aStickerPanelCountsEveryWriteOfTheTwoFlags() {
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50))
        // A freshly made sticker panel has never had either flag written, so the
        // window server still hit-tests it by alpha and its level is untouched.
        #expect(panel.mouseFlagWrites == 0)
        #expect(panel.floatingFlagWrites == 0)
        panel.ignoresMouseEvents = false
        panel.isFloatingPanel = false
        #expect(panel.mouseFlagWrites == 1)
        #expect(panel.floatingFlagWrites == 1)
    }

    @Test func aPanelForVisibleSharingStartsReadOnly() {
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 40_000, y: 0, width: 10, height: 10),
                                                 hideFromSharing: false)
        defer { panel.close() }
        #expect(panel.sharingType == .readOnly)
        #expect(panel.level == PanelPolicy.stickerLevel)
    }
}
