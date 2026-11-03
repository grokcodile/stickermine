import AppKit
import os

/// Where an update is in its lifecycle (Pullcord's `UpdateState`).
enum UpdateState: Equatable {
    /// Running the newest release (or nothing newer carries the DMG yet).
    case upToDate
    /// A newer release with `Stickermine.dmg` exists: Home's strip offers Update.
    case available
    /// Fetching the DMG before opening it and quitting.
    case downloading
    /// The Homebrew helper is upgrading (it quits and relaunches Stickermine).
    case updating
    /// The upgrade didn't finish: the strip offers Update again.
    case failed
}

/// The self-updater (spec section 13), ported from Pullcord's: it asks
/// GitHub for the latest release only where the answer is seen (Home
/// opening, the About version line, and once after a login launch; never
/// polling) and offers a release only if its assets include
/// `Stickermine.dmg`. A Homebrew install (Caskroom entry and running from
/// /Applications/Stickermine.app) upgrades through a detached helper that
/// quits this process by PID, runs `brew upgrade --cask`, clears the
/// quarantine flag and relaunches; any other install downloads the DMG to
/// ~/Downloads (HTTP 200 only), opens it and quits. Before the helper is
/// spawned, the app's termination cleanup runs (`beforeHelper`): the helper's
/// `kill` skips `applicationWillTerminate`.
///
/// Keep Info.plist's version ahead of the newest tag, or every local build
/// offers the release as an update.
@MainActor
final class Updater: ObservableObject {
    nonisolated static let latestReleaseURL = URL(string: "https://api.github.com/repos/grokcodile/stickermine/releases/latest")!
    nonisolated static let dmgName = "Stickermine.dmg"
    nonisolated static let dmgURL = URL(string: "https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg")!
    nonisolated static let releasesPageURL = URL(string: "https://github.com/grokcodile/stickermine/releases/latest")!
    nonisolated static let caskName = "stickermine"
    nonisolated static let caskroomPaths = ["/opt/homebrew/Caskroom/stickermine", "/usr/local/Caskroom/stickermine"]
    nonisolated static let installedBundlePath = "/Applications/Stickermine.app"
    nonisolated static let brewPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    nonisolated static let helperScriptName = "stickermine-update.sh"
    /// A successful Homebrew upgrade kills this process; still being here
    /// after this long means it didn't happen.
    nonisolated static let watchdogInterval: TimeInterval = 180

    /// What a `releases/latest` answer says.
    struct Release: Equatable {
        /// The tag without its leading "v".
        let version: String
        /// Its assets include `Stickermine.dmg`.
        let installable: Bool
    }

    @Published private(set) var state: UpdateState = .upToDate
    /// The newest release when it is newer than this build, else nil.
    @Published private(set) var latestVersion: String?

