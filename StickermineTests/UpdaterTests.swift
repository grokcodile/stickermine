import Foundation
import Testing
@testable import Stickermine

/// No network: a canned `releases/latest` answer stands in for GitHub, and
/// nothing here spawns the helper or downloads anything.
@MainActor
struct UpdaterTests {
    static func json(tag: String?, assets: [String]) -> Data {
        var object: [String: Any] = ["assets": assets.map { ["name": $0] }]
        if let tag { object["tag_name"] = tag }
        return try! JSONSerialization.data(withJSONObject: object)
    }

    @Test func versionsCompareNumericallyComponentByComponent() {
        #expect(Updater.isVersion("1.26", newerThan: "1.9"))
        #expect(Updater.isVersion("1.10", newerThan: "1.9"))
        #expect(Updater.isVersion("2", newerThan: "1.99"))
        #expect(Updater.isVersion("1.0.1", newerThan: "1.0"))
        #expect(!Updater.isVersion("1.9", newerThan: "1.26"))
        #expect(!Updater.isVersion("1.0", newerThan: "1"))
        #expect(!Updater.isVersion("1", newerThan: "1.0"))
        #expect(!Updater.isVersion("1.2", newerThan: "1.2"))
        #expect(Updater.isVersion("1.0", newerThan: "0.1"))
    }

    @Test func onlyAReleaseCarryingTheDMGIsInstallable() throws {
        let ready = try #require(Updater.release(from: Self.json(tag: "v1.2", assets: ["Stickermine.dmg"])))
        #expect(ready == Updater.Release(version: "1.2", installable: true))
        let early = try #require(Updater.release(from: Self.json(tag: "v1.2", assets: [])))
        #expect(!early.installable)
        let other = try #require(Updater.release(from: Self.json(tag: "1.3", assets: ["Stickermine.zip", "stickermine.dmg"])))
        #expect(other == Updater.Release(version: "1.3", installable: false))
        #expect(Updater.release(from: Self.json(tag: nil, assets: ["Stickermine.dmg"])) == nil)
        #expect(Updater.release(from: Data("not json".utf8)) == nil)
        #expect(Updater.release(from: Data(#"{"message": "API rate limit exceeded"}"#.utf8)) == nil)
    }

    @Test func aNewerInstallableReleaseIsOfferedAndNothingElseIs() {
        let updater = Updater(appVersion: "1.0", fetch: { nil }, beforeHelper: {})
        updater.handle(Updater.Release(version: "1.1", installable: false))
        #expect(updater.state == .upToDate)
        #expect(updater.latestVersion == nil)
        updater.handle(Updater.Release(version: "0.9", installable: true))
        #expect(updater.state == .upToDate)
        updater.handle(Updater.Release(version: "1.1", installable: true))
        #expect(updater.state == .available)
        #expect(updater.latestVersion == "1.1")
        updater.handle(Updater.Release(version: "1.0", installable: true))
        #expect(updater.state == .upToDate)
        #expect(updater.latestVersion == nil)
    }

    @Test func aCheckReportsWhetherGitHubAnswered() async {
        let answer = Self.json(tag: "v2.0", assets: ["Stickermine.dmg"])
        let updater = Updater(appVersion: "1.0", fetch: { answer }, beforeHelper: {})
        let reached = await withCheckedContinuation { continuation in
            updater.check { continuation.resume(returning: $0) }
        }
        #expect(reached)
        #expect(updater.state == .available)
        #expect(updater.latestVersion == "2.0")
        let offline = Updater(appVersion: "1.0", fetch: { nil }, beforeHelper: {})
        let failed = await withCheckedContinuation { continuation in
            offline.check { continuation.resume(returning: $0) }
        }
        #expect(!failed)
        #expect(offline.state == .upToDate)
    }

    @Test func homebrewManagesOnlyTheInstalledCopy() {
        #expect(Updater.isHomebrewManaged(caskroomExists: true, bundlePath: "/Applications/Stickermine.app"))
        #expect(!Updater.isHomebrewManaged(caskroomExists: true, bundlePath: "/Users/ethan/Developer/stickermine/build/Stickermine.app"))
        #expect(!Updater.isHomebrewManaged(caskroomExists: false, bundlePath: "/Applications/Stickermine.app"))
        // The test host runs from DerivedData, never /Applications.
        let updater = Updater(appVersion: "1.0", fetch: { nil }, beforeHelper: {})
        #expect(!updater.isHomebrewManaged)
    }

    @Test func theHelperQuitsByPidUpgradesClearsQuarantineAndReopens() {
        let script = Updater.helperScript(brew: "/opt/homebrew/bin/brew", bundle: "/Applications/Stickermine.app", pid: 4242)
        let lines = script.split(separator: "\n").map(String.init)
        #expect(lines == [
            "#!/bin/sh",
            #"export PATH="/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin""#,
            #""/opt/homebrew/bin/brew" update >/dev/null 2>&1"#,
            #""/opt/homebrew/bin/brew" fetch --cask stickermine >/dev/null 2>&1"#,
            "kill 4242 2>/dev/null",
            "for i in $(seq 1 20); do kill -0 4242 2>/dev/null || break; sleep 0.5; done",
            "kill -0 4242 2>/dev/null && kill -9 4242 2>/dev/null",
            #""/opt/homebrew/bin/brew" upgrade --cask stickermine >/dev/null 2>&1"#,
            #"xattr -dr com.apple.quarantine "/Applications/Stickermine.app" 2>/dev/null"#,
            #"open "/Applications/Stickermine.app""#,
        ])
        #expect(!script.contains("pkill"))
    }

    @Test func theAddressesAreStickermines() {
        #expect(Updater.latestReleaseURL.absoluteString == "https://api.github.com/repos/grokcodile/stickermine/releases/latest")
        #expect(Updater.dmgURL.absoluteString == "https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg")
        #expect(Updater.dmgName == "Stickermine.dmg")
        #expect(Updater.caskroomPaths == ["/opt/homebrew/Caskroom/stickermine", "/usr/local/Caskroom/stickermine"])
        #expect(Updater.watchdogInterval == 180)
    }
}
