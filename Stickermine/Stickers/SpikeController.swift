import AppKit
import os

/// The M1 sticker-window spike (spec section 18). It runs only when the app is
/// launched with `-spike`, puts four hard-coded stickers on the main display and
/// logs what the window server does with them. M2 deletes this file and the
/// `-spike` branch in AppDelegate; PanelPolicy, StickerPanel and StickerView stay.
///
/// Layout on the main display (NSScreen.screens[0]):
/// - middle row: Maple with CGImage contents (left), Maple with IOSurface
///   contents (right), both with a layer shadow;
/// - bottom row: a Display P3 swatch (left half P3 red, right half sRGB red),
///   CGImage contents (left), IOSurface contents (right), no shadow.
///
/// Controls: double-click a sticker to edit it; while editing, drag to move,
/// pinch or rotate on the trackpad, press F to toggle Float on top, Esc to stop
/// (focus returns to the app that was frontmost). Clicking elsewhere also stops.
/// Launch with `-spike -spikeRebuild` to recreate every panel 1.5 s after wake,
/// unlock or a display change (the fix to try if panels go stale).
///
/// Watch the log with:
///   log stream --style compact --predicate 'subsystem == "com.ethan.stickermine" AND category == "spike"'
@MainActor
final class SpikeController {
    static let launchArgument = "-spike"
    static let rebuildArgument = "-spikeRebuild"

    private final class Sticker {
        let name: String
        let image: CGImage
        let useSurface: Bool
        let pointSize: CGSize
        let shadow: LayerShadow?
        var panel: StickerPanel
        var view: StickerView
        var scale: CGFloat = 1
        var rotation: CGFloat = 0
        var onTop = false
        var activeGestures: Set<String> = []
        var gestureMaxScale: CGFloat = 1

        init(name: String, image: CGImage, useSurface: Bool, pointSize: CGSize,
             shadow: LayerShadow?, panel: StickerPanel, view: StickerView) {
            self.name = name
            self.image = image
            self.useSurface = useSurface
            self.pointSize = pointSize
            self.shadow = shadow
            self.panel = panel
            self.view = view
        }
    }

