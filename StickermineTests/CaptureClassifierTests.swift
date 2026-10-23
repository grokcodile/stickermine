import Foundation
import Testing
@testable import Stickermine

struct CaptureClassifierTests {
    let url = URL(fileURLWithPath: "/tmp/stickermine-test.png")

    func classify(exists: Bool, size: Int, status: Int32, pasteboard: Bool) -> CaptureOutcome {
        CaptureClassifier.classify(file: url, fileExists: exists, fileSize: size, exitStatus: status,
                                   pasteboardChanged: pasteboard)
    }

    @Test func aNonEmptyFileIsASuccessWhateverElseHappened() {
        #expect(classify(exists: true, size: 10, status: 0, pasteboard: false) == .success(url))
        #expect(classify(exists: true, size: 10, status: 1, pasteboard: true) == .success(url))
    }

    @Test func noFileAndAChangedPasteboardMeansControlWasHeld() {
        #expect(classify(exists: false, size: 0, status: 0, pasteboard: true) == .controlHeldToClipboard)
        // The pasteboard is checked before the exit status.
        #expect(classify(exists: false, size: 0, status: 1, pasteboard: true) == .controlHeldToClipboard)
    }

    @Test func noFileAndExitStatusOneMeansBusyOrBlocked() {
        #expect(classify(exists: false, size: 0, status: 1, pasteboard: false) == .busyOrBlocked)
        // An empty file is no file.
        #expect(classify(exists: true, size: 0, status: 1, pasteboard: false) == .busyOrBlocked)
    }

    @Test func everythingElseIsACancel() {
        #expect(classify(exists: false, size: 0, status: 0, pasteboard: false) == .cancelled)
        #expect(classify(exists: true, size: 0, status: 0, pasteboard: false) == .cancelled)
        #expect(classify(exists: false, size: 0, status: 15, pasteboard: false) == .cancelled)
    }
}
