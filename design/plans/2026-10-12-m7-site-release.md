# M7 Website, Docs and Release Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Stickermine its documents and its website and take it through the first release: `README.md`, `PRIVACY.md`, `TERMS.md` and `CONTACT.md`; the static site in `docs/` with self-hosted Fredoka, its images, favicon and link preview; the `stickermine` cask in `grokcodile/homebrew-tap`; and the release checklist through the `v1.0` tag, GitHub Pages and, once the domain resolves, `stickermine.app`.

**Architecture:** Nothing new runs inside the app. The documents are Markdown at the repo root and the site is one static `docs/index.html` (brand tokens as CSS custom properties, one small inline script for the copy button, Maple's bubble and a future demo loop) with every file it loads beside it. Five Swift Testing suites read these files from the source tree, the way `ProjectSettingsTests` already reads the project file, and hold them to the spec and to the app's own words and addresses (`SettingsText`, `TutorialArt`, `Shortcut`, `Updater`, `AboutLinks`), so the docs can't drift from the app. Three committed scripts in `design/` fetch the font, render the images and check the site. Every outward step (pushing, workflow runs, the repo's visibility, the tap, the tag, Pages, the custom domain) waits for Ethan's explicit yes at that moment.

**Tech Stack:** HTML, CSS and plain JavaScript; Markdown; bash; `/usr/bin/python3` (standard library only); `curl`, `shasum`, `qlmanage`, `sips`, `hdiutil`, `codesign`, `spctl`, `stapler`; Swift Testing (with CoreText, CryptoKit and M2's `MasterImage`); `gh` and `git`; the Homebrew cask DSL.

**Spec:** `design/specs/2026-10-12-stickermine-v1-design.md`. This milestone implements section 3's README, PRIVACY, TERMS and CONTACT contents (with section 14's privacy bullet), section 15 (the website), section 16's tokens, type and sticker rules as they apply to the site, section 17's "Before the first tag" steps 1–5, and section 20's open items as explicit questions to Ethan. The plan index with the Interface Contract is `design/plans/2026-10-12-stickermine-v1-plan.md`; the M1–M6 plans are `design/plans/2026-10-12-m1-foundation.md`, `design/plans/2026-10-12-m2-model-displays.md`, `design/plans/2026-10-12-m3-styles.md`, `design/plans/2026-10-12-m4-capture-picker.md`, `design/plans/2026-10-12-m5-editing.md` and `design/plans/2026-10-12-m6-app-shell.md`.

## Contract changes

**No signature changes.** Additions and one superseded note:

- **Added (test support):** `enum RepoFiles` in `StickermineTests/DocsTestSupport.swift`: `static func url(_ path: String) -> URL`, `static func exists(_ path: String) -> Bool`, `static func text(_ path: String) throws -> String`, `static func data(_ path: String) throws -> Data`, `static func prose(_ path: String) throws -> String`, `static func matches(_ pattern: String, in text: String) throws -> [[String]]`, `static func headings(in markdown: String, level: Int) throws -> [String]`, `static func markdownLinks(in markdown: String) throws -> [String]`, `static func sha256(_ data: Data) -> String`, `static func inOrder(_ needles: [String], in list: [String]) -> Bool`. It builds on M1's `SourceFiles.repoRoot`.
- **Value change, Task 11 only (once `stickermine.app` is bought and resolves):** `AboutLinks.website` becomes `https://stickermine.app/` in the same commit as `docs/CNAME` (M6's note). Its declaration `static let website: URL` is unchanged.
- **Superseded:** M1 Task 1's Interfaces note says the release commit "sets 1.0 before tagging `v1.0`". The spec (section 3) says the committed version is "a dev placeholder kept ahead of the newest release tag; CI stamps the real value from the tag", and M6's `Updater` comment says the same ("Keep Info.plist's version ahead of the newest tag, or every local build offers the release as an update"). So Task 9 sets `Info.plist` to `1.1` before `v1.0` is tagged; the release workflow stamps `1.0` into the release build from the tag.

Task 10 Step 3 records these in the index.

## Global Constraints

All constraints in the index apply. Milestone-specific ones, verbatim from the spec:

- "**README.md:** a user guide like the siblings' (pitch, Features, Install, Requirements, First run, How it works, Uninstall, License, Author). It states the design philosophy, "The app getting smaller as macOS gets better is a success, not a regression." It explains the Screen Recording permission and the periodic system alert (section 5). It never gives a download or installed size, and never says "no menu bar item"." (section 3)
- "**PRIVACY.md:** adapts Pullcord's (short version; the app; what the permission is for; on-device processing; the website; third-party services; changes; contact)." "**TERMS.md:** adapts Pullcord's (License, No warranty, Privacy, Updates, Payments via Ko-fi, What it depends on: `screencapture`, Vision subject lifting, window levels; Not affiliated with Apple, Changes, Contact)." "**CONTACT.md:** how to reach Ethan (email address to be decided, section 20) and the GitHub issues link." (section 3)
- "**Privacy (PRIVACY.md):** no account, no telemetry, no network except the update check. Captures are processed on-device and the temporary screenshot is deleted. Sticker images and layouts stay in Application Support. Stickers are hidden from screen sharing by default, best-effort. Third parties: GitHub (releases, update check, Pages), Homebrew, Ko-fi." (section 14)
- "Port `design/index.html` to `docs/index.html` as a plain static page: colours as CSS custom properties from the tokens in section 16, `prefers-reduced-motion` respected, no tooltips." "**Fredoka self-hosted** in `docs/fonts/` (OFL), so the site loads nothing from third parties." (section 15)
- "**Narrow widths:** the page works at phone width (16 px gutters, no horizontal scroll). Below about 640 px, the brief's fixed values may scale down or wrap (h1 80 px with its 16 px stroke, the description card's `nowrap`, the brew command). Maple is never allowed to cover content: below about 640 px she becomes smaller and non-fixed at the end of the page, and at every width the page has bottom padding so she never covers the footer. Her bubble shows on `:hover`, and also on `:focus-visible` and tap." (section 15)
- "Homebrew sticker: `brew install --cask grokcodile/tap/stickermine`. The copy button reads the command from one `data-copy` attribute that matches the visible text (port Pullcord's `.brew-copy[data-copy]` script: `writeText` with an `execCommand` fallback, swapping the aria-label to "Copied" during the 1.6 s checkmark)." (section 15)
- "Download line: "\<size\> download · macOS 26+ · Apple Silicon · Free", with no version number (matches the siblings and can't go stale). The size is measured from each release's published DMG and updated by hand; it is stated only on the site." "Download links to `https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg`." (section 15) Until `v1.0` is published there is no DMG to measure, so the line reads "macOS 26+ · Apple Silicon · Free" and Task 10 adds the size before Pages goes live.
- "**Demo card:** until the demo is recorded, the 16:10 card shows a still (stickers on a desktop) with no play button and no bracketed note. When it exists: muted, looping, `playsinline`, no native controls (the peeled corner would cut them), autoplay only when reduced motion isn't requested." (section 15)
- "**Footer (in order):** © Stickermine, GitHub (repo), Privacy (`PRIVACY.md` on GitHub), Terms (`TERMS.md` on GitHub), Contact (`CONTACT.md` on GitHub), then ☕️ Buy me a coffee (Ko-fi) last." "**Assets:** `docs/icon.png` (from the app icon), favicon, an Open Graph image from the pickaxe, `docs/dog.png`." (section 15)
- "**Domain:** `docs/CNAME` = `stickermine.app` is added only once the domain is bought and resolves; until then the site, the og:image absolute URL and the About popover's Website link use `https://grokcodile.github.io/stickermine/`." "**Light canvas only** (the design's single look); no dark mode in v1." (section 15)
- The tokens: page background `#F3F0E8`, ink `#1F2340`, blue `#3D4BE0`, mint `#8FE3BE`, pink `#FF4F81`, yellow `#FFD84D`, sticker border `#FFFFFF`. "Type: Fredoka 300–600 on the site; SF Pro Rounded in the app. Sticker rules: white border (8 px pills, 10 px cards), large radius, shadow `0 10px 24px rgba(31,35,64,0.22)`, slight rotation between −4° and +3°." (section 16)
- "**Before the first tag** (each outward step confirmed with Ethan when it happens): 1. Make the repo `grokcodile/stickermine` public if it isn't yet … 2. Ethan sets the six secrets (`MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`, `AC_API_KEY_BASE64`, `TAP_PUSH_TOKEN`) with `gh secret set`. Claude never handles them. 3. Commit `Casks/stickermine.rb` to `homebrew-tap`, copying `pullcord.rb`'s shape. It must contain the three lines the workflow rewrites and then re-checks: quoted placeholder `version "1.0"`, a 64-hex placeholder `sha256`, and `  depends_on macos: :tahoe` (two-space indent; without it the tap step fails after the release is already published). It also has `depends_on arch: :arm64`, `uninstall quit: "com.ethan.stickermine"` and `zap trash:` for `~/Library/Application Support/com.ethan.stickermine`, `~/Library/Caches/com.ethan.stickermine`, `~/Library/HTTPStorages/com.ethan.stickermine` and `~/Library/Preferences/com.ethan.stickermine.plist`. Add a Stickermine row to the tap README. 4. Manual dry run; check the DMG with `codesign`, `spctl` and `stapler`; then tag `v1.0`. 5. After the v1.0 release and cask bump succeed: enable Pages from `main:/docs`, and add `docs/CNAME` once `stickermine.app` is bought and resolves." (section 17)
- Section 20's open items (the contact address, buying the domain, the demo loop, the repo's visibility, the secrets, an optional released Xcode 26.x) are questions for Ethan (Task 9). **No email address is ever invented:** `CONTACT.md` carries a marked gap until Ethan gives one, the release gate refuses to pass while it is there, and no other file carries an address.
- Downloads from the internet (the font, the dry-run artifact) happen only after Ethan's yes, with the file, its source and its rough size stated when asking. The font comes only from Google Fonts' own servers (`fonts.googleapis.com` / `fonts.gstatic.com`) and its licence from the `google/fonts` repository.
- Run every command from the repository root (`/Users/ethan/Developer/stickermine`) in bash or zsh, not fish (several commands use `VAR=$(…)` and heredocs). The sibling repos are read-only references; the only other repo this milestone writes to is `/Users/ethan/Developer/homebrew-tap`, and only on Ethan's yes.
- Test command (from the index): `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`, with `-only-testing:StickermineTests/<Suite>` for one suite. Xcode prints a harmless `Error registering app with AppIntents framework … com.apple.linkd.autoShortcut` line while the test host starts; ignore it.

## Review Focus

The index's five Review Focus items belong to other milestones (1 → M2, 2 and 3 → M4, 4 → M3, 5 → M6); this milestone owns none. It writes item 2's permission panel and system alert and item 5's way back to Home into the README in the app's own words (`ReadmeTests.explainsScreenRecordingAndThePeriodicAlert`, `ReadmeTests.usesTheAppsOwnWords`), and Task 10 Step 14 runs M6's `design/app-shell-checks.md` row 26 against the published release.

Milestone-specific failure modes:

1. **The tap step fails after the release is already published**, because the cask lacks one of the three lines the workflow rewrites (spec 17 step 3), so `brew upgrade` never sees v1.0. Expect: the release run's "Update Homebrew tap" step succeeds and the cask reads `version "1.0"` with the DMG's SHA-256. Pinned by Task 8 Step 3, which runs the rewrite-and-check block copied out of `.github/workflows/release.yml` itself against the new cask, and Task 10 Step 11, which compares the bumped cask with the release run's log.
2. **Maple or her bubble covers content, or the page scrolls sideways on a phone.** Expect: at every width the footer and every sticker stay fully visible, Maple is fixed only where there is room, and a 375 px or 320 px screen never scrolls sideways. Pinned by `SitePageTests.phonesReducedMotionAndMapleFollowTheSpec` (exactly one `position: fixed`, inside the one roomy media query; the bottom padding; the content stacked above her; the 16 px gutters; `overflow-x: clip`) and `design/site-checks.md` rows 4–7, 7b, 7c and 14–16 (Task 7), plus the iPhone check after Pages (Task 10 Step 13).
3. **The documents or the site drift from the app or the spec:** a size in the README, a version in the download line, a copy button that copies something other than what it shows, a third-party font request that breaks PRIVACY.md's promise, an email address outside CONTACT.md, a setting renamed in the app but not in the README. Expect: none of these can be committed with the suite green. Pinned by `ReadmeTests`, `SitePageTests` (`thePageLoadsNothingFromOtherSites`, `theCopyButtonCopiesExactlyTheVisibleCommand`, `theDownloadPillIsTheLatestDMGWithoutAVersion`), `PolicyDocsTests` and `SiteFontTests`.

## Files

| Path | Action | Responsibility |
|---|---|---|
| `StickermineTests/DocsTestSupport.swift` | Create (Task 1) | `RepoFiles`: read repo files, regex matches, headings, links, checksums |
| `StickermineTests/PolicyDocsTests.swift` | Create (Task 1) | PRIVACY, TERMS and CONTACT against the spec and the app |
| `PRIVACY.md`, `TERMS.md`, `CONTACT.md` | Create (Task 1); CONTACT and the dates modified in Task 9 | The policies and how to reach Ethan |
| `StickermineTests/ReadmeTests.swift` | Create (Task 4) | The README's outline, promises and the app's own words |
| `README.md` | Create (Task 4); the still's alt text (only with Ethan's own screenshot) in Task 9; Task 11 changes its Website line | The user guide |
| `design/get-site-font.sh` | Create (Task 2) | Downloads Fredoka and its licence, records checksums |
| `docs/fonts/Fredoka-latin.woff2`, `docs/fonts/OFL.txt`, `docs/fonts/SHA256SUMS` | Create (Task 2, by the script) | The self-hosted font, its licence, the sums checked at download |
| `StickermineTests/SiteFontTests.swift` | Create (Task 2) | The font is Fredoka 300–600, unchanged since download, with its licence |
| `design/make-site-images.sh` | Create (Task 3) | Writes the site's images |
| `docs/icon.png`, `docs/favicon.png`, `docs/dog.png`, `docs/og.png`, `docs/demo-still.jpg` | Create (Task 3, by the script) | Icon, favicon, Maple, link preview, demo still |
| `StickermineTests/SiteImagesTests.swift` | Create (Task 3) | The images are the app's own icon slices and Maple, at the right sizes |
| `docs/index.html` | Create (Task 5); download line in Task 10; demo loop or the still's alt text (optional) in Task 9; addresses in Task 11 | The website |
| `StickermineTests/SitePageTests.swift` | Create (Task 5) | The page against spec sections 15 and 16 and the app's addresses |
| `design/check-site.sh` | Create (Task 6) | HTML structure, local links, release gates, online link statuses |
| `design/site-checks.md` | Create (Task 7) | The page in a browser at desktop and phone widths, with results |
| `/Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb`, `/Users/ethan/Developer/homebrew-tap/README.md` | Create / modify (Task 8, Ethan's yes) | The cask and the tap's app list |
| `design/release-checklist.md` | Create (Task 9); filled in Tasks 9–11 | Every release's steps and the record of each |
| `design/README.md` | Modify (Task 9) | Lists the new scripts and records |
| `Info.plist` | Modify (Task 9) | Dev version `1.1`, ahead of `v1.0` |
| `design/ci-dry-runs.md` | Modify (Tasks 10, 11) | Append the dry-run rows |
| `design/app-shell-checks.md` | Modify (Task 10) | Row 26's result against the release |
| `design/plans/2026-10-12-stickermine-v1-plan.md` | Modify (Task 10) | This milestone's contract additions |
| `docs/CNAME`, `Stickermine/Home/AboutPopover.swift`, `StickermineTests/HomeTextTests.swift` | Create / modify (Task 11) | The domain, and the About popover's Website link |

---

### Task 1: The policy documents (PRIVACY, TERMS, CONTACT)

**Files:**
- Create: `StickermineTests/DocsTestSupport.swift`
- Create: `PRIVACY.md`, `TERMS.md`, `CONTACT.md`
- Test: `StickermineTests/PolicyDocsTests.swift`

**Interfaces:**
- Consumes: `SourceFiles.repoRoot: URL` (M1, `static var`); `Updater.latestReleaseURL: URL` and `Updater.caskName: String` (M6, `nonisolated static let`); `AboutLinks.issues: URL` (M6, `static let`); `SettingsText.sharingTitle: String` (M6, `static let`).
- Produces: `enum RepoFiles` (see Contract changes); the three documents. `CONTACT.md`'s email line is exactly `- **Email:** _(address pending: Ethan adds it before the first release)_` until Task 9 fills it in as `- **Email:** [<address>](mailto:<address>)`.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/DocsTestSupport.swift` (complete file):

```swift
import CryptoKit
import Foundation

/// The repository's documents and website files (M7), read from disk so the
/// tests can hold what they promise against the app and the spec.
enum RepoFiles {
    static func url(_ path: String) -> URL {
        SourceFiles.repoRoot.appendingPathComponent(path)
    }

    static func exists(_ path: String) -> Bool {
        FileManager.default.fileExists(atPath: url(path).path)
    }

    static func text(_ path: String) throws -> String {
        try String(contentsOf: url(path), encoding: .utf8)
    }

    static func data(_ path: String) throws -> Data {
        try Data(contentsOf: url(path))
    }

    /// The file's text with every run of whitespace (line breaks included)
    /// folded into one space, so a re-wrapped paragraph still matches.
    static func prose(_ path: String) throws -> String {
        try text(path).split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Every match of `pattern` in `text`, each as its capture groups with the
    /// whole match first; a group that took no part is "".
    static func matches(_ pattern: String, in text: String) throws -> [[String]] {
        let regex = try NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines])
        let whole = NSRange(text.startIndex..., in: text)
        return regex.matches(in: text, range: whole).map { match in
            (0..<match.numberOfRanges).map { index in
                Range(match.range(at: index), in: text).map { String(text[$0]) } ?? ""
            }
        }
    }

    /// The headings of one level ("## Install" → "Install"), in order.
    static func headings(in markdown: String, level: Int) throws -> [String] {
        let marks = String(repeating: "#", count: level)
        return try matches("^" + marks + " (.+)$", in: markdown).map { $0[1] }
    }

    /// The targets of a Markdown file's links and images, in order.
    static func markdownLinks(in markdown: String) throws -> [String] {
        try matches(#"\]\(([^)\s]+)\)"#, in: markdown).map { $0[1] }
            + matches(#"<img src="([^"]+)""#, in: markdown).map { $0[1] }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// True when `needles` appear in `list` in this order (others may sit between).
    static func inOrder(_ needles: [String], in list: [String]) -> Bool {
        var rest = list[...]
        for needle in needles {
            guard let index = rest.firstIndex(of: needle) else { return false }
            rest = rest[(index + 1)...]
        }
        return true
    }
}
```

`StickermineTests/PolicyDocsTests.swift` (complete file):

```swift
import Foundation
import Testing
@testable import Stickermine

/// PRIVACY.md, TERMS.md and CONTACT.md (spec sections 3 and 14), held to
/// what the app really does and to the one place an address may appear.
@MainActor
struct PolicyDocsTests {
    static let pendingAddress = "- **Email:** _(address pending: Ethan adds it before the first release)_"

    @Test func privacyFollowsTheSiblingsOutline() throws {
        let privacy = try RepoFiles.text("PRIVACY.md")
        #expect(try !RepoFiles.matches(#"^\*\*Effective [A-Z][a-z]+ [0-9]{1,2}, 20[0-9]{2}\*\*$"#, in: privacy).isEmpty)
        #expect(privacy.contains("> **The short version:** Stickermine collects no data."))
        #expect(try RepoFiles.headings(in: privacy, level: 2)
                == ["The app", "The website", "Third-party services", "Changes", "Contact"])
        #expect(try RepoFiles.headings(in: privacy, level: 3) == ["What the permission is for", "What happens to a capture"])
    }

    @Test func privacySaysWhatTheAppAndTheSiteReallyDo() throws {
        let privacy = try RepoFiles.prose("PRIVACY.md")
        // The one request the app makes, and where everything else stays.
        #expect(privacy.contains("`\(Updater.latestReleaseURL.absoluteString)`"))
        #expect(privacy.contains("`~/Library/Application Support/com.ethan.stickermine/`"))
        #expect(privacy.contains("**Screen Recording** is the only permission"))
        #expect(privacy.contains("bypass the system private window picker"))
        #expect(privacy.contains("Apple's Vision framework, on your Mac"))
        #expect(privacy.contains("deletes it straight away"))
        #expect(privacy.contains(SettingsText.sharingTitle))
        #expect(privacy.contains("best effort"))
        // The site serves its own font, so this sentence stays true.
        #expect(privacy.contains("no embedded third-party scripts or fonts"))
        for service in ["**GitHub**", "**Homebrew**", "**Ko-fi**"] {
            #expect(privacy.contains(service), "\(service)")
        }
    }

    @Test func termsCoverTheSpecsSections() throws {
        let terms = try RepoFiles.text("TERMS.md")
        #expect(try !RepoFiles.matches(#"^\*\*Stickermine\*\* — last updated [A-Z][a-z]+ [0-9]{1,2}, 20[0-9]{2}$"#, in: terms).isEmpty)
        #expect(try RepoFiles.headings(in: terms, level: 2) == [
            "License", "No warranty", "Privacy", "Updates", "Payments", "What it depends on",
            "Not affiliated with Apple", "Changes", "Contact",
        ])
        let prose = try RepoFiles.prose("TERMS.md")
        for piece in ["`screencapture`", "Vision's on-device subject lifting", "window levels", "(Ko-fi)",
                      "`brew upgrade --cask \(Updater.caskName)`", "[MIT License](LICENSE)", "[Privacy Policy](PRIVACY.md)"] {
            #expect(prose.contains(piece), "\(piece)")
        }
    }

    @Test func contactHasTheIssuesLinkAndOneAddressLine() throws {
        let contact = try RepoFiles.text("CONTACT.md")
        #expect(contact.contains("(\(AboutLinks.issues.absoluteString))"))
        let emailLines = contact.split(separator: "\n").map(String.init).filter { $0.hasPrefix("- **Email:**") }
        #expect(emailLines.count == 1)
        let line = try #require(emailLines.first)
        // Either the marked gap Ethan fills in before the first release, or a
        // real address written as a mailto link.
        let filledIn = try !RepoFiles.matches(#"^- \*\*Email:\*\* \[([^\]\s@]+@[^\]\s]+)\]\(mailto:\1\)$"#, in: line).isEmpty
        #expect(line == Self.pendingAddress || filledIn, "\(line)")
    }

    @Test func privacyAndTermsSendYouToContactInsteadOfAnAddress() throws {
        for path in ["PRIVACY.md", "TERMS.md"] {
            let text = try RepoFiles.text(path)
            #expect(!text.contains("mailto:"), "\(path)")
            #expect(try RepoFiles.matches(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text).isEmpty, "\(path)")
            #expect(text.contains("[CONTACT.md](CONTACT.md)"), "\(path)")
            #expect(text.contains("(\(AboutLinks.issues.absoluteString))"), "\(path)")
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PolicyDocsTests
```

Expected: all five tests fail with `Caught error: Error Domain=NSCocoaErrorDomain Code=260 "The file “PRIVACY.md” couldn’t be opened because there is no such file."` (`TERMS.md` and `CONTACT.md` for theirs), then `Test run with 5 tests in 1 suite failed` and `** TEST FAILED **`.

- [ ] **Step 3: Write PRIVACY.md**

`PRIVACY.md` (complete file; adapted from Pullcord's, with Stickermine's one permission, its capture path and its one network request):

```markdown
# Privacy Policy

**Effective October 22, 2026**

> **The short version:** Stickermine collects no data. There are no accounts,
> no analytics, and no tracking — in the app or on the website. Your
> screenshots are cut out on your Mac, and your stickers stay on your Mac.

## The app

- Stickermine has no account system and no telemetry. It never collects,
  stores, or transmits personal information.
- There is no license check, no crash reporting, and no "anonymous usage
  statistics".
- The app's only network activity is asking GitHub's public API
  (`https://api.github.com/repos/grokcodile/stickermine/releases/latest`)
  whether there is a newer release — when you open the Home window, when you
  click the version line in About, and once shortly after it starts at
  login — and downloading the new version if you choose to update. These are
  ordinary web requests with nothing of yours added; GitHub's standard server
  logging applies.
- The About popover's links (the website, the GitHub repository, the issue
  tracker and Ko-fi) and the one-time support card's Ko-fi button open in your
  browser.
