import Foundation

/// How one run of `screencapture -i` ended (spec section 5.7).
enum CaptureOutcome: Equatable {
    /// The PNG at this URL exists and isn't empty.
    case success(URL)
    /// Control was held at mouse-up: the image went to the clipboard, no file.
    case controlHeldToClipboard
    /// screencapture exited 1 without a file: another interactive capture is
    /// up, or an MDM restriction forbids screenshots.
    case busyOrBlocked
    /// Esc, a click without a drag, a selection under 10 pt, or anything else.
    case cancelled
}

/// Decides a capture's outcome. Pure: screencapture exits 0 for success and
/// for every cancel alike, so the file decides first and the exit status last.
enum CaptureClassifier {
    /// First match wins: a non-empty file; else a changed pasteboard; else exit
    /// status 1; else a cancel.
    static func classify(file url: URL, fileExists: Bool, fileSize: Int, exitStatus: Int32,
                         pasteboardChanged: Bool) -> CaptureOutcome {
        if fileExists, fileSize > 0 { return .success(url) }
        if pasteboardChanged { return .controlHeldToClipboard }
        if exitStatus == 1 { return .busyOrBlocked }
        return .cancelled
    }
}