    let appVersion: String
    private let fetch: () async -> Data?
    private let beforeHelper: () -> Void
    private var updateStarting = false
    private var watchdog: Timer?
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "updater")

    /// `fetch` defaults to the GitHub request; tests pass canned JSON.
    init(appVersion: String = Updater.bundleVersion, fetch: (() async -> Data?)? = nil,
         beforeHelper: @escaping () -> Void) {
        self.appVersion = appVersion
        self.fetch = fetch ?? { await Updater.liveFetch() }
        self.beforeHelper = beforeHelper
    }

    /// CFBundleShortVersionString, which CI stamps from the release tag.
    nonisolated static var bundleVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// Whether a Homebrew cask installed the copy that is running: the
    /// Caskroom entry alone isn't enough, since a dev build run from ./build
    /// would otherwise hand itself to `brew upgrade`, overwrite the
    /// /Applications copy and reopen the dev build.
    nonisolated static func isHomebrewManaged(caskroomExists: Bool, bundlePath: String) -> Bool {
        caskroomExists && bundlePath == installedBundlePath
    }

    var isHomebrewManaged: Bool {
        let caskroom = Self.caskroomPaths.contains { FileManager.default.fileExists(atPath: $0) }
        return Self.isHomebrewManaged(caskroomExists: caskroom, bundlePath: Bundle.main.bundlePath)
    }

    /// Numeric and component-wise, so 1.26 is newer than 1.17, which is newer
    /// than 1.9; a missing component counts as 0 ("1.0" equals "1").
    nonisolated static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let pa = a.split(separator: ".").map { Int($0) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0
            let y = i < pb.count ? pb[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Parses GitHub's `releases/latest` JSON; nil when it has no tag.
    nonisolated static func release(from data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String, !tag.isEmpty
        else { return nil }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        // CI publishes the release a moment before its DMG upload lands, and
        // both update paths fetch that file: without it, Update would 404.
        let assets = json["assets"] as? [[String: Any]] ?? []
        let installable = assets.contains { $0["name"] as? String == dmgName }
        return Release(version: version, installable: installable)
    }

    /// The only network request Stickermine makes: a GET, nothing sent.
    nonisolated static func liveFetch() async -> Data? {
        var request = URLRequest(url: latestReleaseURL)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    /// Asks GitHub now. `completion` (on the main actor) says whether GitHub
    /// answered, so the About line can say "Couldn't check".
    func check(completion: ((Bool) -> Void)? = nil) {
        Task { [weak self] in
            guard let self else { return }
            let data = await self.fetch()
            guard let data, let release = Self.release(from: data) else {
                completion?(false)
                return
            }
            self.handle(release)
            completion?(true)
        }
    }

    /// A check's answer. An update already under way is never interrupted.
    func handle(_ release: Release) {
        guard state != .updating, state != .downloading else { return }
        let newer = release.installable && Self.isVersion(release.version, newerThan: appVersion)
        let newState: UpdateState = newer ? .available : .upToDate
        let newLatest = newer ? release.version : nil
        guard newState != state || newLatest != latestVersion else { return }
        latestVersion = newLatest
        state = newState
        log.notice("latest release \(release.version, privacy: .public) (installable: \(release.installable)); this is \(self.appVersion, privacy: .public)")
    }

    /// The strip's Update button: Homebrew's helper, or the DMG download.
    func performUpdate() {
        if isHomebrewManaged { startHomebrewUpdate() } else { downloadUpdate() }
    }

    // MARK: Homebrew

    /// The detached helper's script. It does the slow part (index refresh and
    /// download) while Stickermine still shows "Updating…", then quits it by
    /// PID (pkill and pgrep skip their own ancestors, and Homebrew won't quit
    /// an app that brew runs inside), upgrades, clears the quarantine flag
    /// (a quarantined app needs an interactive first launch, and the next
    /// login item launch has nobody to approve it) and reopens the app,
    /// unconditionally, so even a failed upgrade brings it back.
    nonisolated static func helperScript(brew: String, bundle: String, pid: Int32) -> String {
        let brewBin = (brew as NSString).deletingLastPathComponent
        return """
        #!/bin/sh
        export PATH="\(brewBin):/usr/bin:/bin:/usr/sbin:/sbin"
        "\(brew)" update >/dev/null 2>&1
        "\(brew)" fetch --cask \(caskName) >/dev/null 2>&1
        kill \(pid) 2>/dev/null
        for i in $(seq 1 20); do kill -0 \(pid) 2>/dev/null || break; sleep 0.5; done
        kill -0 \(pid) 2>/dev/null && kill -9 \(pid) 2>/dev/null
        "\(brew)" upgrade --cask \(caskName) >/dev/null 2>&1
        xattr -dr com.apple.quarantine "\(bundle)" 2>/dev/null
        open "\(bundle)"

        """
    }

    nonisolated static func brewPath() -> String? {
        brewPaths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private func startHomebrewUpdate() {
        guard !updateStarting, let brew = Self.brewPath() else {
            state = .available
            return
        }
        updateStarting = true
        state = .updating
        let path = NSTemporaryDirectory() + Self.helperScriptName
        let script = Self.helperScript(brew: brew, bundle: Bundle.main.bundlePath,
                                       pid: ProcessInfo.processInfo.processIdentifier)
        do {
            try script.write(toFile: path, atomically: true, encoding: .utf8)
            // Spec section 5.10: screencapture terminated, the library flushed.
            beforeHelper()
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            helper.arguments = [path]
            try helper.run()
            log.notice("Homebrew update helper started")
            armWatchdog()
        } catch {
            log.error("the update helper didn't start: \(error.localizedDescription, privacy: .public)")
            updateStarting = false
            state = .failed
        }
    }

    /// No kill within 180 s: brew found nothing to do or the helper died.
    private func armWatchdog() {
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: Self.watchdogInterval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.state == .updating else { return }
                self.updateStarting = false
                self.state = .failed
                // If brew did replace the app after all, this corrects it.
                self.check()
            }
        }
    }

    // MARK: DMG

    /// Downloads the DMG to ~/Downloads, opens it and quits, so the new build
    /// can be dragged over this one. A non-200 answer (GitHub's 404 page)
    /// never replaces an existing ~/Downloads/Stickermine.dmg; the releases
    /// page opens instead.
    private func downloadUpdate() {
        state = .downloading
        let destination = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/\(Self.dmgName)")
        Task { [weak self] in
            do {
                let (temporary, response) = try await URLSession.shared.download(from: Self.dmgURL)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else {
                    try? FileManager.default.removeItem(at: temporary)
                    throw URLError(.fileDoesNotExist)
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: temporary, to: destination)
                NSWorkspace.shared.open(destination)
                // Quit once the mount request is out, so nothing holds the old app.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    NSApp.terminate(nil)
                }
            } catch {
                let missing = (error as? URLError)?.code == .fileDoesNotExist
                NSWorkspace.shared.open(missing ? Self.releasesPageURL : Self.dmgURL)
                self?.state = .available
            }
        }
    }
}