- Your stickers (one PNG each) and where you placed them (`library.json`) are
  stored in `~/Library/Application Support/com.ethan.stickermine/`. Your
  settings are stored in macOS's own preferences. None of it leaves your Mac.

### What the permission is for

- **Screen Recording** is the only permission Stickermine asks for. macOS
  requires it before an app can open the screenshot crosshair. Stickermine
  only ever receives the area you drag over, and only when you start a capture
  yourself. macOS also asks you from time to time to confirm it (the alert
  saying Stickermine "is requesting to bypass the system private window
  picker").

### What happens to a capture

- macOS's own `screencapture` tool writes the area you selected to a
  temporary file. Stickermine reads it and deletes it straight away.
- The subject is cut out with Apple's Vision framework, on your Mac. Nothing
  is uploaded, and no model is downloaded.
- When you choose a style, the cutout is saved as a PNG in the folder above.
  Cancelling saves nothing.
- Stickers are hidden from screen sharing and screenshots by default ("Hide
  stickers from screen sharing and screenshots" in Home). This is best effort:
  macOS offers no guarantee for it, and some sharing or recording apps may
  still show them.

## The website

- The site is static: no cookies, no analytics, no trackers, no embedded
  third-party scripts or fonts (its Fredoka font is served from the site
  itself).
- It is hosted on GitHub Pages, which — like any web host — may keep standard
  server logs (such as IP addresses) per
  [GitHub's privacy statement](https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement).

## Third-party services

If you choose to use them, these services have their own privacy policies:

- **GitHub** — hosts the code, the releases, the update check, and the site.
- **Homebrew** — if you install or update via `brew`.
- **Ko-fi** — if you leave a tip. Stickermine never sees any payment details.

## Changes

If this policy ever changes, the update will be posted here with a new
effective date. Given what Stickermine is — a small, open-source app that does
its work on your Mac — don't expect much to change.

## Contact

Questions? See [CONTACT.md](CONTACT.md), or
[open an issue](https://github.com/grokcodile/stickermine/issues).
```

- [ ] **Step 4: Write TERMS.md**

`TERMS.md` (complete file; adapted from Pullcord's):

```markdown
# Terms of Service

**Stickermine** — last updated October 22, 2026

Stickermine is a free, open-source macOS app built by Ethan Darling
([grokcodile](https://github.com/grokcodile)). By downloading or using
Stickermine you agree to these terms.

## License

Stickermine is licensed under the [MIT License](LICENSE). You may use, copy,
modify, and redistribute it under those terms.

## No warranty

Stickermine is provided **"as is"**, without warranty of any kind, express or
implied. The author is not liable for any claim, damages, or other liability
arising from its use, as set out in the MIT License. Hiding stickers from
screen sharing and screenshots is best effort, not a guarantee.

## Privacy

Stickermine runs entirely on your Mac, collects no data, and has no analytics
or telemetry. Your captures are processed on your Mac and never uploaded. The
only network request it makes is a version check against GitHub Releases to
offer updates. See the full [Privacy Policy](PRIVACY.md).

## Updates

Stickermine checks GitHub for new releases when you open its Home window. If
you installed with Homebrew, `brew upgrade --cask stickermine` fetches them;
otherwise new versions are on
[GitHub Releases](https://github.com/grokcodile/stickermine/releases). You can
simply not install updates if you prefer.

## Payments

Stickermine is completely free. Nothing is gated, and there are no accounts,
purchases, or subscriptions. The optional tip jar, offered once in the app and
in its About popover, links to a third-party service (Ko-fi) which has its own
terms.

## What it depends on

Stickermine is built on features macOS already provides — the `screencapture`
tool and its crosshair, Vision's on-device subject lifting, and the window
levels that keep stickers above the desktop icons and below your windows.
Those features are Apple's, and they can change or be removed in any macOS
release. Part of Stickermine may stop working, or change, when that happens.

## Not affiliated with Apple

Stickermine is an independent project. macOS is a trademark of Apple Inc.
Stickermine is not affiliated with, endorsed by, or sponsored by Apple.

## Changes

If these terms change, the updated version will be published here with a new
"last updated" date.

## Contact

Questions or problems: see [CONTACT.md](CONTACT.md), or
[open an issue](https://github.com/grokcodile/stickermine/issues).
```

- [ ] **Step 5: Write CONTACT.md**

`CONTACT.md` (complete file). The email line is a marked gap, not an address: section 20 leaves the address to Ethan (the sibling pattern would be `stickermine@ethans.email`, unverified), Task 9 asks him, and `design/check-site.sh --release` refuses to pass until it is filled in.

```markdown
# Contact

Stickermine is made by Ethan Darling ([grokcodile](https://github.com/grokcodile)).

- **Bugs and ideas:** [open an issue on GitHub](https://github.com/grokcodile/stickermine/issues).
  It's the quickest way to reach me, and anyone with the same problem can
  follow along. The Report a Bug link in Stickermine's About popover goes
  there too.
- **Email:** _(address pending: Ethan adds it before the first release)_

Stickermine sends no crash reports or diagnostics, so when you report a
problem, include what you were doing, your macOS version, and Stickermine's
version (the line under its name in the About popover). Please leave anything
private out of screenshots you attach.
```

- [ ] **Step 6: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PolicyDocsTests
```

Expected: `Test run with 5 tests in 1 suite passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 7: Commit**

```bash
git add StickermineTests/DocsTestSupport.swift StickermineTests/PolicyDocsTests.swift PRIVACY.md TERMS.md CONTACT.md
git commit -m "Add the privacy policy, terms and contact page" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The site's font (self-hosted Fredoka)

**Files:**
- Create: `design/get-site-font.sh`
- Create (by the script): `docs/fonts/Fredoka-latin.woff2`, `docs/fonts/OFL.txt`, `docs/fonts/SHA256SUMS`
- Test: `StickermineTests/SiteFontTests.swift`

**Interfaces:**
- Consumes: `RepoFiles` (Task 1).
- Produces: `docs/fonts/Fredoka-latin.woff2` (one variable WOFF2, latin subset, weights 300–600, family "Fredoka"), `docs/fonts/OFL.txt` (SIL Open Font License 1.1, Fredoka's copyright line), `docs/fonts/SHA256SUMS` (two lines in `shasum -a 256` format, file names without a path). Task 3 embeds the font in the link preview; Task 5's page loads it as `fonts/Fredoka-latin.woff2`.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/SiteFontTests.swift` (complete file):

```swift
import CoreText
import Foundation
import Testing
@testable import Stickermine

/// The website's self-hosted Fredoka (spec section 15): the right font, the
/// weights the page uses, its licence beside it, and the bytes that were
/// checked when it was downloaded.
struct SiteFontTests {
    static let font = "docs/fonts/Fredoka-latin.woff2"
    static let licence = "docs/fonts/OFL.txt"
    static let sums = "docs/fonts/SHA256SUMS"

    @Test func theFontIsFredokaFromLightToSemibold() throws {
        let data = try RepoFiles.data(Self.font)
        #expect(data.prefix(4) == Data("wOF2".utf8))
        let descriptors = try #require(CTFontManagerCreateFontDescriptorsFromData(data as CFData) as? [CTFontDescriptor])
        let font = CTFontCreateWithFontDescriptor(try #require(descriptors.first), 16, nil)
        #expect(CTFontCopyFamilyName(font) as String == "Fredoka")
        // One variable file covers the page's weights, 300 to 600.
        let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []
        let weight = try #require(axes.first { ($0[kCTFontVariationAxisIdentifierKey as String] as? NSNumber)?.intValue == 0x7767_6874 })
        let lowest = try #require(weight[kCTFontVariationAxisMinimumValueKey as String] as? NSNumber).doubleValue
        let highest = try #require(weight[kCTFontVariationAxisMaximumValueKey as String] as? NSNumber).doubleValue
        #expect(lowest <= 300)
        #expect(highest >= 600)
    }

    @Test func theFilesStillMatchTheChecksumsRecordedAtDownload() throws {
        let lines = try RepoFiles.text(Self.sums).split(separator: "\n").map(String.init)
        var recorded: [String: String] = [:]
        for line in lines {
            let parts = try RepoFiles.matches(#"^([0-9a-f]{64})  (\S+)$"#, in: line)
            let part = try #require(parts.first, "malformed line: \(line)")
            recorded[part[2]] = part[1]
        }
        #expect(Set(recorded.keys) == ["Fredoka-latin.woff2", "OFL.txt"])
        for (name, sum) in recorded {
            #expect(RepoFiles.sha256(try RepoFiles.data("docs/fonts/" + name)) == sum, "\(name)")
        }
    }

    @Test func theOpenFontLicenceTravelsWithTheFont() throws {
        let licence = try RepoFiles.text(Self.licence)
        #expect(licence.contains("SIL OPEN FONT LICENSE Version 1.1"))
        #expect(licence.contains("Fredoka"))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SiteFontTests
```

Expected: the three tests fail with `Caught error: … "The file “Fredoka-latin.woff2” couldn’t be opened because there is no such file."` (`SHA256SUMS` and `OFL.txt` for the other two), then `Test run with 3 tests in 1 suite failed` and `** TEST FAILED **`.

- [ ] **Step 3: Write the download script**

`design/get-site-font.sh` (complete file):

```bash
#!/bin/bash
# Downloads the website's Fredoka (SIL Open Font License 1.1) into
# docs/fonts/, so the site loads nothing from anyone else (spec section 15):
#
# - Fredoka-latin.woff2: the latin subset as one variable WOFF2 covering
#   weights 300-600, straight from Google Fonts' own servers
#   (fonts.gstatic.com). Its address is read from the Google Fonts CSS, the
#   same file the design mock linked to.
# - OFL.txt: the licence, from the google/fonts repository on GitHub.
#
# Both are checked (WOFF2 signature, licence text), then their SHA-256 sums
# are written to docs/fonts/SHA256SUMS and verified with `shasum -c`.
# SiteFontTests re-checks the files against those sums on every test run.
# Run it again only to update the font, and review the SHA256SUMS diff
# before committing.
set -euo pipefail

cd "$(dirname "$0")/.."
UA='Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15'
CSS_URL='https://fonts.googleapis.com/css2?family=Fredoka:wght@300..600&display=swap'
OFL_URL='https://raw.githubusercontent.com/google/fonts/main/ofl/fredoka/OFL.txt'
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "CSS:     $CSS_URL"
curl -fsSL --proto '=https' -A "$UA" "$CSS_URL" -o "$WORK/fredoka.css"

# The CSS has one @font-face per subset, each after a comment naming it
# (/* hebrew */, /* latin-ext */, /* latin */). Take the latin one's file.
FONT_URL=$(awk '/\/\* latin \*\//{ f = 1 } f && /src: url\(/{ if (match($0, /https:\/\/fonts\.gstatic\.com\/[^)]*\.woff2/)) { print substr($0, RSTART, RLENGTH); exit } }' "$WORK/fredoka.css")
case "$FONT_URL" in
    https://fonts.gstatic.com/s/fredoka/*.woff2) ;;
    *)
        echo "error: no latin Fredoka WOFF2 in the Google Fonts CSS:" >&2
        cat "$WORK/fredoka.css" >&2
        exit 1
        ;;
esac
if ! grep -q "font-weight: 300 600;" "$WORK/fredoka.css"; then
    echo "error: the CSS doesn't describe one variable file for weights 300-600:" >&2
    cat "$WORK/fredoka.css" >&2
    exit 1
fi

echo "Font:    $FONT_URL"
curl -fsSL --proto '=https' -A "$UA" "$FONT_URL" -o "$WORK/Fredoka-latin.woff2"
echo "Licence: $OFL_URL"
curl -fsSL --proto '=https' "$OFL_URL" -o "$WORK/OFL.txt"

if [ "$(head -c 4 "$WORK/Fredoka-latin.woff2")" != "wOF2" ]; then
    echo "error: the font isn't a WOFF2 file" >&2
    exit 1
fi
if ! grep -q "SIL OPEN FONT LICENSE Version 1.1" "$WORK/OFL.txt" || ! grep -q "Fredoka" "$WORK/OFL.txt"; then
    echo "error: OFL.txt isn't Fredoka's SIL Open Font License 1.1" >&2
    exit 1
fi

mkdir -p docs/fonts
cp "$WORK/Fredoka-latin.woff2" "$WORK/OFL.txt" docs/fonts/
(
    cd docs/fonts
    shasum -a 256 Fredoka-latin.woff2 OFL.txt > SHA256SUMS
    shasum -a 256 -c SHA256SUMS
    cat SHA256SUMS
)
ls -l docs/fonts
```

```bash
chmod +x design/get-site-font.sh
bash -n design/get-site-font.sh && echo "syntax OK"
```

Expected: `syntax OK`.

- [ ] **Step 4: Ask Ethan, then download**

Ask: "May I download Fredoka for the website? Two files: `Fredoka-latin.woff2` from fonts.gstatic.com (Google Fonts' own server; the address comes from the Google Fonts CSS at fonts.googleapis.com) and `OFL.txt` from the google/fonts repository on GitHub (raw.githubusercontent.com). Together they are well under 1 MB." Only after his yes:

```bash
./design/get-site-font.sh
```

Expected, in order: `CSS:     https://fonts.googleapis.com/css2?family=Fredoka:wght@300..600&display=swap`, `Font:    https://fonts.gstatic.com/s/fredoka/v<n>/<name>.woff2`, `Licence: https://raw.githubusercontent.com/google/fonts/main/ofl/fredoka/OFL.txt`, then `Fredoka-latin.woff2: OK` and `OFL.txt: OK` (the `shasum -c` check), the two lines of `SHA256SUMS`, and an `ls -l` listing the three files. If it stops with `error: no latin Fredoka WOFF2 in the Google Fonts CSS` or `error: the CSS doesn't describe one variable file for weights 300-600`, it printed the CSS it got: show it to Ethan and don't commit anything. If Ethan says no to the download, stop this milestone here and ask how he wants the font provided (the spec requires Fredoka served from `docs/fonts/`).

- [ ] **Step 5: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SiteFontTests
```

Expected: `Test run with 3 tests in 1 suite passed` and `** TEST SUCCEEDED **`. If `theFontIsFredokaFromLightToSemibold` fails on the weight axis, Google served a static file: show Ethan the test output and the CSS line before going on.

- [ ] **Step 6: Commit**

```bash
git add design/get-site-font.sh docs/fonts StickermineTests/SiteFontTests.swift
git commit -m "Self-host the website's Fredoka with its licence" -m "Downloaded with design/get-site-font.sh; checksums in docs/fonts/SHA256SUMS:" -m "$(cat docs/fonts/SHA256SUMS)" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The site's images

**Files:**
- Create: `design/make-site-images.sh`
- Create (by the script): `docs/icon.png`, `docs/favicon.png`, `docs/dog.png`, `docs/og.png`, `docs/demo-still.jpg`
- Test: `StickermineTests/SiteImagesTests.swift`

**Interfaces:**
- Consumes: `RepoFiles` (Task 1); `enum MasterImage { static func image(at url: URL) -> CGImage? }` (M2); `enum TestImages { static func rgba(of image: CGImage, x: Int, y: Int) -> [UInt8] }` (M1); M6's committed slices `Stickermine/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png` (512 px) and `icon_32x32@2x.png` (64 px); `design/dog.png`, `design/icon-pickaxe.svg`, `design/menubar-glyph.svg`; `docs/fonts/Fredoka-latin.woff2` (Task 2).
- Produces: `docs/icon.png` (512 × 512, the app icon), `docs/favicon.png` (64 × 64), `docs/dog.png` (620 × 910, Maple), `docs/og.png` (1200 × 630, opaque), `docs/demo-still.jpg` (1600 × 1000). Task 4's README and Task 5's page use them.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/SiteImagesTests.swift` (complete file):

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

/// The website's pictures (spec sections 15 and 16): the app's own icon
/// slices, Maple as designed, the link preview and the demo still, all made
/// by the committed design/make-site-images.sh.
struct SiteImagesTests {
    private func image(_ path: String) throws -> CGImage {
        try #require(MasterImage.image(at: RepoFiles.url(path)), "\(path) is missing or unreadable")
    }

    private func near(_ pixel: [UInt8], _ rgb: (Int, Int, Int), within tolerance: Int = 6) -> Bool {
        abs(Int(pixel[0]) - rgb.0) <= tolerance && abs(Int(pixel[1]) - rgb.1) <= tolerance
            && abs(Int(pixel[2]) - rgb.2) <= tolerance && pixel[3] == 255
    }

    @Test func theIconAndFaviconAreTheAppIconsOwnSlices() throws {
        let slices = "Stickermine/Assets.xcassets/AppIcon.appiconset/"
        #expect(try RepoFiles.data("docs/icon.png") == RepoFiles.data(slices + "icon_256x256@2x.png"))
        #expect(try RepoFiles.data("docs/favicon.png") == RepoFiles.data(slices + "icon_32x32@2x.png"))
        #expect(try image("docs/icon.png").width == 512)
        #expect(try image("docs/favicon.png").width == 64)
    }

    @Test func mapleIsTheDesignedCutout() throws {
        #expect(try RepoFiles.data("docs/dog.png") == RepoFiles.data("design/dog.png"))
    }

    @Test func theLinkPreviewIs1200By630OnTheBrandBackground() throws {
        let preview = try image("docs/og.png")
        #expect(preview.width == 1200)
        #expect(preview.height == 630)
        // The page background in the corners (opaque: link previews show
        // transparency as black), the blue tile on the left.
        for (x, y) in [(10, 10), (1190, 10), (10, 620), (1190, 620)] {
            #expect(near(TestImages.rgba(of: preview, x: x, y: y), (0xF3, 0xF0, 0xE8)), "(\(x), \(y))")
        }
        #expect(near(TestImages.rgba(of: preview, x: 130, y: 250), (0x3D, 0x4B, 0xE0)))
    }

    @Test func theDemoStillIs16By10() throws {
        let still = try image("docs/demo-still.jpg")
        #expect(still.width == 1600)
        #expect(still.height == 1000)
    }

    @Test func theScriptThatMakesThemIsCommitted() throws {
        let script = RepoFiles.url("design/make-site-images.sh")
        #expect(FileManager.default.isExecutableFile(atPath: script.path))
        let text = try RepoFiles.text("design/make-site-images.sh")
        for piece in ["qlmanage -t -s", "sips -c", "icon_256x256@2x.png", "icon_32x32@2x.png", "design/dog.png",
                      "docs/fonts/Fredoka-latin.woff2"] {
            #expect(text.contains(piece), "\(piece)")
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SiteImagesTests
```

Expected: all five fail: `Caught error: … "The file “icon.png” couldn’t be opened because there is no such file."` (and `dog.png`), `Expectation failed: MasterImage.image(at: RepoFiles.url(path))` for the link preview and the still, and `Expectation failed: FileManager.default.isExecutableFile(atPath: script.path)` for the script (the script test also records `Caught error: … "make-site-images.sh" couldn’t be opened`); `Test run with 5 tests in 1 suite failed`.

- [ ] **Step 3: Write the image script**

`design/make-site-images.sh` (complete file):

```bash
#!/bin/bash
# Writes the website's images into docs/ (spec sections 15 and 16). Run it
# again when the app icon, Maple or the brand art changes, then commit the
# results: nothing on the site is generated at publish time.
#
# - docs/icon.png and docs/favicon.png are the app icon's own 512 and 64 px
#   slices (Stickermine/Assets.xcassets/AppIcon.appiconset, made by
#   design/make-icon.sh), so the site and the app always show the same icon.
# - docs/dog.png is Maple, as committed in design/.
# - docs/og.png (1200 x 630, the link preview) and docs/demo-still.jpg
#   (1600 x 1000, the demo card until the demo loop is recorded) are drawn as
#   SVG and rendered with qlmanage, which goes through WebKit (so the icon
#   keeps its drop shadow). The link preview is set in the site's own Fredoka,
#   embedded in the SVG from docs/fonts (run design/get-site-font.sh first);
#   the demo still shows the app's tutorial cards, which the app draws in
#   SF Pro Rounded (ui-rounded). qlmanage only renders square thumbnails, so
#   each picture is drawn in the middle of a square and sips crops it out.
set -euo pipefail

cd "$(dirname "$0")/.."
ICONSET="Stickermine/Assets.xcassets/AppIcon.appiconset"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for f in "$ICONSET/icon_256x256@2x.png" "$ICONSET/icon_32x32@2x.png" design/dog.png design/icon-pickaxe.svg design/menubar-glyph.svg docs/fonts/Fredoka-latin.woff2; do
    if [ ! -s "$f" ]; then
        echo "error: $f is missing (design/make-icon.sh makes the icon slices, design/get-site-font.sh the font)" >&2
        exit 1
    fi
done

mkdir -p docs
cp "$ICONSET/icon_256x256@2x.png" docs/icon.png
cp "$ICONSET/icon_32x32@2x.png" docs/favicon.png
cp design/dog.png docs/dog.png
cp design/dog.png "$WORK/dog.png"

ROUNDED="ui-rounded, sans-serif"
SHADOW='<filter id="drop" x="-30%" y="-30%" width="160%" height="170%"><feDropShadow dx="0" dy="12" stdDeviation="14" flood-color="#1F2340" flood-opacity="0.28"/></filter>'
FACE="<style>@font-face { font-family: \"Fredoka\"; font-weight: 300 700; src: url(data:font/woff2;base64,$(base64 -i docs/fonts/Fredoka-latin.woff2 | tr -d '\n')) format(\"woff2\"); }</style>"

# The pickaxe tile from the app icon's design, at (x, y) and size, turned by
# rot degrees, on a white sticker border.
tile() {  # x y size rot
    local x="$1" y="$2" size="$3" rot="$4"
    local border=$(( size / 20 ))
    local cx=$(( x + size / 2 )) cy=$(( y + size / 2 ))
    echo "<g filter=\"url(#drop)\" transform=\"rotate($rot $cx $cy)\">"
    echo "<rect x=\"$(( x - border ))\" y=\"$(( y - border ))\" width=\"$(( size + 2 * border ))\" height=\"$(( size + 2 * border ))\" rx=\"$(( size * 30 / 100 ))\" fill=\"#FFFFFF\"/>"
    sed "1s/<svg /<svg x=\"$x\" y=\"$y\" /; 1s/width=\"1024\" height=\"1024\"/width=\"$size\" height=\"$size\"/" design/icon-pickaxe.svg
    echo "</g>"
}

# A two-line card sticker like the app's tutorial cards.
card() {  # x y w h rot fill ink line1 line2
    local cx=$(( $1 + $3 / 2 )) cy=$(( $2 + $4 / 2 ))
    echo "<g filter=\"url(#drop)\" transform=\"rotate($5 $cx $cy)\">"
    echo "<rect x=\"$1\" y=\"$2\" width=\"$3\" height=\"$4\" rx=\"46\" fill=\"$6\" stroke=\"#FFFFFF\" stroke-width=\"14\"/>"
    echo "<text x=\"$cx\" y=\"$(( cy - 8 ))\" text-anchor=\"middle\" font-family=\"$ROUNDED\" font-weight=\"600\" font-size=\"34\" fill=\"$7\">$8</text>"
    echo "<text x=\"$cx\" y=\"$(( cy + 36 ))\" text-anchor=\"middle\" font-family=\"$ROUNDED\" font-weight=\"600\" font-size=\"34\" fill=\"$7\">$9</text>"
    echo "</g>"
}

render() {  # name side width height out
    qlmanage -t -s "$2" -o "$WORK" "$WORK/$1.svg" > /dev/null 2>&1
    if [ ! -s "$WORK/$1.svg.png" ]; then
        echo "error: qlmanage didn't render $1.svg" >&2
        exit 1
    fi
    sips -c "$4" "$3" "$WORK/$1.svg.png" --out "$5" > /dev/null
}

# The link preview: the icon tile, the name in the h1's style (blue Fredoka
# with a white stroke under the fill), the tagline on the mint card. The
# name's textLength keeps it clear of the tile whatever the font's widths.
{
    echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1200 1200" width="1200" height="1200">'
    echo "<defs>$FACE$SHADOW</defs>"
    echo '<rect width="1200" height="1200" fill="#F3F0E8"/>'
    echo '<g transform="translate(0 285)">'
    tile 102 167 296 -4
    echo '<g filter="url(#drop)" transform="rotate(-2 795 250)"><text x="795" y="290" text-anchor="middle" textLength="620" lengthAdjust="spacing" font-family="Fredoka" font-weight="600" font-size="112" fill="#3D4BE0" stroke="#FFFFFF" stroke-width="24" stroke-linejoin="round" paint-order="stroke fill">Stickermine</text></g>'
    echo '<g filter="url(#drop)" transform="rotate(1.5 795 425)"><rect x="475" y="352" width="640" height="146" rx="44" fill="#8FE3BE" stroke="#FFFFFF" stroke-width="12"/>'
    echo '<text x="795" y="415" text-anchor="middle" font-family="Fredoka" font-weight="400" font-size="31" fill="#1F2340">Turn quick screenshots into fun</text>'
    echo '<text x="795" y="458" text-anchor="middle" font-family="Fredoka" font-weight="400" font-size="31" fill="#1F2340">stickers that live on your desktop.</text></g>'
    echo '</g></svg>'
} > "$WORK/og.svg"
render og 1200 1200 630 docs/og.png

# The demo still: stickers on a desktop. The card's peeled corner hides its
# bottom-right, so nothing sits there.
{
    echo '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 1600 1600" width="1600" height="1600">'
    echo '<defs>'
    echo '<linearGradient id="wall" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3D4BE0"/><stop offset="0.55" stop-color="#5A3FB8"/><stop offset="1" stop-color="#1F2340"/></linearGradient>'
    echo '<radialGradient id="glow" cx="0.3" cy="0.25" r="0.6"><stop offset="0" stop-color="#8FE3BE" stop-opacity="0.35"/><stop offset="1" stop-color="#8FE3BE" stop-opacity="0"/></radialGradient>'
    echo "$SHADOW"
    echo '</defs>'
    echo '<rect width="1600" height="1600" fill="#1F2340"/>'
    echo '<g transform="translate(0 300)">'
    echo '<rect width="1600" height="1000" fill="url(#wall)"/>'
    echo '<rect width="1600" height="1000" fill="url(#glow)"/>'
    echo '<rect width="1600" height="44" fill="#FFFFFF" fill-opacity="0.22"/>'
    sed '1s/<svg /<svg x="1400" y="8" /; 1s/width="200" height="200"/width="28" height="28"/; s/fill="#000" stroke="#000"/fill="#FFFFFF" stroke="#FFFFFF"/; s/ style="color:#000"//' design/menubar-glyph.svg
    echo "<text x=\"1560\" y=\"30\" text-anchor=\"end\" font-family=\"$ROUNDED\" font-weight=\"600\" font-size=\"22\" fill=\"#FFFFFF\">9:41</text>"
    card 960 130 470 150 -2 "#3D4BE0" "#FFFFFF" "Press ⌃⌥⌘S" "to make a sticker"
    card 980 320 450 150 1.5 "#8FE3BE" "#1F2340" "Double-click me to move," "resize or remove."
    tile 200 260 280 -8
    echo '<g filter="url(#drop)" transform="rotate(3 830 770)"><image x="690" y="520" width="280" height="411" href="dog.png"/></g>'
    echo '</g></svg>'
} > "$WORK/still.svg"
render still 1600 1600 1000 "$WORK/still.png"
sips -s format jpeg -s formatOptions 82 "$WORK/still.png" --out docs/demo-still.jpg > /dev/null

for f in docs/icon.png docs/favicon.png docs/dog.png docs/og.png docs/demo-still.jpg; do
    echo "$f $(sips -g pixelWidth "$f" | awk '/pixelWidth/ { print $2 }') x $(sips -g pixelHeight "$f" | awk '/pixelHeight/ { print $2 }')"
done
```

- [ ] **Step 4: Run it**

```bash
chmod +x design/make-site-images.sh
./design/make-site-images.sh
```

Expected, exactly:

```text
docs/icon.png 512 x 512
docs/favicon.png 64 x 64
docs/dog.png 620 x 910
docs/og.png 1200 x 630
docs/demo-still.jpg 1600 x 1000
```

- [ ] **Step 5: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SiteImagesTests
```

Expected: `Test run with 5 tests in 1 suite passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: Look at the two drawn images**

```bash
open -a Preview docs/og.png docs/demo-still.jpg
```

MANUAL VERIFICATION (the executor writes down what Ethan or the executor sees; never mark it passed without looking):

1. `og.png`: the warm off-white background edge to edge; on the left the blue pickaxe tile with its white border, tilted slightly left; on the right "Stickermine" in rounded blue Fredoka with a thick white outline, not touching the tile; below it the mint card with "Turn quick screenshots into fun / stickers that live on your desktop." in dark Fredoka, both lines inside the card with room on both sides.
2. `demo-still.jpg`: a blue-to-purple desktop with a translucent menu bar (white pickaxe glyph and "9:41" at the right); top right the blue card "Press ⌃⌥⌘S / to make a sticker" and the mint card "Double-click me to move, / resize or remove."; the pickaxe tile on the left; Maple in the middle; the bottom-right corner (hidden by the card's peel on the site) empty.

If a text line in `og.png` overflows its card, lower that `font-size` in the script by 2 and run Steps 4–6 again.

- [ ] **Step 7: Commit**

```bash
git add design/make-site-images.sh docs/icon.png docs/favicon.png docs/dog.png docs/og.png docs/demo-still.jpg StickermineTests/SiteImagesTests.swift
git commit -m "Add the website's images and the script that makes them" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: The README

**Files:**
- Create: `README.md`
- Test: `StickermineTests/ReadmeTests.swift`

**Interfaces:**
- Consumes: `RepoFiles` (Task 1); `Updater.caskName: String`, `Updater.dmgURL: URL` (M6); `AboutLinks.website: URL` (M6); `Shortcut.defaultCapture: Shortcut` and `var label: String { get }` (M4); `SettingsText.shortcutTitle`, `.menuBarTitle`, `.loginTitle`, `.sharingTitle`, `.screenRecordingTitle: String` (M6); `@MainActor enum TutorialArt { static let doubleClickText: String; static func shortcutText(for shortcut: Shortcut?) -> String }` (M6); `StickerStyle.allCases` (M2) and `extension StickerStyle { var displayName: String { get } }` (M4); the recorded results in `design/editing-checks.md` (M5) rows 15–16, `design/spike-results.md` (M1) rows 21, 22, 26, 28 and 29, and `design/capture-checks.md` (M4) rows 6 and 8.
- Produces: `README.md`, the user guide. Its local links point at `docs/icon.png` and `docs/demo-still.jpg` (Task 3), `LICENSE` (M1), `PRIVACY.md` and `CONTACT.md` (Task 1); `ReadmeTests.everyLocalLinkPointsAtAFileThatExists` checks that each exists.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/ReadmeTests.swift` (complete file):

```swift
import Foundation
import Testing
@testable import Stickermine

/// README.md as the user guide spec section 3 asks for, using the app's own
/// words for its shortcut, settings, tutorials and styles.
@MainActor
struct ReadmeTests {
    private func readme() throws -> String { try RepoFiles.text("README.md") }

    @Test func neverStatesADownloadOrInstalledSize() throws {
        let text = try readme()
        #expect(try RepoFiles.matches(#"[0-9]+(?:[.,][0-9]+)?(?:\s|&nbsp;)?(?:[kKMG]B|bytes)\b"#, in: text).isEmpty)
        let lower = text.lowercased()
        for phrase in ["download size", "installed size", "mb download", "kb download"] {
            #expect(!lower.contains(phrase), "\(phrase)")
        }
    }

    @Test func neverSaysThereIsNoMenuBarItem() throws {
        let lower = try RepoFiles.prose("README.md").lowercased()
        #expect(!lower.contains("no menu bar item"))
        #expect(!lower.contains("no menu-bar item"))
        #expect(lower.contains("lives in the menu bar"))
    }

    @Test func statesTheDesignPhilosophy() throws {
        #expect(try readme().contains("**The app getting smaller as macOS gets better is a success, not a regression.**"))
    }

    @Test func followsTheSiblingsUserGuideOutline() throws {
        let sections = try RepoFiles.headings(in: try readme(), level: 2)
        #expect(RepoFiles.inOrder(["Features", "Install", "Requirements", "First run", "How it works",
                                   "Uninstall", "License", "Author"], in: sections), "\(sections)")
        #expect(try readme().hasPrefix(#"<img src="docs/icon.png" alt="Stickermine Icon" width="96"/>"#))
    }

    @Test func explainsScreenRecordingAndThePeriodicAlert() throws {
        let text = try RepoFiles.prose("README.md")
        #expect(text.contains("**Screen Recording permission.**"))
        #expect(text.contains("Stickermine never asks at launch"))
        for button in ["**Continue**", "**Open System Settings**", "**Relaunch Stickermine**"] {
            #expect(text.contains(button), "\(button)")
        }
        #expect(text.contains("\"is requesting to bypass the system private window picker\""))
        #expect(text.contains("from time to time"))
    }

    @Test func installsFromTheTapAndTheLatestRelease() throws {
        let text = try readme()
        #expect(text.contains("brew install --cask grokcodile/tap/\(Updater.caskName)"))
        #expect(text.contains("(\(Updater.dmgURL.absoluteString))"))
        #expect(text.contains("> **Apple Silicon, macOS 26 or later.**"))
        #expect(text.contains("`brew uninstall --zap --cask \(Updater.caskName)`"))
        #expect(text.contains("(\(AboutLinks.website.absoluteString))"))
    }

    @Test func usesTheAppsOwnWords() throws {
        let text = try RepoFiles.prose("README.md")
        #expect(text.contains("**\(Shortcut.defaultCapture.label)**"))
        for title in [SettingsText.shortcutTitle, SettingsText.menuBarTitle, SettingsText.loginTitle,
                      SettingsText.sharingTitle, SettingsText.screenRecordingTitle] {
            #expect(text.contains("**\(title)"), "\(title)")
        }
        // Tutorials 1 and 2, as drawn on the first run.
        #expect(text.contains(TutorialArt.doubleClickText.replacingOccurrences(of: "\n", with: " ")))
        #expect(text.contains(TutorialArt.shortcutText(for: .defaultCapture).replacingOccurrences(of: "\n", with: " ")))
        for style in StickerStyle.allCases {
            #expect(text.contains("**\(style.displayName)**"), "\(style)")
        }
        for button in ["**Whole image**", "**Fill holes**", "**Style**", "**Flip**", "**Float on top**", "**Remove**",
                       "**New Sticker**", "**Open Stickermine…**", "**Delete from History…**", "**Quit Stickermine**",
                       "**Maybe later**"] {
            #expect(text.contains(button), "\(button)")
        }
        #expect(text.contains("`~/Library/Application Support/com.ethan.stickermine/`"))
        #expect(text.contains("`defaults write com.ethan.stickermine clickThroughFallback -bool true`"))
    }

    @Test func theAuthorLineSendsYouToContactInsteadOfAnAddress() throws {
        let text = try readme()
        #expect(text.contains("Feedback and bug reports are welcome: see [CONTACT.md](CONTACT.md)."))
        #expect(!text.contains("mailto:"))
        #expect(try RepoFiles.matches(#"[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"#, in: text).isEmpty)
    }

    @Test func everyLocalLinkPointsAtAFileThatExists() throws {
        for target in try RepoFiles.markdownLinks(in: try readme()) where !target.contains("://") {
            let file = String(target.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
            if file.isEmpty { continue }
            #expect(RepoFiles.exists(file), "\(target)")
        }
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/ReadmeTests
```

Expected: all nine tests fail with `Caught error: … "The file “README.md” couldn’t be opened because there is no such file."`, then `Test run with 9 tests in 1 suite failed` and `** TEST FAILED **`.

- [ ] **Step 3: Write README.md**

`README.md` (complete file). Like Pullcord's and Key54's: the pitch with the design philosophy, Features, Install (Homebrew, the disk image, updates, building from source), Requirements (with the Screen Recording permission and the periodic system alert), First run, then Making a sticker, Editing a sticker and Home in the app's own words, How it works, Uninstall, The name, License, Author. No size anywhere, and no email address (CONTACT.md has it).

````markdown
<img src="docs/icon.png" alt="Stickermine Icon" width="96"/>

# Stickermine

[![Latest release](https://img.shields.io/github/v/release/grokcodile/stickermine?sort=semver&label=release)](https://github.com/grokcodile/stickermine/releases/latest)
[![Homebrew](https://img.shields.io/badge/Homebrew-grokcodile%2Ftap-C9782E?logo=homebrew&logoColor=white)](https://github.com/grokcodile/homebrew-tap)
[![Downloads](https://img.shields.io/github/downloads/grokcodile/stickermine/total)](https://github.com/grokcodile/stickermine/releases)
[![macOS 26+](https://img.shields.io/badge/macOS-26%2B-111111)](#requirements)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue)](LICENSE)

**Turn quick screenshots into fun stickers that live on your desktop.**

<img src="docs/demo-still.jpg" alt="A Mac desktop with stickers on it: two note cards, the Stickermine pickaxe and Maple the dog" width="640"/>

Press a shortcut, drag over anything on your screen, and Stickermine cuts out the subject, lets you pick a style, and sticks it to your desktop. It stays exactly where you put it, above your desktop icons and below your windows, until you move, restyle or remove it, just like a real sticker. It lives in the menu bar, works entirely on your Mac, and is free and open source.

It leans on what macOS already does instead of shipping its own engines: the system's screenshot crosshair to pick an area, Apple's on-device subject lifting to cut it out, and ordinary windows to hold the stickers. When macOS learns to do one of those parts better, that part of Stickermine should go. **The app getting smaller as macOS gets better is a success, not a regression.**

Website: [grokcodile.github.io/stickermine](https://grokcodile.github.io/stickermine/)

## Features

- **Make a sticker in seconds:** press **⌃⌥⌘S** (or click the menu bar icon), drag over a photo, an icon, a pet, a product shot, anything, and pick a style.
- **On-device cutout:** the subject is lifted out of its background on your Mac. Several subjects? Click them in the picker to keep or drop each one, or use **Whole image**.
- **Four styles**, chosen per sticker: **Puffy** (a soft, lit, raised sticker), **Outline** (a thick white die-cut border with a shadow), **Shadow** and **None**.
- **Live stickers:** each one is a real object on your desktop, on every desktop Space, with clicks passing straight through its transparent parts.
- **Edit in place:** double-click a sticker to move it, resize and turn it with its corner knob, flip it, restyle it, float it above your windows or remove it.
- **Every display keeps its own layout.** Stickers on a display you unplug are hidden until it comes back, in the same places.
- **History:** every sticker you make is kept, so you can place it again from the Home window.
- **Private by default:** stickers are left out of screen sharing and screenshots (best effort), and nothing you capture leaves your Mac.

## Install

### Homebrew (easiest — also handles updates)

```sh
brew install --cask grokcodile/tap/stickermine
```

New versions arrive with `brew upgrade --cask stickermine`.

### Download the disk image

1. Download the latest **[Stickermine.dmg](https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg)** (or browse [all releases](https://github.com/grokcodile/stickermine/releases)).
2. Open the `.dmg` and drag **Stickermine** into your `Applications` folder.

Stickermine is signed and notarized by Apple, so it opens normally — no "unidentified developer" warning. macOS may show a one-time "downloaded from the Internet" confirmation; just click **Open**.

> **Apple Silicon, macOS 26 or later.**

### Updates

Stickermine checks for a new release when you open its Home window and when you click the version line in its About popover. It never checks in the background while you work: when it starts at login it checks once, and opens Home only if there's an update waiting.

When one is available, a blue strip with an **Update** button appears across the bottom of Home. A Homebrew install upgrades and reopens on the new version by itself. A disk-image install downloads the new `.dmg`, opens it, and quits so you can drag the new version over the old one.

That update check is the only network request Stickermine makes — see [PRIVACY.md](PRIVACY.md).

### Build from source

On an Apple Silicon Mac with macOS 26 and Xcode 26 or later:

```sh
bash install.sh
```

This builds Stickermine, installs it to `/Applications` and launches it. Without the developer's signing certificate the build is signed ad hoc, so macOS asks for Screen Recording again after every rebuild.

## Requirements

- **macOS 26 or later**, on an **Apple Silicon** Mac.
- **Screen Recording permission.** macOS asks for it before any app can open the screenshot crosshair, even though Stickermine only ever sees the area you drag over. Stickermine never asks at launch: the first time you make a sticker, a small panel explains it, and **Continue** brings up macOS's own request. After that, the panel offers **Open System Settings** (Privacy & Security › Screen & System Audio Recording). If you've just turned it on and the panel is still there, click **Relaunch Stickermine**. Home's settings always show whether it's on.
- **macOS checks in from time to time.** On your first sticker, and every so often after that, macOS shows an alert that Stickermine "is requesting to bypass the system private window picker". That is macOS confirming the Screen Recording permission, not something Stickermine shows. It can appear on top of the sticker picker: answer it, and the picker is still there, waiting for you to choose a style.

## First run

1. Open **Stickermine**. Its Home window opens, and three tutorial stickers appear on your desktop beside it: "Press ⌃⌥⌘S to make a sticker", "Double-click me to move, resize or remove." and Maple the dog.
2. Press **⌃⌥⌘S** and drag over something to make your first sticker. The first time, Stickermine asks for Screen Recording (see [Requirements](#requirements)).
3. That's it: Stickermine keeps running in the menu bar and starts at login, so your stickers are there every time you log in.

The tutorial stickers are ordinary stickers: double-click them to try editing. Removing one deletes it for good; they never come back and never show up in your history. If you change the shortcut, the first one shows the new one.

## Making a sticker

1. Press **⌃⌥⌘S**, click the pickaxe in the menu bar, or click **New Sticker** in Home. The screenshot crosshair appears.
2. Drag over what you want. Press **Space** first to pick a whole window instead, or **Esc** to give up. Keep **Control** up while you let go of the mouse: holding it sends the screenshot to the clipboard instead, and Stickermine reminds you to let go of Control first.
3. The picker opens next to the pointer, with every subject it found highlighted:
   - Click a subject to leave it out or bring it back.
   - **Whole image** keeps the whole capture, with rounded corners. It's the only choice when no subject is found (text, plain backgrounds and full app windows usually have none).
   - **Fill holes** closes gaps inside a subject, like the white parts of an icon. Until you touch it, each style uses its own default (on for Puffy and Outline).
4. Click a style, or press **1**–**4**: **Puffy**, **Outline**, **Shadow** or **None**. The previews are exactly what you'll get.
5. The sticker now follows your pointer, at its natural size (shrunk to fit if it's bigger than half the display). Click to stick it down, on any display. **Esc** or a right-click puts it back in your history instead.

**Esc** or the picker's **×** cancels the whole thing and saves nothing. Clicking elsewhere doesn't, so a stray click can't lose your capture.

## Editing a sticker

Stickers ignore single clicks, so you can't move one by accident. **Double-click** a sticker to edit it: it comes to the front, gets a dashed outline, a round knob on its corner and a small toolbar underneath.

- **Drag** it anywhere, including onto another display.
- **Drag the corner knob** to resize and turn it in one go; hold **Shift** to turn in 15° steps.
- **Pinch or rotate** with two fingers on a trackpad.
- **Style** shows the four styles right in the toolbar; click one to restyle the sticker.
- **Flip** mirrors it; **Float on top** keeps it above your windows (click again to put it back under them).
- **Remove**, or press **Delete**, takes it off your desktop. It stays in your history.
- **Esc** finishes editing and hands the focus back to the app you were using; clicking anywhere else finishes it too.

## Home

Open Stickermine again (from Finder or Spotlight), or right-click the menu bar icon and choose **Open Stickermine…**, to bring up Home:

- **History:** every sticker you've made, newest first. Click one to place it again (you pick its style first). Right-click one for **Delete from History…**, which also takes it off every desktop it's on and tells you how many places that is.
- **Settings:**
  - **Capture shortcut:** click and press a new one. A shortcut needs ⌘ or ⌃ (F-keys can stand alone); **Esc** cancels, **Delete** clears it. Home warns you when macOS already uses that chord for one of its own shortcuts. VoiceOver users may want another one, since ⌃⌥⌘S is also VO-⌘-S.
  - **Show menu bar icon:** without it, use the shortcut, or open Stickermine again to come back here.
  - **Launch at login:** on by default, because stickers are only on your desktop while Stickermine runs.
  - **Hide stickers from screen sharing and screenshots:** on by default. It's best effort (screen sharing, recording and screenshot apps usually leave stickers out) and it also keeps them out of your own screenshots.
  - **Screen Recording:** whether the permission is on, with a button to fix it when it isn't.
- **ⓘ** opens About: the version (click it to check for updates), the website, the GitHub repository, a way to buy me a coffee and a bug report link. **Quit Stickermine** takes every sticker off your desktop until you open it again.

After you've placed a few stickers of your own, Stickermine asks once whether you'd like to buy me a coffee. **Maybe later** means never again.

## How it works

**Capturing** runs macOS's own `screencapture` tool in its interactive mode, the same crosshair as ⇧⌘4, so the system draws the selection and Stickermine only receives the area you chose. The temporary screenshot is deleted as soon as it's read.

**Cutting out** uses Apple's Vision framework, the on-device subject lifting built into macOS. Photos, objects, app icons and single controls cut out well; text, landscapes and whole app windows usually have no subject, which is what **Whole image** is for.

**Stickers** are small borderless windows sitting one level above the desktop icons, so every app window goes over them. They join every desktop Space but stay off full-screen apps, and they stay put through Mission Control. They stay put with Stage Manager on, too. Only their visible pixels take clicks.

**Displays:** each display remembers its own layout. If a display changes resolution, stickers keep their places relative to it. A display Stickermine hasn't seen before starts empty.

**Your stickers and layouts** live in `~/Library/Application Support/com.ethan.stickermine/`: `library.json` plus one PNG per sticker. Settings are in macOS's preferences (`com.ethan.stickermine`).

**If transparent parts of stickers ever stop letting clicks through** after a macOS update, there's a fallback that handles it the slow way. Turn it on with `defaults write com.ethan.stickermine clickThroughFallback -bool true` and quit and reopen Stickermine (`defaults delete com.ethan.stickermine clickThroughFallback` turns it off again).

## Uninstall

1. In Home, turn off **Launch at login**, then click **Quit Stickermine**.
2. Delete **Stickermine.app** from `Applications`.
3. Optionally, delete `~/Library/Application Support/com.ethan.stickermine` (your stickers) and remove Stickermine from System Settings › Privacy & Security › Screen & System Audio Recording.

Installed with Homebrew, steps 1 and 2 are `brew uninstall --cask stickermine`; `brew uninstall --zap --cask stickermine` also removes your stickers and settings.

## The name

You mine stickers out of whatever is on your screen, hence the pickaxe.

## License

Released under the [MIT License](LICENSE).

## Author

Built by **Ethan Darling** — [@grokcodile](https://github.com/grokcodile) on GitHub · [u/grokcodile](https://www.reddit.com/user/grokcodile) on Reddit · [LinkedIn](https://www.linkedin.com/in/ethandarling/). Feedback and bug reports are welcome: see [CONTACT.md](CONTACT.md).
````

- [ ] **Step 4: Match the README to what the manual checks recorded**

The text above assumes every check it describes passed. Read the Result cells of `design/editing-checks.md` rows 15 (Pinch) and 16 (Trackpad rotate), `design/spike-results.md` rows 21 (every desktop Space), 22 (not on full-screen Spaces), 26 (Mission Control), 28 and 29 (Stage Manager), and `design/capture-checks.md` rows 6 (granting) and 8 (the system alert on the picker). Then apply exactly the cases that match; with every row passed, change nothing.

(a) Row 15 passed and row 16 didn't (`no rotate`, or anything other than the Expected cell):

```bash
python3 -I - <<'PY'
path = "README.md"
text = open(path, encoding="utf-8").read()
old = "- **Pinch or rotate** with two fingers on a trackpad.\n"
assert text.count(old) == 1, "the pinch line is not as Task 4 wrote it"
open(path, "w", encoding="utf-8").write(text.replace(old, "- **Pinch** with two fingers on a trackpad to resize it.\n"))
PY
```

(b) Row 16 passed and row 15 didn't (`no pinch`):

```bash
python3 -I - <<'PY'
path = "README.md"
text = open(path, encoding="utf-8").read()
old = "- **Pinch or rotate** with two fingers on a trackpad.\n"
assert text.count(old) == 1, "the pinch line is not as Task 4 wrote it"
open(path, "w", encoding="utf-8").write(text.replace(old, "- **Rotate** two fingers on a trackpad to turn it.\n"))
PY
```

(c) Neither row 15 nor row 16 passed (the corner knob is the only path, as M1's spike decision allows):

```bash
python3 -I - <<'PY'
path = "README.md"
text = open(path, encoding="utf-8").read()
old = "- **Pinch or rotate** with two fingers on a trackpad.\n"
assert text.count(old) == 1, "the pinch line is not as Task 4 wrote it"
open(path, "w", encoding="utf-8").write(text.replace(old, ""))
PY
```

(d) Row 28 or 29 didn't pass (Stage Manager):

```bash
python3 -I - <<'PY'
path = "README.md"
text = open(path, encoding="utf-8").read()
old = " They stay put with Stage Manager on, too."
assert text.count(old) == 1, "the Stage Manager sentence is not as Task 4 wrote it"
new = " Stage Manager isn't fully supported yet: with it on, stickers may not stay put or may not answer a double-click."
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
```

If that row's Decision cell in `design/spike-results.md` records a different limit than this sentence states, show Ethan both and use the wording he approves instead of `new`.

(e) Rows 21, 22 and 26 drove M2's window settings, and row 8 drove M4's picker; they should all read as passed by now. If any of them doesn't (for example row 8 says the picker closed when the alert was clicked), don't guess: stop, show Ethan the row and the README sentence it backs ("on every desktop Space" and "They join every desktop Space but stay off full-screen apps, and they stay put through Mission Control." for rows 21, 22 and 26; "answer it, and the picker is still there" for row 8), and write the sentence he approves. Row 6 needs nothing: the README's "If you've just turned it on and the panel is still there, click **Relaunch Stickermine**" holds whichever way it went.

- [ ] **Step 5: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/ReadmeTests
```

Expected: `Test run with 9 tests in 1 suite passed` and `** TEST SUCCEEDED **` (the README's two images, `docs/icon.png` and `docs/demo-still.jpg`, exist since Task 3).

- [ ] **Step 6: Check that no size slipped in**

```bash
grep -nEi '[0-9]+(\.[0-9]+)? ?(kb|mb|gb)\b|download size|installed size|no menu bar item' README.md || echo "README clean"
```

Expected: `README clean`.

- [ ] **Step 7: Commit**

```bash
git add README.md StickermineTests/ReadmeTests.swift
git commit -m "Add the README user guide" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: The website page

**Files:**
- Create: `docs/index.html`
- Test: `StickermineTests/SitePageTests.swift`

**Interfaces:**
- Consumes: `RepoFiles` (Task 1); `Updater.caskName: String`, `Updater.dmgURL: URL` (M6); `AboutLinks.website`, `.repo`, `.kofi: URL` (M6); `TutorialArt.bubbleText: String` (M6); `Bundle.main`'s `LSMinimumSystemVersion` (the root `Info.plist`, M1); the files from Tasks 2 and 3.
- Produces: `docs/index.html`, ported from `design/index.html`: the same stickers, layout and SVG art, with tokens as custom properties, self-hosted Fredoka, real links, the phone layout, Maple as a button whose bubble shows on hover, keyboard focus and tap, Pullcord's copy script, the demo still, and the github.io addresses. Its download line is `<span class="download-line">macOS 26+ · Apple Silicon · Free</span>` until Task 10 adds the size.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/SitePageTests.swift` (complete file):

```swift
import Foundation
import Testing
@testable import Stickermine

/// docs/index.html against spec sections 15 and 16 and the app's own
/// addresses. The page is one static file written in a fixed shape, so the
/// checks read its text.
@MainActor
struct SitePageTests {
    private func page() throws -> String { try RepoFiles.text("docs/index.html") }

    @Test func thePageLoadsNothingFromOtherSites() throws {
        let html = try page()
        for banned in ["googleapis", "gstatic", "@import", "<script src", "rel=\"stylesheet\"", "<iframe",
                       "url(http", "url(//", "srcset="] {
            #expect(!html.contains(banned), "\(banned)")
        }
        // Everything the page itself loads is a file beside it.
        let loaded = try RepoFiles.matches(#"\s(?:src|poster)="([^"]+)""#, in: html).map { $0[1] }
            + RepoFiles.matches(#"<link rel="(?:icon|apple-touch-icon|preload)"[^>]* href="([^"]+)""#, in: html).map { $0[1] }
            + RepoFiles.matches(#"url\("([^"]+)"\)"#, in: html).map { $0[1] }
        #expect(loaded.count >= 6)
        for path in loaded {
            #expect(!path.contains("//"), "\(path)")
            #expect(RepoFiles.exists("docs/" + path), "\(path)")
        }
        #expect(loaded.contains("fonts/Fredoka-latin.woff2"))
    }

    @Test func theColoursAreTheBrandTokens() throws {
        let html = try page()
        let root = try #require(try RepoFiles.matches(#":root \{([^}]*)\}"#, in: html).first?[1])
        let tokens = ["--bg": "#F3F0E8", "--ink": "#1F2340", "--blue": "#3D4BE0", "--mint": "#8FE3BE",
                      "--pink": "#FF4F81", "--yellow": "#FFD84D", "--border": "#FFFFFF"]
        for (name, hex) in tokens {
            #expect(root.contains("\(name): \(hex);"), "\(name)")
            #expect(html.contains("var(\(name))"), "\(name) is never used")
        }
        // The stickers' shadow (spec section 16).
        #expect(root.contains("--shadow: 0 10px 24px rgba(31, 35, 64, 0.22);"))
        #expect(html.contains(#"<meta name="color-scheme" content="light">"#))
        #expect(!html.contains("prefers-color-scheme"))
    }

    @Test func theCopyButtonCopiesExactlyTheVisibleCommand() throws {
        let html = try page()
        let copies = try RepoFiles.matches(#"data-copy="([^"]*)""#, in: html).map { $0[1] }
        let visible = try RepoFiles.matches(#"<code class="brew-command">([^<]*)</code>"#, in: html).map { $0[1] }
        #expect(copies == ["brew install --cask grokcodile/tap/\(Updater.caskName)"])
        #expect(visible == copies)
        #expect(html.contains(#"<button class="brew-copy" type="button" data-copy=""#))
        #expect(html.contains(#"aria-label="Copy install command""#))
        // Pullcord's script: writeText, the execCommand fallback, "Copied" for 1.6 s.
        for piece in [#"document.querySelectorAll(".brew-copy[data-copy]")"#, "navigator.clipboard.writeText(text)",
                      #"document.execCommand("copy")"#, #"btn.setAttribute("aria-label", "Copied");"#, "}, 1600);"] {
            #expect(html.contains(piece), "\(piece)")
        }
    }

    @Test func theDownloadPillIsTheLatestDMGWithoutAVersion() throws {
        let html = try page()
        #expect(try RepoFiles.matches(#"<a class="download" href="([^"]+)">"#, in: html).map { $0[1] }
                == [Updater.dmgURL.absoluteString])
        let lines = try RepoFiles.matches(#"<span class="download-line">([^<]*)</span>"#, in: html).map { $0[1] }
        #expect(lines.count == 1)
        let line = try #require(lines.first)
        let minimum = try #require(Bundle.main.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String)
        let major = String(minimum.split(separator: ".")[0])
        // "<size> download · " is added from the published DMG (M7 release
        // checklist); there is never a version number.
        let pattern = #"^(?:[0-9]+(?:\.[0-9])?&nbsp;(?:KB|MB) download · )?macOS "# + major + #"\+ · Apple Silicon · Free$"#
        #expect(try !RepoFiles.matches(pattern, in: line).isEmpty, "\(line)")
    }

    @Test func theFooterStickersAreInTheSpecsOrder() throws {
        let html = try page()
        let footer = try #require(try RepoFiles.matches(#"<footer class="footer">([\s\S]*?)</footer>"#, in: html).first?[1])
        let items = try RepoFiles.matches(#"<(?:span|a) class="(pill(?: coffee)?)"(?: href="([^"]*)")?[^>]*>([^<]*)</(?:span|a)>"#, in: footer)
        #expect(items.map { $0[3] } == ["© Stickermine", "GitHub", "Privacy", "Terms", "Contact", "☕️ Buy me a coffee"])
        let repo = AboutLinks.repo.absoluteString
        #expect(items.map { $0[2] } == ["", repo, repo + "/blob/main/PRIVACY.md", repo + "/blob/main/TERMS.md",
                                        repo + "/blob/main/CONTACT.md", AboutLinks.kofi.absoluteString])
        #expect(items.map { $0[1] } == ["pill", "pill", "pill", "pill", "pill", "pill coffee"])
    }

    @Test func theSiteAddressIsTheAppsWebsiteLink() throws {
        let html = try page()
        let site = AboutLinks.website.absoluteString
        #expect(site.hasSuffix("/"))
        #expect(try RepoFiles.matches(#"<link rel="canonical" href="([^"]+)">"#, in: html).map { $0[1] } == [site])
        #expect(try RepoFiles.matches(#"<meta property="og:url" content="([^"]+)">"#, in: html).map { $0[1] } == [site])
        #expect(try RepoFiles.matches(#"<meta property="og:image" content="([^"]+)">"#, in: html).map { $0[1] }
                == [site + "og.png"])
        let host = try #require(AboutLinks.website.host)
        if RepoFiles.exists("docs/CNAME") {
            // The bare domain, no newline, like the siblings' files.
            #expect(try RepoFiles.text("docs/CNAME") == host)
            #expect(site == "https://\(host)/")
        } else {
            // Until stickermine.app is bought and resolves, everything uses Pages' own address.
            #expect(site == "https://grokcodile.github.io/stickermine/")
        }
    }

    @Test func thereAreNoTooltipsOrPlaceholders() throws {
        let html = try page()
        #expect(try RepoFiles.matches(#"\stitle="#, in: html).isEmpty)
        // The page's own <title> only: an SVG <title> shows as a tooltip.
        #expect(html.components(separatedBy: "<title>").count - 1 == 1)
        #expect(!html.contains(##"href="#""##))
        #expect(try RepoFiles.matches(#">\s*\[[^\]<]*\]\s*<"#, in: html).isEmpty)
        #expect(!html.contains("DEMO VIDEO"))
        // The address lives in CONTACT.md only (the footer's Contact sticker).
        #expect(!html.contains("mailto:"))
    }

    @Test func phonesReducedMotionAndMapleFollowTheSpec() throws {
        let html = try page()
        #expect(html.contains(#"<meta name="viewport" content="width=device-width, initial-scale=1">"#))
        // Phones: 16 px gutters, and nothing wider than the screen.
        let phone = try #require(try RepoFiles.matches(#"@media \(max-width: 640px\) \{([\s\S]*?)\n\}"#, in: html).first?[1])
        #expect(phone.contains(".page { padding: 24px 16px 32px; gap: 32px; }"))
        #expect(phone.contains(".tagline { white-space: normal;"))
        #expect(phone.contains(".brew-command { font-size: 13px; padding: 10px 12px; overflow-wrap: anywhere; }"))
        #expect(html.contains("overflow-x: clip;"))
        // Two columns never squeeze the brief's 80 px title, nowrap description
        // or brew command: the left column is never narrower than they are.
        #expect(html.contains(".hero { grid-template-columns: minmax(min-content, 1fr) minmax(0, 1.4fr); }"))
        // The content is stacked above Maple, so her bubble can't cover it either.
        #expect(html.contains(".hero, .footer { position: relative; z-index: 6; pointer-events: none; }"))
        #expect(html.contains(".intro > *, .demo, .footer > * { pointer-events: auto; }"))
        #expect(html.contains("  z-index: 5;\n}\n.maple img {"))
        #expect(html.contains("@media (prefers-reduced-motion: reduce) {\n  .bubble { transition: none; }"))
        // Maple is fixed only inside the one media query that leaves her room,
        // and the page then keeps more room under the footer than she shows
        // (0.95 × her width + 40 px against 910 / 620 − 0.56 ≈ 0.91 × her width).
        #expect(html.components(separatedBy: "position: fixed").count - 1 == 1)
        let fixed = try #require(try RepoFiles.matches(#"@media \(min-width: 1200px\) and \(min-height: 740px\) \{([\s\S]*?)\n\}"#, in: html).first?[1])
        #expect(fixed.contains("position: fixed;"))
        #expect(fixed.contains("bottom: calc(var(--maple-w) * -0.56);"))
        #expect(fixed.contains(".page { padding-bottom: calc(var(--maple-w) * 0.95 + 40px); }"))
        // Her bubble: hover (only where there is hover), keyboard focus and a tap.
        #expect(html.contains("@media (hover: hover) {\n  .maple:hover .bubble {"))
        #expect(html.contains(".maple:focus-visible .bubble,\n.maple.is-talking .bubble {"))
        #expect(html.contains(#"maple.classList.toggle("is-talking");"#))
        #expect(html.contains(#"<button class="maple" type="button">"#))
    }

    @Test func mapleSaysWhatHerTutorialStickerSays() throws {
        let html = try page()
        #expect(html.contains(">\(TutorialArt.bubbleText)</text>"))
        #expect(html.contains("says: \(TutorialArt.bubbleText)</span>"))
        #expect(html.contains(#"<img src="dog.png" width="620" height="910" alt="Maple the dog">"#))
    }

    @Test func theDemoCardShowsTheStillOrAQuietLoop() throws {
        let html = try page()
        let demos = try RepoFiles.matches(#"<(img|video) class="demo-still"([^>]*)>"#, in: html)
        #expect(demos.count == 1)
        let demo = try #require(demos.first)
        let attributes = demo[2]
        #expect(attributes.contains(#"width="1600" height="1000""#))
        if demo[1] == "img" {
            #expect(attributes.contains(#"src="demo-still.jpg""#))
        } else {
            for needed in [" muted", " loop", " playsinline", #" poster="demo-still.jpg""#] {
                #expect(attributes.contains(needed), "\(needed)")
            }
            for banned in [" controls", " autoplay"] {
                #expect(!attributes.contains(banned), "\(banned)")
            }
        }
        // A loop plays only while reduced motion isn't requested.
        #expect(html.contains(#"var motion = window.matchMedia("(prefers-reduced-motion: reduce)");"#))
        #expect(html.contains("if (motion.matches) { demo.pause(); } else { demo.play().catch(function () {}); }"))
    }
}
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SitePageTests
```

Expected: all ten fail with `Caught error: … "The file “index.html” couldn’t be opened because there is no such file."`, then `Test run with 10 tests in 1 suite failed` and `** TEST FAILED **`.

- [ ] **Step 3: Write the page**

`docs/index.html` (complete file). What changed from the mock, and why: inline styles became classes on custom-property tokens; the Google Fonts link became a self-hosted `@font-face` (with a preload); the two-column hero became a grid that splits at 1080 px, whose left column never gets narrower than the brief's 80 px title, nowrap description and brew command (at 1080 px a plain 1 : 1.4 split leaves it 380 px, and "Stickermine" at 80 px is roughly 420 px wide on its own, so the mock's title would run into the demo card there); the h1 keeps the mock's `stroke-linejoin: round`; Maple is a `<button>` (so keyboard focus and taps reach her) placed after the footer, fixed to the corner only at 1200 × 740 and up with bottom padding that keeps every line clear of her, and the content is stacked above her so even her bubble passes under the stickers; the bubble's words are SVG text in Fredoka plus a visually hidden copy for screen readers; the 640 px rules give 16 px gutters and wrap the h1, the description, the download line and the brew command; the demo card shows `demo-still.jpg`; the download pill drops the version; the footer gains Terms; the copy button is Pullcord's `data-copy` script; a tap anywhere else puts Maple's bubble away through `pointerdown`, because iOS Safari sends no `click` for a tap on the page background.

```html
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Stickermine: fun stickers from quick screenshots</title>
<meta name="description" content="Turn quick screenshots into fun stickers that live on your desktop. A free, open-source Mac app.">
<meta name="color-scheme" content="light">
<link rel="canonical" href="https://grokcodile.github.io/stickermine/">
<meta property="og:type" content="website">
<meta property="og:title" content="Stickermine">
<meta property="og:description" content="Turn quick screenshots into fun stickers that live on your desktop.">
<meta property="og:url" content="https://grokcodile.github.io/stickermine/">
<meta property="og:image" content="https://grokcodile.github.io/stickermine/og.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:image:alt" content="The Stickermine pickaxe icon beside the name and the tagline">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" type="image/png" href="favicon.png">
<link rel="apple-touch-icon" href="icon.png">
<link rel="preload" href="fonts/Fredoka-latin.woff2" as="font" type="font/woff2" crossorigin>
<style>
/* Fredoka (SIL Open Font License, fonts/OFL.txt), served from this site:
   the page loads nothing from anyone else. */
@font-face {
  font-family: "Fredoka";
  font-style: normal;
  font-weight: 300 600;
  font-display: swap;
  src: url("fonts/Fredoka-latin.woff2") format("woff2");
}

/* Brand tokens (spec section 16). */
:root {
  --bg: #F3F0E8;
  --ink: #1F2340;
  --blue: #3D4BE0;
  --mint: #8FE3BE;
  --pink: #FF4F81;
  --yellow: #FFD84D;
  --border: #FFFFFF;
  --shadow: 0 10px 24px rgba(31, 35, 64, 0.22);
  --shadow-soft: 0 4px 10px rgba(31, 35, 64, 0.15);
  --font: "Fredoka", ui-rounded, system-ui, sans-serif;
  --mono: ui-monospace, Menlo, monospace;
  /* Maple's width; her bubble and the page's bottom room scale with it. */
  --maple-w: 240px;
}

body {
  margin: 0;
  overflow-x: hidden;
  overflow-x: clip;
  background: var(--bg);
  color: var(--ink);
  font-family: var(--font);
  -webkit-font-smoothing: antialiased;
}
a, button { -webkit-tap-highlight-color: transparent; }
a:hover, button:hover { filter: brightness(1.05); }
:focus-visible { outline: 3px solid var(--ink); outline-offset: 4px; }
.visually-hidden {
  position: absolute; width: 1px; height: 1px; margin: -1px; padding: 0;
  overflow: hidden; clip: rect(0 0 0 0); white-space: nowrap; border: 0;
}

.page {
  box-sizing: border-box;
  max-width: 1280px;
  min-height: 100vh;
  margin: 0 auto;
  padding: 48px 56px 32px;
  display: flex;
  flex-direction: column;
  gap: 40px;
}

/* ── hero: one column, two from 1080 px ─────────────────── */
.hero {
  flex-grow: 1;
  display: grid;
  grid-template-columns: minmax(0, 1fr);
  gap: 56px;
  align-items: start;
  padding-top: 16px;
}
.intro {
  min-width: 0;
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 32px;
}
.title { display: flex; flex-wrap: wrap; align-items: center; gap: 24px; }
.tile {
  flex: none;
  width: 128px; height: 128px;
  box-sizing: border-box;
  border: 8px solid var(--border);
  border-radius: 34px;
  background: var(--blue);
  display: flex; align-items: center; justify-content: center;
  transform: rotate(-4deg);
  box-shadow: var(--shadow);
}
.tile svg { width: 92%; height: 92%; }
h1 {
  margin: 0;
  font-size: 80px;
  font-weight: 600;
  line-height: 1;
  color: var(--blue);
  -webkit-text-stroke: 0.2em var(--border);
  paint-order: stroke fill;
  stroke-linejoin: round;
  filter: drop-shadow(0 8px 10px rgba(31, 35, 64, 0.25));
  transform: rotate(-2deg);
}
.tagline {
  margin: 0;
  width: fit-content;
  max-width: 100%;
  box-sizing: border-box;
  background: var(--mint);
  border: 10px solid var(--border);
  border-radius: 36px;
  padding: 18px 34px;
  font-size: clamp(18px, 1.7vw, 28px);
  line-height: 1.35;
  white-space: nowrap;
  transform: rotate(1.5deg);
  box-shadow: 0 10px 24px rgba(31, 35, 64, 0.18);
}
.install { display: flex; flex-wrap: wrap; align-items: flex-start; gap: 28px; max-width: 100%; }
.download {
  display: inline-flex; align-items: center; gap: 12px;
  background: var(--blue);
  color: #FFFFFF;
  border: 8px solid var(--border);
  border-radius: 44px;
  padding: 10px 32px 10px 24px;
  font-size: 24px; font-weight: 600;
  text-decoration: none;
  transform: rotate(-1.5deg);
  box-shadow: var(--shadow);
}
.download svg { flex: none; }
.download-text { display: flex; flex-direction: column; gap: 2px; }
.download-line { font-size: 14px; font-weight: 500; opacity: 0.85; }
.brew {
  display: flex; align-items: stretch;
  max-width: 100%;
  box-sizing: border-box;
  background: var(--ink);
  border: 8px solid var(--border);
  border-radius: 22px;
  overflow: hidden;
  transform: rotate(1deg);
  box-shadow: var(--shadow);
}
.brew-command {
  align-self: center;
  min-width: 0;
  padding: 12px 18px;
  color: #FFFFFF;
  font: 500 18px var(--mono);
}
.brew-copy {
  flex: none;
  display: flex; align-items: center; justify-content: center;
  width: 52px;
  background: transparent;
  color: #FFFFFF;
  border: 0;
  cursor: pointer;
}
.brew-copy svg { width: 24px; height: 24px; }
.brew-copy .ic-check { display: none; }
.brew-copy.copied .ic-copy { display: none; }
.brew-copy.copied .ic-check { display: block; }

/* The demo card: a white sticker with its bottom-right corner peeled up. */
.demo { margin: 0; min-width: 0; position: relative; padding-top: 44px; padding-bottom: 24px; }
.demo-sticker { position: relative; transform: rotate(-1.5deg); filter: drop-shadow(0 16px 18px rgba(31, 35, 64, 0.26)); }
.demo-card {
  box-sizing: border-box;
  background: #FFFFFF;
  border-radius: 44px;
  padding: 12px;
  -webkit-mask-image: linear-gradient(135deg, #000 calc(100% - 67.9px), transparent calc(100% - 67.9px));
  mask-image: linear-gradient(135deg, #000 calc(100% - 67.9px), transparent calc(100% - 67.9px));
}
.demo-still {
  display: block;
  width: 100%;
  height: auto;
  aspect-ratio: 16 / 10;
  object-fit: cover;
  border-radius: 32px;
  background: #23252F;
}
.peel { position: absolute; right: 0; bottom: 0; overflow: visible; filter: drop-shadow(-3px -3px 5px rgba(31, 35, 64, 0.30)); }

/* ── footer: pill stickers ─────────────────────────────── */
.footer { display: flex; flex-wrap: wrap; align-items: center; gap: 14px; font-size: 16px; }
.pill {
  background: #FFFFFF;
  border-radius: 999px;
  padding: 8px 18px;
  color: var(--ink);
  text-decoration: none;
  box-shadow: var(--shadow-soft);
}
.pill.coffee { background: var(--yellow); font-weight: 500; }

/* The content sits above Maple, so neither she nor her bubble can ever
   cover it; the containers let the pointer through to her where they are
   empty, and only their stickers take clicks. */
.hero, .footer { position: relative; z-index: 6; pointer-events: none; }
.intro > *, .demo, .footer > * { pointer-events: auto; }

/* ── Maple ──────────────────────────────────────────────── */
/* She sits after the footer, so she never covers anything. Only where the
   two-column hero leaves her room beside the footer and below the demo card
   (1200 × 740 and up) is she fixed to the bottom-right corner, peeking up
   from below the fold; the page then keeps enough room at the bottom for
   every line to scroll clear of her. */
.maple {
  position: relative;
  align-self: flex-end;
  flex: none;
  width: var(--maple-w);
  margin: 72px 0 0;
  padding: 0;
  border: 0;
  background: none;
  font: inherit;
  color: inherit;
  cursor: pointer;
  z-index: 5;
}
.maple img {
  display: block;
  width: 100%;
  height: auto;
  transform: rotate(3deg);
  transform-origin: 50% 100%;
  filter: drop-shadow(0 8px 14px rgba(31, 35, 64, 0.30));
}
/* The bubble's right end touches her mouth (spec: 322 × 44 at 315 px wide). */
.bubble {
  position: absolute;
  right: calc(100% - var(--maple-w) * 26 / 315);
  top: calc(var(--maple-w) * 80 / 315);
  width: calc(var(--maple-w) * 362 / 315);
  pointer-events: none;
  opacity: 0;
  transform: translateY(8px) rotate(-3deg) scale(0.88);
  transform-origin: 100% 100%;
  transition: opacity 0.15s ease, transform 0.22s cubic-bezier(0.3, 1.5, 0.5, 1);
  filter: drop-shadow(0 6px 8px rgba(31, 35, 64, 0.2));
}
.bubble svg { display: block; width: 100%; height: auto; overflow: visible; }
.bubble-rim { fill: var(--border); stroke: var(--border); stroke-width: 16; stroke-linejoin: round; }
.bubble-fill { fill: var(--pink); }
.bubble text { fill: #FFFFFF; font-family: var(--font); font-size: 18px; font-weight: 500; }
.maple:focus-visible .bubble,
.maple.is-talking .bubble { opacity: 1; transform: translateY(0) rotate(-2deg) scale(0.96); }
@media (hover: hover) {
  .maple:hover .bubble { opacity: 1; transform: translateY(0) rotate(-2deg) scale(0.96); }
}

@media (min-width: 1080px) {
  /* The left column never gets narrower than its widest unbreakable line
     (the 80 px title, the nowrap description, the brew command's long word);
     near 1080 px the demo card gives up the difference. */
  .hero { grid-template-columns: minmax(min-content, 1fr) minmax(0, 1.4fr); }
}
@media (min-width: 1200px) and (min-height: 740px) {
  :root { --maple-w: clamp(200px, min(28vh, 22vw), 315px); }
  .page { padding-bottom: calc(var(--maple-w) * 0.95 + 40px); }
  .maple {
    position: fixed;
    right: 4vw;
    bottom: calc(var(--maple-w) * -0.56);
    margin: 0;
  }
}

/* ── phones ─────────────────────────────────────────────── */
@media (max-width: 640px) {
  :root { --maple-w: 180px; }
  .page { padding: 24px 16px 32px; gap: 32px; }
  .hero { gap: 40px; padding-top: 8px; }
  .intro { gap: 28px; }
  .title { gap: 16px; }
  .tile { width: 88px; height: 88px; border-radius: 24px; border-width: 6px; }
  h1 { font-size: clamp(44px, 13vw, 64px); }
  .tagline { white-space: normal; font-size: 18px; padding: 14px 22px; border-width: 8px; border-radius: 28px; }
  .download { font-size: 20px; padding: 8px 24px 8px 18px; }
  .download-line { white-space: normal; }
  .brew-command { font-size: 13px; padding: 10px 12px; overflow-wrap: anywhere; }
  .brew-copy { width: 44px; }
  .demo { padding-top: 8px; }
  /* A smaller peel: the mask's cut moves with it (its legs are 96/140 of the box). */
  .demo-card {
    border-radius: 30px;
    padding: 8px;
    -webkit-mask-image: linear-gradient(135deg, #000 calc(100% - 46.5px), transparent calc(100% - 46.5px));
    mask-image: linear-gradient(135deg, #000 calc(100% - 46.5px), transparent calc(100% - 46.5px));
  }
  .demo-still { border-radius: 22px; }
  .peel { width: 96px; height: 96px; }
  .footer { gap: 10px; font-size: 15px; }
  .maple { align-self: center; margin-top: 96px; }
  .bubble { right: auto; left: 50%; top: -64px; width: min(300px, calc(100vw - 32px)); margin-left: max(-150px, calc(16px - 50vw)); }
}

@media (prefers-reduced-motion: reduce) {
  .bubble { transition: none; }
}
</style>
</head>
<body>
<svg width="0" height="0" style="position: absolute" aria-hidden="true">
<defs>
<filter id="sh" x="-20%" y="-20%" width="140%" height="150%">
<feDropShadow dx="0" dy="4" stdDeviation="4" flood-color="#000000" flood-opacity="0.3"></feDropShadow>
</filter>
<symbol id="pick" viewBox="0 0 200 200">
<g transform="translate(91.1 108.4) rotate(40) scale(1.05) translate(-100 -117)">
<g filter="url(#sh)" fill="#FFFFFF" stroke="#FFFFFF" stroke-width="20" stroke-linejoin="round">
<path d="M16 104 Q40 70 84 62 L116 62 Q142 62 166 66 L172 90 Q142 84 116 84 L84 84 Q44 84 16 104Z"></path>
<rect x="84" y="58" width="32" height="30" rx="6"></rect>
<rect x="90" y="40" width="20" height="148" rx="9"></rect>
</g>
<rect x="90" y="40" width="20" height="148" rx="9" fill="#E8963A"></rect>
<rect x="94" y="100" width="5" height="80" rx="2.5" fill="#F6B76B"></rect>
<path d="M16 104 Q40 70 84 62 L116 62 Q142 62 166 66 L172 90 Q142 84 116 84 L84 84 Q44 84 16 104Z" fill="#D3DCE5" stroke="#7B8794" stroke-width="4" stroke-linejoin="round"></path>
<path d="M30 97 Q54 74 84 68" fill="none" stroke="#FFFFFF" stroke-width="4" stroke-linecap="round" opacity="0.85"></path>
<rect x="84" y="58" width="32" height="30" rx="6" fill="#5B6572"></rect>
<rect x="84" y="70" width="32" height="5" fill="#434B57"></rect>
</g>
</symbol>
</defs>
</svg>

<div class="page">
  <main class="hero">
    <div class="intro">
      <div class="title">
        <div class="tile"><svg role="img" aria-label="Stickermine pickaxe icon"><use href="#pick"></use></svg></div>
        <h1>Stickermine</h1>
      </div>
      <p class="tagline">Turn quick screenshots into fun<br>stickers that live on your desktop.</p>
      <div class="install">
        <a class="download" href="https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg">
          <svg aria-hidden="true" width="28" height="28" viewBox="0 0 24 24" fill="none" stroke="#FFFFFF" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3 V15"></path><path d="M6.5 10.5 L12 16 L17.5 10.5"></path><path d="M5 20.5 H19"></path></svg>
          <span class="download-text"><span>Download for Mac</span><span class="download-line">macOS 26+ · Apple Silicon · Free</span></span>
        </a>
        <div class="brew">
          <code class="brew-command">brew install --cask grokcodile/tap/stickermine</code>
          <button class="brew-copy" type="button" data-copy="brew install --cask grokcodile/tap/stickermine" aria-label="Copy install command">
            <svg class="ic-copy" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2.5"></rect><path d="M5 15 V6.5 A2.5 2.5 0 0 1 7.5 4 H15"></path></svg>
            <svg class="ic-check" aria-hidden="true" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5 L10 17.5 L19 7"></path></svg>
          </button>
        </div>
      </div>
    </div>
    <figure class="demo">
      <div class="demo-sticker">
        <div class="demo-card">
          <img class="demo-still" src="demo-still.jpg" width="1600" height="1000" alt="A Mac desktop with stickers on it: two note cards, the Stickermine pickaxe and Maple the dog">
        </div>
        <svg class="peel" aria-hidden="true" width="140" height="140" viewBox="-140 -140 140 140"><defs><linearGradient id="flapg" gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="-48" y2="-48"><stop offset="0" stop-color="#FFFFFF"></stop><stop offset="0.55" stop-color="#F4F5F9"></stop><stop offset="1" stop-color="#BFC5D6"></stop></linearGradient></defs><path transform="matrix(0 -1 -1 0 -96 -96)" d="M -96 0 L -44 0 A 44 44 0 0 0 0 -44 L 0 -96 Z" fill="url(#flapg)"></path></svg>
      </div>
    </figure>
  </main>

  <footer class="footer">
    <span class="pill">© Stickermine</span>
    <a class="pill" href="https://github.com/grokcodile/stickermine">GitHub</a>
    <a class="pill" href="https://github.com/grokcodile/stickermine/blob/main/PRIVACY.md">Privacy</a>
    <a class="pill" href="https://github.com/grokcodile/stickermine/blob/main/TERMS.md">Terms</a>
    <a class="pill" href="https://github.com/grokcodile/stickermine/blob/main/CONTACT.md">Contact</a>
    <a class="pill coffee" href="https://ko-fi.com/grokcodile" target="_blank" rel="noopener">☕️ Buy me a coffee</a>
  </footer>

  <button class="maple" type="button">
    <img src="dog.png" width="620" height="910" alt="Maple the dog">
    <span class="bubble">
      <svg viewBox="-20 -20 362 114" aria-hidden="true"><path class="bubble-rim" d="M 18 0 H 304 C 314 0 322 8 322 18 V 26 C 322 32 317 36 310 39 C 313 46 316 52 322 58 C 323 60 321 62 319 61 C 307 57 299 51 294 44 H 18 C 8 44 0 36 0 26 V 18 C 0 8 8 0 18 0 Z"></path><path class="bubble-fill" d="M 18 0 H 304 C 314 0 322 8 322 18 V 26 C 322 32 317 36 310 39 C 313 46 316 52 322 58 C 323 60 321 62 319 61 C 307 57 299 51 294 44 H 18 C 8 44 0 36 0 26 V 18 C 0 8 8 0 18 0 Z"></path><text x="161" y="28.5" text-anchor="middle">Make your desktop make you smile!</text></svg>
      <span class="visually-hidden">says: Make your desktop make you smile!</span>
    </span>
  </button>
</div>

<script>
(function () {
  // The Homebrew sticker's copy button (Pullcord's): the command comes from
  // data-copy, which matches the visible text; writeText, with execCommand
  // for browsers that refuse it; "Copied" for 1.6 s with the checkmark.
  function fallbackCopy(text) {
    var ta = document.createElement("textarea");
    ta.value = text;
    ta.setAttribute("readonly", "");
    ta.style.position = "absolute";
    ta.style.left = "-9999px";
    document.body.appendChild(ta);
    ta.select();
    try { document.execCommand("copy"); } catch (e) {}
    document.body.removeChild(ta);
  }
  document.querySelectorAll(".brew-copy[data-copy]").forEach(function (btn) {
    var label = btn.getAttribute("aria-label") || "Copy command";
    var timer;
    btn.addEventListener("click", function () {
      var text = btn.getAttribute("data-copy");
      var flash = function () {
        btn.classList.add("copied");
        btn.setAttribute("aria-label", "Copied");
        clearTimeout(timer);
        timer = setTimeout(function () {
          btn.classList.remove("copied");
          btn.setAttribute("aria-label", label);
        }, 1600);
      };
      if (navigator.clipboard && navigator.clipboard.writeText) {
        navigator.clipboard.writeText(text).then(flash).catch(function () {
          fallbackCopy(text); flash();
        });
      } else {
        fallbackCopy(text); flash();
      }
    });
  });

  // Maple's bubble: hover and keyboard focus show it (CSS); a tap or click
  // toggles it, and a tap anywhere else puts it away.
  var maple = document.querySelector(".maple");
  if (maple) {
    maple.addEventListener("click", function (event) {
      event.stopPropagation();
      maple.classList.toggle("is-talking");
    });
    // pointerdown, not click: iOS Safari sends no click for a tap on the
    // page background when only the document listens.
    document.addEventListener("pointerdown", function (event) {
      if (!maple.contains(event.target)) { maple.classList.remove("is-talking"); }
    });
  }

  // The demo card: once the recorded loop replaces the still, it plays muted
  // and looping only while reduced motion isn't requested; a click plays or
  // pauses it either way.
  var demo = document.querySelector("video.demo-still");
  if (demo) {
    var motion = window.matchMedia("(prefers-reduced-motion: reduce)");
    var follow = function () {
      if (motion.matches) { demo.pause(); } else { demo.play().catch(function () {}); }
    };
    demo.muted = true;
    follow();
    motion.addEventListener("change", follow);
    demo.addEventListener("click", function () {
      if (demo.paused) { demo.play().catch(function () {}); } else { demo.pause(); }
    });
  }
})();
</script>
</body>
</html>
```

- [ ] **Step 4: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SitePageTests
```

Expected: `Test run with 10 tests in 1 suite passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add docs/index.html StickermineTests/SitePageTests.swift
git commit -m "Add the website, ported from the design mock" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: The site check script

**Files:**
- Create: `design/check-site.sh`

**Interfaces:**
- Consumes: `docs/index.html` (Task 5), `README.md` (Task 4), `PRIVACY.md`, `TERMS.md`, `CONTACT.md` (Task 1), `/usr/bin/python3` and `curl`.
- Produces: `design/check-site.sh [--release | --publish] [--online]`: exit 0 and `check-site: OK` when the page's structure and every local link are sound (and, with `--release`, CONTACT.md has an address; with `--publish`, also the download line has a size); exit 1 with one `problem:` line each otherwise. Always lists the absolute links; `--online` adds each one's final HTTP status. Tasks 9–11 run it as the release gates.

- [ ] **Step 1: Run the check that must fail now**

```bash
bash design/check-site.sh; echo "exit=$?"
```

Expected: `bash: design/check-site.sh: No such file or directory` and `exit=127`.

- [ ] **Step 2: Write the script**

`design/check-site.sh` (complete file). macOS has no current HTML5 validator built in, so the structure check uses Python's own HTML parser:

```bash
#!/bin/bash
# Checks the website and the repo's documents (M7):
#
# 1. docs/index.html's structure, with Python's own HTML parser (the
#    /usr/bin/tidy that came with older macOS releases predates HTML5):
#    one doctype, lang, title, main and h1; every non-void element closed in
#    order; unique ids, and every #id the page points at exists; every img
#    has alt, width and height; every button a type; no title attributes
#    (the page never shows tooltips); target="_blank" links carry rel=noopener.
# 2. Every relative link in README.md, PRIVACY.md, TERMS.md, CONTACT.md and
#    docs/index.html points at a file that exists.
# 3. --release (before tagging a release): CONTACT.md gives an email address.
#    --publish (before the site goes live, implies --release): the download
#    line also states the size of the published Stickermine.dmg.
# 4. --online: every absolute link in those files is fetched (GET of the
#    first KB, redirects followed) and its final HTTP status printed.
#    Statuses are reported, not judged: which ones are 200 depends on how far
#    the release has got (see the M7 plan's link list).
#
# Usage: design/check-site.sh [--release | --publish] [--online]
set -euo pipefail

cd "$(dirname "$0")/.."
/usr/bin/python3 -I - "$@" <<'PY'
import html.parser
import os
import re
import subprocess
import sys

args = sys.argv[1:]
online = "--online" in args
publish = "--publish" in args
release = publish or "--release" in args
problems = []
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "source", "track", "wbr"}


class Page(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.ids = {}
        self.refs = []
        self.counts = {}
        self.doctype = None
        self.lang = None
        self.links = []

    def handle_decl(self, decl):
        self.doctype = decl

    def element(self, tag, attrs, closes_itself):
        a = dict(attrs)
        line = self.getpos()[0]
        self.counts[tag] = self.counts.get(tag, 0) + 1
        if tag == "html":
            self.lang = a.get("lang")
        if "id" in a:
            if a["id"] in self.ids:
                problems.append(f"index.html:{line}: duplicate id {a['id']!r}")
            self.ids[a["id"]] = line
        if "title" in a:
            problems.append(f"index.html:{line}: title attribute on <{tag}> (the page has no tooltips)")
        if tag == "img":
            for need in ("alt", "width", "height"):
                if need not in a:
                    problems.append(f"index.html:{line}: <img> without {need}")
        if tag == "button" and "type" not in a:
            problems.append(f"index.html:{line}: <button> without type")
        if tag == "a" and a.get("target") == "_blank" and "noopener" not in (a.get("rel") or ""):
            problems.append(f"index.html:{line}: target=_blank without rel=noopener")
        for key in ("href", "src", "poster", "content"):
            value = a.get(key)
            if not value:
                continue
            if value.startswith("#"):
                self.refs.append((line, value[1:]))
            elif key != "content" or value.startswith("http"):
                self.links.append((line, value))
        for key in ("filter", "fill", "mask", "clip-path"):
            m = re.match(r"url\(#([^)]+)\)", a.get(key) or "")
            if m:
                self.refs.append((line, m.group(1)))
        if not closes_itself and tag not in VOID:
            self.stack.append((tag, line))

    def handle_starttag(self, tag, attrs):
        self.element(tag, attrs, False)

    def handle_startendtag(self, tag, attrs):
        self.element(tag, attrs, True)

    def handle_endtag(self, tag):
        line = self.getpos()[0]
        if tag in VOID:
            return
        if not self.stack:
            problems.append(f"index.html:{line}: </{tag}> with nothing open")
            return
        open_tag, open_line = self.stack.pop()
        if open_tag != tag:
            problems.append(f"index.html:{line}: </{tag}> closes <{open_tag}> from line {open_line}")


with open("docs/index.html", encoding="utf-8") as fh:
    source = fh.read()
page = Page()
page.feed(source)
page.close()
if (page.doctype or "").lower() != "doctype html":
    problems.append("index.html: the first thing must be <!doctype html>")
if page.lang != "en":
    problems.append("index.html: <html> needs lang=\"en\"")
for tag in ("title", "main", "h1"):
    if page.counts.get(tag) != 1:
        problems.append(f"index.html: {page.counts.get(tag, 0)} <{tag}> elements, expected 1")
for tag, line in page.stack:
    problems.append(f"index.html:{line}: <{tag}> is never closed")
for line, ref in page.refs:
    if ref not in page.ids:
        problems.append(f"index.html:{line}: #{ref} points at no element")
for m in re.finditer(r'url\("?([^")#][^")]*)"?\)', source):
    page.links.append((source.count("\n", 0, m.start()) + 1, m.group(1)))

absolute = {}


def note(path, line, target):
    if re.match(r"^[a-z]+:", target):
        if target.startswith("http"):
            absolute.setdefault(target, f"{path}:{line}")
        return
    file = target.split("#")[0]
    if not file:
        return
    full = os.path.normpath(os.path.join(os.path.dirname(path), file))
    if not os.path.exists(full):
        problems.append(f"{path}:{line}: {target} does not exist")


for line, target in page.links:
    note("docs/index.html", line, target)
for doc in ("README.md", "PRIVACY.md", "TERMS.md", "CONTACT.md"):
    if not os.path.exists(doc):
        problems.append(f"{doc} is missing")
        continue
    with open(doc, encoding="utf-8") as fh:
        for number, text in enumerate(fh, 1):
            for m in re.finditer(r"\]\(([^)\s]+)\)", text):
                note(doc, number, m.group(1))
            for m in re.finditer(r'<img src="([^"]+)"', text):
                note(doc, number, m.group(1))

if release and os.path.exists("CONTACT.md"):
    with open("CONTACT.md", encoding="utf-8") as fh:
        contact = fh.read()
    if not re.search(r"^- \*\*Email:\*\* \[([^\]\s@]+@[^\]\s]+)\]\(mailto:\1\)$", contact, re.M):
        problems.append("CONTACT.md: no email address yet (Ethan gives it before the first release)")
if publish:
    m = re.search(r'<span class="download-line">([^<]*)</span>', source)
    if not m or not re.match(r"^[0-9]+(?:\.[0-9])?&nbsp;(?:KB|MB) download · ", m.group(1)):
        problems.append("index.html: the download line has no size yet (measure the release's Stickermine.dmg)")

for p in problems:
    print("problem:", p)
print(f"{len(absolute)} absolute links:")
for url in sorted(absolute):
    if online:
        result = subprocess.run(["curl", "-sS", "-o", "/dev/null", "-L", "-r", "0-1023", "--max-time", "20",
                                 "-A", "Mozilla/5.0 (Macintosh) check-site", "-w", "%{http_code}", url],
                                capture_output=True, text=True)
        status = result.stdout.strip() or "error"
        print(f"  {status}  {url}  ({absolute[url]})")
    else:
        print(f"  {url}  ({absolute[url]})")
if problems:
    print(f"check-site: {len(problems)} problem(s)")
    sys.exit(1)
print("check-site: OK")
PY
```

- [ ] **Step 3: Run it**

```bash
chmod +x design/check-site.sh
./design/check-site.sh; echo "exit=$?"
./design/check-site.sh --release | grep -E '^(problem|check-site)'
```

Expected from the first command: `21 absolute links:`, then these 21, one per line with the file and line that holds each (in this order):

```text
https://docs.github.com/en/site-policy/privacy-policies/github-general-privacy-statement
https://github.com/grokcodile
https://github.com/grokcodile/homebrew-tap
https://github.com/grokcodile/stickermine
https://github.com/grokcodile/stickermine/blob/main/CONTACT.md
https://github.com/grokcodile/stickermine/blob/main/PRIVACY.md
https://github.com/grokcodile/stickermine/blob/main/TERMS.md
https://github.com/grokcodile/stickermine/issues
https://github.com/grokcodile/stickermine/releases
https://github.com/grokcodile/stickermine/releases/latest
https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg
https://grokcodile.github.io/stickermine/
https://grokcodile.github.io/stickermine/og.png
https://img.shields.io/badge/Homebrew-grokcodile%2Ftap-C9782E?logo=homebrew&logoColor=white
https://img.shields.io/badge/License-MIT-blue
https://img.shields.io/badge/macOS-26%2B-111111
https://img.shields.io/github/downloads/grokcodile/stickermine/total
https://img.shields.io/github/v/release/grokcodile/stickermine?sort=semver&label=release
https://ko-fi.com/grokcodile
https://www.linkedin.com/in/ethandarling/
https://www.reddit.com/user/grokcodile
```

then `check-site: OK` and `exit=0`. The second prints `problem: CONTACT.md: no email address yet (Ethan gives it before the first release)` and `check-site: 1 problem(s)`: the release gate works, and stays shut until Task 9 fills in the address.

- [ ] **Step 4: Prove the structure check catches a broken page**

```bash
T=$(mktemp -d) && mkdir -p "$T/design" "$T/docs" && cp design/check-site.sh "$T/design/" && cp -R docs/. "$T/docs/" && cp README.md PRIVACY.md TERMS.md CONTACT.md LICENSE "$T/" \
  && sed -i '' 's#<span class="pill">© Stickermine</span>#<span class="pill" title="tip">© Stickermine#' "$T/docs/index.html" \
  && "$T/design/check-site.sh" | grep -E '^problem|^check-site'; rm -rf "$T"
```

Expected, exactly:

```text
problem: index.html:381: title attribute on <span> (the page has no tooltips)
problem: index.html:387: </footer> closes <span> from line 381
problem: index.html:396: </div> closes <footer> from line 380
problem: index.html:471: </body> closes <div> from line 348
problem: index.html:472: </html> closes <body> from line 324
problem: index.html:2: <html> is never closed
check-site: 6 problem(s)
```

- [ ] **Step 5: Commit**

```bash
git add design/check-site.sh
git commit -m "Add the website and documents check" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

**The link list, for `--online` runs (Task 10 Step 13 and Task 11):** what each address is expected to return at each stage. `check-site.sh` prints statuses and doesn't judge them, because they depend on how far the release has got.

| Address | Before the repo is public | Public, before `v1.0` | After `v1.0` | After Pages |
|---|---|---|---|---|
| `github.com/grokcodile/stickermine`, `…/issues`, `…/releases`, `…/blob/main/{PRIVACY,TERMS,CONTACT}.md` | 404 | 200 | 200 | 200 |
| `…/releases/latest` | 404 | 200 (an empty releases page) | 200 | 200 |
| `…/releases/latest/download/Stickermine.dmg` | 404 | 404 | 206 or 200 (the DMG; only its first KB is fetched) | same |
| `grokcodile.github.io/stickermine/` and `…/og.png` | 404 | 404 | 404 | 200 |
| `github.com/grokcodile`, `github.com/grokcodile/homebrew-tap`, `docs.github.com/…` | 200 | 200 | 200 | 200 |
| `img.shields.io/…` (README badges) | 200 (the badge says "repo not found" until public) | 200 | 200 | 200 |
| `ko-fi.com/grokcodile`, `reddit.com/user/grokcodile`, `linkedin.com/in/ethandarling/` | 200, or 403/429/999 from their bot protection; open them in a browser instead | same | same | same |

---

### Task 7: The page in a browser (Ethan at the Mac)

**Files:**
- Create: `design/site-checks.md`

**Interfaces:**
- Consumes: everything in `docs/` (Tasks 2, 3 and 5), `design/check-site.sh` (Task 6).
- Produces: `design/site-checks.md` with every row's result: the evidence for what the tests can't see (fonts actually used, layout, Maple's position while scrolling, hover, focus, taps, reduced motion, the clipboard).

- [ ] **Step 1: Check the page and run the site suites**

```bash
./design/check-site.sh | tail -1
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SitePageTests -only-testing:StickermineTests/SiteImagesTests -only-testing:StickermineTests/SiteFontTests
```

Expected: `check-site: OK`, then `Test run with 18 tests in 3 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 2: Write the checklist**

`design/site-checks.md` (complete file; the Result cells start empty):

```markdown
# Website checks (M7)

`docs/index.html` in a real browser: what the tests can't see (the font actually used, layout at real widths, Maple while scrolling, hover, keyboard focus, taps, reduced motion, the clipboard). An agent executing the plan asks Ethan to do each action, or does it in Safari itself if Ethan says so, and writes down exactly what was seen; it never fills in a Result nobody looked at. Rows that can't be run get `not run: <reason>`.

## Setup

1. In a terminal at the repository root, serve the site the way GitHub Pages will (same-origin HTTP, so the font loads as it will online): `/usr/bin/python3 -m http.server 8000 --bind 127.0.0.1 --directory docs`. Leave it running; Ctrl-C stops it after the last row.
2. Ethan ticks "Show features for web developers" in Safari › Settings › Advanced himself (his choice; he notes the old value and restores it afterwards). The agent never changes Safari's or the system's settings.
3. Open `http://127.0.0.1:8000/` in Safari. Develop › Show Web Inspector (⌥⌘I) for the Network, Elements and Console rows; Develop › Enter Responsive Design Mode (⌥⌘R) for the sized rows, typing the width and height into its size fields.

| Field | Value |
|---|---|
| Date | |
| macOS (`sw_vers -productVersion`), Safari version | |
| Display (resolution, scale) | |

## Checks

| # | Check | How | Expected | Result |
|---|---|---|---|---|
| 1 | Nothing from other sites | Network tab, then reload (⌘R). | Every request goes to `127.0.0.1:8000`: `index.html`, `fonts/Fredoka-latin.woff2`, `favicon.png`, `dog.png`, `demo-still.jpg` (and `icon.png` if Safari asks for the touch icon). None to `fonts.googleapis.com`, `fonts.gstatic.com` or any other host. The Console shows no errors. | |
| 2 | The font | Elements: select the h1, then the Font panel in the sidebar. Repeat for the mint description and a footer pill. | "Fredoka" is the font used for all three (semibold for the h1); nothing falls back to the system font. | |
| 3 | Desktop layout | Responsive Design Mode at 1440 × 900. | Left column: the blue pickaxe tile (white border, tilted left) with "Stickermine" in blue with a thick white outline; the mint description in two lines; the blue Download pill reading "Download for Mac" over "macOS 26+ · Apple Silicon · Free" (no version); the dark Homebrew sticker with `brew install --cask grokcodile/tap/stickermine` and a copy icon. Right column: the white demo card with the desktop still and its bottom-right corner peeled up, no play button, no bracketed text. Every sticker slightly rotated. | |
| 4 | Maple at 1440 × 900 | Same size. Look at the bottom right, then scroll slowly to the end and back. | Maple peeks up from the bottom-right corner and stays there while the page scrolls. At no scroll position does she cover a footer pill, the demo card or any other sticker; at the end, the footer sits fully above her. | |
| 5 | Her bubble | Hover Maple. Move away. | The pink bubble "Make your desktop make you smile!" pops up beside her mouth with a small spring, and goes when the pointer leaves. Nothing on the page shows a tooltip. | |
| 6 | 1280 × 800 | Resize to 1280 × 800, scroll to the top, hover Maple. | Maple is still fixed in the corner; where her bubble reaches the footer row, the ☕️ Buy me a coffee pill stays fully visible on top of it. | |
| 7 | 1199 × 900 | Resize to 1199 × 900 and scroll to the end. | Maple is no longer fixed: she sits after the footer at the right, scrolls with the page, and nothing is under her. The hero is still two columns above 1080 px wide. | |
| 7b | 1080 × 800 | Resize to 1080 × 800. | Two columns; "Stickermine" with its white outline stays inside the left column, clear of the demo card; both lines of the mint description stay inside its card; the brew command stays inside the dark sticker. | |
| 7c | 700 × 900 | Resize to 700 × 900; in the Console run `document.documentElement.scrollWidth`. | One column at desktop sizes; prints `700` (no sideways overflow); Maple sits after the footer, not fixed, covering nothing. | |
| 8 | Keyboard | Click the page background, then press Tab repeatedly (in Safari, Option-Tab if plain Tab skips links). | Focus moves Download → copy button → GitHub → Privacy → Terms → Contact → Buy me a coffee → Maple, each with a visible dark outline. On Maple the bubble shows; Shift-Tab back hides it. | |
| 9 | Copy | Click the copy button; within a second select the button in Elements and read its `aria-label`; wait 2 s and read it again. Paste into TextEdit. | A white checkmark replaces the copy icon for about 1.6 s, then the icon returns. The label reads "Copied" during the checkmark and "Copy install command" after. TextEdit gets exactly `brew install --cask grokcodile/tap/stickermine`. | |
| 10 | Hover brightening | Hover the Download pill, the copy button and each footer pill. | Each brightens slightly; none shows a tooltip. | |
| 11 | Reduced motion | In Web Inspector's Elements tab, open User Preference Overrides and set Reduced motion to Reduce, hover Maple, then set it back to System. (Or Ethan turns System Settings › Accessibility › Display › Reduce motion on and off himself; the agent never changes system settings.) | The bubble appears at once without the pop and spring. | |
| 12 | Links | Hover each footer pill and the Download pill and read the address in Safari's status bar (View › Show Status Bar). | GitHub → `https://github.com/grokcodile/stickermine`; Privacy, Terms, Contact → `…/blob/main/PRIVACY.md`, `TERMS.md`, `CONTACT.md`; Buy me a coffee → `https://ko-fi.com/grokcodile`; Download → `https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg`. (Don't click Download before v1.0 exists: it is a 404 until then.) | |
| 13 | Link preview tags | Develop › Show Page Source (⌥⌘U); find the `og:` lines. | `og:image` is `https://grokcodile.github.io/stickermine/og.png`, `og:url` and `canonical` are `https://grokcodile.github.io/stickermine/`; no `CNAME` file in `docs/`. | |
| 14 | Phone, 375 × 812 | Responsive Design Mode at 375 × 812. Try to scroll sideways; in the Console run `document.documentElement.scrollWidth`. Select `.page` in Elements and read its padding. | No sideways scrolling; the Console prints `375`; the page's left and right padding are 16 px. The tile and h1 are smaller with the white outline intact; the description wraps inside its card; the Download line is readable; the brew command wraps inside the dark sticker with the copy button still at its right; the demo card fills the width with a smaller peel; the footer pills wrap onto rows; Maple sits after the footer, centred, not fixed, and nothing is hidden under her. | |
| 15 | Phone tap | Still at 375 × 812, click Maple, move the pointer onto the empty background without clicking, then click the background. | After the click the bubble shows above her head, inside the screen edges, and stays while the pointer is away from her; the click on the background hides it. | |
| 16 | 320 × 640 | Resize to 320 × 640 and repeat row 14's sideways scroll and Console check. | No sideways scrolling; the Console prints `320`; nothing overlaps. | |
| 17 | The two drawn images | Open `http://127.0.0.1:8000/og.png` and `http://127.0.0.1:8000/demo-still.jpg`. | `og.png`: 1200 × 630, the tile left, "Stickermine" in Fredoka with its white outline and the mint tagline card right, nothing clipped. `demo-still.jpg`: the desktop with the two tutorial cards, the tile and Maple. | |

## Outcome

Fill this in once every row has a result: which rows failed, what was fixed (with the commit), and which rows were not run and why.
```

- [ ] **Step 3: Run the checks**

MANUAL VERIFICATION: ask Ethan to do the Setup and rows 1–17 (with 7b and 7c after row 7) in order (or do them yourself in Safari if Ethan says so), and write in each Result cell exactly what was seen. A row that can't be run gets `not run: <reason>`. Never write a result for a row nobody looked at.

- [ ] **Step 4: Fix failures**

For a failed row: change `docs/index.html`, add or adjust the matching `SitePageTests` expectation first when the rule can be read from the source (a media-query value, a selector), run `-only-testing:StickermineTests/SitePageTests` and `./design/check-site.sh`, repeat the row, and write the fix in the Outcome section. If every row passed, write `All rows passed.` in Outcome.

- [ ] **Step 5: Commit**

```bash
git add design/site-checks.md docs/index.html StickermineTests/SitePageTests.swift
git commit -m "Record the website's browser checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The Homebrew cask (needs Ethan's yes for the tap)

**Files:**
- Create: `/Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb`
- Modify: `/Users/ethan/Developer/homebrew-tap/README.md` (add the Stickermine row)

**Interfaces:**
- Consumes: `Updater.caskName` = `"stickermine"` and the bundle ID `com.ethan.stickermine` (M6, M1); the "Update Homebrew tap" step of `.github/workflows/release.yml` (M1, Pullcord's), which rewrites and re-checks exactly `  version "<v>"`, `  sha256 "<64 hex>"` and `  depends_on macos: :<name>`; the shape of `/Users/ethan/Developer/homebrew-tap/Casks/pullcord.rb`.
- Produces: `Casks/stickermine.rb` committed locally in the tap clone (pushed in Task 10 Step 9, right before the tag, so the tap never offers a cask whose DMG doesn't exist for long), and the tap README row.

- [ ] **Step 1: Ask Ethan**

Ask: "May I add `Casks/stickermine.rb` and a Stickermine row in its README to your local `homebrew-tap` clone and commit them there? I'd push that commit only right before tagging v1.0 (Task 10), with your yes then." If he says no, go on with Task 9 but don't start Task 10: the release can't be tagged without the cask in the tap (spec 17 step 3), and Task 9 Step 2 asks again.

Only after his yes, bring the clone up to date (the release workflow pushes cask bumps from CI, so the clone can be behind):

```bash
git -C /Users/ethan/Developer/homebrew-tap status --short
git -C /Users/ethan/Developer/homebrew-tap pull --ff-only
```

Expected: `status` prints nothing (a clean clone; if it prints anything, show Ethan and stop), then `Already up to date.` or a fast-forward.

- [ ] **Step 2: Write the cask**

`/Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb` (complete file; `pullcord.rb`'s shape, with Stickermine's names, the placeholder version and checksum the first release replaces, and the spec's `zap` paths):

```ruby
cask "stickermine" do
  version "1.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/grokcodile/stickermine/releases/download/v#{version}/Stickermine.dmg"
  name "Stickermine"
  desc "Turn screenshots into stickers that live on your desktop"
  homepage "https://grokcodile.github.io/stickermine/"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :tahoe

  app "Stickermine.app"

  uninstall quit: "com.ethan.stickermine"

  zap trash: [
    "~/Library/Application Support/com.ethan.stickermine",
    "~/Library/Caches/com.ethan.stickermine",
    "~/Library/HTTPStorages/com.ethan.stickermine",
    "~/Library/Preferences/com.ethan.stickermine.plist",
  ]
end
```

- [ ] **Step 3: Prove the release workflow can rewrite it**

This runs the tap step's own rewrite-and-check block, cut out of `.github/workflows/release.yml`, against a copy of the cask, with a version and checksum that differ from the placeholders:

```bash
T=$(mktemp -d) && mkdir -p "$T/Casks" && cp /Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb "$T/Casks/"
awk '/CASK_FILE="Casks\/\$\{CASK\}\.rb"/{ f = 1 } f { print } f && /check depends_on/{ exit }' .github/workflows/release.yml | sed -E 's/^          //' > "$T/rewrite.sh"
grep -c '' "$T/rewrite.sh"
MACOS=$(brew ruby -e "puts MacOSVersion.new('$(plutil -extract LSMinimumSystemVersion raw Info.plist)').to_sym")
(cd "$T" && CASK=stickermine VERSION=9.9 SHA=$(printf 'stickermine' | shasum -a 256 | cut -c1-64) MACOS="$MACOS" bash -euo pipefail rewrite.sh) && echo "rewrite OK"
grep -E '^  (version|sha256|depends_on)' "$T/Casks/stickermine.rb"
ruby -c "$T/Casks/stickermine.rb"; ruby -c /Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb
rm -rf "$T"
```

Expected: `17` (the block's lines), `rewrite OK`, then `  version "9.9"`, `  sha256 "<64 hex digits>"`, `  depends_on arch: :arm64` and `  depends_on macos: :tahoe`, then `Syntax OK` twice. If the block prints `::error::Casks/stickermine.rb has no …`, the cask's line differs from what the workflow expects: fix the cask, not the workflow.

- [ ] **Step 4: Add the row to the tap README**

`/Users/ethan/Developer/homebrew-tap/README.md` (complete file; the Stickermine row joins the table in alphabetical order, with the Pages address until the domain exists):

```markdown
# homebrew-tap

Homebrew tap for apps by [grokcodile](https://github.com/grokcodile).

## Install

```sh
brew install --cask grokcodile/tap/<app>
```

…or tap once, then install by name:

```sh
brew tap grokcodile/tap
brew install --cask <app>
```

Update with `brew upgrade` (or `brew upgrade --cask <app>` for just one). Each
cask tracks that app's latest release automatically.

## Apps

| App | What it does | Links |
| --- | --- | --- |
| **Key54** | Bind one app to the right Command (⌘) key — hold to summon it, hold again to switch back. | [Website](https://key54.app) · [Repo](https://github.com/grokcodile/key54) |
| **Pullcord** | The most powerful things macOS can do are often the hardest to reach — Pullcord puts them at your fingertips. | [Website](https://pullcord.app) · [Repo](https://github.com/grokcodile/pullcord) |
| **Stickermine** | Turn quick screenshots into fun stickers that live on your desktop. | [Website](https://grokcodile.github.io/stickermine/) · [Repo](https://github.com/grokcodile/stickermine) |
```

- [ ] **Step 5: Show the change and commit it locally (Ethan's yes)**

```bash
git -C /Users/ethan/Developer/homebrew-tap status --short
git -C /Users/ethan/Developer/homebrew-tap diff README.md
```

Expected: `?? Casks/stickermine.rb` and ` M README.md`; the diff adds exactly the Stickermine row. Show both to Ethan and ask: "Commit these in the tap now (not pushed)?" Only after his yes:

```bash
git -C /Users/ethan/Developer/homebrew-tap add Casks/stickermine.rb README.md
git -C /Users/ethan/Developer/homebrew-tap commit -m "Add the stickermine cask" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C /Users/ethan/Developer/homebrew-tap log --oneline -1
```

Expected: the commit line `… Add the stickermine cask`. Nothing is pushed here.

---

### Task 9: Release preparation with Ethan

**Files:**
- Create: `design/release-checklist.md`
- Modify: `design/README.md`, `CONTACT.md`, `PRIVACY.md`, `TERMS.md`, `Info.plist`
- Modify (only if Ethan provides the demo loop): `docs/index.html`, plus `docs/demo.mp4`
- Modify (only if Ethan provides a screenshot for the still): `docs/demo-still.jpg`, and the still's alt text in `docs/index.html` and `README.md`

**Interfaces:**
- Consumes: Tasks 1–8; `PolicyDocsTests.pendingAddress` (Task 1); `design/check-site.sh --release` (Task 6).
- Produces: `design/release-checklist.md` with the open items answered; CONTACT.md with Ethan's address; the policies dated; `Info.plist` at `1.1`; the repo public and the six secrets set (both by Ethan's decision and, for the secrets, by Ethan's own hands).

- [ ] **Step 1: Write the release checklist and update design/README.md**

`design/release-checklist.md` (complete file):

```markdown
# Release checklist

How every Stickermine release goes out, and the record of each one (spec section 17). Pushing, tagging, editing the tap, enabling Pages and changing the repo's visibility each need Ethan's explicit yes at the time. Claude never handles the CI secrets: Ethan sets them, and the release workflow's Preflight step prints only their byte counts. Run the commands from the repository root in bash or zsh.

## Every release

1. `design/check-site.sh --release` ends `check-site: OK` (CONTACT.md gives an email address).
2. `Info.plist`'s `CFBundleShortVersionString` and `CFBundleVersion` are newer than the tag about to be made (for `v1.0`: `1.1`). The updater compares a running build's version with the newest release, and CI stamps the tag's own version into the release build, so the committed value stays ahead of every published tag.
3. `./build.sh` ends `Built ./build/Stickermine.app`, and the full test suite ends `** TEST SUCCEEDED **`.
4. A manual dry run (`gh workflow run release.yml --ref main`) succeeds, its Preflight prints `signing=true  notary=true  tap=true`, and its `Stickermine-dry-run` DMG passes the `codesign`, `stapler` and `spctl` checks on the DMG and on the app inside it, with the expected version, minimum macOS 26.0 and `arm64` only.
5. Ethan opens the dry-run DMG, drags Stickermine into Applications over the old copy and opens it: no "unidentified developer" warning, the stickers come back, and a capture works.
6. Tag `vX.Y` on `main` and push the tag. The release run publishes `Stickermine.dmg` with generated notes and bumps `Casks/stickermine.rb` in `grokcodile/homebrew-tap` to `X.Y` and the DMG's SHA-256.
7. Write the published DMG's size into the site's download line (`<size> download · macOS 26+ · Apple Silicon · Free`), check with `design/check-site.sh --publish`, commit and push.

## Open items (spec section 20)

| Item | Answer (with the date) |
|---|---|
| Contact address for CONTACT.md | |
| stickermine.app bought, and its DNS | |
| Demo loop recorded | |
| Repo public | |
| The six CI secrets set by Ethan | |
| A released Xcode 26.x next to the beta (optional) | |

## v1.0

| Step | Result |
|---|---|
| Release gate (`check-site.sh --release`, `Info.plist` 1.1) | |
| Build and full test suite | |
| Dry run (run URL, Preflight line) | |
| Dry-run DMG checks | |
| Ethan opened the dry-run DMG | |
| Cask pushed to the tap (commit) | |
| Tag `v1.0` pushed (commit) | |
| Release run (URL, conclusion) | |
| Published `Stickermine.dmg` (bytes) | |
| Cask bump in the tap (commit, version, sha256) | |
| Site download line (size, commit) | |
| Pages enabled from `main:/docs` (URL, status) | |
| `check-site.sh --online` on the live site | |
| Live site in Safari (`site-checks.md` rows 1, 3, 9, 12, 14) and on Ethan's iPhone (tap Maple, tap away, no sideways scroll) | |
| `design/app-shell-checks.md` row 26 | |

## Domain

| Step | Result |
|---|---|
| `dig +short stickermine.app A` | |
| Domain verified for Pages in Ethan's GitHub settings | |
| `docs/CNAME`, `AboutLinks.website` and the site's addresses (commit) | |
| Pages custom domain and HTTPS | |
| Cask homepage and tap README (tap commit) | |
| Dry run after the switch | |
| Release carrying the new About link | |
```

`design/README.md` (complete file; the first bullet now points at the published page, and the new scripts and records are listed):

```markdown
# Stickermine design assets

- `index.html`: the original website mock as a plain static page (open it in a browser; needs `dog.png` beside it and internet for the Fredoka font). The published site is `docs/index.html`, ported from it with the real content; change that one, not this.
- `dog.png`: Maple sticker cutout (620x910, transparent, white die-cut border).
- `icon-pickaxe.svg` / `icon-pickaxe-1024.png`: app icon, blue tile with the pickaxe sticker. Note: the PNG includes the soft shadow under the pickaxe. Rounded-corner tile is baked in; for the macOS asset catalog, export a full-bleed square version if needed.
- `menubar-glyph.svg`: solid one-color pickaxe silhouette for the menu bar (starting point; convert to a template image).
- `make-icon.sh`: renders `icon-pickaxe.svg` into the app icon slices in `Stickermine/Assets.xcassets/AppIcon.appiconset`.
- `get-site-font.sh`: downloads the site's self-hosted Fredoka and its licence into `docs/fonts/` and records their checksums.
- `make-site-images.sh`: writes the site's images into `docs/` (icon, favicon, Maple, the link preview, the demo still).
- `check-site.sh`: checks `docs/index.html` and the repo's documents (structure, links; `--release` and `--publish` add the release gates, `--online` fetches every absolute link).
- `site-checks.md`: the website checked in a browser at desktop and phone widths (M7), with each row's result.
- `release-checklist.md`: the steps of every release, and the record of each one.
```

```bash
git add design/release-checklist.md design/README.md
git commit -m "Add the release checklist" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 2: Ask Ethan the open items (spec section 20)**

Ask each, and wait for an explicit answer to each:

1. "What email address should CONTACT.md give? (The sibling pattern would be `stickermine@ethans.email`; I haven't verified that it exists.) The release can't be tagged until there is one."
2. "Have you bought `stickermine.app`? If so, have you pointed it at GitHub Pages yet?"
3. "Have you recorded the demo loop (capture, style, stick; about 10 s)? If so, where is the file? It should be an H.264 `.mp4`, 16:10, no sound. Optionally, would you rather the demo card showed a real screenshot of your desktop with stickers (1600 × 1000 JPEG, taken by you) instead of the drawn still?"
4. "May I make `grokcodile/stickermine` public now? The updater's unauthenticated API call and GitHub Pages both need it public."
5. "Please set the six release secrets yourself, with `gh secret set <NAME> --repo grokcodile/stickermine` for `MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`, `AC_API_KEY_BASE64` and `TAP_PUSH_TOKEN` (a token with contents:write on `grokcodile/homebrew-tap`). Tell me when they're set; I won't touch them. The dry run's Preflight step will show their byte counts, never their values."
6. "Do you want to install a released Xcode 26.x next to the beta for exact local parity with CI? (Optional; you'd install it yourself.)"

If Task 8's cask wasn't committed because Ethan said no then, ask again now: "The release workflow needs `Casks/stickermine.rb` in the tap before the tag. May I do Task 8 now?" Write each answer, with today's date, into the "Open items" table of `design/release-checklist.md`.

- [ ] **Step 3: Fill in the contact address (only with Ethan's answer)**

Put `ADDRESS='…'` as the first line of the block below, containing exactly what Ethan typed (never the sibling-pattern example unless that is his answer). The Bash tool keeps no shell state between calls, so the variable must be set in the same block as the script:

```bash
ADDRESS='…'
python3 -I - "$ADDRESS" <<'PY'
import re
import sys

address = sys.argv[1]
assert re.fullmatch(r"[^\s@\[\]()]+@[^\s@\[\]()]+\.[A-Za-z]{2,}", address), f"not an email address: {address!r}"
path = "CONTACT.md"
text = open(path, encoding="utf-8").read()
old = "- **Email:** _(address pending: Ethan adds it before the first release)_"
assert text.count(old) == 1, "CONTACT.md's email line is not the pending one"
open(path, "w", encoding="utf-8").write(text.replace(old, f"- **Email:** [{address}](mailto:{address})"))
PY
grep -n 'Email' CONTACT.md
./design/check-site.sh --release | tail -1
```

Expected: `9:- **Email:** [<address>](mailto:<address>)` and `check-site: OK`. If Ethan hasn't decided, leave CONTACT.md as it is and stop before Task 10: `check-site.sh --release` keeps failing, and the release waits for the address.

- [ ] **Step 4: The demo loop or a real still (only if Ethan provided one)**

The Bash tool keeps no shell state between calls, so each block below sets its own variable on its first line, containing exactly what Ethan gave (a `'` inside it is written `'\''`).

If Ethan gave a recorded loop, put `DEMO='…'` (the path he gave) as the first line of this block, then copy it in and swap the still for the video:

```bash
DEMO='…'
cp "$DEMO" docs/demo.mp4 && python3 -I - <<'PY'
path = "docs/index.html"
html = open(path, encoding="utf-8").read()
old = '<img class="demo-still" src="demo-still.jpg" width="1600" height="1000" alt="A Mac desktop with stickers on it: two note cards, the Stickermine pickaxe and Maple the dog">'
new = ('<video class="demo-still" width="1600" height="1000" muted loop playsinline preload="metadata" '
       'poster="demo-still.jpg" aria-label="Making a sticker: a capture, the style picker, and the sticker landing on the desktop">'
       '<source src="demo.mp4" type="video/mp4"></video>')
assert html.count(old) == 1, "the demo still's tag is not as Task 5 wrote it"
open(path, "w", encoding="utf-8").write(html.replace(old, new))
PY
```

If he gave a real screenshot for the still instead (or as well, as the loop's poster), put `STILL='…'` (the path he gave) as the first line of this block; it checks the size and puts it in place:

```bash
STILL='…'
W=$(sips -g pixelWidth "$STILL" | awk '/pixelWidth/ { print $2 }')
H=$(sips -g pixelHeight "$STILL" | awk '/pixelHeight/ { print $2 }')
if [ "$W" = 1600 ] && [ "$H" = 1000 ]; then
  sips -s format jpeg -s formatOptions 82 "$STILL" --out docs/demo-still.jpg > /dev/null && echo "still replaced"
else
  echo "error: the screenshot is ${W} x ${H}, not 1600 x 1000" >&2
fi
```

Expected: `still replaced`. On the error, ask him for one that size and change nothing. The drawn still's description no longer fits his screenshot, so ask Ethan for one sentence describing it, and put it as `ALT='…'` on the first line of this block, which replaces `A Mac desktop with stickers on it: two note cards, the Stickermine pickaxe and Maple the dog` in `README.md` and, unless the loop has already replaced the still there, in `docs/index.html` (the loop's `aria-label` describes the loop itself):

```bash
ALT='…'
python3 -I - "$ALT" <<'PY'
import html
import sys

alt = sys.argv[1].strip()
assert alt and "\n" not in alt and alt != "…", "the description must be Ethan's one sentence"
old = 'alt="A Mac desktop with stickers on it: two note cards, the Stickermine pickaxe and Maple the dog"'
new = f'alt="{html.escape(alt, quote=True)}"'
for path in ("README.md", "docs/index.html"):
    text = open(path, encoding="utf-8").read()
    if path == "docs/index.html" and '<video class="demo-still"' in text:
        continue
    assert text.count(old) == 1, f"{path}: the still's alt text is not as Tasks 4 and 5 wrote it"
    open(path, "w", encoding="utf-8").write(text.replace(old, new))
    print(f"{path}: alt text replaced")
PY
```

Expected: `README.md: alt text replaced` and, without the loop, `docs/index.html: alt text replaced`. Then, for any of these changes:

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SitePageTests -only-testing:StickermineTests/SiteImagesTests -only-testing:StickermineTests/ReadmeTests
./design/check-site.sh | tail -1
```

Expected: `Test run with 24 tests in 3 suites passed` and `check-site: OK`. Then repeat `design/site-checks.md` row 3 (the demo card) and, for the loop, check that it stays paused on its poster with reduced motion on, and that it plays muted and loops with no controls with it off: in Web Inspector's Elements tab, open User Preference Overrides and set Reduced motion to Reduce, reload, then set it back to System and reload. (Or Ethan turns System Settings › Accessibility › Display › Reduce motion on and off himself; the agent never changes system settings.) With neither a loop nor a screenshot, leave the still.

- [ ] **Step 5: Date the policies and move the dev version ahead of v1.0**

```bash
TODAY=$(LC_ALL=en_US.UTF-8 date '+%B %-d, %Y')
sed -i '' -E "s/^\*\*Effective .*\*\*$/**Effective ${TODAY}**/" PRIVACY.md
sed -i '' -E "s/^\*\*Stickermine\*\* — last updated .*$/**Stickermine** — last updated ${TODAY}/" TERMS.md
plutil -replace CFBundleShortVersionString -string 1.1 Info.plist
plutil -replace CFBundleVersion -string 1.1 Info.plist
grep -n 'Effective\|last updated' PRIVACY.md TERMS.md
plutil -lint Info.plist && plutil -extract CFBundleShortVersionString raw Info.plist && plutil -extract CFBundleVersion raw Info.plist
```

Expected: `PRIVACY.md:3:**Effective <today>**`, `TERMS.md:3:**Stickermine** — last updated <today>`, `TERMS.md:59:"last updated" date.` (the Changes section, untouched), `Info.plist: OK`, `1.1`, `1.1`. `git diff Info.plist` shows only the two `<string>0.1</string>` lines turned into `<string>1.1</string>`.

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PolicyDocsTests -only-testing:StickermineTests/ProjectSettingsTests
```

Expected: `** TEST SUCCEEDED **`.

```bash
git add CONTACT.md PRIVACY.md TERMS.md Info.plist README.md design/release-checklist.md docs
git commit -m "Prepare the 1.0 release" -m "The contact address, the policies' dates, and the dev version 1.1, kept ahead of the v1.0 tag (CI stamps 1.0 from the tag)." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 6: Make the repo public (only after Ethan's yes to question 4)**

```bash
gh repo view grokcodile/stickermine --json visibility --jq .visibility
gh repo edit grokcodile/stickermine --visibility public --accept-visibility-change-consequences
gh repo view grokcodile/stickermine --json visibility --jq .visibility
```

Expected: `PRIVATE`, then `✓ Edited repository grokcodile/stickermine`, then `PUBLIC`. (If the first already prints `PUBLIC`, skip the edit.) If `gh repo view` fails with `Could not resolve to a Repository`, the repo doesn't exist yet: record that in the checklist and stop; Task 10 can't run.

- [ ] **Step 7: Record and commit**

Write the outcome of Steps 3–6 into the checklist's "Open items" table (the secrets row says only what Ethan said, for example `set by Ethan on <date>`), then:

```bash
git add design/release-checklist.md
git commit -m "Record the release's open items" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: Final build, full test run, contract update, CI dry run and the v1.0 release

This is the milestone's last task: M7 is complete when its Step 15 is committed. Task 11 belongs to the same spec step (17.5) but waits for the domain, and ends with its own build, test run and dry run.

The Bash tool keeps no shell state between calls, so every block below sets the variables it uses itself (`RUN_ID` is looked up again from `gh run list` wherever a later block needs it), and nothing Ethan runs in his own terminal depends on a variable.

**Files:**
- Modify: `design/plans/2026-10-12-stickermine-v1-plan.md` (Interface Contract)
- Modify: `design/ci-dry-runs.md` (append a row), `design/release-checklist.md` (the v1.0 table), `design/app-shell-checks.md` (row 26), `docs/index.html` (the download line's size)

**Interfaces:**
- Consumes: everything above; the six secrets (set by Ethan); the tap commit from Task 8.
- Produces: a green local build and test run, the index updated, a recorded signed and notarized dry run whose DMG passed the checks, the `v1.0` release with `Stickermine.dmg`, the cask bumped, the site live on GitHub Pages with the DMG's size, and row 26 run against the release. Each outward step waits for Ethan's yes.

- [ ] **Step 1: Build**

Ethan's installed Stickermine can keep running: `build.sh` writes only `./build/`, and the test host in Step 2 skips all startup work, the single-instance hand-over included (M1's test-host guard). Don't quit it with `pkill`: that sends SIGTERM, which skips `applicationWillTerminate` (spec section 12), and the build doesn't need it. Only a copy running from `./build` itself would have its bundle replaced under it, so check for one first:

```bash
pgrep -fl 'build/Stickermine\.app/Contents/MacOS/' || echo "no copy running from ./build"
./build.sh
```

Expected: `no copy running from ./build` (if `pgrep` lists a process instead, ask Ethan to quit that copy from its menu bar icon, then run the block again), then `Type-checking against MacOSX26.5.sdk...`, `Building Stickermine...`, `Signing with: DEA1A3749B06CF3619F72152EFC35A48E380C4E4`, `Signed by certificate DEA1A3749B06CF3619F72152EFC35A48E380C4E4`, and last `Built ./build/Stickermine.app`. This milestone adds no app code, so a failure here comes from an earlier milestone or the toolchain: fix it before anything else.

- [ ] **Step 2: Run the whole test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 480 tests in 64 suites passed` and `** TEST SUCCEEDED **` (M6's 448 tests in 59 suites, plus this milestone's 32 in 5 new suites).

- [ ] **Step 3: Update the index's Interface Contract**

In `design/plans/2026-10-12-stickermine-v1-plan.md`, insert directly above the line `## How each milestone plan is laid out` a heading line `### Documents and website (M7)`, a blank line, a line ```` ```swift ````, the block below, a line ```` ``` ````, and a blank line. (It is fenced as text here only because it lists declarations rather than compilable code.)

```text
enum RepoFiles {                                                 // [M7] StickermineTests/DocsTestSupport.swift (test support, on SourceFiles.repoRoot)
    static func url(_ path: String) -> URL; static func exists(_ path: String) -> Bool
    static func text(_ path: String) throws -> String; static func data(_ path: String) throws -> Data
    static func prose(_ path: String) throws -> String           // whitespace runs folded to one space
    static func matches(_ pattern: String, in text: String) throws -> [[String]]   // capture groups, whole match first
    static func headings(in markdown: String, level: Int) throws -> [String]; static func markdownLinks(in markdown: String) throws -> [String]
    static func sha256(_ data: Data) -> String; static func inOrder(_ needles: [String], in list: [String]) -> Bool
}
// [M7] AboutLinks.website is https://grokcodile.github.io/stickermine/ until docs/CNAME exists, then https://stickermine.app/ (M7 Task 11, same commit as docs/CNAME)
// [M7] Info.plist's CFBundleShortVersionString/CFBundleVersion stay ahead of the newest release tag (1.1 when v1.0 is tagged); CI stamps the tag's version
```

Check:

```bash
grep -c '\[M7\]' design/plans/2026-10-12-stickermine-v1-plan.md
grep -c '^### Documents and website (M7)$' design/plans/2026-10-12-stickermine-v1-plan.md
```

Expected: `3` and `1`.

```bash
git add design/plans/2026-10-12-stickermine-v1-plan.md
git commit -m "Record M7's contract additions in the plan index" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 4: The release gate**

```bash
./design/check-site.sh --release | tail -1
plutil -extract CFBundleShortVersionString raw Info.plist
git status --short
```

Expected: `check-site: OK`, `1.1`, and no output from `git status`. Anything else: go back to Task 9 (the address) or commit what is left. Write the result in the v1.0 table's first row.

- [ ] **Step 5: Push and run the dry run (needs Ethan's explicit yes now)**

If `git remote get-url origin` fails, the GitHub repo doesn't exist yet: append the "not run" row, write "no GitHub repo yet" in the v1.0 table's dry-run row, commit both with Step 8's commands, and stop this milestone here (the release needs the repo):

```bash
REASON="no GitHub repo yet"
echo "| $(date +%F) | M7 end (Task 10) | $(git rev-parse --short HEAD) | none | not run | Ethan: $REASON |" >> design/ci-dry-runs.md
```

If Ethan says no to the dry run, append the same row with his reason in `REASON` (for example `REASON="release later"`), commit with Step 8's commands, and stop. Otherwise ask Ethan: "Push main to grokcodile/stickermine and start a release-workflow dry run (signed and notarized, with your secrets)?" Only after his yes:

```bash
git push
BEFORE=$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')
gh workflow run release.yml --ref main
RUN_ID="$BEFORE"
for _ in $(seq 30); do
  sleep 2
  RUN_ID=$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')
  [ "$RUN_ID" != "$BEFORE" ] && break
done
if [ "$RUN_ID" = "$BEFORE" ]; then
  echo "error: the dispatched run never appeared" >&2
else
  gh run watch "$RUN_ID" --exit-status
  gh run view "$RUN_ID" --log | grep -E 'signing=(true|false)  notary=' | head -1
  ROW=$(gh run view "$RUN_ID" --json headSha,url,conclusion --jq '"\(.headSha[0:7]) | \(.url) | \(.conclusion)"')
  echo "| $(date +%F) | M7 end (Task 10) | ${ROW} | signed and notarized dry run before v1.0 |" >> design/ci-dry-runs.md
fi
```

Expected: `gh run watch` exits 0, the Preflight line reads `signing=true  notary=true  tap=true`, and the appended row ends `| success | signed and notarized dry run before v1.0 |`. If the Preflight line shows any `false`, a secret is missing or empty (its byte count in that step's log is 0): tell Ethan which one, and don't tag. If it prints `error: the dispatched run never appeared`, nothing was recorded: check `gh run list --workflow release.yml` and rerun from `BEFORE=`. On a failed run, read `gh run view "$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')" --log-failed`. A notarization rejection prints the submission ID: `xcrun notarytool log <id>` needs the API key, so ask Ethan to run it; an unknown-symbol error means a macOS 27-only API slipped in (fix it, run the suite, commit, and ask before pushing again); a project-format error means the project file changed from objectVersion 77.

- [ ] **Step 6: Check the dry-run DMG (Ethan's yes for the download)**

Ask: "May I download this run's `Stickermine-dry-run` artifact (`Stickermine.dmg`, a few MB, from grokcodile/stickermine on GitHub) into the repo's gitignored `build/dry-run` folder to check its signature and notarization?" Only after his yes (the first line finds the run again, since the newest dispatched run on `main` is the one Step 5 watched; `build/` is gitignored, so the download stays out of the commits):

```bash
RUN_ID=$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')
WORK=build/dry-run
rm -rf "$WORK" && mkdir -p "$WORK"
gh run download "$RUN_ID" -n Stickermine-dry-run -D "$WORK"
DMG="$WORK/Stickermine.dmg"
codesign --verify --strict --verbose=2 "$DMG"
codesign -dvv "$DMG" 2>&1 | grep -E '^(Authority|TeamIdentifier|Timestamp)='
xcrun stapler validate "$DMG"
spctl --assess -vv --type open --context context:primary-signature "$DMG"
MNT=$(mktemp -d)
hdiutil attach -nobrowse -readonly -mountpoint "$MNT" "$DMG" > /dev/null
ls -l "$MNT"
APP="$MNT/Stickermine.app"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -dvv "$APP" 2>&1 | grep -E '^(Identifier|Authority|TeamIdentifier|Timestamp)=|flags='
xcrun stapler validate "$APP"
spctl --assess -vv --type execute "$APP"
plutil -extract CFBundleShortVersionString raw "$APP/Contents/Info.plist"
plutil -extract LSMinimumSystemVersion raw "$APP/Contents/Info.plist"
lipo -archs "$APP/Contents/MacOS/Stickermine"
hdiutil detach "$MNT"
rmdir "$MNT"
```

Expected, in order: `…/Stickermine.dmg: valid on disk` and `…: satisfies its Designated Requirement`; an `Authority=Developer ID Application: …` line followed by `Authority=Developer ID Certification Authority` and `Authority=Apple Root CA`, a `TeamIdentifier=` and a `Timestamp=` line; `The validate action worked!`; `…: accepted` with `source=Notarized Developer ID`; `ls` shows `Applications -> /Applications` and `Stickermine.app`; the app is `valid on disk` and `satisfies its Designated Requirement`, with `Identifier=com.ethan.stickermine`, the same Developer ID authority, and `flags=0x10000(runtime)`; `The validate action worked!`; `accepted` with `source=Notarized Developer ID`; `1.1` (a dry run has no tag to stamp); `26.0`; `arm64`. Write the results (one line each) in the v1.0 table. Any other result: don't tag; show Ethan the output.

- [ ] **Step 7: Ethan opens the dry-run DMG**

MANUAL VERIFICATION (Ethan does this himself; the executor writes down what he reports):

1. `open /Users/ethan/Developer/stickermine/build/dry-run/Stickermine.dmg` mounts the image and shows its window: Stickermine and an Applications shortcut.
2. Ethan quits the running Stickermine (menu bar icon › Quit Stickermine), drags Stickermine onto Applications and replaces the old copy.
3. He opens Stickermine from Applications. Expected: it opens with no "unidentified developer" or "can't be checked for malicious software" warning (at most the one-time "downloaded from the Internet" confirmation, answered with **Open**); Home opens; the stickers he had are back in place.
4. He presses ⌃⌥⌘S and makes one sticker. Expected: the crosshair appears without a new Screen Recording request (the grant belongs to the Developer ID signature), and the sticker places.

Then `hdiutil detach /Volumes/Stickermine` if the image is still mounted (the workflow names the volume after the app), and `rm -rf build/dry-run`. Record the four observations in the v1.0 table. Afterwards `./install.sh` puts the local build back whenever Ethan wants it.

- [ ] **Step 8: Commit the records**

```bash
git add design/ci-dry-runs.md design/release-checklist.md
git commit -m "Record the pre-release dry run and its DMG checks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 9: Push the cask to the tap (needs Ethan's explicit yes now)**

Ask: "Push the stickermine cask commit to grokcodile/homebrew-tap now? I'll tag v1.0 right after, so the cask's placeholder version is only live for a few minutes." Only after his yes:

```bash
git -C /Users/ethan/Developer/homebrew-tap pull --rebase -q
git -C /Users/ethan/Developer/homebrew-tap push
git -C /Users/ethan/Developer/homebrew-tap log --oneline -1
```

Expected: the push summary, and `… Add the stickermine cask` as the latest commit. Write the commit in the v1.0 table.

- [ ] **Step 10: Tag v1.0 (needs Ethan's explicit yes now)**

Ask: "Push main and tag v1.0 on its head (commit `<the output of git rev-parse --short HEAD>`), then push the tag? That publishes the release and bumps the cask." Only after his yes:

```bash
git push
git tag -a v1.0 -m "Stickermine 1.0"
git push origin v1.0
RUN_ID=""
for _ in $(seq 30); do
  sleep 2
  RUN_ID=$(gh run list --workflow release.yml --event push --limit 5 --json databaseId,headBranch --jq '[.[] | select(.headBranch == "v1.0")][0].databaseId // empty')
  [ -n "$RUN_ID" ] && break
done
if [ -z "$RUN_ID" ]; then echo "error: the tag's run never appeared" >&2; else gh run watch "$RUN_ID" --exit-status; fi
```

Expected: `gh run watch` exits 0; every step succeeds, including "Notarize & staple app", "Notarize & staple DMG", "Gatekeeper check", "Publish release" and "Update Homebrew tap". If the run fails before "Publish release", nothing is published: read `gh run view "$(gh run list --workflow release.yml --event push --limit 5 --json databaseId,headBranch --jq '[.[] | select(.headBranch == "v1.0")][0].databaseId')" --log-failed`, fix, and ask Ethan before deleting and re-pushing the tag (`git push origin :refs/tags/v1.0 && git tag -d v1.0`).

If only "Update Homebrew tap" fails, the release is out; bump the cask by hand (the tap step prints the checksum before it clones):

```bash
RUN_ID=$(gh run list --workflow release.yml --event push --limit 5 --json databaseId,headBranch --jq '[.[] | select(.headBranch == "v1.0")][0].databaseId')
SHA=$(gh run view "$RUN_ID" --log | grep -m1 -oE 'version=1\.0  sha256=[0-9a-f]{64}' | grep -oE '[0-9a-f]{64}$' || true)
if [ ${#SHA} -ne 64 ]; then
  echo "error: the run's log has no checksum (the tap step failed before printing it)" >&2
else
  git -C /Users/ethan/Developer/homebrew-tap pull --ff-only -q
  sed -i '' -E "s/^  version \".*\"/  version \"1.0\"/; s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" /Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb
  git -C /Users/ethan/Developer/homebrew-tap diff
fi
```

Expected: the diff turns the placeholder `sha256` into the run's checksum (`version "1.0"` and `depends_on macos: :tahoe` are already right). If it prints the error instead, ask Ethan: "May I download the published `Stickermine.dmg` (a few MB, from the v1.0 release on GitHub) into the gitignored `build/release` folder to compute its checksum?" Only after his yes:

```bash
mkdir -p build/release
gh release download v1.0 --repo grokcodile/stickermine -p Stickermine.dmg -D build/release --clobber
SHA=$(shasum -a 256 build/release/Stickermine.dmg | cut -c1-64)
git -C /Users/ethan/Developer/homebrew-tap pull --ff-only -q
sed -i '' -E "s/^  version \".*\"/  version \"1.0\"/; s/^  sha256 \".*\"/  sha256 \"${SHA}\"/" /Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb
git -C /Users/ethan/Developer/homebrew-tap diff
rm -rf build/release
```

Either way, show Ethan the diff. Only after his yes: `git -C /Users/ethan/Developer/homebrew-tap commit -am "stickermine 1.0" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" && git -C /Users/ethan/Developer/homebrew-tap push`. Step 11 then finds this commit in place of the bot's.

- [ ] **Step 11: Check the release and the cask bump**

```bash
RUN_ID=$(gh run list --workflow release.yml --event push --limit 5 --json databaseId,headBranch --jq '[.[] | select(.headBranch == "v1.0")][0].databaseId')
gh release view v1.0 --repo grokcodile/stickermine --json tagName,isDraft,assets --jq '.tagName, .isDraft, (.assets[] | "\(.name) \(.size)")'
gh run view "$RUN_ID" --log | grep -m1 -E 'version=1\.0  sha256='
git -C /Users/ethan/Developer/homebrew-tap pull --ff-only -q
grep -E '^  (version|sha256|depends_on macos)' /Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb
git -C /Users/ethan/Developer/homebrew-tap log --oneline -1
```

Expected: `v1.0`, `false`, `Stickermine.dmg <bytes>`; the tap step's line `version=1.0  sha256=<64 hex>  macos=:tahoe (26.0)`; the cask's `  version "1.0"`, `  sha256 "<the same 64 hex>"`, `  depends_on macos: :tahoe`; and the bot's commit `… stickermine 1.0` (or Step 10's hand bump with the same message; if that bump used the downloaded DMG's checksum, the tap step's line is missing and the cask's `sha256` is compared with that checksum instead). Write the URL, the byte count, the tap commit and the checksum into the v1.0 table. Optionally, Ethan can try the tap himself: `brew install --cask grokcodile/tap/stickermine` (it replaces /Applications/Stickermine.app; his choice).

- [ ] **Step 12: Put the DMG's size on the site**

```bash
BYTES=$(gh release view v1.0 --repo grokcodile/stickermine --json assets --jq '.assets[] | select(.name == "Stickermine.dmg") | .size')
python3 -I - "$BYTES" <<'PY'
import re
import sys

n = int(sys.argv[1])
size = f"{n / 1e6:.1f}&nbsp;MB" if n >= 1_000_000 else f"{round(n / 1e3)}&nbsp;KB"
path = "docs/index.html"
html = open(path, encoding="utf-8").read()
new, count = re.subn(r'<span class="download-line">[^<]*</span>',
                     f'<span class="download-line">{size} download · macOS 26+ · Apple Silicon · Free</span>', html)
assert count == 1, f"{count} download lines"
open(path, "w", encoding="utf-8").write(new)
print(size.replace("&nbsp;", " "))
PY
grep -n 'download-line">' docs/index.html
./design/check-site.sh --publish | tail -1
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SitePageTests
```

Expected: the size (for example `2.4 MB`), the page's line `<span class="download-line">2.4&nbsp;MB download · macOS 26+ · Apple Silicon · Free</span>`, `check-site: OK`, and `Test run with 10 tests in 1 suite passed`. The sizes use decimal units, as Finder shows them. Then:

```bash
git add docs/index.html
git commit -m "State the 1.0 download size on the website" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Ask Ethan "Push this?" and push only after his yes (`git push`).

- [ ] **Step 13: Enable GitHub Pages from main:/docs (needs Ethan's explicit yes now)**

First make sure Step 12's size commit is on GitHub, since Pages publishes what `origin/main` holds (`check-site.sh --publish` only reads the local file):

```bash
git fetch -q origin main
git show origin/main:docs/index.html | grep -c 'class="download-line">[0-9]'
```

Expected: `1`. On `0`, Step 12's commit isn't on GitHub yet: ask Ethan to let you push it first (`git push`, after his yes), and don't enable Pages until this prints `1`.

Ask: "Turn on GitHub Pages for grokcodile/stickermine, publishing `main:/docs` at https://grokcodile.github.io/stickermine/?" Only after his yes:

```bash
gh api --method POST repos/grokcodile/stickermine/pages -f "source[branch]=main" -f "source[path]=/docs" --jq '.html_url'
for _ in $(seq 60); do
  STATUS=$(gh api repos/grokcodile/stickermine/pages/builds/latest --jq .status 2>/dev/null || echo pending)
  [ "$STATUS" = "built" ] || [ "$STATUS" = "errored" ] && break
  sleep 5
done
echo "$STATUS"
curl -sS -o /dev/null -w '%{http_code}\n' https://grokcodile.github.io/stickermine/
curl -sS -o /dev/null -w '%{http_code}\n' https://grokcodile.github.io/stickermine/fonts/Fredoka-latin.woff2
./design/check-site.sh --publish --online
```

Expected: `https://grokcodile.github.io/stickermine/`, `built`, `200`, `200`, then every address in Task 6's table at its "After Pages" status (bot-protected sites may differ, as the table says) and `check-site: OK`. Then open https://grokcodile.github.io/stickermine/ in Safari and repeat `design/site-checks.md` rows 1, 3, 9, 12 and 14 on the live site (Network: every request goes to grokcodile.github.io; the footer's Privacy, Terms and Contact open the files on GitHub; the Download pill downloads `Stickermine.dmg`). Then ask Ethan to open https://grokcodile.github.io/stickermine/ on his iPhone and report: tap Maple (expected: the bubble shows above her head, inside the screen edges), tap the empty background (expected: it hides), and try to scroll sideways (expected: the page doesn't move sideways). Write the results into the v1.0 table.

- [ ] **Step 14: Row 26 against the release (Ethan at the Mac)**

MANUAL VERIFICATION: ask Ethan to run `design/app-shell-checks.md` row 26 as written (a local build with `CFBundleShortVersionString` 0.9 in `Info.plist`, not committed; then the login check). Write what he reports into row 26's Result cell, replacing its earlier `not run: no release yet`. Afterwards restore the plist (`git checkout Info.plist`) and run `./install.sh` so the installed copy is a normal build again, or leave the v1.0 DMG copy in place if Ethan prefers.

- [ ] **Step 15: Record and commit**

Fill the remaining rows of the v1.0 table, then:

```bash
git status --short
git add design/release-checklist.md design/app-shell-checks.md
git commit -m "Record the 1.0 release" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Expected from `git status` before the commit: only `design/release-checklist.md` and `design/app-shell-checks.md` (`Info.plist` is back at 1.1 and unmodified). Push only with Ethan's yes (`git push`).

---

### Task 11: stickermine.app (only once the domain is bought and resolves)

Run this task when Ethan says `stickermine.app` is his; until then the site stays on https://grokcodile.github.io/stickermine/ and the "Domain" table in `design/release-checklist.md` stays empty. It may be weeks after Task 10. The About popover's new link reaches users only with the next release.

**Files:**
- Create: `docs/CNAME`
- Modify: `Stickermine/Home/AboutPopover.swift` (`AboutLinks`), `StickermineTests/HomeTextTests.swift` (`theAboutLinksAreTheSpecsInItsOrder`), `docs/index.html`, `README.md`, `design/release-checklist.md`, `design/ci-dry-runs.md`
- Modify (Ethan's yes): `/Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb`, `/Users/ethan/Developer/homebrew-tap/README.md`

**Interfaces:**
- Consumes: `enum AboutLinks { static let website, repo, kofi, issues: URL; static func pretty(_ url: URL) -> String; static func tooltip(for row: Row) -> String }` (M6); `SitePageTests.theSiteAddressIsTheAppsWebsiteLink` and `ReadmeTests.installsFromTheTapAndTheLatestRelease` (Tasks 5 and 4), which already follow `AboutLinks.website` and `docs/CNAME`.
- Produces: `AboutLinks.website == URL(string: "https://stickermine.app/")!` (signature unchanged); `docs/CNAME` containing exactly `stickermine.app` (no newline, like the siblings'); the site, README, cask homepage and tap README on the new address.

- [ ] **Step 1: Ask Ethan to point the domain at Pages**

Ask him to do these himself, at his registrar and in his GitHub settings, and tell you when they're done:

1. Verify the domain for GitHub Pages first (GitHub › Settings › Pages › "Add a domain": a TXT record `_github-pages-challenge-grokcodile.stickermine.app`), so nobody else's Pages site can claim it.
2. Point the apex at GitHub Pages: A records `185.199.108.153`, `185.199.109.153`, `185.199.110.153`, `185.199.111.153`, and AAAA records `2606:50c0:8000::153`, `2606:50c0:8001::153`, `2606:50c0:8002::153`, `2606:50c0:8003::153`. Optionally `www` as a CNAME to `grokcodile.github.io`.

Then:

```bash
dig +short stickermine.app A | sort
```

Expected: the four `185.199.10x.153` addresses. Until they show, stop here. Write the result into the Domain table.

- [ ] **Step 2: Write the failing test**

In `StickermineTests/HomeTextTests.swift`, replace the whole function that starts with `@Test func theAboutLinksAreTheSpecsInItsOrder() {` with:

```swift
    @Test func theAboutLinksAreTheSpecsInItsOrder() {
        #expect(AboutLinks.rows.map(\.title) == ["Website", "Star on GitHub", "Buy me a coffee", "Report a Bug"])
        #expect(AboutLinks.rows.map(\.url.absoluteString) == [
            "https://stickermine.app/",
            "https://github.com/grokcodile/stickermine",
            "https://ko-fi.com/grokcodile",
            "https://github.com/grokcodile/stickermine/issues",
        ])
        #expect(AboutLinks.pretty(AboutLinks.website) == "stickermine.app")
        #expect(AboutLinks.tooltip(for: AboutLinks.rows[2]) == "Tips keep it going\n↗ ko-fi.com/grokcodile")
    }
```

- [ ] **Step 3: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/HomeTextTests
```

Expected: `theAboutLinksAreTheSpecsInItsOrder()` records two issues, `Expectation failed: AboutLinks.rows.map(\.url.absoluteString) == [` (the first address is still the Pages one) and `Expectation failed: AboutLinks.pretty(AboutLinks.website) == "stickermine.app"`, then `Test run with 5 tests in 1 suite failed … with 2 issues` and `** TEST FAILED **`.

- [ ] **Step 4: Change the link, the site and the README together**

In `Stickermine/Home/AboutPopover.swift`, replace the doc comment and the declaration that starts with `enum AboutLinks {` (from the line `/// The About popover's links, in the spec's order (section 13): Website,` to the enum's closing `}`) with:

```swift
/// The About popover's links, in the spec's order (section 13): Website,
/// Star on GitHub, Buy me a coffee, Report a Bug. The Website is
/// stickermine.app, the address docs/CNAME gives the GitHub Pages site
/// (section 15).
enum AboutLinks {
    struct Row: Equatable, Identifiable {
        let title: String
        let symbol: String
        let help: String
        let url: URL
        var id: String { title }
    }

    static let website = URL(string: "https://stickermine.app/")!
    static let repo = URL(string: "https://github.com/grokcodile/stickermine")!
    static let kofi = URL(string: "https://ko-fi.com/grokcodile")!
    static let issues = URL(string: "https://github.com/grokcodile/stickermine/issues")!

    static let rows: [Row] = [
        Row(title: "Website", symbol: "globe", help: "Learn more about Stickermine", url: website),
        Row(title: "Star on GitHub", symbol: "star", help: "A star helps others find it", url: repo),
        Row(title: "Buy me a coffee", symbol: "mug", help: "Tips keep it going", url: kofi),
        Row(title: "Report a Bug", symbol: "ladybug", help: "Open an issue on GitHub", url: issues),
    ]

    /// The address as you'd say it: no scheme, no trailing slash.
    static func pretty(_ url: URL) -> String {
        var text = url.absoluteString
        for scheme in ["https://", "http://"] where text.hasPrefix(scheme) { text.removeFirst(scheme.count) }
        while text.hasSuffix("/") { text.removeLast() }
        return text
    }

    /// A row's tooltip: what it is for, then where it goes.
    static func tooltip(for row: Row) -> String {
        "\(row.help)\n↗ \(pretty(row.url))"
    }
}
```

Then the CNAME, the page's three absolute addresses and the README's Website line:

```bash
printf 'stickermine.app' > docs/CNAME
sed -i '' 's#https://grokcodile.github.io/stickermine/#https://stickermine.app/#g' docs/index.html README.md
sed -i '' 's#\[grokcodile.github.io/stickermine\]#[stickermine.app]#' README.md
grep -c 'grokcodile.github.io' docs/index.html README.md
grep -n 'stickermine.app' docs/index.html README.md
wc -c docs/CNAME
```

Expected: `docs/index.html:0` and `README.md:0`; the page's `canonical`, `og:url` and `og:image` lines and the README's `Website: [stickermine.app](https://stickermine.app/)`; `15 docs/CNAME`.

- [ ] **Step 5: Run the tests**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/HomeTextTests -only-testing:StickermineTests/SitePageTests -only-testing:StickermineTests/ReadmeTests -only-testing:StickermineTests/PolicyDocsTests
./design/check-site.sh --publish | tail -1
```

Expected: `Test run with 29 tests in 4 suites passed`, `** TEST SUCCEEDED **` (`SitePageTests` now takes its `docs/CNAME` branch: the bare host, and the site equal to `https://stickermine.app/`), and `check-site: OK`.

- [ ] **Step 6: Commit (one commit, as M6's note asks)**

```bash
git add docs/CNAME docs/index.html README.md Stickermine/Home/AboutPopover.swift StickermineTests/HomeTextTests.swift
git commit -m "Move the website to stickermine.app" -m "docs/CNAME, the page's canonical and Open Graph addresses, the README and the About popover's Website link change together." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 7: Push and set the custom domain (needs Ethan's explicit yes now)**

Ask: "Push the stickermine.app switch and set it as the Pages custom domain? (stickermine.app only works over HTTPS, so the site is unreachable for the few minutes until GitHub issues its certificate.)" Only after his yes:

```bash
git push
sleep 60
gh api repos/grokcodile/stickermine/pages --jq '.cname, .https_enforced, .status'
```

Expected: `stickermine.app`, then `false` or `true`, then `built`. If the first line is `null`, set it: `gh api --method PUT repos/grokcodile/stickermine/pages -f cname=stickermine.app` (GitHub may commit its own identical `docs/CNAME`; `git pull --ff-only` afterwards). The whole `.app` domain is on the browsers' HSTS preload list, so once the CNAME is live, https://grokcodile.github.io/stickermine/ redirects to stickermine.app and visitors reach nothing until GitHub has issued the certificate (the Pages settings page says so when it has; it can take up to an hour).

Enforcing HTTPS is a separate change to the repo's Pages settings, so it needs its own yes. Once the certificate is issued, ask: "GitHub has issued the certificate; turn on Enforce HTTPS for the Pages site?" Only after his yes (if the `gh api` line above already printed `true` for `https_enforced`, leave out the first line):

```bash
gh api --method PUT repos/grokcodile/stickermine/pages -F https_enforced=true
curl -sS -o /dev/null -w '%{http_code}\n' https://stickermine.app/
curl -sS -o /dev/null -w '%{http_code} %{redirect_url}\n' https://grokcodile.github.io/stickermine/
./design/check-site.sh --publish --online
```

Expected: `200`; `301 https://stickermine.app/`; the link statuses as in Task 6's "After Pages" column, with the two Pages addresses now under `stickermine.app`. Write the results into the Domain table.

- [ ] **Step 8: The cask's homepage and the tap README (needs Ethan's explicit yes now)**

Ask: "Point the stickermine cask's homepage and the tap README's Website link at https://stickermine.app/, commit and push in homebrew-tap?" Only after his yes:

```bash
git -C /Users/ethan/Developer/homebrew-tap pull --ff-only -q
sed -i '' 's#  homepage "https://grokcodile.github.io/stickermine/"#  homepage "https://stickermine.app/"#' /Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb
sed -i '' 's#\[Website\](https://grokcodile.github.io/stickermine/)#[Website](https://stickermine.app)#' /Users/ethan/Developer/homebrew-tap/README.md
git -C /Users/ethan/Developer/homebrew-tap diff --stat
ruby -c /Users/ethan/Developer/homebrew-tap/Casks/stickermine.rb
git -C /Users/ethan/Developer/homebrew-tap commit -am "stickermine: homepage stickermine.app" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
git -C /Users/ethan/Developer/homebrew-tap push
```

Expected: `2 files changed, 2 insertions(+), 2 deletions(-)`, `Syntax OK`, the commit and the push summary.

- [ ] **Step 9: Build, full test run and dry run**

```bash
./build.sh
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Built ./build/Stickermine.app`, then `Test run with 480 tests in 64 suites passed` and `** TEST SUCCEEDED **`.

Ask Ethan: "Start a release-workflow dry run on main after the stickermine.app switch?" Only after his yes:

```bash
BEFORE=$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')
gh workflow run release.yml --ref main
RUN_ID="$BEFORE"
for _ in $(seq 30); do
  sleep 2
  RUN_ID=$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')
  [ "$RUN_ID" != "$BEFORE" ] && break
done
if [ "$RUN_ID" = "$BEFORE" ]; then
  echo "error: the dispatched run never appeared" >&2
else
  gh run watch "$RUN_ID" --exit-status
  ROW=$(gh run view "$RUN_ID" --json headSha,url,conclusion --jq '"\(.headSha[0:7]) | \(.url) | \(.conclusion)"')
  echo "| $(date +%F) | M7 domain (Task 11) | ${ROW} | after the stickermine.app switch |" >> design/ci-dry-runs.md
fi
```

Expected: `gh run watch` exits 0 and the appended row ends `| success | after the stickermine.app switch |`. If Ethan says no, append a "not run" row instead, with his reason (his words) in `REASON` on the first line of the same block:

```bash
REASON='…'
echo "| $(date +%F) | M7 domain (Task 11) | $(git rev-parse --short HEAD) | none | not run | Ethan: $REASON |" >> design/ci-dry-runs.md
```

On a failed run, read `gh run view "$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')" --log-failed`.

- [ ] **Step 10: Record, and ask about the release**

Fill the Domain table's rows, then:

```bash
git add design/release-checklist.md design/ci-dry-runs.md
git commit -m "Record the move to stickermine.app" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Push with Ethan's yes. Ask him whether to release the new About link now as v1.1: if yes, follow the "Every release" list in `design/release-checklist.md` (with `Info.plist` moved ahead to `1.2` before the tag) and add a `## v1.1` table with the same rows as `## v1.0`; if not, write "next release" in the Domain table's last row.
