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

    @Test func stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag() throws {
        let mouseFlag = #"ignoresMouseEvents\s*="#
        // Every file in Stickers/ creates, fills or drives sticker panels. Only a file
        // implementing the hidden click-through fallback (spec section 9) may write
        // the flag, and it must be named here.
        let fallbackFiles: Set<String> = []
        let stickerFiles = SourceFiles.swiftFiles().filter {
            $0.deletingLastPathComponent().lastPathComponent == "Stickers"
                && !fallbackFiles.contains($0.lastPathComponent)
        }
        #expect(stickerFiles.count >= 3)
        for url in stickerFiles {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: mouseFlag, options: .regularExpression) == nil,
                    "\(url.lastPathComponent) writes ignoresMouseEvents")
        }
        let files = SourceFiles.swiftFiles()
        #expect(!files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: #"isFloatingPanel\s*="#, options: .regularExpression) == nil,
                    "\(url.lastPathComponent) assigns isFloatingPanel, which rewrites the level")
        }
    }
}