    private static let scaleLimits: ClosedRange<CGFloat> = 0.25...3
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "spike")
    private let rebuildOnSystemEvents: Bool
    private var stickers: [Sticker] = []
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var previousApp: NSRunningApplication?
    private var mouseUpMonitor: Any?

    init(arguments: [String]) {
        rebuildOnSystemEvents = arguments.contains(Self.rebuildArgument)
    }

    func start() {
        guard let screen = NSScreen.screens.first else {
            log.error("no screens; spike not started")
            return
        }
        guard let maple = BundledImages.cgImage(named: BundledImages.mapleName) else {
            log.error("Maple asset missing; spike not started")
            return
        }
        let frame = screen.frame
        func at(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
            NSPoint(x: frame.minX + frame.width * x, y: frame.minY + frame.height * y)
        }
        // Maple is stored @2x: 620 × 910 px is 310 × 455 pt, scaled down to fit
        // within 45% of the display's height.
        let mapleNatural = CGSize(width: CGFloat(maple.width) / 2, height: CGFloat(maple.height) / 2)
        let fit = min(1, frame.height * 0.45 / mapleNatural.height)
        let maplePoints = CGSize(width: mapleNatural.width * fit, height: mapleNatural.height * fit)
        let shadow = LayerShadow(radius: 8, opacity: 0.35, offset: 5)
        add("maple-cgimage", image: maple, useSurface: false, pointSize: maplePoints,
            shadow: shadow, center: at(0.62, 0.5))
        add("maple-iosurface", image: maple, useSurface: true, pointSize: maplePoints,
            shadow: shadow, center: at(0.84, 0.5))
        if let swatch = Self.makeP3Swatch() {
            let swatchPoints = CGSize(width: CGFloat(swatch.width) / 2, height: CGFloat(swatch.height) / 2)
            add("swatch-cgimage", image: swatch, useSurface: false, pointSize: swatchPoints,
                shadow: nil, center: at(0.62, 0.15))
            add("swatch-iosurface", image: swatch, useSurface: true, pointSize: swatchPoints,
                shadow: nil, center: at(0.84, 0.15))
        }
        installObservers()
        // Row 4 evidence: does the app itself see the mouse-up that ends a window
        // drag? If performDrag(with:) returns early, M5 needs a drag-end signal.
        mouseUpMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            if let self, let panel = event.window as? StickerPanel, panel.isEditing {
                self.log.notice("local leftMouseUp: frame=\(NSStringFromRect(panel.frame), privacy: .public)")
            }
            return event
        }
        logState("launch")
    }

    // MARK: Panels

    private func add(_ name: String, image: CGImage, useSurface: Bool, pointSize: CGSize,
                     shadow: LayerShadow?, center: NSPoint) {
        let (panel, view) = makePanel(name: name, image: image, useSurface: useSurface,
                                      pointSize: pointSize, shadow: shadow, center: center)
        let sticker = Sticker(name: name, image: image, useSurface: useSurface, pointSize: pointSize,
                              shadow: shadow, panel: panel, view: view)
        stickers.append(sticker)
        wire(sticker)
        panel.orderFrontRegardless()
    }

    private func makePanel(name: String, image: CGImage, useSurface: Bool, pointSize: CGSize,
                           shadow: LayerShadow?, center: NSPoint) -> (StickerPanel, StickerView) {
        let size = StickerView.frameSize(pointSize: pointSize, shadow: shadow)
        let rect = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        let panel = PanelPolicy.makeStickerPanel(contentRect: rect)
        let view = StickerView(frame: NSRect(origin: .zero, size: size))
        panel.contentView = view
        var contents: Any = image
        if useSurface {
            if let surface = SurfaceContents.make(from: image) {
                contents = surface
            } else {
                log.error("\(name, privacy: .public): IOSurface creation failed, showing the CGImage")
            }
        }
        view.showContents(contents, pointSize: pointSize, shadow: shadow)
        panel.setFrame(panel.backingAlignedRect(rect, options: .alignAllEdgesNearest), display: false)
        return (panel, view)
    }

    private func wire(_ sticker: Sticker) {
        sticker.view.onDoubleClick = { [weak self, weak sticker] in
            guard let self, let sticker else { return }
            self.beginEditing(sticker)
        }
        sticker.view.onKeyDown = { [weak self, weak sticker] event in
            guard let self, let sticker else { return false }
            return self.handleKey(event, sticker)
        }
        sticker.view.onMagnify = { [weak self, weak sticker] event in
            guard let self, let sticker else { return }
            self.log.notice("\(sticker.name, privacy: .public) magnify phase=\(event.phase.rawValue) amount=\(event.magnification) editing=\(sticker.panel.isEditing)")
            guard sticker.panel.isEditing else { return }
            self.gesture("magnify", phase: event.phase, sticker) {
                sticker.scale *= 1 + event.magnification
            }
        }
        sticker.view.onRotate = { [weak self, weak sticker] event in
            guard let self, let sticker else { return }
            self.log.notice("\(sticker.name, privacy: .public) rotate phase=\(event.phase.rawValue) degrees=\(event.rotation) editing=\(sticker.panel.isEditing)")
            guard sticker.panel.isEditing else { return }
            self.gesture("rotate", phase: event.phase, sticker) {
                sticker.rotation += CGFloat(event.rotation) * .pi / 180
            }
        }
        sticker.view.onDragEnded = { [weak self, weak sticker] in
            guard let self, let sticker else { return }
            // If buttons are still down here, performDrag(with:) returned before the
            // drag finished, and M5 must detect the drag end some other way.
            self.log.notice("\(sticker.name, privacy: .public) performDrag returned: buttonsDown=\(NSEvent.pressedMouseButtons) frame=\(NSStringFromRect(sticker.panel.frame), privacy: .public) screen=\(sticker.panel.screen?.localizedName ?? "none", privacy: .public)")
        }
        sticker.panel.onResignKey = { [weak self, weak sticker] in
            guard let self, let sticker else { return }
            self.endEditing(sticker, returnFocus: false, reason: "resignKey")
        }
    }

    // MARK: Editing

    private func beginEditing(_ sticker: Sticker) {
        for other in stickers where other !== sticker && other.panel.isEditing {
            endEditing(other, returnFocus: false, reason: "another sticker")
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        if let front = NSWorkspace.shared.frontmostApplication, front.processIdentifier != ownPID {
            previousApp = front
        }
        sticker.panel.isEditing = true
        sticker.view.setEditingChrome(true)
        sticker.panel.orderFrontRegardless()
        NSApp.activate()
        sticker.panel.makeKey()
        sticker.panel.makeFirstResponder(sticker.view)
        log.notice("\(sticker.name, privacy: .public) begin editing: key=\(sticker.panel.isKeyWindow) appActive=\(NSApp.isActive) previous=\(self.previousApp?.localizedName ?? "none", privacy: .public)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self, weak sticker] in
            MainActor.assumeIsolated {
                guard let self, let sticker else { return }
                self.log.notice("\(sticker.name, privacy: .public) editing +0.5s: key=\(sticker.panel.isKeyWindow) appActive=\(NSApp.isActive)")
            }
        }
    }

    private func endEditing(_ sticker: Sticker, returnFocus: Bool, reason: String) {
        guard sticker.panel.isEditing else { return }
        if !sticker.activeGestures.isEmpty {
            sticker.activeGestures.removeAll()
            fitFrame(sticker)
        }
        sticker.panel.isEditing = false
        sticker.view.setEditingChrome(false)
        log.notice("\(sticker.name, privacy: .public) end editing (\(reason, privacy: .public))")
        guard returnFocus else { return }
        if let app = previousApp, !app.isTerminated {
            app.activate(options: [])
        } else {
            NSApp.deactivate()
        }
        previousApp = nil
    }

    private func handleKey(_ event: NSEvent, _ sticker: Sticker) -> Bool {
        guard sticker.panel.isEditing else { return false }
        if event.keyCode == 53 {  // Esc
            endEditing(sticker, returnFocus: true, reason: "escape")
            return true
        }
        if event.charactersIgnoringModifiers?.lowercased() == "f" {
            sticker.onTop.toggle()
            sticker.panel.level = PanelPolicy.level(onTop: sticker.onTop)
            log.notice("\(sticker.name, privacy: .public) float on top=\(sticker.onTop) level=\(sticker.panel.level.rawValue)")
            return true
        }
        return false
    }

    // MARK: Gestures

    /// Grows the window to a square once when the first gesture begins, applies
    /// the change to the content layer's transform (never resizing per event),
    /// and shrinks the window around the transformed sticker when the last
    /// gesture ends. M5 replaces this with a re-render at gesture end.
    private func gesture(_ kind: String, phase: NSEvent.Phase, _ sticker: Sticker, change: () -> Void) {
        if !sticker.activeGestures.contains(kind) && !phase.contains(.ended) && !phase.contains(.cancelled) {
            if sticker.activeGestures.isEmpty { growForGesture(sticker) }
            sticker.activeGestures.insert(kind)
        }
        change()
        let upper = min(Self.scaleLimits.upperBound, sticker.gestureMaxScale)
        sticker.scale = min(max(sticker.scale, Self.scaleLimits.lowerBound), upper)
        sticker.view.setContentTransform(scale: sticker.scale, rotation: sticker.rotation)
        if phase.contains(.ended) || phase.contains(.cancelled) {
            sticker.activeGestures.remove(kind)
            if sticker.activeGestures.isEmpty {
                fitFrame(sticker)
                log.notice("\(sticker.name, privacy: .public) gesture end: scale=\(sticker.scale) rotation=\(sticker.rotation) frame=\(NSStringFromRect(sticker.panel.frame), privacy: .public)")
            }
        }
    }

    private func growForGesture(_ sticker: Sticker) {
        // Room for the sticker to double in size and turn freely during this gesture.
        sticker.gestureMaxScale = min(Self.scaleLimits.upperBound, sticker.scale * 2)
        let diagonal = hypot(sticker.pointSize.width, sticker.pointSize.height)
        let side = diagonal * sticker.gestureMaxScale + 2 * (sticker.shadow?.margin ?? 0)
        setFrameKeepingCenter(sticker.panel, size: CGSize(width: side, height: side))
    }

    /// Sizes the window to the transformed sticker's bounding box plus the margin.
    private func fitFrame(_ sticker: Sticker) {
        let box = StickerView.boundingSize(of: sticker.pointSize, scale: sticker.scale, rotation: sticker.rotation)
        let margin = sticker.shadow?.margin ?? 0
        setFrameKeepingCenter(sticker.panel, size: CGSize(width: box.width + 2 * margin, height: box.height + 2 * margin))
    }

    private func setFrameKeepingCenter(_ panel: NSPanel, size: CGSize) {
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        let rect = NSRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                          width: size.width, height: size.height)
        panel.setFrame(panel.backingAlignedRect(rect, options: .alignAllEdgesNearest), display: true)
    }

    // MARK: Staleness checks

    private func installObservers() {
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        let events: [(center: NotificationCenter, name: Notification.Name, label: String, rebuilds: Bool)] = [
            (workspace, NSWorkspace.didWakeNotification, "didWake", true),
            (workspace, NSWorkspace.screensDidWakeNotification, "screensDidWake", true),
            (workspace, NSWorkspace.activeSpaceDidChangeNotification, "activeSpaceDidChange", false),
            (NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, "didChangeScreenParameters", true),
            (distributed, Notification.Name("com.apple.screenIsLocked"), "screenIsLocked", false),
            (distributed, Notification.Name("com.apple.screenIsUnlocked"), "screenIsUnlocked", true),
        ]
        for event in events {
            let label = event.label
            let rebuilds = event.rebuilds
            let token = event.center.addObserver(forName: event.name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.systemEvent(label, rebuilds: rebuilds)
                }
            }
            observers.append((event.center, token))
        }
    }

    private func systemEvent(_ label: String, rebuilds: Bool) {
        logState(label)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.logState(label + " +1.5s")
                if rebuilds && self.rebuildOnSystemEvents {
                    self.rebuildAll(reason: label)
                }
            }
        }
    }

    /// Closes every panel and creates a fresh one at the same place.
    private func rebuildAll(reason: String) {
        log.notice("rebuilding every panel after \(reason, privacy: .public)")
        for sticker in stickers {
            endEditing(sticker, returnFocus: false, reason: "rebuild")
            let old = sticker.panel
            let center = NSPoint(x: old.frame.midX, y: old.frame.midY)
            old.onResignKey = nil
            sticker.view.clearContents()
            old.orderOut(nil)
            old.close()
            let (panel, view) = makePanel(name: sticker.name, image: sticker.image, useSurface: sticker.useSurface,
                                          pointSize: sticker.pointSize, shadow: sticker.shadow, center: center)
            sticker.panel = panel
            sticker.view = view
            wire(sticker)
            view.setContentTransform(scale: sticker.scale, rotation: sticker.rotation)
            fitFrame(sticker)
            panel.level = PanelPolicy.level(onTop: sticker.onTop)
            panel.orderFrontRegardless()
        }
        logState("after rebuild")
    }

    private func logState(_ event: String) {
        let screens = NSScreen.screens
            .map { "\($0.localizedName) \(NSStringFromRect($0.frame))" }
            .joined(separator: "; ")
        log.notice("[\(event, privacy: .public)] screens: \(screens, privacy: .public)")
        for sticker in stickers {
            let panel = sticker.panel
            log.notice("[\(event, privacy: .public)] \(sticker.name, privacy: .public) visible=\(panel.isVisible) occlusionVisible=\(panel.occlusionState.contains(.visible)) windowServerOnscreen=\(Self.windowServerOnscreen(panel.windowNumber), privacy: .public) screen=\(panel.screen?.localizedName ?? "none", privacy: .public) frame=\(NSStringFromRect(panel.frame), privacy: .public) level=\(panel.level.rawValue) key=\(panel.isKeyWindow) editing=\(panel.isEditing)")
        }
    }

    /// The window server's own onscreen flag for one of our windows.
    private static func windowServerOnscreen(_ windowNumber: Int) -> String {
        guard windowNumber > 0,
              let info = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]],
              let entry = info.first
        else { return "absent" }
        return (entry[kCGWindowIsOnscreen as String] as? Bool) == true ? "yes" : "no"
    }

    // MARK: Test images

    /// 480 × 240 px (240 × 120 pt at 2×) in Display P3 with rounded transparent
    /// corners: the left half is P3's own red (1, 0, 0), the right half sRGB red.
    /// On a P3 display the left half looks visibly more saturated.
    private static func makeP3Swatch() -> CGImage? {
        let width = 480
        let height = 240
        guard let p3 = CGColorSpace(name: CGColorSpace.displayP3),
              let p3Red = CGColor(colorSpace: p3, components: [1, 0, 0, 1]),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: p3, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: width, height: height),
                               cornerWidth: 48, cornerHeight: 48, transform: nil))
        context.clip()
        context.setFillColor(p3Red)
        context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
        context.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: width / 2, y: 0, width: width / 2, height: height))
        return context.makeImage()
    }
}
