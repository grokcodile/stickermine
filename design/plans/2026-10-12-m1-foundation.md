# M1 Foundation and Sticker-Window Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Scaffold the Stickermine repo (root `Info.plist`, a hand-written Xcode project with a hosted Swift Testing target, `build.sh`, `install.sh`, `release.yml`, a minimal LSUIElement app), prove it on CI with a dry run, and run the sticker-window spike: Maple on the main display at desktopIcon + 1, double-click to edit, drag, pinch and rotate, with every spike observation recorded in `design/spike-results.md`.

**Architecture:** `Stickermine.xcodeproj` is written by hand in the "Xcode 16.0" format (objectVersion 77) with two folder-synchronized groups, so new Swift files join their target just by being in `Stickermine/` or `StickermineTests/`. The app is a SwiftUI `@main` whose only scene is `Settings { EmptyView() }`; `AppDelegate` skips all startup work when it hosts the tests and, when launched with `-spike`, starts a temporary `SpikeController`. Window policy lives in one place (`PanelPolicy`); each sticker is a `StickerPanel` whose content view is a layer-hosting `StickerView`. `build.sh` builds the project unsigned with `xcodebuild`, checks the product against the root plist, strips it, and signs it exactly like Pullcord.

**Tech Stack:** Swift (language mode 5), AppKit + SwiftUI, Core Animation, Core Image, IOSurface, `os.Logger`, Swift Testing, `xcodebuild` (Xcode 27 beta locally, Xcode 26.6 on CI), bash, GitHub Actions.

**Spec:** `design/specs/2026-10-12-stickermine-v1-design.md`. This milestone implements section 3 (macOS and API ceiling, bundle ID, Xcode project settings, repo layout, LICENSE, .gitignore), section 17 (`build.sh`, `install.sh`, `release.yml`, early CI), section 18 (test hosting; the spike list), and the spike parts of section 4 (window ownership, panel policy), section 9 (level, collection behaviour, panel flags, alpha hit-testing, padded frame, content layer, IOSurface contents, memory, stale windows) and section 10 (double-click, `acceptsFirstMouse`, `canBecomeKey`, drag, pinch, rotate, Esc and resign-key ending editing). The plan index with the Interface Contract is `design/plans/2026-10-12-stickermine-v1-plan.md`.

## Contract changes

**No contract signature changes.** Additions and one deferral:

