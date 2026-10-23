import Foundation
import Testing
@testable import Stickermine

/// The project and Info.plist rules from spec section 3, checked on the files
/// themselves so an edit in Xcode's settings UI can't quietly break them.
struct ProjectSettingsTests {
    private func project() throws -> String {
        try String(contentsOf: SourceFiles.repoRoot.appendingPathComponent("Stickermine.xcodeproj/project.pbxproj"),
                   encoding: .utf8)
    }

    private func rootInfoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: SourceFiles.repoRoot.appendingPathComponent("Info.plist"))
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(plist as? [String: Any])
    }

    private func count(_ needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    @Test func projectFormatIsXcode16WithSynchronizedFolders() throws {
        let text = try project()
        #expect(text.contains("objectVersion = 77;"))
        #expect(text.contains("preferredProjectObjectVersion = 77;"))
        #expect(count("isa = PBXFileSystemSynchronizedRootGroup;", in: text) == 2)
        #expect(text.contains("path = Stickermine;"))
        #expect(text.contains("path = StickermineTests;"))
    }

    @Test func nothingOverridesTheRootInfoPlist() throws {
        let text = try project()
        for forbidden in ["MARKETING_VERSION", "CURRENT_PROJECT_VERSION", "INFOPLIST_KEY_",
                          "CODE_SIGN_ENTITLEMENTS", "ENABLE_APP_SANDBOX = YES"] {
            #expect(!text.contains(forbidden), "project.pbxproj contains \(forbidden)")
        }
        #expect(count("INFOPLIST_FILE = Info.plist;", in: text) == 2)
        // The project and app levels say NO; only the never-shipped test bundle
        // has a generated Info.plist.
        #expect(count("GENERATE_INFOPLIST_FILE = NO;", in: text) == 4)
        #expect(count("GENERATE_INFOPLIST_FILE = YES;", in: text) == 2)
        #expect(count("ENABLE_APP_SANDBOX = NO;", in: text) >= 2)
        #expect(count("PRODUCT_BUNDLE_IDENTIFIER = com.ethan.stickermine;", in: text) == 2)
        #expect(count("PRODUCT_NAME = Stickermine;", in: text) == 2)
    }

    @Test func swiftSettingsAreExplicitAtProjectLevel() throws {
        let text = try project()
        for setting in ["SWIFT_VERSION = 5.0;", "SWIFT_STRICT_CONCURRENCY = minimal;",
                        "SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated;", "SWIFT_APPROACHABLE_CONCURRENCY = NO;"] {
            #expect(count(setting, in: text) == 2, "\(setting) should appear in the project's Debug and Release")
        }
    }

    @Test func deploymentTargetEqualsTheMinimumSystemVersion() throws {
        let minimum = try #require(try rootInfoPlist()["LSMinimumSystemVersion"] as? String)
        #expect(minimum == "26.0")
        let targets = try project()
            .components(separatedBy: "\n")
            .filter { $0.contains("MACOSX_DEPLOYMENT_TARGET = ") }
            .map { $0.trimmingCharacters(in: .whitespaces) }
        #expect(targets.count == 2)
        #expect(targets.allSatisfy { $0 == "MACOSX_DEPLOYMENT_TARGET = \(minimum);" })
    }

    @Test func rootInfoPlistHoldsLiteralValues() throws {
        let plist = try rootInfoPlist()
        #expect(plist["CFBundleIdentifier"] as? String == "com.ethan.stickermine")
        #expect(plist["CFBundleExecutable"] as? String == "Stickermine")
        #expect(plist["CFBundleName"] as? String == "Stickermine")
        #expect(plist["CFBundleDisplayName"] as? String == "Stickermine")
        #expect(plist["CFBundlePackageType"] as? String == "APPL")
        #expect(plist["LSUIElement"] as? Bool == true)
        #expect(plist["NSHumanReadableCopyright"] as? String == "© 2026 Ethan Darling (grokcodile) — MIT License")
        #expect(plist["CFBundleShortVersionString"] is String)
        #expect(plist["CFBundleVersion"] is String)
        for (key, value) in plist {
            if let string = value as? String {
                #expect(!string.contains("$("), "\(key) uses a build-setting variable")
            }
            #expect(!key.hasSuffix("UsageDescription"), "\(key) is a usage-description key")
        }
    }

    @Test func theBuiltAppCarriesTheRootInfoPlistValues() throws {
        // The test host is the built app, so Bundle.main is what Xcode produced.
        let plist = try rootInfoPlist()
        for key in ["CFBundleIdentifier", "CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion"] {
            #expect(Bundle.main.object(forInfoDictionaryKey: key) as? String == plist[key] as? String, "\(key) differs")
        }
    }
}
