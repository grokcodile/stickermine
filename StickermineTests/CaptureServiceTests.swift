import Foundation
import Testing
@testable import Stickermine

/// Never runs screencapture: every test substitutes a shell command.
@MainActor
struct CaptureServiceTests {
    static func shell(_ script: String) -> CaptureService.Command {
        CaptureService.Command(executable: URL(fileURLWithPath: "/bin/sh"),
                               arguments: { ["-c", script, "sh", $0.path] })
    }

    static func run(_ service: CaptureService) async -> CaptureOutcome {
        await withCheckedContinuation { continuation in
            service.capture { continuation.resume(returning: $0) }
        }
    }

    static func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    @Test func theRealCommandIsScreencaptureWithTheSpecsFlags() {
        let command = CaptureService.Command.screencapture
        let url = URL(fileURLWithPath: "/tmp/stickermine-X.png")
        #expect(command.executable.path == "/usr/sbin/screencapture")
        #expect(command.arguments(url) == ["-i", "-J", "selection", "-o", "-x", "-t", "png", "/tmp/stickermine-X.png"])
        for forbidden in ["-c", "-u", "-U", "-p", "-r", "-s"] {
            #expect(!command.arguments(url).contains(forbidden))
        }
    }

    @Test func aWrittenFileIsASuccess() async throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = CaptureService(command: Self.shell(#"printf png > "$1""#), temporaryDirectory: folder,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { false })
        let outcome = await Self.run(service)
        guard case .success(let url) = outcome else {
            Issue.record("expected a success, got \(outcome)")
            return
        }
        #expect(url.deletingLastPathComponent().standardizedFileURL == folder.standardizedFileURL)
        #expect(url.lastPathComponent.hasPrefix("stickermine-"))
        #expect(url.pathExtension == "png")
        #expect(try Data(contentsOf: url) == Data("png".utf8))
        #expect(!service.isRunning)
    }

    @Test func exitStatusOneWithoutAFileIsBusy() async {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = CaptureService(command: Self.shell("exit 1"), temporaryDirectory: folder,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { false })
        #expect(await Self.run(service) == .busyOrBlocked)
    }

    @Test func aCancelWritesNothingAndExitsZero() async {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = CaptureService(command: Self.shell("exit 0"), temporaryDirectory: folder,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { false })
        #expect(await Self.run(service) == .cancelled)
    }

    @Test func aChangedPasteboardWithoutAFileMeansControlWasHeld() async {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var count = 0
        let service = CaptureService(command: Self.shell("exit 0"), temporaryDirectory: folder,
                                     pasteboardChangeCount: { count += 1; return count }, modifiersHeld: { false })
        #expect(await Self.run(service) == .controlHeldToClipboard)
    }

    @Test func screencaptureWaitsForTheModifiersToBeReleased() async {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        var polls = 0
        var pollsWhenItRan = -1
        let service = CaptureService(command: Self.shell(#"printf png > "$1""#), temporaryDirectory: folder,
                                     pasteboardChangeCount: { pollsWhenItRan = pollsWhenItRan < 0 ? polls : pollsWhenItRan; return 7 },
                                     modifiersHeld: { polls += 1; return polls < 5 })
        guard case .success = await Self.run(service) else {
            Issue.record("expected a success")
            return
        }
        // The pasteboard is read just before screencapture starts: after the
        // fifth poll found the modifiers released.
        #expect(pollsWhenItRan == 5)
    }

    @Test func heldModifiersDelayTheCaptureAtMostTheWait() async {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = CaptureService(command: Self.shell(#"printf png > "$1""#), temporaryDirectory: folder,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { true }, modifierWait: 0.1)
        let start = Date()
        guard case .success = await Self.run(service) else {
            Issue.record("expected a success")
            return
        }
        #expect(Date().timeIntervalSince(start) >= 0.1)
    }

    @Test func oneCaptureAtATimeAndCancellingCallsNoCompletion() async {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let service = CaptureService(command: Self.shell(#"printf png > "$1"; exec sleep 5"#),
                                     temporaryDirectory: folder, pasteboardChangeCount: { 7 },
                                     modifiersHeld: { false })
        var outcomes: [CaptureOutcome] = []
        service.capture { outcomes.append($0) }
        service.capture { outcomes.append($0) }   // ignored: one is running
        #expect(service.isRunning)
        await Self.pause(0.4)
        let written = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        #expect(written.count == 1)
        service.cancelRunning()
        #expect(!service.isRunning)
        await Self.pause(0.4)
        #expect(outcomes.isEmpty)
        // The temporary file went with the cancel.
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).isEmpty)
    }

    @Test func leftoverCapturesAreDeletedAndNothingElse() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        for name in ["stickermine-A.png", "stickermine-B.png", "other.png", "stickermine-notes.txt"] {
            try Data("x".utf8).write(to: folder.appendingPathComponent(name))
        }
        #expect(CaptureService.deleteLeftovers(in: folder) == 2)
        let left = try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
        #expect(left == ["other.png", "stickermine-notes.txt"])
    }
}