- **Deferred to M2:** `StickerView.show(_ rendered: RenderedSticker, shadow: StyleParameters?, style: StickerStyle)` is not written in M1, because `RenderedSticker`, `StyleParameters` and `StickerStyle` don't exist until M2. M1's spike signature is `StickerView.showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?)`, and it stays as the primitive. M2 adds the contract method inside `StickerView`, calling `showContents(rendered.contents, pointSize: rendered.pointBounds, shadow: nil)` (M2's baseline renderer has no shadow). M3 then passes a `LayerShadow` built from `StyleParameters`: its pixel values divided by the panel's backing scale factor, and `nil` for `.none`.
- **Added (used by M2, M3 and M5):**
  - `PanelPolicy.floatingLevel: NSWindow.Level` (`.floating`) and `PanelPolicy.level(onTop: Bool) -> NSWindow.Level`.
  - `StickerPanel.onResignKey: (() -> Void)?`.
  - `struct LayerShadow: Equatable { var radius: CGFloat; var opacity: Float; var offset: CGFloat; var margin: CGFloat { get } }` (points; margin = ceil(3 × radius) + |offset|).
  - On `StickerView`: `let hitPadLayer: CALayer`, `let outlineLayer: CAShapeLayer`, `var onKeyDown: ((NSEvent) -> Bool)?`, `var onMagnify: ((NSEvent) -> Void)?`, `var onRotate: ((NSEvent) -> Void)?`, `var onDragEnded: (() -> Void)?`, `private(set) var contentPointSize: CGSize`, `private(set) var layerShadow: LayerShadow?`, `private(set) var contentScale: CGFloat`, `private(set) var contentRotation: CGFloat`, `private(set) var isShowingEditingChrome: Bool`, `static let hitPadAlpha: CGFloat`, `static func frameSize(pointSize: CGSize, shadow: LayerShadow?) -> CGSize`, `static func boundingSize(of size: CGSize, scale: CGFloat, rotation: CGFloat) -> CGSize`, `func showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?)`, `func clearContents()`, `func setContentTransform(scale: CGFloat, rotation: CGFloat)`, `func setEditingChrome(_ visible: Bool)`.
  - `enum SurfaceContents { static func make(from image: CGImage) -> IOSurface? }`.
  - `enum BundledImages { static let mapleName: String; static func cgImage(named name: String) -> CGImage? }`.
  - `AppDelegate.isRunningTests: Bool` (`nonisolated static`) and `AppDelegate.didRunStartup: Bool` (`private(set) static`, set on the line right after the test-host guard so `AppDelegateTests` can prove the guard returned early; every later version of `applicationDidFinishLaunching` keeps that line there).
  - Test support: `enum SourceFiles` (`repoRoot`, `appRoot`, `contents(of:)`, `swiftFiles()`) and `enum TestImages` (`bands(width:height:top:bottom:colorSpace:)`, `rgba(of:x:y:)`) in `StickermineTests/TestSupport.swift`.
- **Temporary:** `SpikeController` (`Stickermine/Stickers/SpikeController.swift`) and the `-spike` branch in `AppDelegate.applicationDidFinishLaunching`. **M2 deletes both** when `StickerManager` and its own debug path arrive. Everything else from this milestone stays in the target.

Task 12 copies these additions into the index's Interface Contract.

## Global Constraints

All constraints in the index apply. Milestone-specific ones, verbatim from the spec:

- "**Project format "Xcode 16.0"** (objectVersion 77, the oldest that supports folder-synchronized groups), never a 26.3 or 27.0 format, so Xcode 26.6 on CI can open it. Two synchronized root groups: `Stickermine/` and `StickermineTests/`." (section 3)
- "`ENABLE_APP_SANDBOX = NO`, no `CODE_SIGN_ENTITLEMENTS`, `CODE_SIGNING_ALLOWED = NO` for command-line builds (signing happens in `build.sh`)." (section 3)
- "`MACOSX_DEPLOYMENT_TARGET = 26.0` at project level." (section 3)
- "**Info.plist:** `INFOPLIST_FILE = Info.plist`, `GENERATE_INFOPLIST_FILE = NO`, and no `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` or `INFOPLIST_KEY_*` settings at any level." The test bundle is the one exception to `GENERATE_INFOPLIST_FILE = NO`: it never ships, has no version settings, and needs some Info.plist, so its target sets `GENERATE_INFOPLIST_FILE = YES` (pinned by `ProjectSettingsTests`; Task 12 Step 3 records the exception in the index's Global Constraints).
- "The root `Info.plist` holds literal strings (never `$(…)` variables) … No usage-description keys (none exists for Screen Recording)." (section 3)
- "**A shared scheme** `Stickermine` is committed (`xcshareddata/xcschemes/Stickermine.xcscheme`), with `StickermineTests` in its Test action." (section 3)
- "**Panel policy (every `NSPanel` the app creates):** set `isReleasedWhenClosed = false` and an explicit `hidesOnDeactivate` …; never touch `isFloatingPanel` (setting it rewrites the level); set `level` last." (section 4)
- "**Never write `ignoresMouseEvents`.** Left untouched, the window server hit-tests by the rendered alpha … Writing it, even `false`, switches the window to rectangle hit-testing permanently." (section 9)
- "**Test hosting:** the test bundle is hosted in the app. `AppDelegate` returns before any startup work … when `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`." (section 18)
- "Whether the spike's code is kept in the real target is a plan decision." Decision: kept, except `SpikeController` and the `-spike` launch path (see Contract changes).
- Load bundled images by name (`NSImage(named:)` through `BundledImages`), never through Xcode's generated asset symbols (`ImageResource`): `build.sh`'s macOS 26 SDK type-check only sees the files in `Stickermine/`.
- Run every command from the repository root (`/Users/ethan/Developer/stickermine`) in bash or zsh, not fish: several commands use `VAR=$(…)` assignments and `<(…)` process substitution.
- Test command (from the index): `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`, with `-only-testing:StickermineTests/<Suite>` for one suite. Xcode prints a harmless `Error registering app with AppIntents framework … com.apple.linkd.autoShortcut` line while the test host starts; ignore it.

## Review Focus

The index's five Review Focus items belong to other milestones (1 → M2, 2 and 3 → M4, 4 → M3, 5 → M6); this milestone owns none. It feeds item 1: spike rows 31–39 (display unplug and replug, lid, sleep, lock, overnight) decide whether M2 must rebuild panels after those events.

Milestone-specific failure modes:

1. **A sticker silently switches to rectangle hit-testing or loses its level** because some code writes `ignoresMouseEvents` or `isFloatingPanel` on a sticker panel (the getter reads `false` either way, so nothing at runtime shows it). Expect: transparent pixels always click through and the level never changes. Pinned by `PanelPolicyTests.stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag` (Task 6; Task 7 widens its mouse-flag scan to every file in `Stickermine/Stickers/`, so `SpikeController.swift` and the files M2–M5 add there are covered without editing the test) and spike rows 14–17 (Task 11).
2. **The shipped app's version or minimum macOS drifts from the root `Info.plist`** after an edit in Xcode's settings UI or an accepted "Update to recommended settings" (which can add `MARKETING_VERSION`, `INFOPLIST_KEY_*` or a newer project format). Expect: every release reports the tag's version and Xcode 26.6 still opens the project. Pinned by `ProjectSettingsTests` (Task 2) and `build.sh`'s plist and deployment-target checks, including the deliberate mismatch run in Task 3.
3. **`xcodebuild test` starts the real app**, which from M4 on would register the global shortcut, add a status item and restore stickers on the developer's desktop. Expect: the test host shows no window and does no startup work. Pinned by `AppDelegateTests` (Task 2): `detectsTheTestHost` pins the environment check, and `startupWorkIsSkippedInTheTestHost` pins the guard itself through `AppDelegate.didRunStartup` (nothing else M1 does at startup is visible to a test: the accessory policy matches `LSUIElement`, and the spike needs `-spike`).

## Files

| Path | Action | Responsibility |
|---|---|---|
| `Info.plist` | Create (Task 1) | Literal bundle metadata; `LSMinimumSystemVersion` is the one place the supported macOS is set |
| `LICENSE` | Create (Task 1) | MIT, "Copyright (c) 2026 Ethan (grokcodile)" |
| `Stickermine.xcodeproj/project.pbxproj` | Create (Task 2) | App target + hosted unit-test target, synchronized groups, every build setting |
| `Stickermine.xcodeproj/xcshareddata/xcschemes/Stickermine.xcscheme` | Create (Task 2) | Shared scheme; tests in its Test action |
| `Stickermine/App/StickermineApp.swift` | Create (Task 2) | `@main`; `Settings { EmptyView() }` only |
| `Stickermine/App/AppDelegate.swift` | Create (Task 2), modify (Task 10) | Test-host guard, accessory policy, the temporary `-spike` launch path |
| `Stickermine/Assets.xcassets/Contents.json` | Create (Task 2) | Asset catalog root |
| `Stickermine/Assets.xcassets/Maple.imageset/` | Create (Task 9) | Maple (`design/dog.png`) as a @2x image |
| `Stickermine/Stickers/PanelPolicy.swift` | Create (Task 6) | Level, collection behaviour, panel flags; the only sticker-panel factory |
| `Stickermine/Stickers/StickerPanel.swift` | Create (Task 6) | `canBecomeKey == isEditing`; resign-key callback |
| `Stickermine/Stickers/LayerShadow.swift` | Create (Task 7) | Layer-shadow values in points and the frame margin |
| `Stickermine/Stickers/StickerView.swift` | Create (Task 7) | Layer-hosting content view: content, hit pad and outline layers; mouse, key and gesture events |
| `Stickermine/Stickers/SurfaceContents.swift` | Create (Task 8) | CGImage → upright, colour-tagged IOSurface for layer contents |
| `Stickermine/UI/BundledImages.swift` | Create (Task 9) | Asset-catalog image → full-resolution CGImage |
| `Stickermine/Stickers/SpikeController.swift` | Create (Task 10); M2 deletes | The spike: four stickers, editing, gestures, staleness logging |
| `StickermineTests/TestSupport.swift` | Create (Task 2), modify (Task 7) | `SourceFiles` (repo paths), `TestImages` (bitmaps, pixel reads) |
| `StickermineTests/AppDelegateTests.swift` | Create (Task 2) | Test-host guard |
| `StickermineTests/ProjectSettingsTests.swift` | Create (Task 2) | Project format, forbidden and required settings, literal plist |
| `StickermineTests/PanelPolicyTests.swift` | Create (Task 6), modify (Task 7) | Level, behaviour, flags, key rules, source scan |
| `StickermineTests/LayerShadowTests.swift` | Create (Task 7) | Margin formula |
| `StickermineTests/StickerViewTests.swift` | Create (Task 7) | Layer tree, layout, shadow, chrome, transform |
| `StickermineTests/SurfaceContentsTests.swift` | Create (Task 8) | Orientation, alpha, colour-space tag |
| `StickermineTests/BundledImagesTests.swift` | Create (Task 9) | Maple loads at 620 × 910 with transparency |
| `build.sh` | Create (Task 3) | Unsigned xcodebuild, plist checks, strip, Pullcord's signing |
| `install.sh` | Create (Task 4) | Pullcord's, renamed |
| `.github/workflows/release.yml` | Create (Task 4) | Pullcord's with only `APP`/`CASK` changed |
| `design/ci-dry-runs.md` | Create (Task 5), append (Task 12) | Log of CI dry runs |
| `design/spike-results.md` | Create (Task 11), fill (Tasks 11–12) | Every spike item with how to test, expected, result, decision |
| `design/plans/2026-10-12-stickermine-v1-plan.md` | Modify (Task 12) | Interface Contract additions from this milestone; the test bundle's `GENERATE_INFOPLIST_FILE` exception in Global Constraints |

`.gitignore` already lists everything spec section 3 asks for (`build/` covers `build/DerivedData`); it is not changed.

---

### Task 1: Root Info.plist and LICENSE

**Files:**
- Create: `Info.plist`
- Create: `LICENSE`

**Interfaces:**
- Consumes: nothing.
- Produces: `Info.plist` keys read by later tasks: `LSMinimumSystemVersion` = `26.0` (build.sh, release.yml, the project's deployment target), `CFBundleShortVersionString`/`CFBundleVersion` = `0.1` (dev placeholder; the release commit "Stickermine 1.0" sets 1.0 before tagging `v1.0`), `CFBundleIdentifier` = `com.ethan.stickermine`, `CFBundleExecutable` = `Stickermine`.

- [ ] **Step 1: Run the check that must fail now**

```bash
plutil -lint Info.plist && plutil -extract LSMinimumSystemVersion raw Info.plist && diff LICENSE /Users/ethan/Developer/pullcord/LICENSE && echo "scaffold files OK"
```

Expected: `Info.plist: (The file “Info.plist” couldn’t be opened because there is no such file.)` and exit status 1.

- [ ] **Step 2: Create `Info.plist`**

`Info.plist` (complete file):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDisplayName</key>
	<string>Stickermine</string>
	<key>CFBundleExecutable</key>
	<string>Stickermine</string>
	<key>CFBundleIdentifier</key>
	<string>com.ethan.stickermine</string>
	<key>CFBundleName</key>
	<string>Stickermine</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>0.1</string>
	<key>LSMinimumSystemVersion</key>
	<string>26.0</string>
	<key>LSUIElement</key>
	<true/>
	<key>NSHumanReadableCopyright</key>
	<string>© 2026 Ethan Darling (grokcodile) — MIT License</string>
</dict>
</plist>
```

- [ ] **Step 3: Create `LICENSE`**

`LICENSE` (complete file, identical to Pullcord's):

```text
MIT License

Copyright (c) 2026 Ethan (grokcodile)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

- [ ] **Step 4: Run the checks**

```bash
plutil -lint Info.plist && plutil -extract LSMinimumSystemVersion raw Info.plist && diff LICENSE /Users/ethan/Developer/pullcord/LICENSE && echo "scaffold files OK"
grep -c '\$(' Info.plist
for p in .DS_Store build/ dist/ CLAUDE.md junk/ .claude/ '*.p8' '*.p12' '*.o' xcuserdata/ '*.xcuserstate'; do grep -qxF "$p" .gitignore || echo "missing from .gitignore: $p"; done
```

Expected, in order: `Info.plist: OK`, `26.0`, `scaffold files OK`, then `0` (no build-setting variables), and nothing from the `.gitignore` loop.

- [ ] **Step 5: Commit**

```bash
git add Info.plist LICENSE
git commit -m "Add the root Info.plist and the MIT license" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Xcode project, hosted test target and minimal app

**Files:**
- Create: `Stickermine.xcodeproj/project.pbxproj`
- Create: `Stickermine.xcodeproj/xcshareddata/xcschemes/Stickermine.xcscheme`
- Create: `Stickermine/App/StickermineApp.swift`
- Create: `Stickermine/App/AppDelegate.swift`
- Create: `Stickermine/Assets.xcassets/Contents.json`
- Test: `StickermineTests/TestSupport.swift`, `StickermineTests/AppDelegateTests.swift`, `StickermineTests/ProjectSettingsTests.swift`

**Interfaces:**
- Consumes: `Info.plist` (Task 1).
- Produces:
  - Targets `Stickermine` (app, product `Stickermine.app`) and `StickermineTests` (unit-test bundle hosted in the app); scheme `Stickermine`. Any `.swift` file placed under `Stickermine/` or `StickermineTests/` is compiled into that target with no project edit.
  - `@MainActor final class AppDelegate: NSObject, NSApplicationDelegate` with `nonisolated static var isRunningTests: Bool` and `private(set) static var didRunStartup: Bool`.
  - Test support: `enum SourceFiles { static var repoRoot: URL; static var appRoot: URL; static func contents(of relativePath: String) throws -> String; static func swiftFiles() -> [URL] }`.

Settings decided here (all visible in the file below): project level `ARCHS = arm64`, `MACOSX_DEPLOYMENT_TARGET = 26.0`, `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, `SWIFT_APPROACHABLE_CONCURRENCY = NO`, `GENERATE_INFOPLIST_FILE = NO`, `ENABLE_APP_SANDBOX = NO`, `CODE_SIGN_IDENTITY = "-"` with `CODE_SIGN_STYLE = Manual` (so `xcodebuild test` and Xcode's Run sign to run locally; `build.sh` passes `CODE_SIGNING_ALLOWED=NO` and signs on its own). App target: `INFOPLIST_FILE = Info.plist`, `PRODUCT_NAME = Stickermine`, `PRODUCT_BUNDLE_IDENTIFIER = com.ethan.stickermine`, `ENABLE_HARDENED_RUNTIME = YES` (Xcode drops it for its local ad-hoc signature with a note; the shipped runtime flag comes from `build.sh`'s `codesign --options runtime`). Test target: `TEST_HOST`/`BUNDLE_LOADER` pointing at the app's executable, `GENERATE_INFOPLIST_FILE = YES`. No `ASSETCATALOG_COMPILER_APPICON_NAME` yet: M6 adds the app icon and that setting together.

- [ ] **Step 1: Create the project file**

```bash
mkdir -p Stickermine.xcodeproj/xcshareddata/xcschemes Stickermine/App StickermineTests
```

`Stickermine.xcodeproj/project.pbxproj` (complete file; tabs for indentation as shown):

```text
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXContainerItemProxy section */
		5A1C0A000000000000000050 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = 5A1C0A000000000000000001 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = 5A1C0A000000000000000030;
			remoteInfo = Stickermine;
		};
/* End PBXContainerItemProxy section */

/* Begin PBXFileReference section */
		5A1C0A000000000000000004 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		5A1C0A000000000000000020 /* Stickermine.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = Stickermine.app; sourceTree = BUILT_PRODUCTS_DIR; };
		5A1C0A000000000000000021 /* StickermineTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = StickermineTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		5A1C0A000000000000000010 /* Stickermine */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = Stickermine;
			sourceTree = "<group>";
		};
		5A1C0A000000000000000011 /* StickermineTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = StickermineTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		5A1C0A000000000000000041 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		5A1C0A000000000000000044 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		5A1C0A000000000000000002 = {
			isa = PBXGroup;
			children = (
				5A1C0A000000000000000004 /* Info.plist */,
				5A1C0A000000000000000010 /* Stickermine */,
				5A1C0A000000000000000011 /* StickermineTests */,
				5A1C0A000000000000000003 /* Products */,
			);
			sourceTree = "<group>";
		};
		5A1C0A000000000000000003 /* Products */ = {
			isa = PBXGroup;
			children = (
				5A1C0A000000000000000020 /* Stickermine.app */,
				5A1C0A000000000000000021 /* StickermineTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		5A1C0A000000000000000030 /* Stickermine */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 5A1C0A000000000000000071 /* Build configuration list for PBXNativeTarget "Stickermine" */;
			buildPhases = (
				5A1C0A000000000000000040 /* Sources */,
				5A1C0A000000000000000041 /* Frameworks */,
				5A1C0A000000000000000042 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				5A1C0A000000000000000010 /* Stickermine */,
			);
			name = Stickermine;
			packageProductDependencies = (
			);
			productName = Stickermine;
			productReference = 5A1C0A000000000000000020 /* Stickermine.app */;
			productType = "com.apple.product-type.application";
		};
		5A1C0A000000000000000031 /* StickermineTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = 5A1C0A000000000000000072 /* Build configuration list for PBXNativeTarget "StickermineTests" */;
			buildPhases = (
				5A1C0A000000000000000043 /* Sources */,
				5A1C0A000000000000000044 /* Frameworks */,
				5A1C0A000000000000000045 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				5A1C0A000000000000000051 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				5A1C0A000000000000000011 /* StickermineTests */,
			);
			name = StickermineTests;
			packageProductDependencies = (
			);
			productName = StickermineTests;
			productReference = 5A1C0A000000000000000021 /* StickermineTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		5A1C0A000000000000000001 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {
					5A1C0A000000000000000030 = {
						CreatedOnToolsVersion = 16.0;
					};
					5A1C0A000000000000000031 = {
						CreatedOnToolsVersion = 16.0;
						TestTargetID = 5A1C0A000000000000000030;
					};
				};
			};
			buildConfigurationList = 5A1C0A000000000000000070 /* Build configuration list for PBXProject "Stickermine" */;
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = 5A1C0A000000000000000002;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = 5A1C0A000000000000000003 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				5A1C0A000000000000000030 /* Stickermine */,
				5A1C0A000000000000000031 /* StickermineTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		5A1C0A000000000000000042 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		5A1C0A000000000000000045 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		5A1C0A000000000000000040 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		5A1C0A000000000000000043 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		5A1C0A000000000000000051 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = 5A1C0A000000000000000030 /* Stickermine */;
			targetProxy = 5A1C0A000000000000000050 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin XCBuildConfiguration section */
		5A1C0A000000000000000060 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ARCHS = arm64;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Manual;
				COPY_PHASE_STRIP = NO;
				DEAD_CODE_STRIPPING = YES;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GENERATE_INFOPLIST_FILE = NO;
				MACOSX_DEPLOYMENT_TARGET = 26.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_APPROACHABLE_CONCURRENCY = NO;
				SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_STRICT_CONCURRENCY = minimal;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		5A1C0A000000000000000061 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				ARCHS = arm64;
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Manual;
				COPY_PHASE_STRIP = NO;
				DEAD_CODE_STRIPPING = YES;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_APP_SANDBOX = NO;
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_USER_SCRIPT_SANDBOXING = YES;
				GENERATE_INFOPLIST_FILE = NO;
				MACOSX_DEPLOYMENT_TARGET = 26.0;
				SDKROOT = macosx;
				SWIFT_APPROACHABLE_CONCURRENCY = NO;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_STRICT_CONCURRENCY = minimal;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		5A1C0A000000000000000062 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.ethan.stickermine;
				PRODUCT_NAME = Stickermine;
			};
			name = Debug;
		};
		5A1C0A000000000000000063 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				COMBINE_HIDPI_IMAGES = YES;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = YES;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = com.ethan.stickermine;
				PRODUCT_NAME = Stickermine;
			};
			name = Release;
		};
		5A1C0A000000000000000064 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.ethan.stickermine.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Stickermine.app/Contents/MacOS/Stickermine";
			};
			name = Debug;
		};
		5A1C0A000000000000000065 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				GENERATE_INFOPLIST_FILE = YES;
				PRODUCT_BUNDLE_IDENTIFIER = com.ethan.stickermine.tests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/Stickermine.app/Contents/MacOS/Stickermine";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		5A1C0A000000000000000070 /* Build configuration list for PBXProject "Stickermine" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				5A1C0A000000000000000060 /* Debug */,
				5A1C0A000000000000000061 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		5A1C0A000000000000000071 /* Build configuration list for PBXNativeTarget "Stickermine" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				5A1C0A000000000000000062 /* Debug */,
				5A1C0A000000000000000063 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		5A1C0A000000000000000072 /* Build configuration list for PBXNativeTarget "StickermineTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				5A1C0A000000000000000064 /* Debug */,
				5A1C0A000000000000000065 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = 5A1C0A000000000000000001 /* Project object */;
}
```

- [ ] **Step 2: Create the shared scheme**

`Stickermine.xcodeproj/xcshareddata/xcschemes/Stickermine.xcscheme` (complete file):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES"
      buildArchitectures = "Automatic">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "5A1C0A000000000000000030"
               BuildableName = "Stickermine.app"
               BlueprintName = "Stickermine"
               ReferencedContainer = "container:Stickermine.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO"
            parallelizable = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "5A1C0A000000000000000031"
               BuildableName = "StickermineTests.xctest"
               BlueprintName = "StickermineTests"
               ReferencedContainer = "container:Stickermine.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "5A1C0A000000000000000030"
            BuildableName = "Stickermine.app"
            BlueprintName = "Stickermine"
            ReferencedContainer = "container:Stickermine.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "5A1C0A000000000000000030"
            BuildableName = "Stickermine.app"
            BlueprintName = "Stickermine"
            ReferencedContainer = "container:Stickermine.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 3: Check that Xcode reads the project**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild -list -project Stickermine.xcodeproj
```

Expected (after the "Command line invocation" lines):

```text
Information about project "Stickermine":
    Targets:
        Stickermine
        StickermineTests

    Build Configurations:
        Debug
        Release

    If no build configuration is specified and -scheme is not passed then "Release" is used.

    Schemes:
        Stickermine
```

- [ ] **Step 4: Write the failing tests**

`StickermineTests/TestSupport.swift` (complete file for now; Task 7 adds `TestImages`):

```swift
import Foundation

/// The repository's own files, for tests that guard rules no runtime check can see.
enum SourceFiles {
    /// The repository root, found from this file's location in `<repo>/StickermineTests`.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// `<repo>/Stickermine`, the app target's synchronized folder.
    static var appRoot: URL {
        repoRoot.appendingPathComponent("Stickermine")
    }

    static func contents(of relativePath: String) throws -> String {
        try String(contentsOf: appRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func swiftFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
}
```

`StickermineTests/AppDelegateTests.swift` (complete file):

```swift
import AppKit
import Testing
@testable import Stickermine

@MainActor
struct AppDelegateTests {
    @Test func detectsTheTestHost() {
        #expect(AppDelegate.isRunningTests)
    }

    @Test func startupWorkIsSkippedInTheTestHost() {
        #expect(!AppDelegate.didRunStartup)
    }

    @Test func testHostShowsNoWindows() {
        #expect(NSApp.windows.filter(\.isVisible).isEmpty)
    }
}
```

`StickermineTests/ProjectSettingsTests.swift` (complete file):

```swift
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
```

- [ ] **Step 5: Run the tests to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `** TEST FAILED **` with `error: Unable to resolve module dependency: 'Stickermine' (in target 'StickermineTests' from project 'Stickermine')` (the app target has no Swift sources yet).

- [ ] **Step 6: Write the minimal app**

`Stickermine/Assets.xcassets/Contents.json` (complete file):

```json
{
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`Stickermine/App/StickermineApp.swift` (complete file):

```swift
import SwiftUI

/// The SwiftUI entry point. Its only scene is an empty Settings scene, so SwiftUI
/// never opens a window of its own: every window in Stickermine is an AppKit
/// window or panel owned by a controller that AppDelegate holds (spec section 4).
@main
struct StickermineApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}
```

`Stickermine/App/AppDelegate.swift` (complete file; Task 10 replaces it):

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is hosting the unit-test bundle. Every startup step
    /// (single-instance check, hotkey, status item, sticker restore, launch repair,
    /// SMAppService, updater) must be skipped then, so tests never show a window
    /// or touch system state (spec section 18).
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Set right after the test-host guard, so a test can prove the guard returned
    /// early (nothing in M1's startup is visible enough to test otherwise).
    private(set) static var didRunStartup = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 7: Run the tests to see them pass**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 9 tests in 2 suites passed` and `** TEST SUCCEEDED **`. No window or Dock icon appears while it runs.

- [ ] **Step 8: Commit**

```bash
git status --short
git add Stickermine.xcodeproj Stickermine StickermineTests
git commit -m "Add the Xcode project, a hosted test target and the minimal app" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`git status --short` must show `Stickermine.xcodeproj/`, `Stickermine/` and `StickermineTests/` as untracked, besides any not-yet-committed plan files under `design/plans/`, and never `build/` (`xcodebuild` also creates `Stickermine.xcodeproj/project.xcworkspace/` holding only empty folders, which git ignores).

---

### Task 3: build.sh

**Files:**
- Create: `build.sh`

**Interfaces:**
- Consumes: `Info.plist` (Task 1); the `Stickermine` scheme and target (Task 2).
- Produces: `./build.sh` → a stripped, signed `build/Stickermine.app` (Developer ID `DEA1A3749B06CF3619F72152EFC35A48E380C4E4` when it is a valid identity, else ad-hoc; an explicitly set `SIGN_IDENTITY` that isn't usable is an error). `install.sh` (Task 4) and `release.yml` (`bash build.sh`) call it. Environment it honours: `DEVELOPER_DIR` (else falls back as below), `SIGN_IDENTITY`, `CI` (skips the local type-check).

What it does, in order: Pullcord's identity selection (verbatim); the `DEVELOPER_DIR` fallback (`/Applications/Xcode.app`, then `/Applications/Xcode-beta.app`, only when `DEVELOPER_DIR` is unset and `xcode-select -p` is the Command Line Tools); reads `MIN_MACOS` from `Info.plist` and fails if the project's `MACOSX_DEPLOYMENT_TARGET` (from `-showBuildSettings`) differs; the optional macOS 26 SDK type-check (spec section 3); `xcodebuild … CODE_SIGNING_ALLOWED=NO build` into `build/DerivedData` and `ditto` to `build/Stickermine.app`; the plist equality checks; `strip -x`; Pullcord's signing block (verbatim). Pullcord's `rm -rf ./build`, `mkdir`, `swiftc`, `cp Info.plist` and `cp icon/AppIcon.icns` lines are dropped: Xcode produces the bundle, and only `build/Stickermine.app` is replaced so `build/DerivedData` stays incremental. Two flags are added to the spec's xcodebuild line: `-destination 'generic/platform=macOS'` (without it xcodebuild warns "Using the first of multiple matching destinations") and `-quiet` (CI logs keep warnings and errors only). The plist check covers the spec's three keys plus `CFBundleIdentifier` and `CFBundleExecutable`, which `install.sh` relies on.

- [ ] **Step 1: Write `build.sh`**

`build.sh` (complete file):

```bash
#!/bin/bash
# Builds Stickermine.app into ./build. Used by both install.sh and CI.
#
# xcodebuild compiles the Xcode project unsigned (CODE_SIGNING_ALLOWED=NO);
# everything about the signature happens here, after the product is copied out
# of DerivedData and stripped.
#
# Code-signing: SIGN_IDENTITY picks the identity and must be a certificate's SHA-1
# hash (40 hex digits). It defaults to the Developer ID Application cert for team
# 8UP5SFXY56 (G2 Sub-CA, expires 2031-09-16). Sign by hash, never by name: the
# keychain can hold several identities with the identical name — the older cert
# Apple is retiring was there too — so a name is ambiguous (codesign refuses to
# choose, and the old `grep | head -1` quietly took the first, older one). An
# identity you set explicitly that isn't usable is an error, even if it's the same
# hash as the default; only the *default* missing (a machine that never had this
# cert) falls back to ad-hoc.
#
# The fallback matters for more than distribution. macOS keys Screen Recording
# to the app's designated requirement — with a Developer ID that's the stable
# "identifier + team OU", but an ad-hoc signature has no cert, so it reduces to
# the binary's cdhash. That changes on *every* build, so each rebuild looks like
# a brand-new app and has to be granted Screen Recording again.
set -e

cd "$(dirname "$0")"

APP_NAME="Stickermine"
BUILD_DIR="./build/${APP_NAME}.app"
PRODUCT="./build/DerivedData/Build/Products/Release/${APP_NAME}.app"
# Mirrored by the pinned hash in .github/workflows/release.yml.
DEFAULT_SIGN_IDENTITY="DEA1A3749B06CF3619F72152EFC35A48E380C4E4"
# Remember whether the caller chose the identity (empty counts as unset): one that
# was chosen and can't be used must fail rather than fall back to ad-hoc — CI
# exports exactly the default hash, so comparing against the default can't tell.
SIGN_IDENTITY_EXPLICIT="${SIGN_IDENTITY:+1}"
SIGN_IDENTITY="${SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
if ! printf '%s' "$SIGN_IDENTITY" | grep -Eq '^[0-9A-Fa-f]{40}$'; then
    echo "error: SIGN_IDENTITY must be a certificate SHA-1 hash (40 hex digits), not a name." >&2
    exit 1
fi
# `find-identity -v` lists only *valid* identities, so a cert that is expired,
# untrusted or missing its private key is absent here too — "not found" below
# means "not usable", not necessarily "not installed".
if ! security find-identity -v -p codesigning 2>/dev/null | grep -qiE "^ *[0-9]+\) ${SIGN_IDENTITY} "; then
    if [ -n "$SIGN_IDENTITY_EXPLICIT" ]; then
        echo "error: SIGN_IDENTITY=${SIGN_IDENTITY} is not among the valid code-signing identities" >&2
        echo "       (missing, expired, untrusted, or no private key)." >&2
        exit 1
    fi
    SIGN_IDENTITY=""
fi
BUILD_ABS="$PWD/${BUILD_DIR#./}"

# xcodebuild needs a full Xcode. When xcode-select points at the Command Line
# Tools (as on Ethan's Mac), use /Applications/Xcode.app, else Xcode-beta.app.
# CI's runner selects its Xcode itself, so this never fires there.
if [ -z "${DEVELOPER_DIR:-}" ] && [ "$(xcode-select -p 2>/dev/null)" = "/Library/Developer/CommandLineTools" ]; then
    for candidate in /Applications/Xcode.app /Applications/Xcode-beta.app; do
        if [ -d "${candidate}/Contents/Developer" ]; then
            export DEVELOPER_DIR="${candidate}/Contents/Developer"
            break
        fi
    done
    if [ -z "${DEVELOPER_DIR:-}" ]; then
        echo "error: xcode-select points at the Command Line Tools and no Xcode.app or Xcode-beta.app is installed." >&2
        exit 1
    fi
fi

# Info.plist's LSMinimumSystemVersion is the one place the supported macOS is set:
# the deployment target is read from it here, and release.yml writes the same
# value into the Homebrew cask's `depends_on macos`. The project's own
# MACOSX_DEPLOYMENT_TARGET must say the same, so a build from Xcode itself can't
# quietly target something else.
MIN_MACOS="$(plutil -extract LSMinimumSystemVersion raw Info.plist)"
PROJECT_MIN_MACOS="$(xcodebuild -project "${APP_NAME}.xcodeproj" -target "${APP_NAME}" \
    -configuration Release -showBuildSettings 2>/dev/null \
    | awk -F ' = ' '/^ *MACOSX_DEPLOYMENT_TARGET = / { print $2; exit }')"
if [ "$PROJECT_MIN_MACOS" != "$MIN_MACOS" ]; then
    echo "error: Info.plist LSMinimumSystemVersion is ${MIN_MACOS}, but the project's" >&2
    echo "       MACOSX_DEPLOYMENT_TARGET is '${PROJECT_MIN_MACOS}'. Make them equal." >&2
    exit 1
fi

# Optional fast pre-check against the API ceiling: CI builds with the macOS 26
# SDK, so a macOS 27-only symbol (even behind #available) fails the release.
# Locally Xcode only has the 27 SDK, but the Command Line Tools ship a 26 SDK to
# type-check against. Skipped on CI (it builds with the 26 SDK anyway) and on
# Macs without that SDK.
CLT_SWIFTC="/Library/Developer/CommandLineTools/usr/bin/swiftc"
SDK26="/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk"
if [ -z "${CI:-}" ] && [ -x "$CLT_SWIFTC" ] && [ -d "$SDK26" ]; then
    echo "Type-checking against $(basename "$(readlink "$SDK26" || echo "$SDK26")")..."
    SOURCES=()
    while IFS= read -r -d '' f; do SOURCES+=("$f"); done < <(find "${APP_NAME}" -name '*.swift' -print0)
    "$CLT_SWIFTC" -typecheck -swift-version 5 -parse-as-library \
        -sdk "$SDK26" -target "arm64-apple-macos${MIN_MACOS}" "${SOURCES[@]}"
fi

echo "Building ${APP_NAME}..."

rm -rf "${BUILD_DIR}"
# Releases are Apple Silicon only, so the architecture is pinned rather than
# taken from whatever Mac builds.
xcodebuild -project "${APP_NAME}.xcodeproj" -scheme "${APP_NAME}" -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath build/DerivedData \
    ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET="${MIN_MACOS}" CODE_SIGNING_ALLOWED=NO \
    -quiet build
ditto "${PRODUCT}" "${BUILD_DIR}"

# The built app must carry exactly the root Info.plist's version and minimum
# macOS: a build setting such as MARKETING_VERSION would silently override them,
# every release would ship as 1.0, and the updater would offer it forever.
for key in CFBundleIdentifier CFBundleExecutable CFBundleShortVersionString CFBundleVersion LSMinimumSystemVersion; do
    want="$(plutil -extract "$key" raw Info.plist)"
    got="$(plutil -extract "$key" raw "${BUILD_DIR}/Contents/Info.plist" 2>/dev/null || true)"
    if [ "$got" != "$want" ]; then
        echo "error: built ${key} is '${got}', but Info.plist says '${want}'." >&2
        exit 1
    fi
done

# Local symbols are a large share of the binary and nothing reads them at
# runtime — Swift reflection uses its own metadata sections, not the symbol
# table. An `xcodebuild build` Release product isn't stripped (measured about
# -18%). Has to happen before codesign, or it breaks the signature.
# (-x keeps global symbols; a full strip can break Swift binaries.)
strip -x "${BUILD_DIR}/Contents/MacOS/${APP_NAME}"

if [ -n "$SIGN_IDENTITY" ]; then
    echo "Signing with: ${SIGN_IDENTITY}"
    # --options runtime is the hardened runtime, which notarization requires.
    # --timestamp gets a trusted timestamp, so the signature outlives the cert.
    codesign --force --options runtime --timestamp \
        --sign "$SIGN_IDENTITY" "${BUILD_DIR}"
    codesign --verify --strict --verbose=1 "${BUILD_DIR}"
    # Prove who signed it. `codesign -dvv` can't: the old and new certs share a
    # name and team and it prints no hash, so a signature from the wrong one reads
    # identically. The signing certificate's own fingerprint is unambiguous.
    CERT_DIR="$(mktemp -d)"
    ( cd "$CERT_DIR" && codesign -d --extract-certificates "$BUILD_ABS" 2>/dev/null )
    SIGNED_BY="$(openssl x509 -inform DER -in "$CERT_DIR/codesign0" -noout -fingerprint -sha1 | sed 's/.*=//; s/://g')"
    rm -rf "${CERT_DIR:?}"
    if [ "$(printf '%s' "$SIGNED_BY" | tr a-f A-F)" != "$(printf '%s' "$SIGN_IDENTITY" | tr a-f A-F)" ]; then
        echo "error: signed by certificate ${SIGNED_BY}, expected ${SIGN_IDENTITY}." >&2
        exit 1
    fi
    echo "Signed by certificate ${SIGNED_BY}"
else
    echo "Signing identity ${DEFAULT_SIGN_IDENTITY} not among the valid identities — signing ad-hoc."
    echo "  (macOS will forget this app's permissions on every rebuild.)"
    # No --deep: Apple deprecated it for signing, and there is nothing nested
    # in this bundle to descend into anyway.
    codesign --force --sign - "${BUILD_DIR}"
fi

echo "Built ${BUILD_DIR}"
```

```bash
chmod +x build.sh
```

- [ ] **Step 2: Run the deployment-target guard against a deliberate mismatch (must fail)**

```bash
TMP="$(mktemp -d)" && cp -R build.sh Info.plist Stickermine Stickermine.xcodeproj "$TMP"/ && plutil -replace LSMinimumSystemVersion -string 26.1 "$TMP/Info.plist" && "$TMP/build.sh"; echo "exit=$?"; rm -rf "$TMP"
```

Expected:

```text
error: Info.plist LSMinimumSystemVersion is 26.1, but the project's
       MACOSX_DEPLOYMENT_TARGET is '26.0'. Make them equal.
exit=1
```

- [ ] **Step 3: Build**

```bash
./build.sh
```

Expected output (Developer ID certificate present, as on Ethan's Mac):

```text
Type-checking against MacOSX26.5.sdk...
Building Stickermine...
Signing with: DEA1A3749B06CF3619F72152EFC35A48E380C4E4
./build/Stickermine.app: replacing existing signature
./build/Stickermine.app: valid on disk
./build/Stickermine.app: satisfies its Designated Requirement
Signed by certificate DEA1A3749B06CF3619F72152EFC35A48E380C4E4
Built ./build/Stickermine.app
```

On a Mac without that certificate the signing lines are instead `Signing identity DEA1A374… not among the valid identities — signing ad-hoc.` and `(macOS will forget this app's permissions on every rebuild.)`. On a Mac without `/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk` the first line is absent.

- [ ] **Step 4: Inspect the product**

```bash
plutil -extract CFBundleShortVersionString raw build/Stickermine.app/Contents/Info.plist
plutil -extract LSUIElement raw build/Stickermine.app/Contents/Info.plist
codesign -dv build/Stickermine.app 2>&1 | grep -E '^(Identifier|CodeDirectory|TeamIdentifier)'
lipo -archs build/Stickermine.app/Contents/MacOS/Stickermine
vtool -show-build build/Stickermine.app/Contents/MacOS/Stickermine | grep -E 'minos|sdk'
```

Expected: `0.1`; `true`; `Identifier=com.ethan.stickermine`, a `CodeDirectory … flags=0x10000(runtime) …` line and `TeamIdentifier=8UP5SFXY56` (ad-hoc builds show `flags=0x2(adhoc)` and `TeamIdentifier=not set`); `arm64`; `minos 26.0` and `sdk 27.0` (the local Xcode 27 beta SDK; CI's build shows `sdk 26.5`).

Then confirm the two signing blocks are Pullcord's, byte for byte:

```bash
diff <(sed -n '/^DEFAULT_SIGN_IDENTITY=/,/^BUILD_ABS=/p' /Users/ethan/Developer/pullcord/build.sh) <(sed -n '/^DEFAULT_SIGN_IDENTITY=/,/^BUILD_ABS=/p' build.sh) && echo "identity block verbatim"
diff <(sed -n '/^if \[ -n "\$SIGN_IDENTITY" \]; then/,$p' /Users/ethan/Developer/pullcord/build.sh) <(sed -n '/^if \[ -n "\$SIGN_IDENTITY" \]; then/,$p' build.sh) && echo "signing block verbatim"
```

Expected: `identity block verbatim` and `signing block verbatim`, with no diff lines.

- [ ] **Step 5: Commit**

```bash
git add build.sh
git commit -m "Add build.sh: unsigned xcodebuild, plist checks, strip, pinned-hash signing" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: install.sh and the release workflow

**Files:**
- Create: `install.sh`
- Create: `.github/workflows/release.yml`

**Interfaces:**
- Consumes: `./build.sh` (Task 3).
- Produces: `./install.sh` (build, quit the running copy, replace `/Applications/Stickermine.app`, `open` it, report the instance count). `.github/workflows/release.yml` with `APP: Stickermine`, `CASK: stickermine`: a tag `v*` builds, notarizes and publishes `Stickermine.dmg` and bumps `Casks/stickermine.rb`; a manual run (`workflow_dispatch`) is a dry run that keeps the `Stickermine-dry-run` artifact for 7 days.

- [ ] **Step 1: Write `install.sh`**

`install.sh` (complete file; Pullcord's with `APP_NAME`, `BUNDLE_ID` and the comments changed):

```bash
#!/bin/bash
# Builds Stickermine and installs it to /Applications, quitting and replacing
# whatever copy is already there. This is the one to run day to day.
#
# Running the app straight out of ./build seems fine and isn't: a rebuild replaces
# that bundle, so a running instance has its bundle pulled out from under it. The
# process keeps going — its executable is still mapped — but LaunchServices now
# sees the rebuilt bundle as a different app on disk, so launching it again starts
# a SECOND copy rather than reusing the first. Do that a few times and several
# copies are running at once.
#
# That is worse than untidy. Every instance restores its own set of sticker
# windows, so each sticker sits on the desktop several times over, and every copy
# registers the same global capture shortcut (Carbon hotkeys aren't exclusive), so
# one keypress starts several captures at once.
# Installing to a stable path and quitting the old copy first is what stops it.
# Launching with `open` from /Applications also keeps the Screen Recording grant
# attached to the one Developer ID-signed copy.
#
# build.sh deliberately doesn't do any of this: CI calls it and needs the app left
# sitting in ./build.
set -e

cd "$(dirname "$0")"

APP_NAME="Stickermine"
BUNDLE_ID="com.ethan.stickermine"
BUILT="./build/${APP_NAME}.app"
DEST="/Applications/${APP_NAME}.app"

./build.sh

# -i because the executable's case has varied across builds: same bundle as far as
# this case-insensitive filesystem is concerned, different string as far as pkill is.
if pgrep -ix "$APP_NAME" >/dev/null; then
    echo "Quitting the running copy..."
    pkill -ix "$APP_NAME" || true
    # Wait for it to actually go. Its windows and hotkey are released by the
    # kernel when the process dies, so there is nothing to lose by being patient
    # here and something to lose by copying over a bundle still in use.
    for _ in $(seq 30); do
        pgrep -ix "$APP_NAME" >/dev/null || break
        sleep 0.1
    done
    if pgrep -ix "$APP_NAME" >/dev/null; then
        echo "  ...didn't quit on its own, forcing."
        pkill -9 -ix "$APP_NAME" 2>/dev/null || true
        sleep 0.3
    fi
fi

# Replace rather than move onto: this filesystem is case-insensitive, so an older
# /Applications/Stickermine.app IS this path, and `mv` onto an existing directory
# would nest the new bundle inside the old one instead of replacing it.
if [ -e "$DEST" ]; then
    installed_id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
        "${DEST}/Contents/Info.plist" 2>/dev/null || true)
    # Never delete something that isn't ours, however much the name matches.
    if [ "$installed_id" != "$BUNDLE_ID" ]; then
        echo "Refusing to replace ${DEST}." >&2
        echo "  Its bundle id is '${installed_id:-unreadable}', not ${BUNDLE_ID}." >&2
        exit 1
    fi
    rm -rf "$DEST"
fi

mv "$BUILT" "$DEST"
# Leave nothing behind to launch by accident — a stray second bundle is how this
# started. (That includes the copy xcodebuild left in build/DerivedData.)
rm -rf ./build

echo "Installed ${DEST}"
open "$DEST"

# Confirm exactly one is running, since "how many copies are there" is the whole point.
sleep 1
count=$(pgrep -ix "$APP_NAME" | wc -l | tr -d ' ')
echo "Running instances: ${count}"
if [ "$count" != "1" ]; then
    echo "  Expected exactly 1 — check with: pgrep -ilx ${APP_NAME}" >&2
fi
```

```bash
chmod +x install.sh
bash -n install.sh && echo "syntax OK"
diff <(grep -v '^ *#' /Users/ethan/Developer/pullcord/install.sh) <(grep -v '^ *#' install.sh)
```

Expected: `syntax OK`, then a diff of the code (comments excluded) that shows only the two names:

```text
5,6c5,6
< APP_NAME="Pullcord"
< BUNDLE_ID="com.ethan.pullcord"
---
> APP_NAME="Stickermine"
> BUNDLE_ID="com.ethan.stickermine"
```

- [ ] **Step 2: Copy Pullcord's workflow, changing only APP and CASK**

```bash
mkdir -p .github/workflows
sed -e 's/^      APP: Pullcord$/      APP: Stickermine/' -e 's/^      CASK: pullcord$/      CASK: stickermine/' /Users/ethan/Developer/pullcord/.github/workflows/release.yml > .github/workflows/release.yml
diff /Users/ethan/Developer/pullcord/.github/workflows/release.yml .github/workflows/release.yml
grep -c 'DEA1A3749B06CF3619F72152EFC35A48E380C4E4' .github/workflows/release.yml build.sh
```

Expected diff output, exactly:

```text
23,24c23,24
<       APP: Pullcord
<       CASK: pullcord
---
>       APP: Stickermine
>       CASK: stickermine
```

and the hash counts `.github/workflows/release.yml:1` and `build.sh:1` (the workflow's pinned `SIGN_IDENTITY` and build.sh's `DEFAULT_SIGN_IDENTITY` are the same certificate). The workflow's header comments still mention Key54 and "Both apps"; they stay as they are, so a `diff` against Pullcord's shows only `APP`/`CASK` (updating those comments is a cross-repo change for another day).

- [ ] **Step 3: MANUAL VERIFICATION of install.sh (replaces /Applications/Stickermine.app)**

Run `./install.sh`. It rebuilds, then deletes `./build` (including `build/DerivedData`, so the next test run rebuilds from scratch).

1. Expected output ends with `Installed /Applications/Stickermine.app` and `Running instances: 1`.
2. Expected on screen: nothing at all (no window, no Dock icon, no menu bar item; this build has no UI without `-spike`).
3. `pgrep -lx Stickermine` prints exactly one line.
4. Quit it: `pkill -x Stickermine`, then `pgrep -x Stickermine` prints nothing.

Record what you saw in the commit message body if anything differed.

- [ ] **Step 4: Commit**

```bash
git add install.sh .github/workflows/release.yml
git commit -m "Add install.sh and the release workflow from Pullcord" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: First CI dry run on the scaffold

The spec (section 17) wants the GitHub repo created and a manual dry run as soon as the scaffold builds: it is the only check against CI's Xcode 26.6 project format, SDK, Swift and actool. Creating the repo, pushing and starting a workflow are outward-facing steps: **each needs Ethan's explicit yes at the time**. Claude never handles CI secrets; without them the dry run builds and packages an ad-hoc-signed DMG and skips notarization, which is enough for this check.

**Files:**
- Create: `design/ci-dry-runs.md`

**Interfaces:**
- Consumes: everything from Tasks 1–4.
- Produces: `grokcodile/stickermine` on GitHub with `main` pushed (if Ethan agrees); `design/ci-dry-runs.md`, a running log that every later milestone appends to.

- [ ] **Step 1: Ask Ethan**

Ask, and wait for an explicit answer to each: "Create `grokcodile/stickermine` on GitHub now, private or public (spec section 20 leaves it to you)? Push `main` to it? Start a dry run of the release workflow?" If any answer is no, skip to Step 4 and record the dry run as not run, with his reason.

- [ ] **Step 2: Create the repo and push (only after the yes)**

```bash
gh repo create grokcodile/stickermine --private --source . --remote origin --description "Turn quick screenshots into fun stickers that live on your desktop."
git push -u origin main
```

Use `--public` instead of `--private` if that is what Ethan chose. Expected: `✓ Created repository grokcodile/stickermine on GitHub`, `✓ Added remote …`, then the push summary ending `branch 'main' set up to track 'origin/main'.`

- [ ] **Step 3: Run the dry run (only after the yes)**

```bash
BEFORE=$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')
gh workflow run release.yml --ref main
RUN_ID="$BEFORE"
for _ in $(seq 30); do
  sleep 2
  RUN_ID=$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId // 0')
  [ "$RUN_ID" != "$BEFORE" ] && break
done
if [ "$RUN_ID" = "$BEFORE" ]; then echo "error: the dispatched run never appeared" >&2; else gh run watch "$RUN_ID" --exit-status; fi
```

The loop waits (up to a minute) for the run this dispatch created, so `RUN_ID` can never be an older, already finished run. If it prints `error: the dispatched run never appeared`, check `gh run list --workflow release.yml` and repeat this step; don't record anything for it.

Expected: the run ends `✓ main Release · <id>` with exit status 0. In its log (`gh run view "$RUN_ID" --log`): Preflight prints `signing=false  notary=false  tap=false`; Build prints `Building Stickermine...`, then `signing ad-hoc` and `Built ./build/Stickermine.app`; the notarize, Gatekeeper, publish and tap steps are skipped; "Keep dry-run DMG" uploads `Stickermine-dry-run`.

If the Build step fails: `gh run view "$RUN_ID" --log-failed`. A project-format error ("future Xcode project file format") means the project file was changed from objectVersion 77; an unknown-symbol error means a macOS 27-only API slipped in. Fix it here, run the test suite, commit, ask Ethan before pushing again, and repeat Step 3.

- [ ] **Step 4: Record the result**

`design/ci-dry-runs.md` (complete file):

```markdown
# CI dry runs

`gh workflow run release.yml --ref main` builds the app on GitHub's `macos-26` runner (Xcode 26.6, macOS 26 SDK), signs and notarizes it when the repo's secrets exist (ad-hoc otherwise), packages `Stickermine.dmg` and keeps it as the `Stickermine-dry-run` artifact for 7 days. It is the only check against CI's project format, SDK, Swift and actool, so it runs as soon as the scaffold builds and again at the end of every milestone (spec section 17). One row per run, newest last.

| Date | Point | Commit | Run | Conclusion | Notes |
|---|---|---|---|---|---|
```

Then append this run's row. After a run (in the same shell as Step 3 `RUN_ID` is still set; in a new shell the first line sets it to the newest dispatched run, which by now is the one Step 3 watched):

```bash
RUN_ID=${RUN_ID:-$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')}
ROW=$(gh run view "$RUN_ID" --json headSha,url,conclusion --jq '"\(.headSha[0:7]) | \(.url) | \(.conclusion)"')
echo "| $(date +%F) | M1 scaffold (Task 5) | ${ROW} | |" >> design/ci-dry-runs.md
```

If the dry run was not run, append instead (with Ethan's reason in the last column):

```bash
echo "| $(date +%F) | M1 scaffold (Task 5) | $(git rev-parse --short HEAD) | none | not run | Ethan: $REASON |" >> design/ci-dry-runs.md
```

after setting `REASON` to his words, for example `REASON="repo later"`.

- [ ] **Step 5: Commit (push only with Ethan's yes)**

```bash
git add design/ci-dry-runs.md
git commit -m "Record the first CI dry run" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: PanelPolicy and StickerPanel

**Files:**
- Create: `Stickermine/Stickers/PanelPolicy.swift`
- Create: `Stickermine/Stickers/StickerPanel.swift`
- Test: `StickermineTests/PanelPolicyTests.swift`

**Interfaces:**
- Consumes: `SourceFiles` (Task 2).
- Produces (contract names):

```swift
@MainActor enum PanelPolicy {
    static var stickerLevel: NSWindow.Level { get }                       // desktopIcon + 1
    static let floatingLevel: NSWindow.Level                              // .floating
    static let stickerBehavior: NSWindow.CollectionBehavior               // [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]
    static func level(onTop: Bool) -> NSWindow.Level
    static func applyCommon(to panel: NSPanel, hidesOnDeactivate: Bool)   // isReleasedWhenClosed, hidesOnDeactivate, isExcludedFromWindowsMenu, isRestorable
    static func makeStickerPanel(contentRect: NSRect) -> StickerPanel
}
@MainActor final class StickerPanel: NSPanel {
    var placementID: UUID?
    var isEditing: Bool                                                   // canBecomeKey == isEditing; canBecomeMain == false
    var onResignKey: (() -> Void)?
}
```

- [ ] **Step 1: Write the failing test**

`StickermineTests/PanelPolicyTests.swift` (complete file; Task 7 widens the mouse-flag scan to every file in `Stickers/`):

```swift
import AppKit
import Testing
@testable import Stickermine

@MainActor
struct PanelPolicyTests {
    @Test func stickerLevelIsOneAboveTheDesktopIcons() {
        let icons = Int(CGWindowLevelForKey(.desktopIconWindow))
        #expect(PanelPolicy.stickerLevel.rawValue == icons + 1)
        #expect(PanelPolicy.stickerLevel.rawValue > Int(CGWindowLevelForKey(.desktopWindow)))
        #expect(PanelPolicy.stickerLevel < .normal)
    }

    @Test func floatOnTopUsesTheFloatingLevel() {
        #expect(PanelPolicy.level(onTop: true) == .floating)
        #expect(PanelPolicy.level(onTop: false) == PanelPolicy.stickerLevel)
    }

    @Test func stickerBehaviorIsExactlyTheSpecSet() {
        #expect(PanelPolicy.stickerBehavior == [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone])
        #expect(!PanelPolicy.stickerBehavior.contains(.fullScreenAuxiliary))
        #expect(!PanelPolicy.stickerBehavior.contains(.canJoinAllApplications))
        #expect(!PanelPolicy.stickerBehavior.contains(.moveToActiveSpace))
        #expect(!PanelPolicy.stickerBehavior.contains(.transient))
    }

    @Test func stickerPanelHasEveryPolicyFlag() {
        let rect = NSRect(x: 100, y: 100, width: 200, height: 150)
        let panel = PanelPolicy.makeStickerPanel(contentRect: rect)
        defer { panel.close() }
        #expect(panel.styleMask == [.borderless, .nonactivatingPanel])
        #expect(panel.backingType == .buffered)
        #expect(panel.level == PanelPolicy.stickerLevel)
        #expect(panel.collectionBehavior == PanelPolicy.stickerBehavior)
        #expect(!panel.isOpaque)
        #expect(panel.backgroundColor == .clear)
        #expect(!panel.hasShadow)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.canHide)
        #expect(panel.isExcludedFromWindowsMenu)
        #expect(panel.animationBehavior == .none)
        #expect(!panel.isRestorable)
        #expect(panel.sharingType == .none)
        #expect(!panel.isFloatingPanel)
        #expect(panel.frame == rect)
        #expect(!panel.isVisible)
    }

    @Test func stickerPanelBecomesKeyOnlyWhileEditing() {
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50))
        defer { panel.close() }
        #expect(!panel.canBecomeKey)
        panel.isEditing = true
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        panel.isEditing = false
        #expect(!panel.canBecomeKey)
    }

    @Test func applyCommonOverridesPlainPanelDefaults() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 10, height: 10),
                            styleMask: [.borderless], backing: .buffered, defer: true)
        // The trap the policy exists for: a plain NSPanel hides whenever the app
        // isn't active, which in an accessory app is almost always.
        #expect(panel.hidesOnDeactivate)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.isExcludedFromWindowsMenu)
        #expect(!panel.isRestorable)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: true)
        #expect(panel.hidesOnDeactivate)
    }

    @Test func stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag() throws {
        let mouseFlag = #"ignoresMouseEvents\s*="#
        for file in ["Stickers/PanelPolicy.swift", "Stickers/StickerPanel.swift"] {
            let text = try SourceFiles.contents(of: file)
            #expect(text.range(of: mouseFlag, options: .regularExpression) == nil, "\(file) writes ignoresMouseEvents")
        }
        let files = SourceFiles.swiftFiles()
        #expect(!files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: #"isFloatingPanel\s*="#, options: .regularExpression) == nil,
                    "\(url.lastPathComponent) assigns isFloatingPanel, which rewrites the level")
        }
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PanelPolicyTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'PanelPolicy' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Stickers/PanelPolicy.swift` (complete file):

```swift
import AppKit

/// Every window-policy constant lives here, so the sticker level, collection
/// behaviour and panel flags are decided in one place (spec sections 4 and 9).
///
/// Rules for every NSPanel the app creates:
/// - isReleasedWhenClosed is false, and hidesOnDeactivate is set explicitly (a
///   plain NSPanel defaults to true, which leaves it invisible and unclickable in
///   an accessory app that isn't active);
/// - the floating-panel flag is never touched: assigning it rewrites the level;
/// - the level is assigned last.
///
/// Sticker panels additionally never have their mouse-event flag written: left
/// untouched, the window server hit-tests by rendered alpha (alpha 0 clicks pass
/// through); writing it, with either value, switches the window to rectangle
/// hit-testing for good (spec section 9).
@MainActor
enum PanelPolicy {
    /// One level above Finder's desktop-icon window. Below it, Finder's
    /// screen-sized desktop window catches every click; above it is every app
    /// window. At exactly this level ScreenCaptureKit pickers that exclude desktop
    /// windows also leave stickers out.
    static var stickerLevel: NSWindow.Level {
        NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
    }

    /// The level of a sticker with Float on top switched on.
    static let floatingLevel: NSWindow.Level = .floating

    /// On every desktop Space, never on full-screen Spaces, untouched by Mission
    /// Control, and skipped by window cycling.
    static let stickerBehavior: NSWindow.CollectionBehavior = [
        .canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone,
    ]

    static func level(onTop: Bool) -> NSWindow.Level {
        onTop ? floatingLevel : stickerLevel
    }

    /// The flags every panel in the app gets, whatever it is for.
    static func applyCommon(to panel: NSPanel, hidesOnDeactivate: Bool) {
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = hidesOnDeactivate
        panel.isExcludedFromWindowsMenu = true
        panel.isRestorable = false
    }

    /// The only way a sticker window is created.
    static func makeStickerPanel(contentRect: NSRect) -> StickerPanel {
        let panel = StickerPanel(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.canHide = false
        panel.animationBehavior = .none
        // "Hide stickers from screen sharing and screenshots" defaults to on;
        // StickerManager switches live panels to .readOnly when it is off.
        panel.sharingType = .none
        panel.collectionBehavior = stickerBehavior
        panel.level = stickerLevel  // last
        return panel
    }
}
```

`Stickermine/Stickers/StickerPanel.swift` (complete file):

```swift
import AppKit

/// One borderless, non-activating panel per placed sticker. Created only by
/// `PanelPolicy.makeStickerPanel(contentRect:)`.
@MainActor
final class StickerPanel: NSPanel {
    /// The placement this panel draws (nil for the M1 spike's hard-coded stickers).
    var placementID: UUID?

    /// A borderless panel can't become key by default. It may while its sticker is
    /// being edited, so Esc, Delete and trackpad gestures arrive.
    var isEditing = false

    /// Called after the panel stops being key (a click elsewhere, Esc handing focus
    /// back, the app deactivating). Editing ends here.
    var onResignKey: (() -> Void)?

    override var canBecomeKey: Bool { isEditing }
    override var canBecomeMain: Bool { false }

    override func resignKey() {
        super.resignKey()
        onResignKey?()
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 16 tests in 3 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Stickers/PanelPolicy.swift Stickermine/Stickers/StickerPanel.swift StickermineTests/PanelPolicyTests.swift
git commit -m "Add PanelPolicy and StickerPanel" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: LayerShadow and StickerView

**Files:**
- Create: `Stickermine/Stickers/LayerShadow.swift`
- Create: `Stickermine/Stickers/StickerView.swift`
- Modify: `StickermineTests/TestSupport.swift` (whole file replaced: adds `TestImages`)
- Modify: `StickermineTests/PanelPolicyTests.swift` (one function replaced: the mouse-flag scan covers every file in `Stickers/`)
- Test: `StickermineTests/LayerShadowTests.swift`, `StickermineTests/StickerViewTests.swift`

**Interfaces:**
- Consumes: `StickerPanel.isEditing` (Task 6).
- Produces:

```swift
struct LayerShadow: Equatable {
    var radius: CGFloat; var opacity: Float; var offset: CGFloat           // points; offset is downward
    var margin: CGFloat { get }                                            // ceil(3 × radius) + |offset|
}
@MainActor final class StickerView: NSView {
    let contentLayer: CALayer
    let hitPadLayer: CALayer
    let outlineLayer: CAShapeLayer
    var onDoubleClick: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?
    var onMagnify: ((NSEvent) -> Void)?
    var onRotate: ((NSEvent) -> Void)?
    var onDragEnded: (() -> Void)?
    private(set) var contentPointSize: CGSize
    private(set) var layerShadow: LayerShadow?
    private(set) var contentScale: CGFloat
    private(set) var contentRotation: CGFloat
    private(set) var isShowingEditingChrome: Bool
    static let hitPadAlpha: CGFloat                                        // 1/255
    static func frameSize(pointSize: CGSize, shadow: LayerShadow?) -> CGSize
    static func boundingSize(of size: CGSize, scale: CGFloat, rotation: CGFloat) -> CGSize
    func showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?)
    func clearContents()
    func setContentTransform(scale: CGFloat, rotation: CGFloat)
    func setEditingChrome(_ visible: Bool)
}
enum TestImages {                                                          // test target
    static func bands(width: Int, height: Int, top: (UInt8, UInt8, UInt8), bottom: (UInt8, UInt8, UInt8), colorSpace: CGColorSpace = sRGB) -> CGImage
    static func rgba(of image: CGImage, x: Int, y: Int) -> [UInt8]
}
```

The property is `layerShadow`, not `shadow`: `NSView` already has `shadow: NSShadow?`.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/TestSupport.swift` (complete new version; replaces Task 2's file):

```swift
import CoreGraphics
import Foundation

/// Small bitmaps built in code, and a pixel reader.
enum TestImages {
    /// A `width` × `height` image whose top half is `top` and bottom half is
    /// `bottom` (opaque RGB, 0–255), with its right-most column fully transparent.
    static func bands(
        width: Int, height: Int,
        top: (UInt8, UInt8, UInt8), bottom: (UInt8, UInt8, UInt8),
        colorSpace: CGColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    ) -> CGImage {
        let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ rgb: (UInt8, UInt8, UInt8), _ rect: CGRect) {
            context.setFillColor(CGColor(
                colorSpace: colorSpace,
                components: [CGFloat(rgb.0) / 255, CGFloat(rgb.1) / 255, CGFloat(rgb.2) / 255, 1])!)
            context.fill(rect)
        }
        // Core Graphics' origin is bottom-left, so the top half starts at height / 2.
        fill(bottom, CGRect(x: 0, y: 0, width: width, height: height / 2))
        fill(top, CGRect(x: 0, y: height / 2, width: width, height: height - height / 2))
        context.clear(CGRect(x: width - 1, y: 0, width: 1, height: height))
        return context.makeImage()!
    }

    /// Premultiplied sRGB RGBA bytes of the pixel at (`x`, `y`), y = 0 being the top row.
    static func rgba(of image: CGImage, x: Int, y: Int) -> [UInt8] {
        let context = CGContext(
            data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
            bytesPerRow: image.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = context.data!.assumingMemoryBound(to: UInt8.self)
        let offset = y * image.width * 4 + x * 4
        return (0..<4).map { bytes[offset + $0] }
    }
}

/// The repository's own files, for tests that guard rules no runtime check can see.
enum SourceFiles {
    /// The repository root, found from this file's location in `<repo>/StickermineTests`.
    static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// `<repo>/Stickermine`, the app target's synchronized folder.
    static var appRoot: URL {
        repoRoot.appendingPathComponent("Stickermine")
    }

    static func contents(of relativePath: String) throws -> String {
        try String(contentsOf: appRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    static func swiftFiles() -> [URL] {
        let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }
}
```

`StickermineTests/LayerShadowTests.swift` (complete file):

```swift
import CoreGraphics
import Testing
@testable import Stickermine

struct LayerShadowTests {
    @Test func marginIsThreeRadiiRoundedUpPlusTheOffset() {
        #expect(LayerShadow(radius: 4, opacity: 0.35, offset: 2).margin == 14)
        #expect(LayerShadow(radius: 3.2, opacity: 0.35, offset: -2).margin == 12)
        #expect(LayerShadow(radius: 0, opacity: 0, offset: 0).margin == 0)
    }
}
```

`StickermineTests/StickerViewTests.swift` (complete file):

```swift
import AppKit
import Testing
@testable import Stickermine

@MainActor
struct StickerViewTests {
    private let shadow = LayerShadow(radius: 4, opacity: 0.35, offset: 2)
    private let pointSize = CGSize(width: 100, height: 50)

    private func makeView() -> StickerView {
        StickerView(frame: NSRect(origin: .zero, size: StickerView.frameSize(pointSize: pointSize, shadow: shadow)))
    }

    @Test func isLayerHostingWithItsThreeLayersInOrder() {
        let view = makeView()
        #expect(view.wantsLayer)
        let sublayers = view.layer?.sublayers ?? []
        #expect(sublayers.count == 3)
        #expect(sublayers.first === view.hitPadLayer)
        #expect(sublayers.dropFirst().first === view.contentLayer)
        #expect(sublayers.last === view.outlineLayer)
    }

    @Test func frameSizeAddsTheShadowMarginOnEverySide() {
        #expect(StickerView.frameSize(pointSize: pointSize, shadow: shadow) == CGSize(width: 128, height: 78))
        #expect(StickerView.frameSize(pointSize: pointSize, shadow: nil) == pointSize)
    }

    @Test func showContentsCentresTheBitmapAndAppliesTheLayerShadow() throws {
        let view = makeView()
        let image = TestImages.bands(width: 200, height: 100, top: (255, 0, 0), bottom: (0, 0, 255))
        view.showContents(image, pointSize: pointSize, shadow: shadow)
        #expect(view.contentLayer.bounds.size == pointSize)
        #expect(view.contentLayer.position == CGPoint(x: 64, y: 39))
        let contents = try #require(view.contentLayer.contents)
        #expect((contents as AnyObject) === image)
        #expect(view.contentLayer.shadowRadius == 4)
        #expect(view.contentLayer.shadowOpacity == 0.35)
        #expect(view.contentLayer.shadowOffset == CGSize(width: 0, height: -2))
        #expect(view.hitPadLayer.frame == view.bounds)
    }

    @Test func noShadowMeansAZeroShadowOpacity() {
        let view = StickerView(frame: NSRect(origin: .zero, size: pointSize))
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: pointSize, shadow: nil)
        #expect(view.contentLayer.shadowOpacity == 0)
        #expect(view.contentLayer.position == CGPoint(x: 50, y: 25))
    }

    @Test func clearContentsDropsTheBitmap() {
        let view = makeView()
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: pointSize, shadow: shadow)
        view.clearContents()
        #expect(view.contentLayer.contents == nil)
    }

    @Test func editingChromeIsAHitPadOfAlphaOneOver255() {
        let view = makeView()
        #expect(view.hitPadLayer.isHidden)
        #expect(view.outlineLayer.isHidden)
        view.setEditingChrome(true)
        #expect(view.isShowingEditingChrome)
        #expect(!view.hitPadLayer.isHidden)
        #expect(!view.outlineLayer.isHidden)
        let alpha = view.hitPadLayer.backgroundColor?.alpha ?? 0
        #expect(abs(alpha - 1.0 / 255.0) < 1e-6)
        view.setEditingChrome(false)
        #expect(view.hitPadLayer.isHidden)
        #expect(view.outlineLayer.isHidden)
    }

    @Test func outlineIsDrawnAtTheWindowsBackingScale() {
        let view = makeView()
        #expect(view.outlineLayer.contentsScale == 1)
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(origin: .zero, size: view.frame.size))
        defer { panel.close() }
        panel.contentView = view
        // A layer-hosting view's sublayers stay at 1× unless the view sets them,
        // which leaves the dashed outline blurry on a Retina display.
        #expect(view.outlineLayer.contentsScale == panel.backingScaleFactor)
    }

    @Test func acceptsTheFirstMouseClick() {
        #expect(makeView().acceptsFirstMouse(for: nil))
    }

    @Test func boundingSizeOfAScaledRotatedSticker() {
        let quarter = StickerView.boundingSize(of: pointSize, scale: 2, rotation: .pi / 2)
        #expect(abs(quarter.width - 100) < 1e-9)
        #expect(abs(quarter.height - 200) < 1e-9)
        let eighth = StickerView.boundingSize(of: CGSize(width: 100, height: 100), scale: 1, rotation: .pi / 4)
        #expect(abs(eighth.width - 100 * 2.0.squareRoot()) < 1e-9)
    }

    @Test func contentTransformScalesAndRotatesAroundTheCentre() {
        let view = makeView()
        view.showContents(TestImages.bands(width: 2, height: 2, top: (0, 0, 0), bottom: (0, 0, 0)),
                          pointSize: pointSize, shadow: shadow)
        view.setContentTransform(scale: 2, rotation: .pi / 2)
        let t = view.contentLayer.transform
        #expect(abs(t.m11) < 1e-9)
        #expect(abs(t.m12 - 2) < 1e-9)
        #expect(abs(t.m21 + 2) < 1e-9)
        #expect(abs(t.m22) < 1e-9)
        #expect(view.contentLayer.position == CGPoint(x: 64, y: 39))
        #expect(view.contentScale == 2)
    }
}
```

In `StickermineTests/PanelPolicyTests.swift`, replace the whole function that starts with `@Test func stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag() throws {` (its first loop reads `for file in ["Stickers/PanelPolicy.swift", "Stickers/StickerPanel.swift"] {`) with this complete version. Instead of a hand-kept list, the mouse-flag scan now covers every file in `Stickermine/Stickers/`, so `SpikeController.swift` (Task 10) and the files M2–M5 add there (`StickerManager`, `StickerEditor`, `ToolbarPill`) are checked without anyone remembering to extend it:

```swift
    @Test func stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag() throws {
        let mouseFlag = #"ignoresMouseEvents\s*="#
        // Every file in Stickers/ creates, fills or drives sticker panels. Only a file
        // implementing the hidden click-through fallback (spec section 9) may write
        // the flag, and it must be named here.
        let fallbackFiles: Set<String> = []
        let stickerFiles = SourceFiles.swiftFiles().filter {
            $0.deletingLastPathComponent().lastPathComponent == "Stickers"
                && !fallbackFiles.contains($0.lastPathComponent)
        }
        #expect(stickerFiles.count >= 3)
        for url in stickerFiles {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: mouseFlag, options: .regularExpression) == nil,
                    "\(url.lastPathComponent) writes ignoresMouseEvents")
        }
        let files = SourceFiles.swiftFiles()
        #expect(!files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(text.range(of: #"isFloatingPanel\s*="#, options: .regularExpression) == nil,
                    "\(url.lastPathComponent) assigns isFloatingPanel, which rewrites the level")
        }
    }
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/StickerViewTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'StickerView' in scope` and `error: cannot find 'LayerShadow' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Stickers/LayerShadow.swift` (complete file):

```swift
import CoreGraphics

/// A drop shadow drawn by Core Animation on the sticker's content layer, never
/// baked into the bitmap: a baked blur would catch clicks across its whole faint
/// tail, a layer shadow doesn't (spec section 8). All values are in points.
struct LayerShadow: Equatable {
    var radius: CGFloat
    var opacity: Float
    /// Downward offset on screen.
    var offset: CGFloat

    /// Transparent padding on every side of the sticker rect so the shadow is
    /// never clipped by the window (spec section 9).
    var margin: CGFloat { ceil(3 * radius) + abs(offset) }
}
```

`Stickermine/Stickers/StickerView.swift` (complete file):

```swift
import AppKit
import QuartzCore

/// The content view of a StickerPanel: a layer-hosting view whose root layer
/// holds three sublayers we own, back to front:
/// - `hitPadLayer`: alpha 1/255 over the whole padded frame while editing, so the
///   transparent parts of the box (and later the corner knob) can be grabbed;
///   hidden otherwise, so transparent pixels click through.
/// - `contentLayer`: the sticker bitmap (CGImage or IOSurface), centred, with the
///   layer shadow. Gesture transforms go on this layer, never on the root.
/// - `outlineLayer`: the subtle editing outline.
@MainActor
final class StickerView: NSView {
    let contentLayer = CALayer()
    let hitPadLayer = CALayer()
    let outlineLayer = CAShapeLayer()

    /// A double-click on an inactive (not editing) sticker.
    var onDoubleClick: (() -> Void)?
    /// Key presses while the panel is key. Return true when handled.
    var onKeyDown: ((NSEvent) -> Bool)?
    /// Trackpad pinch and rotate, delivered whatever the editing state.
    var onMagnify: ((NSEvent) -> Void)?
    var onRotate: ((NSEvent) -> Void)?
    /// Called right after `performDrag(with:)` returns for a drag started while editing.
    var onDragEnded: (() -> Void)?

    /// The sticker's unrotated, unscaled size in points (the bitmap's bounds).
    private(set) var contentPointSize: CGSize = .zero
    private(set) var layerShadow: LayerShadow?
    private(set) var contentScale: CGFloat = 1
    private(set) var contentRotation: CGFloat = 0
    private(set) var isShowingEditingChrome = false

    static let hitPadAlpha: CGFloat = 1.0 / 255.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let root = CALayer()
        root.isOpaque = false
        // Assigning the layer before wantsLayer makes this a layer-hosting view:
        // AppKit leaves the layer tree to us.
        layer = root
        wantsLayer = true

        hitPadLayer.backgroundColor = NSColor(white: 0, alpha: Self.hitPadAlpha).cgColor
        hitPadLayer.isHidden = true

        contentLayer.contentsGravity = .resize
        contentLayer.minificationFilter = .trilinear

        outlineLayer.fillColor = nil
        outlineLayer.strokeColor = NSColor.controlAccentColor.withAlphaComponent(0.9).cgColor
        outlineLayer.lineWidth = 1.5
        outlineLayer.lineDashPattern = [5, 4]
        outlineLayer.isHidden = true

        root.addSublayer(hitPadLayer)
        root.addSublayer(contentLayer)
        root.addSublayer(outlineLayer)
        layoutStickerLayers()
    }

    required init?(coder: NSCoder) {
        fatalError("StickerView is only created in code")
    }

    /// The window size for a sticker of `pointSize` with `shadow`: the sticker
    /// rect plus the shadow margin on every side (zero margin without a shadow).
    static func frameSize(pointSize: CGSize, shadow: LayerShadow?) -> CGSize {
        let margin = shadow?.margin ?? 0
        return CGSize(width: pointSize.width + 2 * margin, height: pointSize.height + 2 * margin)
    }

    /// The axis-aligned bounding box of `size` scaled by `scale` and rotated by
    /// `rotation` radians.
    static func boundingSize(of size: CGSize, scale: CGFloat, rotation: CGFloat) -> CGSize {
        let c = abs(cos(rotation))
        let s = abs(sin(rotation))
        return CGSize(
            width: (size.width * c + size.height * s) * scale,
            height: (size.width * s + size.height * c) * scale
        )
    }

    /// Shows `contents` (a CGImage or an IOSurface, as accepted by
    /// `CALayer.contents`) at `pointSize`, with an optional layer shadow.
    /// M2 adds `show(_:shadow:style:)` on top of this.
    func showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?) {
        contentPointSize = pointSize
        layerShadow = shadow
        withoutAnimation {
            contentLayer.contents = contents
            if let shadow {
                contentLayer.shadowColor = NSColor.black.cgColor
                contentLayer.shadowOpacity = shadow.opacity
                contentLayer.shadowRadius = shadow.radius
                // Layer-hosting views aren't flipped: negative y points down.
                contentLayer.shadowOffset = CGSize(width: 0, height: -shadow.offset)
            } else {
                contentLayer.shadowOpacity = 0
            }
        }
        layoutStickerLayers()
    }

    /// Drops the bitmap. Call before ordering out and closing a panel for good:
    /// a closed window keeps its contents alive until the next event otherwise.
    func clearContents() {
        withoutAnimation { contentLayer.contents = nil }
    }

    /// Scales and rotates the content around its centre (a live gesture preview).
    func setContentTransform(scale: CGFloat, rotation: CGFloat) {
        contentScale = scale
        contentRotation = rotation
        withoutAnimation {
            contentLayer.transform = CATransform3DScale(
                CATransform3DMakeRotation(rotation, 0, 0, 1), scale, scale, 1)
            updateOutlinePath()
        }
    }

    /// The hit pad and outline shown while the sticker is being edited.
    func setEditingChrome(_ visible: Bool) {
        isShowingEditingChrome = visible
        withoutAnimation {
            hitPadLayer.isHidden = !visible
            outlineLayer.isHidden = !visible
        }
    }

    /// Layer-hosting views don't pass the backing scale to their sublayers, so the
    /// dashed outline (the only layer that draws vector content) gets it here:
    /// when the view joins a window and whenever that window's scale changes.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        matchOutlineToBackingScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        matchOutlineToBackingScale()
    }

    private func matchOutlineToBackingScale() {
        guard let scale = window?.backingScaleFactor else { return }
        withoutAnimation { outlineLayer.contentsScale = scale }
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layoutStickerLayers()
    }

    private func layoutStickerLayers() {
        withoutAnimation {
            hitPadLayer.frame = bounds
            outlineLayer.frame = bounds
            contentLayer.bounds = CGRect(origin: .zero, size: contentPointSize)
            contentLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            updateOutlinePath()
        }
    }

    private func updateOutlinePath() {
        let box = Self.boundingSize(of: contentPointSize, scale: contentScale, rotation: contentRotation)
        let rect = CGRect(x: bounds.midX - box.width / 2, y: bounds.midY - box.height / 2,
                          width: box.width, height: box.height).insetBy(dx: -2, dy: -2)
        outlineLayer.path = CGPath(rect: rect, transform: nil)
    }

    private func withoutAnimation(_ body: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        body()
        CATransaction.commit()
    }

    // MARK: Events

    /// The first click on a sticker of an inactive app must reach us.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { false }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        let editing = (window as? StickerPanel)?.isEditing ?? false
        guard editing else {
            // Inactive stickers absorb single clicks; a double-click starts editing.
            if event.clickCount == 2 { onDoubleClick?() }
            return
        }
        window?.performDrag(with: event)
        onDragEnded?()
    }

    override func keyDown(with event: NSEvent) {
        if onKeyDown?(event) == true { return }
        super.keyDown(with: event)
    }

    override func magnify(with event: NSEvent) {
        onMagnify?(event)
    }

    override func rotate(with event: NSEvent) {
        onRotate?(event)
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 27 tests in 5 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Stickers/LayerShadow.swift Stickermine/Stickers/StickerView.swift StickermineTests/TestSupport.swift StickermineTests/LayerShadowTests.swift StickermineTests/StickerViewTests.swift StickermineTests/PanelPolicyTests.swift
git commit -m "Add StickerView, the layer-hosting sticker content view" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: IOSurface contents

**Files:**
- Create: `Stickermine/Stickers/SurfaceContents.swift`
- Test: `StickermineTests/SurfaceContentsTests.swift`

**Interfaces:**
- Consumes: `TestImages` (Task 7).
- Produces: `enum SurfaceContents { static func make(from image: CGImage) -> IOSurface? }`: a BGRA premultiplied surface, row 0 = the image's top row, rendered with `CIContext.render(_:to:bounds:colorSpace:)` in the image's own colour space and tagged with `kIOSurfaceColorSpace` (spec section 9). A BGRA surface can only hold RGB, so a gray, CMYK or indexed image is rendered and tagged as sRGB instead. The spike (Task 10) shows it next to CGImage contents; M3 decides which to keep from spike rows 15–16.

- [ ] **Step 1: Write the failing test**

`StickermineTests/SurfaceContentsTests.swift` (complete file):

```swift
import CoreGraphics
import CoreVideo
import IOSurface
import Testing
@testable import Stickermine

struct SurfaceContentsTests {
    @Test func surfaceIsUprightPremultipliedBGRA() throws {
        let image = TestImages.bands(width: 8, height: 8, top: (255, 0, 0), bottom: (0, 0, 255))
        let surface = try #require(SurfaceContents.make(from: image))
        #expect(surface.width == 8)
        #expect(surface.height == 8)
        #expect(surface.pixelFormat == kCVPixelFormatType_32BGRA)
        _ = surface.lock(options: .readOnly, seed: nil)
        defer { _ = surface.unlock(options: .readOnly, seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        let rowBytes = surface.bytesPerRow
        func bgra(_ x: Int, _ y: Int) -> [UInt8] { (0..<4).map { bytes[y * rowBytes + x * 4 + $0] } }
        let top = bgra(1, 0)        // memory row 0 must be the image's top (red)
        let bottom = bgra(1, 7)     // the last row its bottom (blue)
        let clear = bgra(7, 0)      // the transparent column stays transparent
        #expect(top[2] > 250 && top[0] < 5 && top[3] == 255)
        #expect(bottom[0] > 250 && bottom[2] < 5 && bottom[3] == 255)
        #expect(clear == [0, 0, 0, 0])
    }

    @Test func surfaceIsTaggedWithTheImageColourSpace() throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = TestImages.bands(width: 4, height: 4, top: (255, 0, 0), bottom: (0, 255, 0), colorSpace: p3)
        let surface = try #require(SurfaceContents.make(from: image))
        let tag = try #require(IOSurfaceCopyValue(surface, kIOSurfaceColorSpace))
        let space = try #require(CGColorSpace(propertyListPlist: tag))
        #expect(space.name == CGColorSpace.displayP3)
    }

    @Test func aGrayImageBecomesAnSRGBSurface() throws {
        // M3 can meet gray masters and bundled art; a BGRA surface can't be tagged gray.
        let gray = try #require(CGColorSpace(name: CGColorSpace.genericGrayGamma2_2))
        let context = try #require(CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: gray, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        let image = try #require(context.makeImage())
        let surface = try #require(SurfaceContents.make(from: image))
        let tag = try #require(IOSurfaceCopyValue(surface, kIOSurfaceColorSpace))
        let space = try #require(CGColorSpace(propertyListPlist: tag))
        #expect(space.model == .rgb)
        #expect(space.name == CGColorSpace.sRGB)
        _ = surface.lock(options: .readOnly, seed: nil)
        defer { _ = surface.unlock(options: .readOnly, seed: nil) }
        let bytes = surface.baseAddress.assumingMemoryBound(to: UInt8.self)
        // White stays white: B, G, R and A all near 255.
        #expect((0..<4).allSatisfy { bytes[$0] > 250 })
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SurfaceContentsTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'SurfaceContents' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Stickers/SurfaceContents.swift` (complete file):

```swift
import CoreGraphics
import CoreImage
import CoreVideo
import IOSurface

/// Turns a bitmap into an IOSurface for `CALayer.contents`. An IOSurface costs
/// about 1× the bitmap's bytes in the app; a CGImage as layer contents costs
/// about 2× (spec section 9). The M1 spike checks colour and alpha hit-testing
/// with these surfaces before M3 commits to them.
enum SurfaceContents {
    private static let context = CIContext(options: [.cacheIntermediates: false])

    /// A BGRA, premultiplied surface holding `image` upright (row 0 = top row),
    /// rendered in the image's own colour space when that is RGB (sRGB otherwise)
    /// and tagged with it.
    static func make(from image: CGImage) -> IOSurface? {
        let width = image.width
        let height = image.height
        // A BGRA surface can only hold RGB: gray, CMYK or indexed images are
        // rendered (and tagged) as sRGB instead.
        let rgbSpace = image.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard width > 0, height > 0,
              let colorSpace = rgbSpace ?? CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: 4,
            .bytesPerRow: IOSurfaceAlignProperty(kIOSurfaceBytesPerRow, width * 4),
            .pixelFormat: kCVPixelFormatType_32BGRA,
        ]
        guard let surface = IOSurface(properties: properties) else { return nil }
        // Core Image puts the image's (0,0) at the surface's lower-left corner,
        // which is the last row in memory, so the surface reads top-down.
        context.render(
            CIImage(cgImage: image),
            to: surface,
            bounds: CGRect(x: 0, y: 0, width: width, height: height),
            colorSpace: colorSpace
        )
        if let serialized = colorSpace.copyPropertyList() {
            IOSurfaceSetValue(surface, kIOSurfaceColorSpace, serialized)
        }
        return surface
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 30 tests in 6 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Stickers/SurfaceContents.swift StickermineTests/SurfaceContentsTests.swift
git commit -m "Add IOSurface layer contents tagged with the image's colour space" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Maple in the asset catalog

**Files:**
- Create: `Stickermine/Assets.xcassets/Maple.imageset/Contents.json`
- Create: `Stickermine/Assets.xcassets/Maple.imageset/Maple.png` (copied from `design/dog.png`)
- Create: `Stickermine/UI/BundledImages.swift`
- Test: `StickermineTests/BundledImagesTests.swift`

**Interfaces:**
- Consumes: `TestImages.rgba(of:x:y:)` (Task 7).
- Produces: the asset `Maple` (620 × 910 px stored as @2x, so 310 × 455 pt); `enum BundledImages { static let mapleName: String /* "Maple" */; static func cgImage(named name: String) -> CGImage? }`, which draws the largest representation 1:1 into an sRGB premultiplied RGBA bitmap. M6's tutorial sticker reuses both.

- [ ] **Step 1: Write the failing test**

`StickermineTests/BundledImagesTests.swift` (complete file):

```swift
import CoreGraphics
import Testing
@testable import Stickermine

struct BundledImagesTests {
    @Test func mapleLoadsAtFullResolutionWithItsTransparency() throws {
        let maple = try #require(BundledImages.cgImage(named: BundledImages.mapleName))
        #expect(maple.width == 620)
        #expect(maple.height == 910)
        #expect(TestImages.rgba(of: maple, x: 0, y: 0)[3] == 0)
        #expect(TestImages.rgba(of: maple, x: 310, y: 455)[3] == 255)
    }

    @Test func aMissingAssetIsNil() {
        #expect(BundledImages.cgImage(named: "NoSuchAsset") == nil)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/BundledImagesTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'BundledImages' in scope`.

- [ ] **Step 3: Add the asset and the loader**

```bash
mkdir -p Stickermine/Assets.xcassets/Maple.imageset Stickermine/UI
cp design/dog.png Stickermine/Assets.xcassets/Maple.imageset/Maple.png
cmp design/dog.png Stickermine/Assets.xcassets/Maple.imageset/Maple.png && echo "Maple copied"
```

Expected: `Maple copied`.

`Stickermine/Assets.xcassets/Maple.imageset/Contents.json` (complete file):

```json
{
  "images" : [
    {
      "filename" : "Maple.png",
      "idiom" : "universal",
      "scale" : "2x"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

`Stickermine/UI/BundledImages.swift` (complete file):

```swift
import AppKit

/// Bitmaps bundled in Assets.xcassets, read at full pixel resolution.
enum BundledImages {
    /// Maple, copied from design/dog.png (620 × 910 px, stored as @2x).
    static let mapleName = "Maple"

    /// The named asset's largest representation drawn 1:1 into an sRGB,
    /// premultiplied RGBA bitmap. nil when the asset is missing.
    static func cgImage(named name: String) -> CGImage? {
        guard let image = NSImage(named: name),
              let rep = image.representations.max(by: { $0.pixelsWide < $1.pixelsWide }),
              rep.pixelsWide > 0, rep.pixelsHigh > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: rep.pixelsWide, height: rep.pixelsHigh,
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        rep.draw(in: NSRect(x: 0, y: 0, width: rep.pixelsWide, height: rep.pixelsHigh))
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 32 tests in 7 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Assets.xcassets/Maple.imageset Stickermine/UI/BundledImages.swift StickermineTests/BundledImagesTests.swift
git commit -m "Add Maple to the asset catalog and a full-resolution loader" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The spike controller and the -spike launch path

**Files:**
- Create: `Stickermine/Stickers/SpikeController.swift` (temporary; M2 deletes it)
- Modify: `Stickermine/App/AppDelegate.swift` (whole file replaced)

**Interfaces:**
- Consumes: `PanelPolicy.makeStickerPanel(contentRect:)`, `PanelPolicy.level(onTop:)`, `StickerPanel.isEditing`/`onResignKey`, `StickerView` (all of Task 7's API), `LayerShadow`, `SurfaceContents.make(from:)`, `BundledImages.cgImage(named:)`.
- Produces: `@MainActor final class SpikeController { static let launchArgument: String /* "-spike" */; static let rebuildArgument: String /* "-spikeRebuild" */; init(arguments: [String]); func start() }`, started by `AppDelegate` only when the launch arguments contain `-spike` (never under tests). It logs to subsystem `com.ethan.stickermine`, category `spike`.

What the spike does: four stickers on the main display (`NSScreen.screens[0]`): Maple with CGImage contents and Maple with IOSurface contents (both with a `LayerShadow(radius: 8, opacity: 0.35, offset: 5)`, so a 29 pt margin), and a Display P3 swatch with each kind of contents. Double-click enters editing (outline + hit pad, `makeKey`, `NSApp.activate()`); while editing: `performDrag` to move, pinch and rotate transform the content layer (window grown once to a square at gesture start, shrunk to the transformed bounding box at the end), F toggles Float on top, Esc ends editing and reactivates the previously frontmost app; resigning key ends editing. A local `.leftMouseUp` monitor logs `local leftMouseUp` for mouse-ups the app receives on an editing sticker, which shows whether a drag's end reaches the app at all (row 4). It logs each sticker's window state at launch and on wake, screens-did-wake, Space change, screen-parameter change, lock and unlock, and again 1.5 s later; with `-spikeRebuild` it closes and recreates every panel 1.5 s after wake, unlock and screen changes.

- [ ] **Step 1: Write the spike controller**

`Stickermine/Stickers/SpikeController.swift` (complete file):

```swift
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
```

- [ ] **Step 2: Start it from AppDelegate**

`Stickermine/App/AppDelegate.swift` (complete new version; replaces Task 2's whole file, adding the `spike` property and the `-spike` branch at the end of `applicationDidFinishLaunching`):

```swift
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    /// True when this process is hosting the unit-test bundle. Every startup step
    /// (single-instance check, hotkey, status item, sticker restore, launch repair,
    /// SMAppService, updater) must be skipped then, so tests never show a window
    /// or touch system state (spec section 18).
    nonisolated static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Set right after the test-host guard, so a test can prove the guard returned
    /// early (nothing in M1's startup is visible enough to test otherwise).
    private(set) static var didRunStartup = false

    /// The M1 sticker-window spike, running only when launched with `-spike`.
    /// M2 removes it together with SpikeController.
    private var spike: SpikeController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(SpikeController.launchArgument) {
            let controller = SpikeController(arguments: arguments)
            spike = controller
            controller.start()
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
```

- [ ] **Step 3: Run the whole suite (the guard keeps the spike out of the test host)**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 32 tests in 7 suites passed` and `** TEST SUCCEEDED **`; no sticker appears on screen during the run.

- [ ] **Step 4: Build**

```bash
pkill -x Stickermine || true
./build.sh
```

Expected: ends with `Built ./build/Stickermine.app`.

- [ ] **Step 5: MANUAL VERIFICATION (Ethan at the Mac; record what was seen, never assume)**

In a second terminal: `log stream --style compact --predicate 'subsystem == "com.ethan.stickermine" AND category == "spike"'`. Run `open -g build/Stickermine.app --args -spike` (`-g` launches it in the background), then click a Safari window (or any other app's) so it is frontmost.

1. Expected: within a second, two Maples (middle row, right half of the main display) with soft shadows, and two rounded red swatches (bottom row). No Dock icon; Stickermine is not in ⌘Tab.
2. Expected log: four `[launch] <name> visible=true … level=-2147483602 key=false editing=false` lines (the level is desktopIcon + 1 on this macOS).
3. Single-click a Maple's opaque pixels. Expected: nothing changes; Safari stays frontmost.
4. Double-click it. Expected: a dashed accent-coloured outline around Maple; log `begin editing: key=true …` (the `local leftMouseUp` line right after it is the double-click's own release) and, 0.5 s later, `editing +0.5s: key=true appActive=true`.
5. Drag it. Expected: it follows the cursor; log `performDrag returned: buttonsDown=0 …`. Note whether a `local leftMouseUp` line follows it.
6. Press Esc. Expected: the outline disappears and Safari is frontmost again; log `end editing (escape)`.
7. Put a desktop file icon under a transparent area of a Maple window (beside her, inside the window), then click the icon. Expected: the icon is selected.
8. `pkill -x Stickermine`. Expected: all four stickers disappear.

Record each observation in Task 11's table (rows 1–5, 7 and 14 cover these).

- [ ] **Step 6: Commit**

```bash
git add Stickermine/Stickers/SpikeController.swift Stickermine/App/AppDelegate.swift
git commit -m "Add the sticker-window spike behind -spike" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: Spike results

**Files:**
- Create: `design/spike-results.md`

**Interfaces:**
- Consumes: the `-spike` build (Task 10).
- Produces: `design/spike-results.md`, every spike item from spec section 18 plus the IOSurface, shadow and staleness items, with Result filled from real observations and the Decisions table answered (row 38, rows 40–41 and their decisions are filled in Task 12). M2 (rebuild on wake, fallback click-through, Stage Manager), M3 (IOSurface or CGImage, shadow margin) and M5 (drag end, gestures, focus hand-back, clicking another sticker) read it.

- [ ] **Step 1: Write the results table**

`design/spike-results.md` (complete file; the Result and Outcome cells start empty):

````markdown
# Sticker-window spike: results

The M1 spike (spec section 18) checks the sticker window before any capture UI exists. Each row is one observation. **Result** is filled in by whoever runs the check, with what was actually seen (and the relevant log line where one is named). The checks need a person at the Mac: a trackpad, real displays, sleep and lock, and System Settings. An agent executing the plan asks Ethan to do them and records his answers; it never fills a Result itself.

## Setup

1. `pkill -x Stickermine || true` (only one copy may run).
2. `./build.sh` (Developer ID signed when the certificate is present).
3. In a second terminal: `log stream --style compact --predicate 'subsystem == "com.ethan.stickermine" AND category == "spike"'`
4. `open -g build/Stickermine.app --args -spike`, then click any other app's window so that app is frontmost.
5. Four stickers appear on the main display (the one with the menu bar): **maple-cgimage** (middle row, left), **maple-iosurface** (middle row, right), **swatch-cgimage** (bottom row, left), **swatch-iosurface** (bottom row, right). Each swatch is P3 red on its left half and sRGB red on its right half.
6. Controls: double-click a sticker to edit it. While editing: drag to move, pinch and rotate on the trackpad, **F** toggles Float on top, **Esc** stops editing. Clicking anywhere else is expected to stop editing too (row 8 checks it, including a click on another sticker). Quit with `pkill -x Stickermine` (or ⌘Q while a sticker is being edited).
7. Row 38 runs overnight in Task 12, after everything else. Row 39 relaunches with `-spike -spikeRebuild`; rows 40–41 use the CI dry-run build (Task 12 Step 6).

Record the environment before starting:

| Field | Value |
|---|---|
| Date | |
| macOS (`sw_vers -productVersion`, `sw_vers -buildVersion`) | |
| Mac model | |
| Displays (name, resolution, scale, which is main) | |
| Stage Manager on or off at the start | |
| App under test (local `build/` or CI dry-run DMG, with the run URL) | |

## A. Editing basics

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 1 | Level: above icons, below apps | Put a file icon on the desktop under maple-cgimage's opaque pixels; then drag a TextEdit window over the sticker. | Maple covers the icon; the TextEdit window covers Maple. Log `level=-2147483602` (or desktopIcon+1 on this OS). | | Keeps `PanelPolicy.stickerLevel` = desktopIcon + 1. If stickers can't be clicked or cover apps, switch to normal − 1 in `PanelPolicy` and repeat rows 1–5. |
| 2 | Inactive click is absorbed | With Safari (or any app) frontmost, single-click maple-cgimage's opaque pixels once. | Nothing happens: Safari stays frontmost (its menu bar stays), no desktop icon gets selected, no log line. | | Confirms `acceptsFirstMouse` + non-activating panel. If the click activates Stickermine, M5 must restore focus after single clicks. |
| 3 | Double-click enters editing | With Safari frontmost, double-click maple-cgimage's opaque pixels. | Dashed outline appears; log `begin editing: key=true appActive=…` and `editing +0.5s: key=true appActive=true`; note what the menu bar shows (an `.accessory` app is documented to have no menu bar of its own, so Safari's menus may stay visible while Stickermine is active). | | `appActive=true` at +0.5 s confirms `NSApp.activate()` is enough for M5's editing entry. If `key=false`, M5 must call `makeKeyAndOrderFront` after activation instead. |
| 4 | Drag moves the sticker | While editing, drag from an opaque pixel, release. | Sticker follows the cursor without lag; log `performDrag returned: buttonsDown=0 frame=…`; note whether a `local leftMouseUp` line follows. | | `buttonsDown=0`: M5 treats `performDrag(with:)` returning as the drag end. `buttonsDown≠0` (returned early): if `local leftMouseUp` was logged, M5 ends the drag on a local `.leftMouseUp` monitor; if not, M5 ends it on `windowDidMove` plus polling `NSEvent.pressedMouseButtons == 0`. |
| 5 | Hit pad grabs transparent pixels | While editing, drag from a transparent pixel inside the dashed box (for example beside Maple's ear). | The sticker drags. | | Confirms the alpha 1/255 hit pad. If the click passes through, raise `StickerView.hitPadAlpha` to 2/255 and retest. |
| 6 | Drag to another display | With two displays: while editing, drag maple-cgimage onto the other display and release. | It lands where released; log `screen=<other display>`. | | M5's cross-display drag can read `panel.screen`/frame after the drag. |
| 7 | Esc ends editing | While editing (Safari was frontmost before), press Esc. | Outline disappears; Safari is frontmost again; log `end editing (escape)`. | | Confirms the focus hand-back in M5 (`previousApp.activate`). |
| 8 | Clicking elsewhere ends editing | While editing maple-cgimage, click a Finder window or the desktop. Re-enter editing, then single-click swatch-cgimage's opaque pixels once. | Outline disappears; log `end editing (resignKey)`. For the click on the other sticker, record whether Maple's editing ends (by design it may not: a non-editing sticker can't become key). | | Confirms `resignKey` as M5's editing-end trigger. If the click on the other sticker doesn't end it, M5 ends editing on any mouse-down on a non-editing sticker. |
| 9 | Pinch while editing | While editing maple-cgimage, pinch on the trackpad over it. | Log `magnify phase=… editing=true`; Maple scales live around its centre; window grows once at the start and shrinks to fit at the end (`gesture end` log); no clipping. | | Events arrive: M5 implements pinch. No events: M5 relies on the corner knob alone and the README drops pinch. |
| 10 | Rotate while editing | While editing, rotate two fingers on the trackpad over Maple. | Log `rotate phase=… editing=true`; Maple turns around its centre; the shadow turns with it (expected until M5 re-bakes); no clipping. | | Same as row 9 for rotation. |
| 11 | Gestures when not editing | Without editing, pinch and rotate over Maple. | No visible change. Note whether `magnify`/`rotate` log lines appear with `editing=false`. | | Lines appear: gestures reach non-key panels and M5 must keep ignoring them outside editing. No lines: key status is required, as designed. |
| 12 | Float on top | While editing, press F; click another app's window so it moves over the sticker area; press F again after re-entering editing. | First F: log `float on top=true level=3`, the sticker stays above app windows. Second F: back under app windows. | | Confirms `.floating` for Float on top. |
| 13 | Float on top vs full-screen apps | With one sticker floated, switch to a full-screen app Space. | The sticker is not on the full-screen Space. | | v1 keeps `.fullScreenNone` for floated stickers (spec section 1: stickers over full-screen apps aren't in v1). |

## B. Click-through, contents and shadow

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 14 | Click-through, CGImage contents | Place a desktop file icon under a transparent corner of maple-cgimage's window (inside its frame, outside Maple). Click it, then double-click it. | The icon selects, then opens. | | Alpha hit-testing works: keep it (no `ignoresMouseEvents`). Fails: turn on the fallback design (spec section 9, `clickThroughFallback`) by default in M2. |
| 15 | Click-through, IOSurface contents | Same as row 14 with maple-iosurface. | Same as row 14. | | Passes: M3 may use IOSurface contents. Fails while row 14 passes: M3 uses CGImage contents. |
| 16 | P3 colour, IOSurface vs CGImage | On a P3 display (built-in MacBook display or a P3 external), compare swatch-cgimage with swatch-iosurface, and maple-cgimage with maple-iosurface. Optionally read values with Digital Color Meter set to "Display native values". | Each pair looks identical. On a P3 display each swatch's left half (P3 red) is visibly more saturated than its right half (sRGB red). | | Identical: M3 renders to IOSurface in the capture's colour space tagged with `kIOSurfaceColorSpace`. Any shift: M3 uses CGImage contents. |
| 17 | Swatch corners click through | Click on a desktop icon placed under a swatch's rounded transparent corner, for both swatches. | The icon gets the click. | | Same as rows 14–15. |
| 18 | Layer shadow fits the padded frame | Look at both Maples' shadows against a light wallpaper, especially at the bottom edge. | The shadow fades out fully, with no straight cut-off line; it falls downward. | | Margin `ceil(3 × radius) + abs(offset)` is enough. A cut-off: M3 raises the factor in `LayerShadow.margin`. |
| 19 | Shadow isn't hittable | Put a desktop icon under the visible shadow just below Maple's paws; click it. | The icon gets the click. | | Confirms the layer shadow (not baked) decision in spec section 8. |
| 20 | Stickers render with sharing type none | Look at all four stickers. | All render normally on screen (they use `sharingType = .none`). | | Confirms the default-on "Hide from screen sharing" setting doesn't affect on-screen drawing. |

## C. Spaces, Show Desktop, Mission Control, Stage Manager

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 21 | Every desktop Space | Add a second desktop in Mission Control; switch with ⌃→ and ⌃←. | All stickers are on both desktops at the same place. They stay still while the wallpaper slides (accepted trade-off). | | Confirms `.canJoinAllSpaces` + `.stationary`. |
| 22 | Not on full-screen Spaces | Make an app full screen (⌃⌘F); switch to it and back. | No sticker on the full-screen Space, none flashing during the transition. | | Confirms `.fullScreenNone`. |
| 23 | Show Desktop (F11 / fn-F11) | Press the Show Desktop key. Then double-click a sticker. Press it again. | Windows move aside; stickers stay put and visible; the double-click enters editing. | | No Show Desktop handling in M2/M5. If stickers move or vanish, M2 must re-assert frames after the reveal. |
| 24 | Show Desktop gesture | Spread thumb and three fingers on the trackpad; double-click a sticker; pinch back. | Same as row 23. | | Same as row 23. |
| 25 | Click wallpaper to reveal desktop | Desktop & Dock › "Click wallpaper to reveal desktop": Always (note the old value and restore it afterwards). Click a sticker's opaque pixels, then a transparent pixel, then the bare wallpaper. While the desktop is revealed, double-click a sticker. | Opaque pixel: no reveal. Transparent pixel or wallpaper: windows move aside; stickers stay put and visible. Record whether the double-click during the reveal enters editing (spec section 18: stickers stay put and clickable). | | Same as row 23. |
| 26 | Mission Control | Open Mission Control (F3 or ⌃↑), then close it. Repeat with one sticker floated (F). | Stickers stay visible in place and are not listed as windows. The floated sticker doesn't draw over Mission Control's own UI. | | Confirms `.stationary`. If the floated sticker covers Mission Control's UI, M2 tries `.transient` in place of `.stationary` for floated stickers only and repeats rows 21 and 26. |
| 27 | App Exposé and cycling | ⌃↓ in any app; ⌘Tab; ⌘\` in Finder. | Stickers stay in place; Stickermine isn't in ⌘Tab; ⌘\` never selects a sticker. | | Confirms `.ignoresCycle` and the accessory policy. |
| 28 | Stage Manager | Turn Stage Manager on (Control Center). Open two apps; double-click a sticker; drag it. | Stickers stay in place behind the stage; editing and dragging work. | | Works: README says Stickermine works with Stage Manager. Fails: M2 tests `.canJoinAllApplications` (only with `.fullScreenNone`) and the README states the limit. |
| 29 | Stage Manager, desktop items hidden | Desktop & Dock › Stage Manager "Show Items": uncheck "On Desktop" (restore afterwards). Repeat row 28. | Same as row 28: stickers stay above the hidden desktop's click-catcher and stay double-clickable. | | Same as row 28. |
| 30 | Hide Others | In another app press ⌥⌘H. | Stickers stay visible (`canHide = false`). | | Confirms `canHide = false`. |

## D. Displays, sleep, lock and staleness

Keep the `log stream` running for this section; every event logs each sticker's `visible`, `occlusionVisible`, `windowServerOnscreen`, `screen` and `frame`, immediately and again 1.5 s later.

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 31 | Display disconnect | With an external display: move maple-iosurface onto it (edit, drag), stop editing, then unplug the display. | No crash. Record where macOS puts the sticker (moved to the remaining display, or gone) from the `didChangeScreenParameters +1.5s` lines. | | M2's reconcile must order out panels of a missing display itself and never let macOS's move be saved. |
| 32 | Display reconnect | Plug the display back in. | Record whether the sticker returns to the external display by itself. | | M2 re-applies frames from the model on every reconcile (expected: macOS doesn't restore it). |
| 33 | Lid closed with an external display (MacBook only) | Close the lid with an external display and keyboard attached; open it again. | No crash; record where the stickers are after each step. | | Same as rows 31–32. |
| 34 | Sleep and wake | Apple menu › Sleep; wait 30 s; wake and unlock. Double-click each sticker. | All four draw; each enters editing; `didWake +1.5s` and `screensDidWake +1.5s` lines show `visible=true windowServerOnscreen=yes`. | | Draw and click: no rebuild on wake. Missing or unclickable: M2 rebuilds every panel on wake (spec section 9), if row 39 shows the rebuild fixes it. |
| 35 | Screen lock and unlock | ⌃⌘Q; wait 10 s; unlock. Double-click each sticker. | Same as row 34 with `screenIsUnlocked` lines. | | Same as row 34, for unlock. |
| 36 | Mirroring | Displays settings: mirror the built-in display to the external, then stop mirroring. | No crash; record where the stickers are while mirrored and afterwards. | | M2's mirror rules (spec section 11). |
| 37 | Resolution change | Displays settings: pick a different "Larger Text / More Space" option for the main display, then restore it. | Stickers stay on the main display; record whether any ends up off screen. | | M2's closest-size rule and draw-time clamping. |
| 38 | Long-lived panels | Runs last, in Task 12 Step 7, on the CI dry-run build (the local build when there is none). Leave the spike running overnight (at least 8 h, including a sleep). Next day, double-click each sticker. | All four draw and enter editing. | | Same as row 34. |
| 39 | Rebuild as the fix (only if 34, 35 or 38 failed) | `pkill -x Stickermine`, then `open -g build/Stickermine.app --args -spike -spikeRebuild`; repeat the failed row. | Log `rebuilding every panel after …`; then all stickers draw and enter editing. | | Rebuild fixes it: M2 closes and recreates all panels 1.5 s after wake, unlock and display changes, ending any editing first. |

## E. Builds and macOS versions

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 40 | CI dry-run build | Download the `Stickermine-dry-run` artifact from the CI dry run (Task 12), open the DMG, copy the app to a temporary folder (not /Applications), `pkill -x Stickermine`, then `open -g <folder>/Stickermine.app --args -spike` and click another app's window so it is frontmost. Repeat rows 1–5, 7–10, 14–18 and 21–23. | Same results as the local build. `vtool -show-build <app>/Contents/MacOS/Stickermine` shows `sdk 26.x`. | | Any difference: the behaviour depends on the linked SDK, so every later spike-style check runs on a dry-run build. |
| 41 | macOS 26.x | On a Mac running macOS 26.x (if one is available), run the dry-run build as in row 40 and repeat rows 1–5, 14–16 and 21–23. | Same results as on 27.x. | | Differences become explicit 26.x workarounds (or raise `LSMinimumSystemVersion`). |

## Decisions

Fill this in from the rows above once the run is complete.

| Question | Rows | Outcome |
|---|---|---|
| Sticker level stays desktopIcon + 1? | 1–3 | |
| Alpha click-through works, or the fallback mode becomes the default? | 14, 15, 17 | |
| Contents type for M3: IOSurface or CGImage? | 15, 16, 40 | |
| Do pinch and rotate reach the editing sticker? | 9–11 | |
| Does `performDrag(with:)` return at the drag's end? | 4 | |
| Does clicking another sticker end editing? | 8 | |
| Do panels go stale, and does a rebuild fix it? | 34, 35, 38, 39 | |
| Stage Manager supported as is? | 28, 29 | |
| Any difference between the local and the CI (26.x SDK) build? | 40, 41 | |
````

- [ ] **Step 2: Run sections A to D with Ethan**

Follow the file's Setup, then rows 1–37 in order, then row 39 if row 34 or 35 failed. Write `pending: runs in Task 12 Step 7` in row 38's Result: it needs the spike left running overnight, so it runs last (Task 12 Step 7) and blocks nothing before it. For each row, Ethan does the action; write in Result exactly what he reports, plus the named log line copied from the `log stream` terminal. If a row can't be run (no external display, no trackpad, no P3 display), write `not run: <reason>` in its Result. Rows 38 and 40–41 run in Task 12.

- [ ] **Step 3: Answer the Decisions table for rows 1–37 and 39**

For each question whose rows have results, write the outcome in one sentence naming the milestone it changes, for example `IOSurface: rows 15–16 matched CGImage, so M3 uses IOSurface contents.` Answer "Do panels go stale, and does a rebuild fix it?" from rows 34, 35 and 39 for now, ending with `(row 38 pending)`; Task 12 Step 7 updates it. Leave the last question ("Any difference between the local and the CI (26.x SDK) build?") for Task 12.

- [ ] **Step 4: Commit**

```bash
git add design/spike-results.md
git commit -m "Record the sticker-window spike results" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: Final build, full test run, CI dry run and contract update

**Files:**
- Modify: `design/ci-dry-runs.md` (append a row)
- Modify: `design/spike-results.md` (rows 38 and 40–41, the staleness decision and the last decision)
- Modify: `design/plans/2026-10-12-stickermine-v1-plan.md` (Interface Contract additions; the test bundle's `GENERATE_INFOPLIST_FILE` exception in Global Constraints)

**Interfaces:**
- Consumes: everything above.
- Produces: a green local build and test run, a recorded CI dry run on the M1 head, the overnight spike row (38), and the index's contract and Global Constraints updated with this milestone's additions.

- [ ] **Step 1: Build**

```bash
pkill -x Stickermine || true
./build.sh
```

Expected: ends with `Signed by certificate DEA1A3749B06CF3619F72152EFC35A48E380C4E4` and `Built ./build/Stickermine.app`.

- [ ] **Step 2: Run the whole test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 32 tests in 7 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 3: Update the index's Interface Contract and Global Constraints**

In `design/plans/2026-10-12-stickermine-v1-plan.md`, replace the whole code block under `### Stickers (M1 spike → M2/M3/M5)` (from the line `@MainActor enum PanelPolicy {` to the closing `}` of `StickerManager`) with:

```swift
@MainActor enum PanelPolicy {
    static var stickerLevel: NSWindow.Level { get }             // desktopIcon + 1
    static let floatingLevel: NSWindow.Level                    // .floating (Float on top)            [M1]
    static let stickerBehavior: NSWindow.CollectionBehavior
    static func level(onTop: Bool) -> NSWindow.Level            // floatingLevel or stickerLevel       [M1]
    static func makeStickerPanel(contentRect: NSRect) -> StickerPanel
    static func applyCommon(to panel: NSPanel, hidesOnDeactivate: Bool)   // isReleasedWhenClosed=false etc.
}
@MainActor final class StickerPanel: NSPanel {                  // canBecomeKey == isEditing
    var placementID: UUID?; var isEditing: Bool
    var onResignKey: (() -> Void)?                              //                                     [M1]
}
struct LayerShadow: Equatable {                                 // points; margin = ceil(3 × radius) + |offset|   [M1]
    var radius: CGFloat; var opacity: Float; var offset: CGFloat; var margin: CGFloat { get }
}
@MainActor final class StickerView: NSView {                    // layer-hosting; owns `contentLayer`
    let contentLayer: CALayer
    let hitPadLayer: CALayer; let outlineLayer: CAShapeLayer    // editing chrome                      [M1]
    var onDoubleClick: (() -> Void)?
    var onKeyDown: ((NSEvent) -> Bool)?; var onMagnify: ((NSEvent) -> Void)?           //              [M1]
    var onRotate: ((NSEvent) -> Void)?; var onDragEnded: (() -> Void)?                 //              [M1]
    private(set) var contentPointSize: CGSize; private(set) var layerShadow: LayerShadow?          //  [M1]
    private(set) var contentScale: CGFloat; private(set) var contentRotation: CGFloat              //  [M1]
    private(set) var isShowingEditingChrome: Bool; static let hitPadAlpha: CGFloat                 //  [M1]
    static func frameSize(pointSize: CGSize, shadow: LayerShadow?) -> CGSize                       //  [M1]
    static func boundingSize(of size: CGSize, scale: CGFloat, rotation: CGFloat) -> CGSize         //  [M1]
    func showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?)                    //  [M1]
    func clearContents(); func setContentTransform(scale: CGFloat, rotation: CGFloat)              //  [M1]
    func setEditingChrome(_ visible: Bool)                                                         //  [M1]
    func show(_ rendered: RenderedSticker, shadow: StyleParameters?, style: StickerStyle)          //  added in M2, on top of showContents
}
enum SurfaceContents { static func make(from image: CGImage) -> IOSurface? }       // upright BGRA, tagged colour space   [M1]
enum BundledImages { static let mapleName: String; static func cgImage(named name: String) -> CGImage? }   //            [M1]
extension AppDelegate {                                         // test-host guard                     [M1]
    nonisolated static var isRunningTests: Bool                 // XCTestConfigurationFilePath != nil
    private(set) static var didRunStartup: Bool                 // set right after the guard; AppDelegateTests expects false
}
@MainActor final class StickerManager {
    init(library: LibraryController, screens: ScreenProvider, renderer: StyleRenderer)
    func restoreAll()
    func scheduleReconcile()                                    // 450 ms debounce
    func reconcileNow()
    func place(sticker: UUID, style: StickerStyle, centerOnScreen: NSPoint, pointSize: CGSize)   // a user placement
    func remove(placement: UUID)
    func deleteSticker(_ sticker: UUID)
    func panel(for placement: UUID) -> StickerPanel?
    func setSharingHidden(_ hidden: Bool)
    var editingPlacement: UUID? { get }
    func endEditing(discardGesture: Bool)
}
```

Also, in the index's **Global Constraints**, in the line that starts `- Project format **"Xcode 16.0"**`, replace

```text
`GENERATE_INFOPLIST_FILE = NO`;
```

with

```text
`GENERATE_INFOPLIST_FILE = NO` (the never-shipped `StickermineTests` bundle alone uses `YES`; pinned by `ProjectSettingsTests`);
```

so later milestones' reviewers read the test target's setting as the recorded exception it is, not a violation. Check: `grep -c 'bundle alone uses' design/plans/2026-10-12-stickermine-v1-plan.md` prints `1`.

- [ ] **Step 4: Commit locally**

```bash
git add design/plans/2026-10-12-stickermine-v1-plan.md
git commit -m "Record M1's contract additions in the plan index" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: CI dry run (needs Ethan's explicit yes now)**

If `git remote get-url origin` fails, the GitHub repo doesn't exist yet: append the "not run" row to `design/ci-dry-runs.md` (Task 5 Step 4's second command, with `M1 end (Task 12)` as the point and `REASON="no GitHub repo yet"`), mark rows 40–41 of `design/spike-results.md` `not run: no CI build yet`, and go to Step 7 (row 38 then runs on the local build).

Otherwise ask Ethan: "Push main to grokcodile/stickermine and start a release-workflow dry run?" Only after his yes:

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
  ROW=$(gh run view "$RUN_ID" --json headSha,url,conclusion --jq '"\(.headSha[0:7]) | \(.url) | \(.conclusion)"')
  echo "| $(date +%F) | M1 end (Task 12) | ${ROW} | |" >> design/ci-dry-runs.md
fi
```

The loop waits (up to a minute) for the run this dispatch created, so Task 5's finished run can never be watched or recorded as the M1-end run. Expected: `gh run watch` exits 0 and the appended row ends `| success | |`. If it prints `error: the dispatched run never appeared`, nothing was recorded: check `gh run list --workflow release.yml` and rerun the lines from `BEFORE=` on. On a failed run, follow Task 5 Step 3's failure handling, then rerun this step.

- [ ] **Step 6: Spike rows 40–41 on the dry-run build**

In the same shell as Step 5 `RUN_ID` is still set; in a new shell the first line sets it to the newest dispatched run, which is the one Step 5 watched.

```bash
RUN_ID=${RUN_ID:-$(gh run list --workflow release.yml --branch main --event workflow_dispatch --limit 1 --json databaseId --jq '.[0].databaseId')}
rm -rf "${TMPDIR}stickermine-dryrun" && mkdir -p "${TMPDIR}stickermine-dryrun"
gh run download "$RUN_ID" --name Stickermine-dry-run --dir "${TMPDIR}stickermine-dryrun"
hdiutil attach -nobrowse -readonly -mountpoint "${TMPDIR}stickermine-dryrun/mnt" "${TMPDIR}stickermine-dryrun/Stickermine.dmg"
ditto "${TMPDIR}stickermine-dryrun/mnt/Stickermine.app" "${TMPDIR}stickermine-dryrun/Stickermine.app"
hdiutil detach "${TMPDIR}stickermine-dryrun/mnt"
vtool -show-build "${TMPDIR}stickermine-dryrun/Stickermine.app/Contents/MacOS/Stickermine" | grep -E 'minos|sdk'
pkill -x Stickermine || true
open -g "${TMPDIR}stickermine-dryrun/Stickermine.app" --args -spike
```

Expected: `minos 26.0` and `sdk 26.5` (or another 26.x), and the four stickers appear. Click another app's window so it is frontmost before repeating rows 2–3. Ethan repeats the rows listed in row 40 (and row 41 if a macOS 26.x Mac is available); record the results in rows 40–41 and answer the last Decisions question. Without the repo's signing secrets the dry-run app is ad-hoc signed; if Gatekeeper refuses to open it, run `xattr -dr com.apple.quarantine "${TMPDIR}stickermine-dryrun/Stickermine.app"` (it was downloaded through `gh`, so this is usually not needed) and open it again (with `open -g`, as above). Leave this dry-run spike running: Step 7 uses it for row 38.

- [ ] **Step 7: Row 38 overnight (the last check; nothing else waits on it)**

If Step 6 ran, its dry-run spike is still running: leave it. If it didn't (no CI build), start the local build instead:

```bash
pkill -x Stickermine || true
open -g build/Stickermine.app --args -spike
```

Keep the `log stream` terminal open. Leave the spike running for at least 8 h, including a sleep (Apple menu › Sleep, or the Mac sleeping on its own overnight). Next day, Ethan does row 38 (double-click each sticker); replace `pending: …` in its Result with what he reports and the `didWake +1.5s` and `screensDidWake +1.5s` lines. If row 38 failed and row 39 hasn't already shown that a rebuild fixes staleness, run row 39 for row 38 (`-spike -spikeRebuild`, another night) and record that too. Then rewrite the "Do panels go stale, and does a rebuild fix it?" outcome from rows 34, 35, 38 and 39, dropping `(row 38 pending)`, and quit:

```bash
pkill -x Stickermine
pgrep -x Stickermine || echo "not running"
```

Expected: `not running`.

- [ ] **Step 8: Commit the records**

```bash
git add design/ci-dry-runs.md design/spike-results.md
git commit -m "Record M1's CI dry run, the dry-run spike checks and the overnight check" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Push only with Ethan's yes (`git push`).

## Notes for later milestones

- **M2** deletes `Stickermine/Stickers/SpikeController.swift` and, in `AppDelegate`, the `spike` property and the `if arguments.contains(SpikeController.launchArgument) { … }` block, keeping `Self.didRunStartup = true` as the first line after the test-host guard (`AppDelegateTests.startupWorkIsSkippedInTheTestHost` relies on it); `StickerManager` creates panels through `PanelPolicy.makeStickerPanel(contentRect:)` and fills them with `StickerView.showContents` (wrapped by the contract's `show(_:shadow:style:)`). It reads `design/spike-results.md` rows 31–39 to decide whether to rebuild panels after wake, unlock and display changes.
- **M3** reads rows 15–16 (IOSurface or CGImage) and 18 (shadow margin).
- **M5** reads rows 3–11 (activation, drag end, gestures, focus hand-back, whether clicking another sticker ends editing). `StickerView.onDragEnded` fires right after `performDrag(with:)` returns.
- **M6** adds `AppIcon.appiconset` and sets `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon` in the app target's Debug and Release settings; it also owns the main menu (the SwiftUI `Settings` scene currently gives an active Stickermine an empty Settings window on ⌘,).
- Never accept Xcode's "Update to recommended settings" or a project-format change for this project: `ProjectSettingsTests` fails if either breaks the rules above.
