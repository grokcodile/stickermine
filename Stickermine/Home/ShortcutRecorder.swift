import AppKit
import Carbon.HIToolbox
import SwiftUI

/// What one key press does while the recorder listens (spec section 13),
/// ported from Pullcord's RecorderButton. Pure.
enum ShortcutRecording {
    enum Outcome: Equatable {
        /// Bare Esc: stop listening, keep the shortcut.
        case cancel
        /// Bare Delete or Forward Delete: no shortcut.
        case clear
        /// A chord without ⌘ or ⌃ that isn't an F-key: refused, keep listening.
        case reject
        case record(Shortcut)
    }

    /// The Carbon mask for the four modifiers a shortcut can carry.
    static func carbonModifiers(_ flags: NSEvent.ModifierFlags) -> UInt32 {
        var mask: UInt32 = 0
        if flags.contains(.command) { mask |= UInt32(cmdKey) }
        if flags.contains(.shift) { mask |= UInt32(shiftKey) }
        if flags.contains(.option) { mask |= UInt32(optionKey) }
        if flags.contains(.control) { mask |= UInt32(controlKey) }
        return mask
    }

    /// "Bare" allows Shift, as in Pullcord: ⇧Esc still cancels.
    static func outcome(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Outcome {
        let modifiers = carbonModifiers(flags)
        let bare = modifiers & ~UInt32(shiftKey) == 0
        let code = Int(keyCode)
        if bare && code == kVK_Escape { return .cancel }
        if bare && (code == kVK_Delete || code == kVK_ForwardDelete) { return .clear }
        let shortcut = Shortcut(keyCode: UInt32(keyCode), modifiers: modifiers)
        return shortcut.isAcceptable ? .record(shortcut) : .reject
    }
}

/// The capture-shortcut field: click to record. While it listens, the global
/// hotkey is suspended (`onRecordingChange(true)`) so the chord being typed
/// can't start a capture; bare Esc cancels, bare Delete clears, and a chord
/// without ⌘ or ⌃ (F-keys excepted) beeps and keeps listening. One recorder
/// listens at a time; Home cancels it when it closes or resigns key.
@MainActor
final class ShortcutRecorderButton: NSButton {
    /// The recorder that is listening, if any.
    private(set) static weak var active: ShortcutRecorderButton?

    static let listeningTitle = "Type a shortcut…"
    static let emptyTitle = "Record Shortcut"

    var shortcut: Shortcut? {
        didSet { updateTitle() }
    }
    /// A recorded chord, or nil after bare Delete. Runs before the hotkeys resume.
    var onChange: ((Shortcut?) -> Void)?
    /// True when listening starts, false when it stops (the hotkeys suspend and resume).
    var onRecordingChange: ((Bool) -> Void)?
    /// A refused chord (the button beeps).
    var onRejected: (() -> Void)?

    private(set) var isRecording = false
    private var monitor: Any?

    init(shortcut: Shortcut?) {
        self.shortcut = shortcut
        super.init(frame: NSRect(x: 0, y: 0, width: 160, height: 28))
        bezelStyle = .rounded
        setButtonType(.momentaryPushIn)
        target = self
        action = #selector(clicked(_:))
        updateTitle()
    }

    required init?(coder: NSCoder) {
        fatalError("ShortcutRecorderButton is only created in code")
    }

    @objc private func clicked(_ sender: Any?) {
        if isRecording { cancelRecording() } else { beginRecording() }
    }

    func beginRecording() {
        Self.active?.cancelRecording()
        guard !isRecording else { return }
        isRecording = true
        Self.active = self
        updateTitle()
        onRecordingChange?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.handle(event) else { return event }
            return nil
        }
    }

    /// One key press while listening; true when it was used (and swallowed).
    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard isRecording, event.type == .keyDown else { return false }
        switch ShortcutRecording.outcome(keyCode: event.keyCode, flags: event.modifierFlags) {
        case .cancel:
            cancelRecording()
        case .clear:
            finish(with: nil)
        case .reject:
            NSSound.beep()
            onRejected?()
        case .record(let recorded):
            finish(with: recorded)
        }
        return true
    }

    /// Stops listening and keeps the shortcut. Safe to call when not listening.
    func cancelRecording() {
        stopListening()
    }

    private func finish(with recorded: Shortcut?) {
        shortcut = recorded
        // The new shortcut is stored and registered (suspended) before the
        // hotkeys resume, so the old chord never comes back in between.
        onChange?(recorded)
        stopListening()
    }

    private func stopListening() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        if Self.active === self { Self.active = nil }
        updateTitle()
        onRecordingChange?(false)
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { cancelRecording() }
        super.viewWillMove(toWindow: newWindow)
    }

    private func updateTitle() {
        title = isRecording ? Self.listeningTitle : (shortcut?.label ?? Self.emptyTitle)
    }
}

/// The recorder in SwiftUI (Home's settings section).
struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut?
    let onChange: (Shortcut?) -> Void
    let onRecordingChange: (Bool) -> Void
    let onRejected: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderButton {
        let button = ShortcutRecorderButton(shortcut: shortcut)
        button.setContentHuggingPriority(.required, for: .horizontal)
        return button
    }

    func updateNSView(_ button: ShortcutRecorderButton, context: Context) {
        if !button.isRecording, button.shortcut != shortcut { button.shortcut = shortcut }
        button.onChange = onChange
        button.onRecordingChange = onRecordingChange
        button.onRejected = onRejected
    }
}
