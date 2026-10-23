import AppKit
import CoreGraphics
import SwiftUI

/// The Screen Recording check, behind a protocol so tests never touch TCC.
protocol ScreenRecordingAccess {
    /// Whether access is granted; never prompts.
    func preflight() -> Bool
    /// Prompts only while the state is undetermined (a denied app isn't
    /// re-prompted); returns the current state.
    @discardableResult func request() -> Bool
}

struct LiveScreenRecordingAccess: ScreenRecordingAccess {
    func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult func request() -> Bool { CGRequestScreenCaptureAccess() }
}

/// What the permission panel offers (spec section 14). Pure.
struct PermissionPanelState: Equatable {
    enum Action: Equatable {
        /// First time: `CGRequestScreenCaptureAccess()` (preflight can't tell
        /// "denied" from "never asked").
        case requestAccess
        /// Privacy & Security › Screen & System Audio Recording.
        case openSettings
        /// Quit and reopen, in case the in-process preflight result is stale.
        case relaunch
    }

    /// `didRequestScreenCapture` (spec section 12).
    var didRequest: Bool
    /// The user left the panel and came back while access was still off.
    var cameBackWithoutAccess = false

    var actions: [Action] {
        guard didRequest else { return [.requestAccess] }
        return cameBackWithoutAccess ? [.openSettings, .relaunch] : [.openSettings]
    }

    /// The state the panel shows when a capture brings it up. A capture
    /// triggered again while the panel is up (after the request) is the user
    /// coming back without access too (spec section 14), and once Relaunch was
    /// offered it stays: neither resets to Open System Settings alone.
    static func whenShown(didRequest: Bool, panelIsUp: Bool, previous: PermissionPanelState) -> PermissionPanelState {
        PermissionPanelState(didRequest: didRequest,
                             cameBackWithoutAccess: didRequest && (panelIsUp || previous.cameBackWithoutAccess))
    }
}

/// Shown instead of a capture when Screen Recording is off (spec section 14):
/// a standalone floating panel centred on the cursor's display (there is
/// usually no Home window to hang a sheet on). Never shown at launch.
@MainActor
final class PermissionPanel: NSObject, NSWindowDelegate {
    static let didRequestKey = "didRequestScreenCapture"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    final class Model: ObservableObject {
        @Published var state: PermissionPanelState

        init(state: PermissionPanelState) {
            self.state = state
        }
    }

    private let access: ScreenRecordingAccess
    private let defaults: UserDefaults
    private let screens: ScreenProvider
    private let openURL: (URL) -> Void
    let model: Model
    private var panel: NSPanel?
    private var hasResignedKey = false

    /// Access turned out to be on when the user came back; the panel closed.
    var onGranted: (() -> Void)?

    init(access: ScreenRecordingAccess = LiveScreenRecordingAccess(), defaults: UserDefaults = .standard,
         screens: ScreenProvider, openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.access = access
        self.defaults = defaults
        self.screens = screens
        self.openURL = openURL
        model = Model(state: PermissionPanelState(didRequest: defaults.bool(forKey: Self.didRequestKey)))
        super.init()
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// The panel policy (spec section 4): titled (so it can be key and has a
    /// close button), never hidden on deactivation (the user goes to System
    /// Settings and back), floating; the level last.
    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.level = .floating  // last
        return panel
    }

    /// Shows (or brings forward) the panel, centred on the display under the cursor.
    func show() {
        model.state = PermissionPanelState.whenShown(didRequest: defaults.bool(forKey: Self.didRequestKey),
                                                     panelIsUp: panel != nil, previous: model.state)
        hasResignedKey = false
        let panel = self.panel ?? makeContent()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        if let display = StickerManager.display(containing: mouse, in: screens.currentDisplays()) {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: (display.visibleFrame.midX - size.width / 2).rounded(),
                                         y: (display.visibleFrame.midY - size.height / 2).rounded()))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    func perform(_ action: PermissionPanelState.Action) {
        switch action {
        case .requestAccess:
            defaults.set(true, forKey: Self.didRequestKey)
            model.state.didRequest = true
            access.request()
        case .openSettings:
            openURL(Self.settingsURL)
        case .relaunch:
            Self.relaunch()
        }
    }

    /// The user came back: with access on, close; otherwise offer Relaunch too.
    func recheck() {
        if access.preflight() {
            close()
            onGranted?()
        } else if model.state.didRequest {
            model.state.cameBackWithoutAccess = true
        }
    }

    /// Quits, and a detached shell opens the app again once this process is gone.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                            Bundle.main.bundlePath]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hasResignedKey = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard hasResignedKey else { return }
        recheck()
    }

    func windowWillClose(_ notification: Notification) {
        panel?.delegate = nil
        panel = nil
    }

    private func makeContent() -> NSPanel {
        let panel = Self.makePanel()
        let host = NSHostingView(rootView: PermissionView(model: model,
                                                          perform: { [weak self] in self?.perform($0) },
                                                          dismiss: { [weak self] in self?.close() }))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.delegate = self
        return panel
    }
}

private struct PermissionView: View {
    @ObservedObject var model: PermissionPanel.Model
    let perform: (PermissionPanelState.Action) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Allow Screen Recording")
                    .font(.title3.weight(.semibold))
            }
            Text("Stickermine uses the macOS screenshot crosshair, and macOS asks for Screen Recording permission before an app can start it. Everything you capture stays on this Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Text("macOS will also check in from time to time and ask you to confirm that Stickermine can see your screen.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.state.didRequest {
                Text("Turn on Stickermine in System Settings › Privacy & Security › Screen & System Audio Recording, then make a sticker again.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Not Now", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                ForEach(model.state.actions, id: \.self) { action in
                    switch action {
                    case .requestAccess:
                        Button("Continue") { perform(.requestAccess) }
                            .keyboardShortcut(.defaultAction)
                    case .openSettings:
                        Button("Open System Settings") { perform(.openSettings) }
                            .keyboardShortcut(.defaultAction)
                    case .relaunch:
                        Button("Relaunch Stickermine") { perform(.relaunch) }
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(22)
        .padding(.top, 8)
        .frame(width: 420)
    }
}
