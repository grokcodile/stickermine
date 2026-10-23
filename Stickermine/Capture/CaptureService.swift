import AppKit
import os

/// Runs the system's screenshot crosshair, `/usr/sbin/screencapture -i`, one
/// capture at a time (spec section 5).
///
/// 1. Waits (up to about 1 s) for the shortcut's modifiers to be released: with
///    Control still down at mouse-up, screencapture sends the image to the
///    clipboard and writes no file.
/// 2. Records the pasteboard's change count.
/// 3. Runs screencapture into `NSTemporaryDirectory()/stickermine-<UUID>.png`,
///    logging its stdout and stderr.
/// 4. When it exits, classifies the result (`CaptureClassifier`) on the main
///    thread and calls the completion once.
@MainActor
final class CaptureService {
    /// The program and its arguments for a given output file. Tests substitute
    /// a shell script; the app always runs `screencapture`.
    struct Command {
        let executable: URL
        let arguments: (URL) -> [String]

        /// `-i` interactive (Space still toggles window capture), `-J selection`
        /// start in selection mode, `-o` no window shadow, `-x` silent, `-t png`.
        /// Never `-c`, `-u`, `-U`, `-p` or `-r` (spec section 5.6).
        static let screencapture = Command(
            executable: URL(fileURLWithPath: "/usr/sbin/screencapture"),
            arguments: { ["-i", "-J", "selection", "-o", "-x", "-t", "png", $0.path] })
    }

    /// Temporary captures are named `stickermine-<UUID>.png`.
    static let filePrefix = "stickermine-"
    /// How often and how long to wait for the modifiers to be released.
    static let modifierPollInterval: TimeInterval = 0.02

    private let command: Command
    private let temporaryDirectory: URL
    private let pasteboardChangeCount: () -> Int
    private let modifiersHeld: () -> Bool
    private let modifierWait: TimeInterval
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "capture")

    private var process: Process?
    private var outputURL: URL?
    private var waitWork: DispatchWorkItem?
    /// Bumped by every capture and by `cancelRunning()`, so a cancelled run's
    /// termination never calls a completion.
    private var generation = 0

    /// A capture is under way: waiting for the modifiers or screencapture running.
    private(set) var isRunning = false

    init(command: Command = .screencapture,
         temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
         pasteboardChangeCount: @escaping () -> Int = { NSPasteboard.general.changeCount },
         modifiersHeld: @escaping () -> Bool = {
             !NSEvent.modifierFlags.intersection([.control, .option, .command, .shift]).isEmpty
         },
         modifierWait: TimeInterval = 1.0) {
        self.command = command
        self.temporaryDirectory = temporaryDirectory
        self.pasteboardChangeCount = pasteboardChangeCount
        self.modifiersHeld = modifiersHeld
        self.modifierWait = modifierWait
    }

    /// Starts a capture; `completion` runs once on the main thread, unless
    /// `cancelRunning()` is called first. Ignored while a capture runs.
    func capture(completion: @escaping (CaptureOutcome) -> Void) {
        guard !isRunning else {
            log.notice("capture ignored: one is already running")
            return
        }
        isRunning = true
        generation += 1
        waitForModifiers(until: Date().addingTimeInterval(modifierWait), generation: generation,
                         completion: completion)
    }

    /// Ends a running capture without calling its completion: terminates
    /// screencapture and deletes its temporary file (Quit, the updater's
    /// helper, a cancelled session; spec section 5.10).
    func cancelRunning() {
        guard isRunning else { return }
        generation += 1
        waitWork?.cancel()
        waitWork = nil
        if let process, process.isRunning {
            process.terminate()
            log.notice("terminated screencapture")
        }
        process = nil
        if let outputURL { try? FileManager.default.removeItem(at: outputURL) }
        outputURL = nil
        isRunning = false
    }

    /// Deletes leftover captures from an earlier run (spec section 5.10).
    static func deleteLeftovers() {
        deleteLeftovers(in: URL(fileURLWithPath: NSTemporaryDirectory()))
    }

    /// Deletes every `stickermine-*.png` in `directory`; returns how many.
    @discardableResult
    static func deleteLeftovers(in directory: URL) -> Int {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        var deleted = 0
        for name in names where name.hasPrefix(filePrefix) && name.hasSuffix(".png") {
            if (try? FileManager.default.removeItem(at: directory.appendingPathComponent(name))) != nil {
                deleted += 1
            }
        }
        return deleted
    }

    // MARK: Steps

    private func waitForModifiers(until deadline: Date, generation: Int,
                                  completion: @escaping (CaptureOutcome) -> Void) {
        guard generation == self.generation else { return }
        if modifiersHeld(), Date() < deadline {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    self?.waitForModifiers(until: deadline, generation: generation, completion: completion)
                }
            }
            waitWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.modifierPollInterval, execute: work)
            return
        }
        waitWork = nil
        run(generation: generation, completion: completion)
    }

    private func run(generation: Int, completion: @escaping (CaptureOutcome) -> Void) {
        let url = temporaryDirectory.appendingPathComponent("\(Self.filePrefix)\(UUID().uuidString).png")
        let startCount = pasteboardChangeCount()
        let process = Process()
        process.executableURL = command.executable
        process.arguments = command.arguments(url)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.terminationHandler = { [weak self] finished in
            let status = finished.terminationStatus
            let stdout = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            let stderr = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.finished(url: url, status: status, stdout: stdout, stderr: stderr,
                                   startCount: startCount, generation: generation, completion: completion)
                }
            }
        }
        self.process = process
        outputURL = url
        do {
            try process.run()
        } catch {
            log.error("screencapture didn't start: \(error.localizedDescription, privacy: .public)")
            self.process = nil
            outputURL = nil
            isRunning = false
            completion(.busyOrBlocked)
        }
    }

    private func finished(url: URL, status: Int32, stdout: String, stderr: String, startCount: Int,
                          generation: Int, completion: (CaptureOutcome) -> Void) {
        guard generation == self.generation else {
            // Cancelled: the file (if any) is not wanted.
            try? FileManager.default.removeItem(at: url)
            return
        }
        process = nil
        outputURL = nil
        isRunning = false
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? Int
        let outcome = CaptureClassifier.classify(
            file: url, fileExists: size != nil, fileSize: size ?? 0, exitStatus: status,
            pasteboardChanged: pasteboardChangeCount() != startCount)
        if case .success = outcome {} else { try? FileManager.default.removeItem(at: url) }
        let out = stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let err = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        log.notice("screencapture exited \(status): \(String(describing: outcome), privacy: .public) stdout=\(out, privacy: .public) stderr=\(err, privacy: .public)")
        completion(outcome)
    }
}
