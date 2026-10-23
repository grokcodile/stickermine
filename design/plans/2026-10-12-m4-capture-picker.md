# M4 Capture, Cutout, Picker and Placement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make real stickers. A press of ⌃⌥⌘S (or a click on the new menu bar icon) checks Screen Recording, waits for the shortcut's modifiers to be let go, runs the system's `screencapture -i` crosshair, cuts the subjects out on-device with Vision, and opens a picker next to the cursor: click subjects in or out, switch to the whole image, fill holes, and pick one of four live style previews (or press 1–4). The master PNG and its history entry are saved, and the styled sticker follows the cursor until a click places it on the display under it. Everything that can go wrong on the way (no permission, Control still held, another capture already up, a cancel, a flat colour with no subject, the system's privacy alert landing on the picker, Quit in the middle) ends cleanly. The temporary `-debugPlaceMaple` path from M2/M3 goes away.

**Architecture:** Pure, AppKit-free types hold the rules: `Shortcut` (Carbon key + mask, label), `CaptureClassifier` (spec 5.7's first-match order), `MaskSampler` (click → subject on Vision's 512 × 512 top-down masks), `HoleFiller` (flood-fill the outside, fill the rest), `MasterImage` (load with ICC and DPI, crop to alpha + 2 px), `CutoutEngine`/`CutoutAnalysis` (Vision pass 1, pass 2 on small boxes intersected with a dilated pass-1 mask, `CIBlendWithMask` with an `NSNull`-colour-space mask, whole image with rounded corners) and `PickerState`/`PickerModel` (selection and Fill holes rules; cutouts and the four previews, rendered in UI order through the app's one `StyleRenderer` under in-flight IDs, so a preview is exactly what gets placed). AppKit controllers own the windows: `HotkeyCenter` (Carbon `RegisterEventHotKey`), `StatusItemController` (`NSStatusItem` with the `MenuBarGlyph` template), `CaptureService` (one `screencapture` process at a time, pasteboard change count, termination handler, cancel and leftovers), `PickerController` + `PickerPanel` (SwiftUI `PickerView` in a key-capable floating panel that survives losing key), `PlacementSession` (a transient panel with an explicit `ignoresMouseEvents = false` that follows the cursor and places through `StickerManager.place`), `PermissionPanel` and `HUD`. `SessionCoordinator` runs one session at a time from trigger to placement, ends editing first, orders Home out when asked, cancels on Quit, and hands focus back. `AppDelegate` wires the triggers.

**Tech Stack:** Swift 5 language mode, AppKit + SwiftUI (`NSHostingView`), Vision (`GenerateForegroundInstanceMaskRequest`, `ImageRequestHandler`), Core Image, Core Video, ImageIO, Carbon (HIToolbox hotkeys), `Process` (`/usr/sbin/screencapture`), `os.Logger`, Swift Testing, `xcodebuild` (Xcode 27 beta locally, Xcode 26.6 on CI).

**Spec:** `design/specs/2026-10-12-stickermine-v1-design.md`. This milestone implements section 5 (capture: triggers, one session at a time, the permission gate, the modifier wait, the warm-up, the exact `screencapture` flags, the outcome order, loading with ICC and DPI, the expected system alert, termination and leftovers), section 6 (cutout: pass 1, per-instance masks and click mapping, never instance 0 or an empty set, pass 2 on small boxes, `CIBlendWithMask` with an `NSNull` mask, Fill holes, whole image, the master PNG with DPI), section 7 (the picker panel and the placement session in full), section 14 (the permission panel; privacy is M7's documents), the menu bar icon part of section 13 (glyph, left-click capture, right-click/Control-click menu with New Sticker and Quit; Open Stickermine… and hiding the icon are M6), and the section 18 unit tests for click → subject mapping and capture outcome classification. The plan index with the Interface Contract is `design/plans/2026-10-12-stickermine-v1-plan.md`; the M1–M3 plans are `design/plans/2026-10-12-m1-foundation.md`, `design/plans/2026-10-12-m2-model-displays.md` and `design/plans/2026-10-12-m3-styles.md`.

## Contract changes

Signature changes (items 2–4 keep every call written against the index compiling; item 1 adds a required leading `file:` argument, and CaptureService is its only caller):

1. **`CaptureClassifier.classify(file url: URL, fileExists: Bool, fileSize: Int, exitStatus: Int32, pasteboardChanged: Bool) -> CaptureOutcome`** gains a leading `file:` argument: `.success(URL)` carries the file's URL, and the contract's four-argument form has nothing to build it from.
2. **`SessionCoordinator.init(capture:cutout:stickers:library:store:renderer:screens: ScreenProvider? = nil, access: ScreenRecordingAccess = LiveScreenRecordingAccess(), showMessage: ((String) -> Void)? = nil, presentPermission: (() -> Void)? = nil, restoresFocus: Bool = true)`**: the six contract arguments are unchanged; the defaulted ones let tests replace the screens, the Screen Recording check, the HUD and the permission panel, and keep focus where it is (nil means the live screens, the HUD and the panel).
3. **`SessionCoordinator.startCapture(orderingOut window: NSWindow? = nil)`**: `startCapture()` still compiles. M6's Home passes its window, which is ordered out just before `screencapture` runs and not shown again (spec section 5.2).
4. **`StyleRenderer.setInFlightMaster(_ image: CGImage?, for sticker: UUID)`** (M3's type gains it): renders for that ID use the in-memory image until it is cleared. The picker's cutouts aren't in the library yet; M3's notes asked for previews "through the app's single StyleRenderer, with an in-flight ID". Setting or clearing it also drops the cached inscribed radius for that ID, so the `invalidateCache(for:)` call M3's notes mention happens inside it.
5. **`MasterImage.Failure` gains `case unreadable`** (thrown by `load(url:)`).

Additions (Task 19 copies them into the index):

- `Shortcut`: `fKeyCodes`, `menuKeyEquivalent`, `keyName(_:)`, stored as `{"k", "m"}` through its `CodingKeys`.
- `HotkeyCenter`: `init()`, `signature` ('STKM'), `lastStatus`, `isRegistered`, `invalidate()`, `fire()`.
- `CaptureService`: `Command` (with `.screencapture`), `filePrefix`, `modifierPollInterval`, `init(command:temporaryDirectory:pasteboardChangeCount:modifiersHeld:modifierWait:)` (all defaulted), `deleteLeftovers(in:)`.
- `MasterImage`: `cropPadding`, `alphaBounds(of:)`, `croppedToAlpha(_:padding:)`.
- `MaskSampler`: `threshold`, `value(in:atUnitTopLeft:)`, `bounds(of:)`. `HoleFiller`: `defaultEdge`, `threshold`.
- `enum CutoutError { case emptySelection, released, emptyMask, renderFailed }`. `CutoutEngine`: `typealias Perform`, `static let vision`, `init(perform:)`, `context`, `warmUpImage()`. `CutoutAnalysis`: `init(capture:handler:observation:masks:context:perform:)`, `displayImage`, `bounds(of:)`, `static func refines(_:width:height:)`, `refinedCutoutCount`, `release()`, `refineBelow`, `refineMargin`, `cornerRadiusFraction`, `displayLongSide`, `maskImage(_:)`, `coverageImage(_:)`, `roundedCorners(_:)`, `downsampled(_:longSide:)`.
- `StyleRenderer.inFlightMasterCount` (how many in-flight masters are registered; tests check the picker lets go of them).
- `enum CutoutSource`, `struct PickerState`, `@MainActor final class PickerModel` (`Picker/PickerModel.swift`); `StickerStyle.displayName`, `struct PickerView`, `PreviewHost` (`Picker/PickerView.swift`); `PickerPanel` and `@MainActor final class PickerController` (`Picker/PickerPanel.swift`); `PlacementPanel`, `PlacementView`, `@MainActor final class PlacementSession` (`Picker/PlacementSession.swift`).
- `protocol ScreenRecordingAccess`, `LiveScreenRecordingAccess`, `struct PermissionPanelState` (with `whenShown(didRequest:panelIsUp:previous:)`), `@MainActor final class PermissionPanel` (`Onboarding/PermissionPanel.swift`); `@MainActor final class HUD` (`UI/HUD.swift`); `@MainActor final class StatusItemController` (`App/StatusItemController.swift`).
- `SessionCoordinator`: `enum Stage`, `stage`, `onPlaced`, `currentSticker`.
- Test support: `enum CaptureImages` (`StickermineTests/CaptureTestSupport.swift`).

Deleted (as the M2 and M3 notes require): `Stickermine/App/DebugMaple.swift`, `StickermineTests/DebugMapleTests.swift`, the `-debugPlaceMaple` branch in `AppDelegate` and the `DebugMaple` lines of `AppDelegateTests`. `StyleGallery` stays as a debug tool.

Deviations from the spec's wording, all within its intent:

- "Couldn’t start a capture" uses the typographic apostrophe, like Pullcord's HUD.
- Turning Whole image **off** (by its checkbox) selects every subject again; spec section 7 says what turning it on and clicking subjects do, and a selection can't be empty with Whole image off.
- The first touch of an untouched (Auto) Fill holes turns it on, like clicking a mixed-state checkbox; later touches flip it.
- A capture's `pixelsPerPoint` falls back to `LibraryStore.defaultPixelsPerPoint` (2) when the PNG has no DPI, the same default launch repair uses (`screencapture` always writes DPI unless `-r`, which is never passed).
- When pass 2 finds nothing on the crop (seen with a flat square filling its crop), the pass-1 mask is used.

## Global Constraints

All constraints in the index apply. Milestone-specific ones, verbatim from the spec:

- "**One session at a time** (`SessionCoordinator`). … While a session is active, every trigger (shortcut, menu bar click, New Sticker, history-grid clicks) is ignored, the menu's New Sticker item is disabled, and double-clicks on stickers don't enter editing. Starting a session first ends any sticker's editing, discarding an in-progress gesture. A capture started from Home orders Home out before `screencapture` runs; Home isn't reshown afterwards. The menu's Quit cancels the session, then quits." (section 5.2)
- "**Permission gate:** call `CGPreflightScreenCaptureAccess()`. If false, don't start `screencapture`; show the permission panel (section 14). Never ask at launch." (section 5.3)
- "Run `/usr/sbin/screencapture -i -J selection -o -x -t png <NSTemporaryDirectory()/stickermine-<UUID>.png>` with `Process`. … Never pass `-c`, `-u`, `-U`, `-p` or `-r`. Capture stdout and stderr for logging." (section 5.6)
- "**Outcome, first match wins:** 1. The file exists and is non-empty: success. 2. No file and the pasteboard `changeCount` changed: HUD "Let go of Control before releasing the mouse". 3. No file and exit status 1: HUD "Couldn't start a capture" … 4. Otherwise: a cancel … Show nothing; the session ends." (section 5.7)
- "**Load** with ImageIO, keeping the embedded ICC profile. The sticker's natural point size is pixels × 72 / DPI … Delete the temp file right after loading." (section 5.8)
- "on `applicationWillTerminate`, the menu's Quit, and before the updater spawns its helper, terminate a running `screencapture` process, delete its temp file and flush the pending library save. At launch, delete any leftover `stickermine-*.png` in `NSTemporaryDirectory()`." (section 5.10)
- "(macOS 15+, on the ANE or GPU; never force the CPU, which fails)" … "Don't use `instanceAtPoint`, `pixel(at:)` or `allInstancesMask` (their coordinate behaviour contradicts the documentation, and `allInstancesMask`'s pixel buffer is macOS 27-only)." … "**Never pass instance 0** (it selects the background) and never pass an empty set" … "wrapped with `CIImage(cvPixelBuffer:options: [.colorSpace: NSNull()])` (otherwise Core Image linearises it and the edge shifts). Don't use `generateMaskedImage`" (section 6)
- "**Cancel:** only Esc or the panel's own × button. Losing key status or a click outside never cancels, because the system alert (section 5.9) appears at this moment and clicking it must not discard the capture. Cancelling saves nothing." (section 7)
- "It sets an explicit `ignoresMouseEvents = false` (allowed for this transient panel), so its whole rectangle receives clicks even over transparent pixels, and it can become key so Esc arrives." (section 7) Sticker panels still never have it written (index constraint; `PanelPolicyTests` scans `Stickers/`, and the placement panel lives in `Picker/`).
- "SwiftUI's `MenuBarExtra` isn't used because it can't run an action on a plain click." … "loaded with `NSImage(named:)` and sized to 18×18 pt (the SVG reports 200×200 pt)" (section 13)
- "**Dev builds must be Developer-ID signed** (the default in `build.sh`) and launched with `open` (via `install.sh`), so the grant attaches to Stickermine's designated requirement and survives rebuilds." (section 14)
- From M2/M3, unchanged: every display a test builds sits at x ≥ 40 000 pt, and every test that orders a panel in closes it before it suspends or returns, so the test host never shows a window. New in M4: tests never run `screencapture` (a shell command stands in), never call the Screen Recording APIs (a fake `ScreenRecordingAccess`), never create an `NSStatusItem`, never show the picker, the permission panel or the HUD, never move focus (`restoresFocus: false`), and register only the unused chord ⌃⌥⇧⌘F19 as a hotkey, unregistering it before returning. `Shortcut.swift`, `CaptureClassifier.swift`, `MaskSampler.swift`, `HoleFiller.swift`, `CutoutEngine.swift`, `PickerModel.swift` and `MasterImage.swift` never import AppKit or SwiftUI (`LibraryModelTests.pureLogicFilesStayFreeOfAppKit`, extended in Task 1).
- As in M1–M3: run every command from the repository root (`/Users/ethan/Developer/stickermine`) in bash or zsh, not fish. The test command is `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`, with `-only-testing:StickermineTests/<Suite>` for one suite. Ignore the harmless lines the test host prints: `com.apple.linkd.autoShortcut`, `MDB_MAP_FULL`, `[VisionLog] PostProcessingOperation error` (Vision on the flat-colour images), M3's deliberate `Compiler failed to build request` / `program_source:` lines, and `render of … failed: missingMaster` from tests whose renderer has no masters.

## Review Focus

Owned from the index:

- **Item 2, first capture ever** (permission undetermined, then the "bypass the private window picker" alert landing on the picker). Expect: the permission panel explains and requests; after granting, the next shortcut works; clicking the system alert never discards the capture. Pinned by `SessionCoordinatorTests.withoutScreenRecordingThePermissionPanelShowsInsteadOfACapture`, `PermissionPanelTests` (all five: the first-time request and the Relaunch rules, among them a capture triggered again while the panel is up; the remembered flag; the Settings URL; Relaunch on coming back; the panel staying while the user is in System Settings), `PickerPanelTests.thePanelFollowsThePanelPolicyAndSurvivesLosingKey` (non-activating, so the keys arrive even if activation is refused), and Task 18 rows 3–8 and 5b (`design/capture-checks.md`), run by Ethan after he removes Stickermine from Screen & System Audio Recording himself (or on a fresh user account).
- **Item 3, awkward captures** (flat colour, text-only, a window capture with transparent corners, a tiny selection, a 5K full-screen capture). Expect: the Whole image path works, alpha is kept, nothing crashes, memory falls back after the picker closes. Pinned by `CutoutEngineTests.flatColoursHaveNoSubject` (solid colours and the gradient Vision throws on), `aThrownErrorOrNilMeansNoSubject`, `theWholeImageKeepsItsAlphaAndRoundsItsCorners` (a window capture with transparent corners), `MasterImageTests.croppingKeepsTheVisiblePixelsPlusTwo`, `PickerModelTests.withoutSubjectsWholeImageIsOnAndLocked`, `PickerModelTests.aCutoutThatFinishesAfterThePickerClosedIsNotKept` (a cutout still computing at Esc is never kept by the renderer), and Task 18 rows 18–23 (with the resident memory read before, during and after the picker).

Milestone-specific failure modes:

1. **A capture leaks: a `screencapture` left running, a temporary PNG left behind, or two captures at once** (Quit while the crosshair is up, a second shortcut press, a cancelled session). Expect: one capture at a time; Quit or cancel terminates the process and deletes its file; launch deletes leftovers. Pinned by `CaptureServiceTests.oneCaptureAtATimeAndCancellingCallsNoCompletion`, `leftoverCapturesAreDeletedAndNothingElse`, `SessionCoordinatorTests.oneSessionAtATimeAndCancelEndsIt`, `anUnreadableCaptureIsDeletedAndExplained`, `AppDelegateTests.launchWiresTheCaptureTriggersAndCleansUp`, and Task 18 rows 9 and 15.
2. **What gets placed differs from the preview that was picked**: a stale cutout after the selection changed, the wrong Fill holes value on confirm, or an in-flight master cleared before the placement rendered. Expect: the confirmed preview's own cutout and ID become the sticker. Pinned by `PickerModelTests.confirmingUsesThatStylesCutoutAndID`, `previewsRenderInUIOrderFromOneCutoutPerFillHolesValue`, `selectionChangesAreDebounced`, `finishingLetsGoOfEveryCutoutButTheConfirmedOne`, `aCutoutThatFinishesAfterThePickerClosedIsNotKept` (a cutout that completes after Esc, or after another style was confirmed, is dropped instead of registered under an ID nothing clears), `StyleRendererTests.anInFlightMasterIsRenderedUntilItIsCleared`, and Task 18 rows 12–14.
3. **The cutout's colours or edge shift** (the mask linearised by Core Image, `generateMaskedImage`'s missing colour space, the capture's ICC profile lost on load or save). Expect: exact colours in the capture's colour space and Vision's own edge. Pinned by `CutoutEngineTests.aSmallSelectionIsRefinedCutOutAndCroppedWithItsColours` (the disc's exact sRGB colour and colour space), `MasterImageTests.theEmbeddedProfileIsKept` (Display P3 through save and load), and Task 18 row 16 (a P3 photo on a P3 display).

## Files

| Path | Action | Responsibility |
|---|---|---|
| `Stickermine/App/Shortcut.swift` | Create (Task 1) | Carbon key + mask, the default ⌃⌥⌘S, label, acceptability, menu key equivalent |
| `Stickermine/App/HotkeyCenter.swift` | Create (Task 2) | The Carbon global hotkey: register, suspend, resume |
| `Stickermine/Capture/CaptureClassifier.swift` | Create (Task 3) | `CaptureOutcome`; spec 5.7's first-match order |
| `Stickermine/Capture/CaptureService.swift` | Create (Task 4) | Modifier wait, pasteboard count, one `screencapture` process, cancel, leftovers |
| `Stickermine/Capture/MasterImage.swift` | Modify (Task 5) | Adds `LoadedCapture`, `load(url:)` with ICC and DPI, alpha bounds and the 2 px crop |
| `Stickermine/Capture/MaskSampler.swift` | Create (Task 6) | Click → subject on top-down OneComponent32Float masks; mask bounds |
| `Stickermine/Capture/HoleFiller.swift` | Create (Task 7) | Fill holes on a float alpha mask |
| `Stickermine/Capture/CutoutEngine.swift` | Create (Task 8) | Vision pass 1 and 2, masks, the cutout, the whole image, warm-up |
| `Stickermine/Capture/StyleRenderer.swift` | Modify (Task 9) | In-flight masters for cutouts not yet in the library |
| `Stickermine/Picker/PickerModel.swift` | Create (Task 10) | Selection and Fill holes rules; cutouts and previews; confirm |
| `Stickermine/Picker/PickerView.swift` | Create (Task 11) | The picker's SwiftUI content; previews through `StickerView` |
| `Stickermine/Picker/PickerPanel.swift` | Create (Task 11) | The key-capable floating panel near the cursor; Esc and 1–4 |
| `Stickermine/Picker/PlacementSession.swift` | Create (Task 12) | The sticker following the cursor until a click places it |
| `Stickermine/UI/HUD.swift` | Create (Task 13) | Short status pills |
| `Stickermine/Onboarding/PermissionPanel.swift` | Create (Task 14) | The Screen Recording explainer: request, Open System Settings, Relaunch |
| `Stickermine/Assets.xcassets/MenuBarGlyph.imageset/` | Create (Task 15) | `design/menubar-glyph.svg` as a vector template image |
| `Stickermine/App/StatusItemController.swift` | Create (Task 15) | The menu bar icon: left-click capture, right-click menu |
| `Stickermine/App/SessionCoordinator.swift` | Create (Task 16) | One session at a time: permission, capture, cutout, picker, save, placement, focus |
| `Stickermine/App/AppDelegate.swift` | Modify (Task 17) | Wires the triggers, cleans leftovers, cancels on Quit and terminate; Maple branch removed |
| `Stickermine/App/DebugMaple.swift` | Delete (Task 17) | (M2/M3's temporary debug path) |
| `StickermineTests/CaptureTestSupport.swift` | Create (Task 5) | Generated captures for Vision, padded mask buffers |
| `StickermineTests/ShortcutTests.swift` | Create (Task 1) | Default, labels, acceptability, `{k, m}` storage, menu keys |
| `StickermineTests/HotkeyCenterTests.swift` | Create (Task 2) | Register, suspend, resume, nil, handler |
| `StickermineTests/CaptureClassifierTests.swift` | Create (Task 3) | The first-match order |
| `StickermineTests/CaptureServiceTests.swift` | Create (Task 4) | Flags, outcomes, modifier wait, one at a time, cancel, leftovers |
| `StickermineTests/MasterImageTests.swift` | Create (Task 5) | DPI round trip, default DPI, ICC kept, delete after load, crop |
| `StickermineTests/MaskSamplerTests.swift` | Create (Task 6) | Top-down rows, padded rows, threshold, overlap, bounds |
| `StickermineTests/HoleFillerTests.swift` | Create (Task 7) | Enclosed hole, speckle, open gap, soft edge, depth |
| `StickermineTests/CutoutEngineTests.swift` | Create (Task 8) | Two shapes, refine, colours, Fill holes on a toggle, flat colours, thrown errors, whole image, release |
| `StickermineTests/StyleRendererTests.swift` | Modify (Task 9) | In-flight masters |
| `StickermineTests/PickerModelTests.swift` | Create (Task 10) | Every selection and Fill holes rule; previews, confirm, debounce, finish, re-place |
| `StickermineTests/PickerPanelTests.swift` | Create (Task 11) | Panel position, keys 1–4, panel policy |
| `StickermineTests/PlacementSessionTests.swift` | Create (Task 12) | Fit to half the display, the panel and view, placing and cancelling |
| `StickermineTests/HUDTests.swift` | Create (Task 13) | Messages, position, panel flags |
| `StickermineTests/PermissionPanelTests.swift` | Create (Task 14) | Request once, Settings URL, Relaunch, panel flags |
| `StickermineTests/StatusItemControllerTests.swift` | Create (Task 15) | Glyph, asset, menu, session state, click rules |
| `StickermineTests/SessionCoordinatorTests.swift` | Create (Task 16) | Permission gate, one session, outcomes, read-only |
| `StickermineTests/AppDelegateTests.swift` | Modify (Task 17) | Maple path gone; launch wiring and terminate order |
| `StickermineTests/LibraryModelTests.swift` | Modify (Task 1) | The new pure files stay AppKit-free |
| `StickermineTests/DebugMapleTests.swift` | Delete (Task 17) | (with DebugMaple) |
| `design/capture-checks.md` | Create (Task 18) | The real capture flow on this Mac, with Ethan, and its results |
| `design/ci-dry-runs.md` | Modify (Task 19) | M4's dry-run row |
| `design/plans/2026-10-12-stickermine-v1-plan.md` | Modify (Task 19) | The contract changes and additions above |

---

### Task 1: Shortcut

**Files:**
- Create: `Stickermine/App/Shortcut.swift`
- Test: Create `StickermineTests/ShortcutTests.swift`; Modify `StickermineTests/LibraryModelTests.swift` (the pure-file list)

**Interfaces:**
- Consumes: Carbon's `kVK_ANSI_S`, `controlKey`, `optionKey`, `shiftKey`, `cmdKey` (`import Carbon.HIToolbox`).
- Produces:

```text
struct Shortcut: Codable, Equatable {                  // App/Shortcut.swift; encoded as {"k": keyCode, "m": modifiers}
    var keyCode: UInt32; var modifiers: UInt32         // Carbon mask
    static let defaultCapture: Shortcut                // keyCode 1, controlKey|optionKey|cmdKey (0x1900)
    static let fKeyCodes: [UInt32]                     // F1–F20, in order
    var label: String { get }                          // "⌃⌥⌘S": glyphs ⌃ ⌥ ⇧ ⌘, then the key, no spaces
    var isAcceptable: Bool { get }                     // contains ⌘ or ⌃, or is an F-key
    var menuKeyEquivalent: String? { get }             // "s"; F-keys and arrows as their NSFunctionKey characters; nil otherwise
    static func keyName(_ code: UInt32) -> String      // Pullcord's table; "key<code>" when unknown
}
```

- [ ] **Step 1: Write the failing test**

`StickermineTests/ShortcutTests.swift`:

```swift
import Carbon.HIToolbox
import Foundation
import Testing
@testable import Stickermine

struct ShortcutTests {
    @Test func theDefaultIsControlOptionCommandS() {
        #expect(Shortcut.defaultCapture.keyCode == 1)
        #expect(Shortcut.defaultCapture.modifiers == UInt32(controlKey | optionKey | cmdKey))
        #expect(Shortcut.defaultCapture.modifiers == 0x1900)
        #expect(Shortcut.defaultCapture.label == "⌃⌥⌘S")
    }

    @Test func labelsUseApplesModifierOrderWithoutSpaces() {
        let all = Shortcut(keyCode: 40, modifiers: UInt32(cmdKey | shiftKey | optionKey | controlKey))
        #expect(all.label == "⌃⌥⇧⌘K")
        #expect(Shortcut(keyCode: 122, modifiers: 0).label == "F1")
        #expect(Shortcut(keyCode: 49, modifiers: UInt32(cmdKey)).label == "⌘Space")
        #expect(Shortcut(keyCode: 200, modifiers: UInt32(cmdKey)).label == "⌘key200")
    }

    @Test func aChordNeedsCommandOrControlUnlessItIsAnFKey() {
        #expect(Shortcut(keyCode: 1, modifiers: UInt32(cmdKey)).isAcceptable)
        #expect(Shortcut(keyCode: 1, modifiers: UInt32(controlKey)).isAcceptable)
        #expect(!Shortcut(keyCode: 1, modifiers: UInt32(optionKey)).isAcceptable)
        #expect(!Shortcut(keyCode: 1, modifiers: UInt32(optionKey | shiftKey)).isAcceptable)
        #expect(!Shortcut(keyCode: 1, modifiers: 0).isAcceptable)
        #expect(Shortcut(keyCode: 111, modifiers: 0).isAcceptable)     // F12 alone
        #expect(Shortcut(keyCode: 90, modifiers: UInt32(shiftKey)).isAcceptable)   // ⇧F20
    }

    @Test func storesAsKAndM() throws {
        let data = try JSONEncoder().encode(Shortcut.defaultCapture)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Int])
        #expect(object == ["k": 1, "m": 6400])
        #expect(try JSONDecoder().decode(Shortcut.self, from: data) == Shortcut.defaultCapture)
    }

    @Test func menusShowLowercaseCharactersAndFunctionKeys() {
        #expect(Shortcut.defaultCapture.menuKeyEquivalent == "s")
        #expect(Shortcut(keyCode: 29, modifiers: UInt32(cmdKey)).menuKeyEquivalent == "0")
        #expect(Shortcut(keyCode: 122, modifiers: 0).menuKeyEquivalent == "\u{F704}")   // F1
        #expect(Shortcut(keyCode: 90, modifiers: 0).menuKeyEquivalent == "\u{F717}")    // F20
        #expect(Shortcut(keyCode: 49, modifiers: UInt32(cmdKey)).menuKeyEquivalent == " ")
        #expect(Shortcut(keyCode: 36, modifiers: UInt32(cmdKey)).menuKeyEquivalent == nil)   // Return
    }
}
```

In `StickermineTests/LibraryModelTests.swift`, inside `pureLogicFilesStayFreeOfAppKit`, replace the declaration of `pure` (M3 Task 8's version):

```swift
        let pure: Set<String> = ["Library.swift", "LayoutResolver.swift", "DisplayRegistry.swift",
                                 "LibraryStore.swift", "LibraryController.swift", "StyleParameters.swift",
                                 "StyleRenderer.swift", "MasterImage.swift", "StickerGeometry.swift",
                                 "StyleRecipes.swift", "PuffyKernel.swift", "SurfaceContents.swift"]
```

with this one, which adds every pure file this milestone creates (a name is checked as soon as its file exists):

```swift
        let pure: Set<String> = ["Library.swift", "LayoutResolver.swift", "DisplayRegistry.swift",
                                 "LibraryStore.swift", "LibraryController.swift", "StyleParameters.swift",
                                 "StyleRenderer.swift", "MasterImage.swift", "StickerGeometry.swift",
                                 "StyleRecipes.swift", "PuffyKernel.swift", "SurfaceContents.swift",
                                 "Shortcut.swift", "CaptureClassifier.swift", "MaskSampler.swift",
                                 "HoleFiller.swift", "CutoutEngine.swift", "PickerModel.swift"]
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/ShortcutTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'Shortcut' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/App/Shortcut.swift`:

```swift
import Carbon.HIToolbox
import Foundation

/// A global shortcut: a virtual key code and a Carbon modifier mask
/// (`cmdKey | shiftKey | optionKey | controlKey`), the form
/// `RegisterEventHotKey` takes. Ported from Pullcord's `Shortcut`. Stored as
/// `{k, m}` (spec section 12); M6 adds the storage, the recorder and the
/// system-shortcut check.
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32

    private enum CodingKeys: String, CodingKey {
        case keyCode = "k"
        case modifiers = "m"
    }

    /// ⌃⌥⌘S: key code 1 (kVK_ANSI_S) with Control, Option and Command.
    static let defaultCapture = Shortcut(keyCode: UInt32(kVK_ANSI_S),
                                         modifiers: UInt32(controlKey | optionKey | cmdKey))

    /// Virtual key codes for F1–F20, the only keys that may be used without
    /// ⌘ or ⌃.
    static let fKeyCodes: [UInt32] = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109,
                                      103, 111, 105, 107, 113, 106, 64, 79, 80, 90]

    /// "⌃⌥⌘S": the modifier glyphs in Apple's order ⌃ ⌥ ⇧ ⌘, then the key, with
    /// no spaces (spec section 13 writes the tutorial as "Press ⌃⌥⌘S").
    var label: String {
        var text = ""
        if modifiers & UInt32(controlKey) != 0 { text += "⌃" }
        if modifiers & UInt32(optionKey) != 0 { text += "⌥" }
        if modifiers & UInt32(shiftKey) != 0 { text += "⇧" }
        if modifiers & UInt32(cmdKey) != 0 { text += "⌘" }
        return text + Self.keyName(keyCode)
    }

    /// Every chord must include ⌘ or ⌃; an F-key may stand alone (spec section 13).
    var isAcceptable: Bool {
        modifiers & UInt32(cmdKey | controlKey) != 0 || Self.fKeyCodes.contains(keyCode)
    }

    /// The character a menu item shows for this key (lowercase for letters),
    /// or nil for a key a menu can't show.
    var menuKeyEquivalent: String? {
        if let index = Self.fKeyCodes.firstIndex(of: keyCode) {
            // NSF1FunctionKey is U+F704; F1–F20 follow it in order.
            return UnicodeScalar(0xF704 + index).map { String(Character($0)) }
        }
        switch keyCode {
        case UInt32(kVK_Space): return " "
        case UInt32(kVK_LeftArrow): return "\u{F702}"
        case UInt32(kVK_RightArrow): return "\u{F703}"
        case UInt32(kVK_DownArrow): return "\u{F701}"
        case UInt32(kVK_UpArrow): return "\u{F700}"
        default:
            // Letters, digits and punctuation; the glyph names (↩, ⌫, ⎋ …) aren't keys.
            let name = Self.keyName(keyCode)
            guard name.count == 1, name.unicodeScalars.allSatisfy(\.isASCII) else { return nil }
            return name.lowercased()
        }
    }

    /// The name a label shows for a key code (Pullcord's table).
    static func keyName(_ code: UInt32) -> String {
        let names: [UInt32: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C",
            9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
            18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9",
            26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[",
            34: "I", 35: "P", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\",
            43: ",", 44: "/", 45: "N", 46: "M", 47: ".", 50: "`", 49: "Space",
            36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 76: "⌤",
            123: "←", 124: "→", 125: "↓", 126: "↑",
            116: "⇞", 121: "⇟", 115: "↖", 119: "↘", 117: "⌦",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
            98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
            105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18",
            80: "F19", 90: "F20",
        ]
        return names[code] ?? "key\(code)"
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 191 tests in 23 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/App/Shortcut.swift StickermineTests/ShortcutTests.swift StickermineTests/LibraryModelTests.swift
git commit -m "Add Shortcut with the default Control-Option-Command-S" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: HotkeyCenter

**Files:**
- Create: `Stickermine/App/HotkeyCenter.swift`
- Test: Create `StickermineTests/HotkeyCenterTests.swift`

**Interfaces:**
- Consumes: `Shortcut` (Task 1); Carbon `InstallEventHandler`, `RegisterEventHotKey`, `UnregisterEventHotKey`, `RemoveEventHandler`.
- Produces:

```text
@MainActor final class HotkeyCenter {                  // App/HotkeyCenter.swift
    static let signature: OSType                       // 0x53544B4D 'STKM'
    init()
    private(set) var lastStatus: OSStatus              // of the last RegisterEventHotKey (noErr proves no exclusivity)
    var isRegistered: Bool { get }
    func register(_ s: Shortcut?, handler: @escaping () -> Void)   // contract; nil registers nothing
    func suspend()                                     // contract; unregisters (M6's recorder)
    func resume()                                      // contract
    func invalidate()                                  // unregisters and removes the Carbon handler (tests)
    func fire()                                        // runs the handler, as a press does
}
```

A press arrives on the Carbon event handler, which checks the signature and this center's ID and hops to the main actor. Carbon hotkeys need no Accessibility or Input Monitoring permission and aren't exclusive (spec section 13): another app holding the same chord still gets `noErr`.

- [ ] **Step 1: Write the failing test**

`StickermineTests/HotkeyCenterTests.swift` (it registers only ⌃⌥⇧⌘F19 and always unregisters it):

```swift
import Carbon.HIToolbox
import Testing
@testable import Stickermine

/// Registers ⌃⌥⇧⌘F19, a chord nothing else uses, and unregisters it before returning.
@MainActor
struct HotkeyCenterTests {
    static let unusual = Shortcut(keyCode: 80, modifiers: UInt32(controlKey | optionKey | shiftKey | cmdKey))

    @Test func registersSuspendsAndResumes() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        center.register(Self.unusual) {}
        #expect(center.isRegistered)
        #expect(center.lastStatus == noErr)
        center.suspend()
        #expect(!center.isRegistered)
        center.resume()
        #expect(center.isRegistered)
    }

    @Test func aShortcutSetWhileSuspendedWaitsForResume() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        center.suspend()
        center.register(Self.unusual) {}
        #expect(!center.isRegistered)
        center.resume()
        #expect(center.isRegistered)
    }

    @Test func noShortcutRegistersNothing() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        center.register(Self.unusual) {}
        center.register(nil) {}
        #expect(!center.isRegistered)
        center.resume()
        #expect(!center.isRegistered)
    }

    @Test func aPressRunsTheLatestHandler() {
        let center = HotkeyCenter()
        defer { center.invalidate() }
        var presses: [String] = []
        center.register(Self.unusual) { presses.append("first") }
        center.register(Self.unusual) { presses.append("second") }
        center.fire()
        #expect(presses == ["second"])
        #expect(HotkeyCenter.signature == 0x5354_4B4D)   // 'STKM'
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/HotkeyCenterTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'HotkeyCenter' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/App/HotkeyCenter.swift`:

```swift
import Carbon.HIToolbox
import Foundation
import os

/// The capture shortcut as a Carbon global hotkey (spec section 5.1): no
/// Accessibility or Input Monitoring permission is needed. One shortcut per
/// center. `suspend()` unregisters it while the shortcut recorder (M6) listens
/// and `resume()` registers it again. Ported from Pullcord's installHandler and
/// syncHotkeys, with its own signature 'STKM'.
@MainActor
final class HotkeyCenter {
    /// 'STKM'
    static let signature: OSType = 0x5354_4B4D

    /// Carbon IDs are per center, so several centers (tests) never answer
    /// each other's presses.
    private static var nextID: UInt32 = 1

    private let id: UInt32
    private var eventHandler: EventHandlerRef?
    private var hotKey: EventHotKeyRef?
    private var shortcut: Shortcut?
    private var handler: (() -> Void)?
    private var isSuspended = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "hotkey")

    /// The status of the last `RegisterEventHotKey` call (noErr when none ran).
    /// Carbon hotkeys aren't exclusive, so noErr doesn't prove no other app
    /// uses the chord.
    private(set) var lastStatus: OSStatus = noErr

    init() {
        id = Self.nextID
        Self.nextID += 1
    }

    var isRegistered: Bool { hotKey != nil }

    /// Replaces the shortcut (nil: none) and what a press does. While suspended
    /// it is registered on `resume()`.
    func register(_ shortcut: Shortcut?, handler: @escaping () -> Void) {
        unregisterHotKey()
        self.shortcut = shortcut
        self.handler = handler
        installEventHandlerIfNeeded()
        if !isSuspended { registerHotKey() }
    }

    func suspend() {
        isSuspended = true
        unregisterHotKey()
    }

    func resume() {
        isSuspended = false
        if !isRegistered { registerHotKey() }
    }

    /// Unregisters the shortcut and removes the Carbon handler (tests; the app's
    /// center lives as long as the app).
    func invalidate() {
        unregisterHotKey()
        handler = nil
        if let eventHandler {
            RemoveEventHandler(eventHandler)
            self.eventHandler = nil
        }
    }

    /// Runs the handler, as a press of the shortcut does.
    func fire() {
        handler?()
    }

    private func registerHotKey() {
        guard let shortcut, hotKey == nil else { return }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        lastStatus = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, hotKeyID,
                                         GetEventDispatcherTarget(), 0, &ref)
        if lastStatus == noErr, let ref {
            hotKey = ref
        } else {
            log.error("registering \(shortcut.label, privacy: .public) failed: \(self.lastStatus)")
        }
    }

    private func unregisterHotKey() {
        if let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installEventHandlerIfNeeded() {
        guard eventHandler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData -> OSStatus in
            guard let event, let userData else { return OSStatus(eventNotHandledErr) }
            var pressedID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &pressedID)
            let center = Unmanaged<HotkeyCenter>.fromOpaque(userData).takeUnretainedValue()
            guard pressedID.signature == HotkeyCenter.signature, pressedID.id == center.id else {
                return OSStatus(eventNotHandledErr)
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated { center.fire() }
            }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        if status != noErr {
            log.error("InstallEventHandler failed: \(status)")
        }
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 195 tests in 24 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/App/HotkeyCenter.swift StickermineTests/HotkeyCenterTests.swift
git commit -m "Add HotkeyCenter: the capture shortcut as a Carbon hotkey" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: CaptureClassifier

**Files:**
- Create: `Stickermine/Capture/CaptureClassifier.swift`
- Test: Create `StickermineTests/CaptureClassifierTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces (see Contract changes item 1):

```text
enum CaptureOutcome: Equatable { case success(URL), controlHeldToClipboard, busyOrBlocked, cancelled }
enum CaptureClassifier {
    static func classify(file url: URL, fileExists: Bool, fileSize: Int, exitStatus: Int32, pasteboardChanged: Bool) -> CaptureOutcome
}
```

`screencapture` exits 0 for a success and for every cancel (Esc, ⌘., a click without a drag, a selection under 10 pt, Control-to-clipboard) and 1 when another interactive capture is up or an MDM profile forbids screenshots, so the file decides first and the exit status last. An empty file counts as no file.

- [ ] **Step 1: Write the failing test**

`StickermineTests/CaptureClassifierTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/CaptureClassifierTests
```

Expected: `** TEST FAILED **` with `error: cannot find type 'CaptureOutcome' in scope` and `error: cannot find 'CaptureClassifier' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/CaptureClassifier.swift`:

```swift
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
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 199 tests in 25 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/CaptureClassifier.swift StickermineTests/CaptureClassifierTests.swift
git commit -m "Classify screencapture outcomes in the spec's first-match order" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: CaptureService

**Files:**
- Create: `Stickermine/Capture/CaptureService.swift`
- Test: Create `StickermineTests/CaptureServiceTests.swift`

**Interfaces:**
- Consumes: `CaptureClassifier`, `CaptureOutcome` (Task 3); `NSPasteboard.general.changeCount`, `NSEvent.modifierFlags`, `Process`.
- Produces:

```text
@MainActor final class CaptureService {               // Capture/CaptureService.swift
    struct Command { let executable: URL; let arguments: (URL) -> [String]; static let screencapture: Command }
    static let filePrefix: String                      // "stickermine-"
    static let modifierPollInterval: TimeInterval      // 0.02
    init(command: Command = .screencapture,
         temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
         pasteboardChangeCount: @escaping () -> Int = { NSPasteboard.general.changeCount },
         modifiersHeld: @escaping () -> Bool = { ⌃, ⌥, ⌘ or ⇧ down },
         modifierWait: TimeInterval = 1.0)
    private(set) var isRunning: Bool                   // contract: `var isRunning: Bool { get }`
    func capture(completion: @escaping (CaptureOutcome) -> Void)   // contract; ignored while running; completion once, on main
    func cancelRunning()                               // contract; terminates, deletes the file, no completion
    static func deleteLeftovers()                      // contract; NSTemporaryDirectory()
    @discardableResult static func deleteLeftovers(in directory: URL) -> Int   // stickermine-*.png only
}
```

The tests never run `screencapture`: a `/bin/sh` command writes (or doesn't write) the file it is given and exits with the status under test.

- [ ] **Step 1: Write the failing test**

`StickermineTests/CaptureServiceTests.swift`:

```swift
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
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/CaptureServiceTests
```

Expected: `** TEST FAILED **` with `error: cannot find type 'CaptureService' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/CaptureService.swift`:

```swift
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
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 208 tests in 26 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/CaptureService.swift StickermineTests/CaptureServiceTests.swift
git commit -m "Add CaptureService: one screencapture at a time, modifier wait, cancel and leftovers" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: MasterImage: loading captures and cropping cutouts

**Files:**
- Modify: `Stickermine/Capture/MasterImage.swift` (whole file shown; M2's members are unchanged)
- Test: Create `StickermineTests/CaptureTestSupport.swift`, `StickermineTests/MasterImageTests.swift`

**Interfaces:**
- Consumes: M2's `MasterImage` (`pngData`, `fileInfo`, `pixelsPerPoint(fromDPI:)`, `image(at:)`), `LibraryStore.defaultPixelsPerPoint`, test fixtures `Fixtures` (M2) and `TestImages` (M1).
- Produces:

```text
struct LoadedCapture { let image: CGImage; let pixelsPerPoint: Double }      // contract
added to enum MasterImage:
    enum Failure: Error { case cannotEncode, unreadable }                    // .unreadable is new (Contract changes item 5)
    static let cropPadding: Int                                              // 2 (spec 6.8)
    static func load(url: URL) throws -> LoadedCapture                       // contract; ICC kept, decoded at once, DPI → ppp (2 when absent)
    static func alphaBounds(of image: CGImage) -> CGRect?                    // pixels, top-left origin; nil when fully transparent
    static func croppedToAlpha(_ image: CGImage, padding: Int = cropPadding) -> CGImage?   // + padding, kept inside the image
test support, StickermineTests/CaptureTestSupport.swift:
    enum CaptureImages {
        static let sRGB: CGColorSpace
        static func draw(width:height:colorSpace:_:) -> CGImage
        static func twoShapes() -> CGImage                                   // 1200 × 800: red disc, blue square
        static let discCentre: CGPoint; static let squareCentre: CGPoint; static let backgroundPoint: CGPoint   // 0–1, top-left
        static func toggle() -> CGImage                                      // white knob in a green track on white
        static func flat(width:height:red:green:blue:) -> CGImage; static func gradient() -> CGImage
        static func window(width:height:) -> CGImage                         // rounded window capture, transparent corners
        static func loaded(_ image: CGImage, pixelsPerPoint: Double = 2) -> LoadedCapture
        static func maskBuffer(width:height:rowPadding:_:) -> CVPixelBuffer  // OneComponent32Float, padded rows, y = 0 top
        static func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8]
    }
```

- [ ] **Step 1: Write the failing test**

`StickermineTests/CaptureTestSupport.swift` (the generated captures every M4 test uses; Tasks 6 and 8 rely on it too):

```swift
import CoreGraphics
import CoreVideo
import Foundation
@testable import Stickermine

/// Generated captures and masks for the M4 tests.
enum CaptureImages {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    static func draw(width: Int, height: Int, colorSpace: CGColorSpace = sRGB,
                     _ body: (CGContext) -> Void) -> CGImage {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        body(context)
        return context.makeImage()!
    }

    /// 1200 × 800 on warm white: a red disc (280 px) lower left, centred at
    /// (300, 540) from the top-left, and a blue square (260 px) upper right,
    /// centred at (890, 250). Vision finds two subjects.
    static func twoShapes() -> CGImage {
        draw(width: 1200, height: 800) { context in
            context.setFillColor(CGColor(srgbRed: 0.96, green: 0.95, blue: 0.92, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 1200, height: 800))
            context.setFillColor(CGColor(srgbRed: 0.9, green: 0.2, blue: 0.25, alpha: 1))
            context.fillEllipse(in: CGRect(x: 160, y: 120, width: 280, height: 280))
            context.setFillColor(CGColor(srgbRed: 0.15, green: 0.3, blue: 0.85, alpha: 1))
            context.fill(CGRect(x: 760, y: 420, width: 260, height: 260))
        }
    }

    /// The disc's and the square's centres, 0–1 from the top-left.
    static let discCentre = CGPoint(x: 300.0 / 1200, y: 540.0 / 800)
    static let squareCentre = CGPoint(x: 890.0 / 1200, y: 250.0 / 800)
    static let backgroundPoint = CGPoint(x: 600.0 / 1200, y: 400.0 / 800)

    /// 600 × 400 white: a green toggle track (300 × 120) with its white knob
    /// (100 px) on the right: the white-on-white case Fill holes exists for.
    /// The knob's centre is 3/4 across and halfway down the cutout.
    static func toggle() -> CGImage {
        draw(width: 600, height: 400) { context in
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 400))
            context.addPath(CGPath(roundedRect: CGRect(x: 150, y: 140, width: 300, height: 120),
                                   cornerWidth: 60, cornerHeight: 60, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.78, blue: 0.35, alpha: 1))
            context.fillPath()
            context.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
            context.fillEllipse(in: CGRect(x: 340, y: 150, width: 100, height: 100))
        }
    }

    /// One flat colour.
    static func flat(width: Int = 600, height: Int = 400, red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        draw(width: width, height: height) { context in
            context.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    /// A red-to-blue gradient (Vision throws `requestCancelled` on it on macOS 27.2).
    static func gradient() -> CGImage {
        draw(width: 600, height: 400) { context in
            let gradient = CGGradient(colorsSpace: sRGB,
                                      colors: [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                               CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)] as CFArray,
                                      locations: [0, 1])!
            context.drawLinearGradient(gradient, start: .zero, end: CGPoint(x: 600, y: 0), options: [])
        }
    }

    /// A window capture: a light grey rounded rect (radius 40) on transparent,
    /// with dark text-like bars; Vision finds no subject.
    static func window(width: Int = 800, height: Int = 500) -> CGImage {
        draw(width: width, height: height) { context in
            let rect = CGRect(x: 0, y: 0, width: width, height: height)
            context.addPath(CGPath(roundedRect: rect, cornerWidth: 40, cornerHeight: 40, transform: nil))
            context.setFillColor(CGColor(srgbRed: 0.93, green: 0.93, blue: 0.93, alpha: 1))
            context.fillPath()
            context.setFillColor(CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1))
            context.fill(CGRect(x: 40, y: height - 80, width: 300, height: 30))
            context.fill(CGRect(x: 40, y: height - 140, width: 500, height: 14))
            context.fill(CGRect(x: 40, y: height - 170, width: 460, height: 14))
        }
    }

    static func loaded(_ image: CGImage, pixelsPerPoint: Double = 2) -> LoadedCapture {
        LoadedCapture(image: image, pixelsPerPoint: pixelsPerPoint)
    }

    /// A OneComponent32Float buffer whose rows are `rowPadding` bytes longer
    /// than needed (so code must use the real bytes per row). `value(x, y)`
    /// gives each pixel, y = 0 being the top row.
    static func maskBuffer(width: Int = 512, height: Int = 512, rowPadding: Int = 64,
                           _ value: (Int, Int) -> Float) -> CVPixelBuffer {
        let rowBytes = width * 4 + rowPadding
        let bytes = UnsafeMutableRawPointer.allocate(byteCount: rowBytes * height, alignment: 16)
        for y in 0..<height {
            let row = (bytes + y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width { row[x] = value(x, y) }
        }
        var buffer: CVPixelBuffer?
        CVPixelBufferCreateWithBytes(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent32Float,
                                     bytes, rowBytes, { _, base in base?.deallocate() }, nil, nil, &buffer)
        return buffer!
    }

    /// Premultiplied RGBA bytes at (x, y), y = 0 the top row, read in sRGB.
    static func rgba(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
        TestImages.rgba(of: image, x: x, y: y)
    }
}
```

`StickermineTests/MasterImageTests.swift`:

```swift
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import Stickermine

struct MasterImageTests {
    @Test func dpiSurvivesARoundTrip() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = Fixtures.image(width: 120, height: 80)
        for pixelsPerPoint in [1.0, 2.0, 3.0] {
            let url = folder.appendingPathComponent("\(pixelsPerPoint).png")
            try MasterImage.pngData(image, pixelsPerPoint: pixelsPerPoint).write(to: url)
            let loaded = try MasterImage.load(url: url)
            #expect(loaded.pixelsPerPoint == pixelsPerPoint)
            #expect(loaded.image.width == 120)
            #expect(loaded.image.height == 80)
            #expect(MasterImage.fileInfo(at: url)?.pixelsPerPoint == pixelsPerPoint)
        }
    }

    @Test func aFileWithoutDPIGetsTheDefault() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("plain.png")
        try Fixtures.pngData(width: 40, height: 20, pixelsPerPoint: nil).write(to: url)
        #expect(try MasterImage.load(url: url).pixelsPerPoint == LibraryStore.defaultPixelsPerPoint)
    }

    @Test func theEmbeddedProfileIsKept() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let image = Fixtures.image(width: 32, height: 32, colorSpace: p3)
        let url = folder.appendingPathComponent("p3.png")
        try MasterImage.pngData(image, pixelsPerPoint: 2).write(to: url)
        let loaded = try MasterImage.load(url: url)
        #expect(loaded.image.colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func theFileCanGoRightAfterLoading() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("gone.png")
        try MasterImage.pngData(Fixtures.image(width: 50, height: 50), pixelsPerPoint: 2).write(to: url)
        let loaded = try MasterImage.load(url: url)
        try FileManager.default.removeItem(at: url)
        #expect(TestImages.rgba(of: loaded.image, x: 10, y: 10) == [255, 0, 0, 255])
    }

    @Test func anUnreadableFileThrows() throws {
        let folder = Fixtures.temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("junk.png")
        try Data("not a png".utf8).write(to: url)
        #expect(throws: (any Error).self) { try MasterImage.load(url: url) }
    }

    @Test func croppingKeepsTheVisiblePixelsPlusTwo() throws {
        // 100 × 60, transparent except a 10 × 8 block at x 30, y 20 from the top.
        let image = CaptureImages.draw(width: 100, height: 60) { context in
            context.setFillColor(CGColor(srgbRed: 0, green: 0.5, blue: 1, alpha: 1))
            context.fill(CGRect(x: 30, y: 60 - 20 - 8, width: 10, height: 8))
        }
        #expect(MasterImage.alphaBounds(of: image) == CGRect(x: 30, y: 20, width: 10, height: 8))
        let cropped = try #require(MasterImage.croppedToAlpha(image))
        #expect(cropped.width == 14)
        #expect(cropped.height == 12)
        #expect(TestImages.rgba(of: cropped, x: 1, y: 1)[3] == 0)
        #expect(TestImages.rgba(of: cropped, x: 2, y: 2)[3] == 255)
        #expect(TestImages.rgba(of: cropped, x: 11, y: 9)[3] == 255)
        #expect(TestImages.rgba(of: cropped, x: 12, y: 10)[3] == 0)
    }

    @Test func croppingStaysInsideTheImage() throws {
        let opaque = Fixtures.image(width: 40, height: 30)
        let cropped = try #require(MasterImage.croppedToAlpha(opaque))
        #expect(cropped.width == 40)
        #expect(cropped.height == 30)
        let empty = CaptureImages.draw(width: 20, height: 20) { _ in }
        #expect(MasterImage.croppedToAlpha(empty) == nil)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/MasterImageTests
```

Expected: `** TEST FAILED **` with `error: cannot find type 'LoadedCapture' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/MasterImage.swift` (complete file; it replaces M2's version: `pngData`, `fileInfo`, `pixelsPerPoint(fromDPI:)` and `image(at:)` are unchanged, `Failure` gains `unreadable`, and `LoadedCapture`, `cropPadding`, `load(url:)`, `alphaBounds(of:)` and `croppedToAlpha(_:padding:)` are new):

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A screenshot loaded for cutting out (spec section 5.8): its pixels with the
/// embedded colour profile, and its pixels per point from the file's DPI, so
/// the sticker's natural point size is pixels / pixelsPerPoint on mixed 1×/2×
/// setups too.
struct LoadedCapture {
    let image: CGImage
    let pixelsPerPoint: Double
}

/// Master PNGs on disk (spec section 6.8): written with DPI = 72 × pixels per
/// point, so recovery can restore a sticker's natural size from the file alone.
/// Also loads screenshots (`load(url:)`) and crops cutouts to their pixels.
enum MasterImage {
    enum Failure: Error {
        case cannotEncode
        case unreadable
    }

    /// What launch repair needs from a PNG without decoding its pixels.
    struct FileInfo: Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        /// From the file's DPI; nil when the file has none.
        let pixelsPerPoint: Double?
    }

    /// The transparent border a master keeps around its pixels (spec section 6.8).
    static let cropPadding = 2

    /// PNG data for `image` (its colour profile embedded) with DPI = 72 × `pixelsPerPoint`.
    static func pngData(_ image: CGImage, pixelsPerPoint: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, UTType.png.identifier as CFString, 1, nil)
        else { throw Failure.cannotEncode }
        let dpi = 72 * pixelsPerPoint
        let properties: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.cannotEncode }
        return data as Data
    }

    /// Pixel size and DPI-derived pixels per point; nil when the file isn't a readable image.
    static func fileInfo(at url: URL) -> FileInfo? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0,
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0
        else { return nil }
        let dpi = properties[kCGImagePropertyDPIWidth] as? Double
        return FileInfo(pixelWidth: width, pixelHeight: height,
                        pixelsPerPoint: dpi.flatMap(pixelsPerPoint(fromDPI:)))
    }

    /// DPI / 72, rounded to 0.01 (PNG stores pixels per metre, so 144 DPI can
    /// come back as 143.99). nil for a DPI that isn't positive.
    static func pixelsPerPoint(fromDPI dpi: Double) -> Double? {
        guard dpi > 0 else { return nil }
        return (dpi / 72 * 100).rounded() / 100
    }

    /// The master's pixels as stored (colour profile kept). Thread-safe.
    static func image(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetCount(source) > 0
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Loads a screenshot with ImageIO, keeping its embedded ICC profile and
    /// decoding it at once, so the file can be deleted right after. Pixels per
    /// point come from the DPI (`LibraryStore.defaultPixelsPerPoint` when the
    /// file has none).
    static func load(url: URL) throws -> LoadedCapture {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0,
              let image = CGImageSourceCreateImageAtIndex(
                  source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary),
              image.width > 0, image.height > 0
        else { throw Failure.unreadable }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let dpi = properties?[kCGImagePropertyDPIWidth] as? Double
        return LoadedCapture(image: image,
                             pixelsPerPoint: dpi.flatMap(pixelsPerPoint(fromDPI:)) ?? LibraryStore.defaultPixelsPerPoint)
    }

    /// The smallest pixel rect (top-left origin) holding every pixel whose alpha
    /// isn't 0; nil when the image is fully transparent.
    static func alphaBounds(of image: CGImage) -> CGRect? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        context.setBlendMode(.copy)
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        var minX = width, minY = height, maxX = -1, maxY = -1
        // Row 0 of the context's memory is the image's top row; alpha is byte 3.
        for y in 0..<height {
            let row = pixels + y * width * 4
            var x = 0
            while x < width, row[x * 4 + 3] == 0 { x += 1 }
            guard x < width else { continue }
            var last = width - 1
            while row[last * 4 + 3] == 0 { last -= 1 }
            minX = min(minX, x)
            maxX = max(maxX, last)
            minY = min(minY, y)
            maxY = y
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
    }

    /// `image` cropped to its alpha bounds plus `padding` pixels on every side
    /// (kept inside the image); nil when it is fully transparent.
    static func croppedToAlpha(_ image: CGImage, padding: Int = cropPadding) -> CGImage? {
        guard let bounds = alphaBounds(of: image) else { return nil }
        let padded = bounds.insetBy(dx: -CGFloat(padding), dy: -CGFloat(padding))
            .intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        if padded.width == CGFloat(image.width), padded.height == CGFloat(image.height) { return image }
        // CGImage cropping takes a rect with the image's top-left as origin.
        return image.cropping(to: padded)
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 215 tests in 27 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/MasterImage.swift StickermineTests/CaptureTestSupport.swift StickermineTests/MasterImageTests.swift
git commit -m "Load captures with their profile and DPI; crop cutouts to their pixels" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: MaskSampler

**Files:**
- Create: `Stickermine/Capture/MaskSampler.swift`
- Test: Create `StickermineTests/MaskSamplerTests.swift`

**Interfaces:**
- Consumes: Core Video only; `CaptureImages.maskBuffer` (Task 5) in the tests.
- Produces:

```text
enum MaskSampler {                                     // Capture/MaskSampler.swift; pure
    static let threshold: Float                        // 0.5
    static func subject(atUnitTopLeft p: CGPoint, masks: [(index: Int, mask: CVPixelBuffer)]) -> Int?   // contract; > 0.5, the strongest wins
    static func value(in buffer: CVPixelBuffer, atUnitTopLeft p: CGPoint) -> Float?   // row = Int(v × h), col = Int(u × w), bytesPerRow
    static func bounds(of buffer: CVPixelBuffer) -> CGRect?                            // unit rect, top-left origin, > 0.5
}
```

Vision's per-instance masks are 512 × 512 whatever the capture's aspect ratio, rows top-down; `instanceAtPoint`, `pixel(at:)` and `allInstancesMask` are never used (spec section 6.2). The test masks have padded rows, so code that assumes `width × 4` bytes per row fails.

- [ ] **Step 1: Write the failing test**

`StickermineTests/MaskSamplerTests.swift`:

```swift
import CoreGraphics
import CoreVideo
import Testing
@testable import Stickermine

/// Synthetic 512 × 512 coverage masks, rows top-down, with padded rows.
struct MaskSamplerTests {
    /// Instance 1 covers the top-left quarter, instance 2 the bottom-right quarter.
    static let masks: [(index: Int, mask: CVPixelBuffer)] = [
        (1, CaptureImages.maskBuffer { x, y in x < 256 && y < 256 ? 1 : 0 }),
        (2, CaptureImages.maskBuffer { x, y in x >= 256 && y >= 256 ? 0.9 : 0 }),
    ]

    @Test func rowsAreReadTopDown() {
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.25, y: 0.25), masks: Self.masks) == 1)
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.75, y: 0.75), masks: Self.masks) == 2)
    }

    @Test func backgroundIsNil() {
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.25, y: 0.75), masks: Self.masks) == nil)
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.75, y: 0.25), masks: Self.masks) == nil)
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.5, y: 0.5), masks: []) == nil)
    }

    @Test func coverageMustBeAboveOneHalf() {
        let half: [(index: Int, mask: CVPixelBuffer)] = [(3, CaptureImages.maskBuffer { _, _ in 0.5 })]
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.5, y: 0.5), masks: half) == nil)
        let more: [(index: Int, mask: CVPixelBuffer)] = [(3, CaptureImages.maskBuffer { _, _ in 0.51 })]
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.5, y: 0.5), masks: more) == 3)
    }

    @Test func overlappingSubjectsGoToTheStrongerOne() {
        let overlap: [(index: Int, mask: CVPixelBuffer)] = [
            (1, CaptureImages.maskBuffer { _, _ in 0.6 }),
            (2, CaptureImages.maskBuffer { _, _ in 0.8 }),
        ]
        #expect(MaskSampler.subject(atUnitTopLeft: CGPoint(x: 0.1, y: 0.1), masks: overlap) == 2)
    }

    @Test func edgesAndOutsidePoints() {
        #expect(MaskSampler.value(in: Self.masks[0].mask, atUnitTopLeft: CGPoint(x: 0, y: 0)) == 1)
        // u = 1 or v = 1 reads the last column or row.
        #expect(MaskSampler.value(in: Self.masks[1].mask, atUnitTopLeft: CGPoint(x: 1, y: 1)) == 0.9)
        #expect(MaskSampler.value(in: Self.masks[0].mask, atUnitTopLeft: CGPoint(x: -0.1, y: 0.5)) == nil)
        #expect(MaskSampler.value(in: Self.masks[0].mask, atUnitTopLeft: CGPoint(x: 0.5, y: 1.2)) == nil)
    }

    @Test func boundsAreUnitTopLeft() throws {
        let box = try #require(MaskSampler.bounds(of: Self.masks[1].mask))
        #expect(box == CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5))
        let empty = CaptureImages.maskBuffer { _, _ in 0 }
        #expect(MaskSampler.bounds(of: empty) == nil)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/MaskSamplerTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'MaskSampler' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/MaskSampler.swift`:

```swift
import CoreGraphics
import CoreVideo

/// Maps a click to a subject on Vision's per-instance coverage masks (spec
/// section 6.2): `generateMask(for: [i])` returns a 512 × 512
/// OneComponent32Float buffer with rows top-down, whatever the image's aspect
/// ratio. Pure: no AppKit, no Vision.
enum MaskSampler {
    /// Coverage above this counts as the subject.
    static let threshold: Float = 0.5

    /// The instance whose coverage at `p` (0–1, top-left origin) is above 0.5,
    /// the highest when masks overlap; nil means background.
    static func subject(atUnitTopLeft p: CGPoint, masks: [(index: Int, mask: CVPixelBuffer)]) -> Int? {
        var best: (index: Int, value: Float)?
        for entry in masks {
            guard let value = value(in: entry.mask, atUnitTopLeft: p), value > threshold else { continue }
            if best == nil || value > best!.value { best = (entry.index, value) }
        }
        return best?.index
    }

    /// The coverage at `p` (0–1, top-left origin): row = Int(v × height),
    /// col = Int(u × width), read with the buffer's own bytes per row. nil for
    /// a point outside 0–1 or a buffer that isn't OneComponent32Float.
    static func value(in buffer: CVPixelBuffer, atUnitTopLeft p: CGPoint) -> Float? {
        guard p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1,
              CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float
        else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let row = min(height - 1, Int(p.y * CGFloat(height)))
        let col = min(width - 1, Int(p.x * CGFloat(width)))
        let rowStart = base + row * CVPixelBufferGetBytesPerRow(buffer)
        return rowStart.assumingMemoryBound(to: Float.self)[col]
    }

    /// The unit rect (top-left origin) of the pixels above the threshold; nil
    /// when there are none.
    static func bounds(of buffer: CVPixelBuffer) -> CGRect? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float else { return nil }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard width > 0, height > 0 else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width where row[x] > threshold {
                minX = min(minX, x)
                maxX = max(maxX, x)
                minY = min(minY, y)
                maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: CGFloat(minX) / CGFloat(width), y: CGFloat(minY) / CGFloat(height),
                      width: CGFloat(maxX - minX + 1) / CGFloat(width),
                      height: CGFloat(maxY - minY + 1) / CGFloat(height))
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 221 tests in 28 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/MaskSampler.swift StickermineTests/MaskSamplerTests.swift
git commit -m "Map clicks to subjects on Vision's top-down coverage masks" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: HoleFiller

**Files:**
- Create: `Stickermine/Capture/HoleFiller.swift`
- Test: Create `StickermineTests/HoleFillerTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces:

```text
enum HoleFiller {                                      // Capture/HoleFiller.swift; pure
    static let defaultEdge: Int                        // 3 (spec 6.6: "within 2–3 px of the outside")
    static let threshold: Float                        // 0.5
    static func fill(alpha: inout [Float], width: Int, height: Int, edge: Int)   // contract
}
```

The outside is every pixel below 0.5 that is 4-connected to the border; pixels within `edge` 8-connected steps of it keep their alpha (the soft edge Vision drew), everything deeper becomes 1, so enclosed holes and the faint speckle inside them close.

- [ ] **Step 1: Write the failing test**

`StickermineTests/HoleFillerTests.swift`:

```swift
import Foundation
import Testing
@testable import Stickermine

struct HoleFillerTests {
    /// A `size` × `size` mask from `value(x, y)`.
    static func mask(_ size: Int, _ value: (Int, Int) -> Float) -> [Float] {
        (0..<(size * size)).map { value($0 % size, $0 / size) }
    }

    /// A ring: opaque between radius 6 and 15 around (20, 20), a hole inside.
    static func ring(hole: Float = 0) -> [Float] {
        mask(40) { x, y in
            let d = hypot(Double(x) - 20, Double(y) - 20)
            if d < 6 { return hole }
            return d < 15 ? 1 : 0
        }
    }

    @Test func anEnclosedHoleIsFilled() {
        var alpha = Self.ring()
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 20] == 1)          // the centre
        #expect(alpha[0] == 0)                     // the outside stays clear
        #expect(alpha[20 * 40 + 37] == 0)
    }

    @Test func faintSpeckleInsideAHoleIsCleared() {
        var alpha = Self.ring(hole: 0.3)
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 20] == 1)
    }

    @Test func aGapOpenToTheOutsideIsNotAHole() {
        // A C shape: the ring with a slot cut from the hole to the right edge.
        var alpha = Self.mask(40) { x, y in
            let d = hypot(Double(x) - 20, Double(y) - 20)
            if d < 6 || (x >= 20 && abs(y - 20) <= 1) { return 0 }
            return d < 15 ? 1 : 0
        }
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 20] == 0)
    }

    @Test func theSoftOuterEdgeKeepsItsAlpha() {
        // Opaque 20 × 20 block with a 0.6 rim one pixel wide, on clear.
        var alpha = Self.mask(40) { x, y in
            if (10..<30).contains(x) && (10..<30).contains(y) { return 1 }
            if (9..<31).contains(x) && (9..<31).contains(y) { return 0.6 }
            return 0
        }
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[9 * 40 + 20] == 0.6)
        #expect(alpha[20 * 40 + 9] == 0.6)
    }

    @Test func pixelsFartherThanTheEdgeBecomeOpaque() {
        // A 0.7 square: everything deeper than 3 px from the outside becomes 1.
        var alpha = Self.mask(40) { x, y in (10..<30).contains(x) && (10..<30).contains(y) ? 0.7 : 0 }
        HoleFiller.fill(alpha: &alpha, width: 40, height: 40, edge: 3)
        #expect(alpha[20 * 40 + 11] == 0.7)    // 2 px in
        #expect(alpha[20 * 40 + 12] == 0.7)    // 3 px in
        #expect(alpha[20 * 40 + 13] == 1)      // 4 px in
    }

    @Test func aMismatchedSizeChangesNothing() {
        var alpha: [Float] = [0, 0.2, 1]
        HoleFiller.fill(alpha: &alpha, width: 2, height: 2, edge: 3)
        #expect(alpha == [0, 0.2, 1])
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/HoleFillerTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'HoleFiller' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/HoleFiller.swift`:

```swift
/// Fill holes (spec section 6.6): closes white-on-white gaps such as toggle
/// knobs and calculator keys. Flood-fills the outside of the mask from the
/// image border through pixels with alpha below 0.5, then sets alpha to 1
/// everywhere that isn't within `edge` pixels of that outside, so the soft
/// outer edge stays as Vision drew it. Pure.
enum HoleFiller {
    /// The spec's "within 2–3 px of the outside".
    static let defaultEdge = 3
    static let threshold: Float = 0.5

    /// `alpha`: `width` × `height` values in 0–1, row by row (any row order).
    static func fill(alpha: inout [Float], width: Int, height: Int, edge: Int) {
        let count = width * height
        guard width > 0, height > 0, alpha.count == count else { return }

        // 1. The outside: every below-threshold pixel 4-connected to the border.
        var outside = [Bool](repeating: false, count: count)
        var queue: [Int] = []
        queue.reserveCapacity(count / 4)
        func seed(_ index: Int) {
            if !outside[index], alpha[index] < threshold {
                outside[index] = true
                queue.append(index)
            }
        }
        for x in 0..<width {
            seed(x)
            seed((height - 1) * width + x)
        }
        for y in 0..<height {
            seed(y * width)
            seed(y * width + width - 1)
        }
        var head = 0
        while head < queue.count {
            let index = queue[head]
            head += 1
            let x = index % width
            let y = index / width
            if x > 0 { seed(index - 1) }
            if x < width - 1 { seed(index + 1) }
            if y > 0 { seed(index - width) }
            if y < height - 1 { seed(index + width) }
        }

        // 2. Distance from the outside (8-connected steps), up to `edge`.
        var distance = [Int32](repeating: Int32.max, count: count)
        var frontier: [Int] = []
        for index in 0..<count where outside[index] {
            distance[index] = 0
            // Seed only outside pixels with an inside 4-neighbour: every inside
            // pixel next to the outside touches one of them, so the distances are
            // the same and the rest of the outside (most of a large capture) is
            // never visited.
            let x = index % width
            let y = index / width
            if (x > 0 && !outside[index - 1]) || (x < width - 1 && !outside[index + 1])
                || (y > 0 && !outside[index - width]) || (y < height - 1 && !outside[index + width]) {
                frontier.append(index)
            }
        }
        var step: Int32 = 0
        while !frontier.isEmpty, step < Int32(edge) {
            step += 1
            var next: [Int] = []
            for index in frontier {
                let x = index % width
                let y = index / width
                for dy in -1...1 {
                    let ny = y + dy
                    guard ny >= 0, ny < height else { continue }
                    for dx in -1...1 {
                        let nx = x + dx
                        guard nx >= 0, nx < width else { continue }
                        let neighbour = ny * width + nx
                        if distance[neighbour] > step {
                            distance[neighbour] = step
                            next.append(neighbour)
                        }
                    }
                }
            }
            frontier = next
        }

        // 3. Everything farther than `edge` from the outside becomes opaque.
        for index in 0..<count where distance[index] > Int32(edge) {
            alpha[index] = 1
        }
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 227 tests in 29 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/HoleFiller.swift StickermineTests/HoleFillerTests.swift
git commit -m "Add HoleFiller for the picker's Fill holes" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: CutoutEngine and CutoutAnalysis

**Files:**
- Create: `Stickermine/Capture/CutoutEngine.swift`
- Test: Create `StickermineTests/CutoutEngineTests.swift`

**Interfaces:**
- Consumes: `LoadedCapture`, `MasterImage.croppedToAlpha` (Task 5), `MaskSampler` (Task 6), `HoleFiller` (Task 7), `SurfaceContents.colorSpace(for:)` (M3); Vision's `GenerateForegroundInstanceMaskRequest`, `ImageRequestHandler`, `InstanceMaskObservation.generateMask(for:)` and `generateScaledMask(for:scaledToImageFrom:)` (all in the macOS 26 SDK).
- Produces:

```text
enum CutoutError: Error, Equatable { case emptySelection, released, emptyMask, renderFailed }
final class CutoutEngine: @unchecked Sendable {                       // contract: prewarm(), analyze(_:)
    typealias Perform = @Sendable (ImageRequestHandler) async throws -> InstanceMaskObservation?
    static let vision: Perform                                         // performs GenerateForegroundInstanceMaskRequest()
    let context: CIContext                                             // Metal-backed, no cached intermediates
    init(perform: @escaping Perform = CutoutEngine.vision)
    func prewarm()                                                     // a throwaway request on warmUpImage(), off the main actor
    func analyze(_ capture: LoadedCapture) async -> CutoutAnalysis     // nil, no instances or any throw → no subjects
    static func warmUpImage() -> CGImage?
}
final class CutoutAnalysis: @unchecked Sendable {
    static let refineBelow: Double; static let refineMargin: Double    // 0.6, 0.08
    static let cornerRadiusFraction: Double; static let displayLongSide: Int   // 0.04, 1024
    let capture: LoadedCapture; let subjectIndices: [Int]              // contract
    let displayImage: CGImage                                          // the capture at most 1024 px long, for the picker
    init(capture:handler:observation:masks:context:perform:)
    func subject(atUnitTopLeft p: CGPoint) -> Int?                     // contract
    func highlightMask(for index: Int) -> CGImage?                     // contract; 512 × 512 white, alpha = coverage
    func bounds(of selection: Set<Int>) -> CGRect?                     // union of the boxes, unit, top-left
    static func refines(_ unitBounds: CGRect, width: Int, height: Int) -> Bool
    var refinedCutoutCount: Int { get }
    func cutout(selection: Set<Int>, fillHoles: Bool) async throws -> CGImage   // contract; cropped master, capture's colour space
    func wholeImage() -> CGImage                                       // contract; alpha kept, corners 4%, cropped; computed once
    func release()                                                     // drops the handler, observation and masks
    static func maskImage(_ buffer: CVPixelBuffer) -> CIImage          // NSNull colour space
    static func coverageImage(_ buffer: CVPixelBuffer) -> CGImage?
    static func roundedCorners(_ image: CGImage) -> CGImage?
    static func downsampled(_ image: CGImage, longSide: Int) -> CGImage?
}
```

These tests run Vision for real on generated captures (verified while writing this plan on macOS 27.2: the two-shapes capture gives 2 subjects, the toggle 1 with its knob cut out as a hole, solid colours `nil`, the red-to-blue gradient a thrown `requestCancelled`; a flat square filling its pass-2 crop finds nothing, so pass 2 falls back to pass 1 there). The checks only assert what the spec relies on, so they hold whichever of `nil` or a throw macOS 26 returns.

- [ ] **Step 1: Write the failing test**

`StickermineTests/CutoutEngineTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
import Vision
@testable import Stickermine

/// Vision on generated captures (spec sections 6 and 18).
struct CutoutEngineTests {
    @Test func twoShapesAreTwoSubjectsFoundWhereTheyAre() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        #expect(analysis.subjectIndices.count == 2)
        #expect(!analysis.subjectIndices.contains(0))
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        let square = try #require(analysis.subject(atUnitTopLeft: CaptureImages.squareCentre))
        #expect(disc != square)
        #expect(analysis.subject(atUnitTopLeft: CaptureImages.backgroundPoint) == nil)
        #expect(analysis.displayImage.width == 1024)
    }

    @Test func aSmallSelectionIsRefinedCutOutAndCroppedWithItsColours() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        let cutout = try await analysis.cutout(selection: [disc], fillHoles: false)
        #expect(analysis.refinedCutoutCount == 1)
        // The 280 px disc plus 2 px on each side, give or take Vision's edge.
        #expect(abs(cutout.width - 284) <= 8)
        #expect(abs(cutout.height - 284) <= 8)
        let centre = CaptureImages.rgba(cutout, x: cutout.width / 2, y: cutout.height / 2)
        #expect(centre[3] == 255)
        #expect(abs(Int(centre[0]) - 230) <= 2 && abs(Int(centre[1]) - 51) <= 2 && abs(Int(centre[2]) - 64) <= 2)
        // The disc's box corner is background: cut away.
        #expect(CaptureImages.rgba(cutout, x: 3, y: 3)[3] == 0)
        #expect(cutout.colorSpace?.name == CGColorSpace.sRGB)
    }

    @Test func aLargeSelectionSkipsPassTwo() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        let cutout = try await analysis.cutout(selection: Set(analysis.subjectIndices), fillHoles: false)
        #expect(analysis.refinedCutoutCount == 0)
        // Both shapes: x 160–1020, y 120–680 from the top, plus 2 px, plus the
        // soft edge of a 512 px mask stretched over 1200 px.
        #expect(abs(cutout.width - 864) <= 16)
        #expect(abs(cutout.height - 564) <= 16)
    }

    @Test func fillHolesClosesAWhiteKnobOnAWhiteBackground() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.toggle()))
        let selection = Set(analysis.subjectIndices)
        #expect(!selection.isEmpty)
        let plain = try await analysis.cutout(selection: selection, fillHoles: false)
        let filled = try await analysis.cutout(selection: selection, fillHoles: true)
        #expect(filled.width == plain.width && filled.height == plain.height)
        let knob = (x: plain.width * 3 / 4, y: plain.height / 2)
        #expect(CaptureImages.rgba(plain, x: knob.x, y: knob.y)[3] == 0)      // Vision cut the knob out
        #expect(CaptureImages.rgba(filled, x: knob.x, y: knob.y)[3] == 255)   // Fill holes put it back
        #expect(CaptureImages.rgba(filled, x: 0, y: 0)[3] == 0)               // the outside stays clear
    }

    @Test func flatColoursHaveNoSubject() async {
        let engine = CutoutEngine()
        for image in [CaptureImages.flat(red: 0.1, green: 0.3, blue: 0.9),
                      CaptureImages.flat(red: 1, green: 1, blue: 1),
                      CaptureImages.gradient()] {
            let analysis = await engine.analyze(CaptureImages.loaded(image))
            #expect(analysis.subjectIndices.isEmpty)
        }
    }

    @Test func aThrownErrorOrNilMeansNoSubject() async {
        let throwing = CutoutEngine(perform: { _ in throw VisionError.requestCancelled("test") })
        #expect(await throwing.analyze(CaptureImages.loaded(CaptureImages.twoShapes())).subjectIndices.isEmpty)
        let empty = CutoutEngine(perform: { _ in nil })
        let analysis = await empty.analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        #expect(analysis.subjectIndices.isEmpty)
        // With no subject, a cutout is refused and the whole image still works.
        await #expect(throws: CutoutError.self) { try await analysis.cutout(selection: [1], fillHoles: false) }
        #expect(analysis.wholeImage().width == 1200)
    }

    @Test func theWholeImageKeepsItsAlphaAndRoundsItsCorners() {
        let window = CaptureImages.window()
        let whole = CutoutAnalysis(capture: CaptureImages.loaded(window), handler: nil, observation: nil, masks: [],
                                   context: CutoutEngine().context, perform: CutoutEngine.vision).wholeImage()
        #expect(whole.width == 800)
        #expect(whole.height == 500)
        #expect(CaptureImages.rgba(whole, x: 2, y: 2)[3] == 0)          // the window's own transparent corner
        #expect(CaptureImages.rgba(whole, x: 400, y: 250)[3] == 255)
        #expect(CaptureImages.rgba(whole, x: 1, y: 250)[3] == 255)      // 4% of 500 = 20 < the window's 40

        let opaque = CaptureImages.flat(red: 0.5, green: 0.5, blue: 0.5)   // 600 × 400: radius 16
        let rounded = CutoutAnalysis(capture: CaptureImages.loaded(opaque), handler: nil, observation: nil, masks: [],
                                     context: CutoutEngine().context, perform: CutoutEngine.vision).wholeImage()
        #expect(CaptureImages.rgba(rounded, x: 1, y: 1)[3] == 0)
        #expect(CaptureImages.rgba(rounded, x: 16, y: 16)[3] == 255)
        #expect(CaptureImages.rgba(rounded, x: 0, y: 200)[3] == 255)
    }

    @Test func emptySelectionsTheBackgroundAndReleasedAnalysesAreRefused() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        await #expect(throws: CutoutError.emptySelection) { try await analysis.cutout(selection: [], fillHoles: false) }
        await #expect(throws: CutoutError.emptySelection) { try await analysis.cutout(selection: [0], fillHoles: true) }
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        analysis.release()
        await #expect(throws: CutoutError.released) { try await analysis.cutout(selection: [disc], fillHoles: false) }
        #expect(analysis.subject(atUnitTopLeft: CaptureImages.discCentre) == nil)
    }

    @Test func highlightMasksShowEachSubjectsCoverage() async throws {
        let analysis = await CutoutEngine().analyze(CaptureImages.loaded(CaptureImages.twoShapes()))
        let disc = try #require(analysis.subject(atUnitTopLeft: CaptureImages.discCentre))
        let mask = try #require(analysis.highlightMask(for: disc))
        #expect(mask.width == 512 && mask.height == 512)
        #expect(CaptureImages.rgba(mask, x: Int(CaptureImages.discCentre.x * 512), y: Int(CaptureImages.discCentre.y * 512))[3] > 200)
        #expect(CaptureImages.rgba(mask, x: Int(CaptureImages.squareCentre.x * 512), y: Int(CaptureImages.squareCentre.y * 512))[3] == 0)
    }

    @Test func passTwoIsForBoxesUnderSixtyPercentOfTheLongSide() {
        #expect(CutoutAnalysis.refines(CGRect(x: 0, y: 0, width: 0.5, height: 0.5), width: 1000, height: 1000))
        #expect(!CutoutAnalysis.refines(CGRect(x: 0, y: 0, width: 0.6, height: 0.1), width: 1000, height: 1000))
        // A tall box on a wide capture: 0.9 × 500 = 450 px < 0.6 × 1000.
        #expect(CutoutAnalysis.refines(CGRect(x: 0, y: 0, width: 0.1, height: 0.9), width: 1000, height: 500))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/CutoutEngineTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'CutoutEngine' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/CutoutEngine.swift`:

```swift
import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import Metal
import Vision
import os

enum CutoutError: Error, Equatable {
    /// No subject was selected (never ask Vision for an empty set or for 0).
    case emptySelection
    /// The picker closed and the Vision handler was let go.
    case released
    /// The mask came out empty.
    case emptyMask
    case renderFailed
}

/// On-device subject cutout with Vision's foreground instance masks (spec
/// section 6). `analyze` runs pass 1 on a capture and returns a
/// `CutoutAnalysis` for the picker. Never forces the CPU (it fails there).
/// Thread-safe; call it from any task.
final class CutoutEngine: @unchecked Sendable {
    /// Runs the foreground-instance request on a handler. Tests substitute one
    /// that throws or finds nothing.
    typealias Perform = @Sendable (ImageRequestHandler) async throws -> InstanceMaskObservation?

    static let vision: Perform = { handler in
        try await handler.perform(GenerateForegroundInstanceMaskRequest())
    }

    /// The Metal-backed context every cutout renders with.
    let context: CIContext
    private let perform: Perform
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "cutout")

    init(perform: @escaping Perform = CutoutEngine.vision) {
        self.perform = perform
        let options: [CIContextOption: Any] = [.cacheIntermediates: false]
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: options)
        } else {
            context = CIContext(options: options)
        }
    }

    /// Loads the Vision model with a throwaway request (about 100 ms cold) while
    /// the crosshair is up (spec section 5.5). Returns at once.
    func prewarm() {
        let perform = self.perform
        Task.detached(priority: .userInitiated) {
            guard let image = CutoutEngine.warmUpImage() else { return }
            _ = try? await perform(ImageRequestHandler(image))
        }
    }

    /// Pass 1 on the full capture. nil, no instances and any thrown error (Vision
    /// throws `requestCancelled` on flat colours) all mean "no subject": the
    /// analysis then has no subjects and the picker offers the whole image.
    func analyze(_ capture: LoadedCapture) async -> CutoutAnalysis {
        let handler = ImageRequestHandler(capture.image)
        var observation: InstanceMaskObservation?
        do {
            observation = try await perform(handler)
        } catch {
            log.notice("no subject: Vision threw \(String(describing: error), privacy: .public)")
        }
        var masks: [(index: Int, mask: CVPixelBuffer)] = []
        if let observation {
            // Instance 0 is the background; never ask for it.
            for index in observation.allInstances.sorted() where index > 0 {
                do {
                    masks.append((index, try observation.generateMask(for: IndexSet(integer: index))))
                } catch {
                    log.error("mask for instance \(index) failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        log.notice("pass 1: \(masks.count) subjects in \(capture.image.width)x\(capture.image.height)")
        return CutoutAnalysis(capture: capture, handler: masks.isEmpty ? nil : handler,
                              observation: masks.isEmpty ? nil : observation, masks: masks,
                              context: context, perform: perform)
    }

    /// A small picture with one obvious subject, for the warm-up request.
    static func warmUpImage() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: 0.95, green: 0.94, blue: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        context.setFillColor(CGColor(srgbRed: 0.85, green: 0.2, blue: 0.3, alpha: 1))
        context.fillEllipse(in: CGRect(x: 16, y: 16, width: 32, height: 32))
        return context.makeImage()
    }
}

/// What Vision found in one capture, kept while the picker is open (spec
/// section 6). Holds the pass-1 handler and observation (about 130 MB at peak)
/// until `release()`. Thread-safe.
final class CutoutAnalysis: @unchecked Sendable {
    /// Pass 2 runs when the selection's box is under this share of the
    /// capture's long side.
    static let refineBelow = 0.6
    /// Pass 2 looks at the box plus this share of its size on every side.
    static let refineMargin = 0.08
    /// Whole image: corners rounded at 4% of the short side.
    static let cornerRadiusFraction = 0.04
    /// The picker shows the capture downsampled to this long side.
    static let displayLongSide = 1024

    let capture: LoadedCapture
    /// Vision's instance indices, ascending; empty when there is no subject.
    let subjectIndices: [Int]
    /// The capture at most `displayLongSide` pixels long, for the picker.
    let displayImage: CGImage

    private let context: CIContext
    private let perform: CutoutEngine.Perform
    private let lock = NSLock()
    private var handler: ImageRequestHandler?
    private var observation: InstanceMaskObservation?
    private var masks: [(index: Int, mask: CVPixelBuffer)]
    private var whole: CGImage?
    private var refinedCount = 0

    init(capture: LoadedCapture, handler: ImageRequestHandler?, observation: InstanceMaskObservation?,
         masks: [(index: Int, mask: CVPixelBuffer)], context: CIContext, perform: @escaping CutoutEngine.Perform) {
        self.capture = capture
        self.handler = handler
        self.observation = observation
        self.masks = masks
        self.context = context
        self.perform = perform
        subjectIndices = masks.map(\.index)
        displayImage = Self.downsampled(capture.image, longSide: Self.displayLongSide) ?? capture.image
    }

    /// The subject under `p` (0–1, top-left origin of the capture); nil is background.
    func subject(atUnitTopLeft p: CGPoint) -> Int? {
        MaskSampler.subject(atUnitTopLeft: p, masks: currentMasks())
    }

    /// A 512 × 512 white image whose alpha is the subject's coverage, for the
    /// picker's highlight (stretched over the capture).
    func highlightMask(for index: Int) -> CGImage? {
        guard let mask = currentMasks().first(where: { $0.index == index })?.mask else { return nil }
        return Self.coverageImage(mask)
    }

    /// The union of the selected subjects' boxes (0–1, top-left origin).
    func bounds(of selection: Set<Int>) -> CGRect? {
        let boxes = currentMasks().filter { selection.contains($0.index) }.compactMap { MaskSampler.bounds(of: $0.mask) }
        guard let first = boxes.first else { return nil }
        return boxes.dropFirst().reduce(first) { $0.union($1) }
    }

    /// Pass 2 is worth it when the box's long side is under 60% of the capture's.
    static func refines(_ unitBounds: CGRect, width: Int, height: Int) -> Bool {
        let longSide = max(unitBounds.width * CGFloat(width), unitBounds.height * CGFloat(height))
        return Double(longSide) < refineBelow * Double(max(width, height))
    }

    /// How many cutouts used pass 2 (diagnostics and tests).
    var refinedCutoutCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return refinedCount
    }

    /// The selected subjects cut out of the capture, cropped to their pixels
    /// plus 2 px, in the capture's colour space: the master as it will be
    /// saved. A small selection is refined with pass 2 (spec section 6.4);
    /// Fill holes closes enclosed gaps (6.6).
    func cutout(selection: Set<Int>, fillHoles: Bool) async throws -> CGImage {
        let picked = selection.filter { $0 > 0 }.sorted()
        guard !picked.isEmpty else { throw CutoutError.emptySelection }
        guard let (handler, observation) = visionState() else { throw CutoutError.released }
        let width = capture.image.width
        let height = capture.image.height
        let full = CGRect(x: 0, y: 0, width: width, height: height)

        let firstPass = Self.maskImage(try observation.generateScaledMask(
            for: IndexSet(picked), scaledToImageFrom: handler))
        var mask = firstPass
        if let unit = bounds(of: Set(picked)), Self.refines(unit, width: width, height: height),
           let refined = await refinedMask(unit: unit, firstPass: firstPass) {
            mask = refined
            countRefinement()
        }
        try Task.checkCancellation()
        if fillHoles {
            mask = try filled(mask, width: width, height: height)
        }
        // CIBlendWithMask over an empty background keeps the original's exact
        // colours (generateMaskedImage would drop the colour space).
        let blended = CIImage(cgImage: capture.image).applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage.empty(),
            kCIInputMaskImageKey: mask,
        ])
        guard let space = SurfaceContents.colorSpace(for: capture.image),
              let rendered = context.createCGImage(blended, from: full, format: .RGBA8, colorSpace: space)
        else { throw CutoutError.renderFailed }
        context.clearCaches()
        try Task.checkCancellation()
        guard let cropped = MasterImage.croppedToAlpha(rendered) else { throw CutoutError.emptyMask }
        return cropped
    }

    /// The original capture with its own alpha kept (window captures have
    /// transparent corners) and corners rounded at 4% of the short side,
    /// cropped to its pixels plus 2 px (spec section 6.7). Computed once.
    func wholeImage() -> CGImage {
        lock.lock()
        if let whole {
            lock.unlock()
            return whole
        }
        lock.unlock()
        let rounded = Self.roundedCorners(capture.image) ?? capture.image
        let result = MasterImage.croppedToAlpha(rounded) ?? rounded
        lock.lock()
        whole = result
        lock.unlock()
        return result
    }

    /// Lets go of the Vision handler, observation and masks (the picker closed).
    func release() {
        lock.lock()
        handler = nil
        observation = nil
        masks = []
        lock.unlock()
    }

    // MARK: Helpers

    private func currentMasks() -> [(index: Int, mask: CVPixelBuffer)] {
        lock.lock()
        defer { lock.unlock() }
        return masks
    }

    /// The pass-1 handler and observation; nil after `release()`.
    private func visionState() -> (ImageRequestHandler, InstanceMaskObservation)? {
        lock.lock()
        defer { lock.unlock() }
        guard let handler, let observation else { return nil }
        return (handler, observation)
    }

    private func countRefinement() {
        lock.lock()
        refinedCount += 1
        lock.unlock()
    }

    /// Pass 2 on the box plus 8%: the union of what Vision finds there,
    /// intersected with a slightly dilated pass-1 mask, as a full-size mask.
    /// nil when pass 2 finds nothing (the pass-1 mask is used then).
    private func refinedMask(unit: CGRect, firstPass: CIImage) async -> CIImage? {
        let width = CGFloat(capture.image.width)
        let height = CGFloat(capture.image.height)
        let box = CGRect(x: unit.minX * width, y: unit.minY * height, width: unit.width * width,
                         height: unit.height * height)
        let marginX = max(8, box.width * CGFloat(Self.refineMargin))
        let marginY = max(8, box.height * CGFloat(Self.refineMargin))
        let region = box.insetBy(dx: -marginX, dy: -marginY).integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        guard !region.isEmpty, let crop = capture.image.cropping(to: region) else { return nil }
        let cropHandler = ImageRequestHandler(crop)
        guard let second = try? await perform(cropHandler) else { return nil }
        let instances = IndexSet(second.allInstances.filter { $0 > 0 })
        guard !instances.isEmpty,
              let secondMask = try? second.generateScaledMask(for: instances, scaledToImageFrom: cropHandler)
        else { return nil }
        // Core Image is y-up: the crop's top-left region sits at height − maxY.
        let placedRegion = CGRect(x: region.minX, y: height - region.maxY, width: region.width, height: region.height)
        let placed = Self.maskImage(secondMask)
            .transformed(by: CGAffineTransform(translationX: placedRegion.minX, y: placedRegion.minY))
        let texel = Double(max(width, height)) / 512
        let dilated = firstPass.applyingFilter("CIMorphologyMaximum", parameters: [
            kCIInputRadiusKey: max(2, 1.5 * texel),
        ])
        let combined = placed.applyingFilter("CIMinimumCompositing", parameters: [
            kCIInputBackgroundImageKey: dilated,
        ]).cropped(to: placedRegion)
        return combined.composited(over: CIImage(color: CIColor.black)
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height)))
    }

    /// `mask` rendered into a float buffer, holes filled (`HoleFiller`), and
    /// wrapped again without colour management.
    private func filled(_ mask: CIImage, width: Int, height: Int) throws -> CIImage {
        var created: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_OneComponent32Float,
                            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &created)
        guard let buffer = created else { throw CutoutError.renderFailed }
        context.render(mask, to: buffer, bounds: CGRect(x: 0, y: 0, width: width, height: height), colorSpace: nil)
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw CutoutError.renderFailed }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var alpha = [Float](repeating: 0, count: width * height)
        alpha.withUnsafeMutableBufferPointer { values in
            for y in 0..<height {
                let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in 0..<width { values[y * width + x] = row[x] }
            }
        }
        HoleFiller.fill(alpha: &alpha, width: width, height: height, edge: HoleFiller.defaultEdge)
        alpha.withUnsafeBufferPointer { values in
            for y in 0..<height {
                let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
                for x in 0..<width { row[x] = values[y * width + x] }
            }
        }
        return Self.maskImage(buffer)
    }

    /// A Vision mask as a Core Image mask. The NSNull colour space stops Core
    /// Image from treating the coverage as gamma-encoded grey and linearising
    /// it, which would shift the edge (spec section 6.5).
    static func maskImage(_ buffer: CVPixelBuffer) -> CIImage {
        CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
    }

    /// White, with the coverage as premultiplied alpha.
    static func coverageImage(_ buffer: CVPixelBuffer) -> CGImage? {
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_OneComponent32Float,
              width > 0, height > 0, let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: width * 4, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = context.data
        else { return nil }
        CVPixelBufferLockBaseAddress(buffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let pixels = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        for y in 0..<height {
            let row = (base + y * rowBytes).assumingMemoryBound(to: Float.self)
            for x in 0..<width {
                let value = UInt8(max(0, min(1, row[x])) * 255)
                let pixel = pixels + (y * width + x) * 4
                pixel[0] = value
                pixel[1] = value
                pixel[2] = value
                pixel[3] = value
            }
        }
        return context.makeImage()
    }

    /// `image` clipped to a rounded rect (radius 4% of the short side), its own
    /// alpha kept, in its own colour space when that is RGB.
    static func roundedCorners(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        let radius = CGFloat(cornerRadiusFraction) * CGFloat(min(width, height))
        guard let space = SurfaceContents.colorSpace(for: image),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.clip()
        context.draw(image, in: rect)
        return context.makeImage()
    }

    /// `image` scaled down to at most `longSide` pixels (unchanged when smaller).
    static func downsampled(_ image: CGImage, longSide: Int) -> CGImage? {
        let scale = Double(longSide) / Double(max(image.width, image.height))
        guard scale < 1 else { return image }
        let width = max(1, Int((Double(image.width) * scale).rounded()))
        let height = max(1, Int((Double(image.height) * scale).rounded()))
        guard let space = SurfaceContents.colorSpace(for: image),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 237 tests in 30 suites passed` and `** TEST SUCCEEDED **`. Vision logs `[VisionLog] PostProcessingOperation error` for the flat-colour images; that is the no-subject path, not a failure.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/CutoutEngine.swift StickermineTests/CutoutEngineTests.swift
git commit -m "Add CutoutEngine: Vision subjects, pass 2, Fill holes and the whole image" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: StyleRenderer: in-flight masters

**Files:**
- Modify: `Stickermine/Capture/StyleRenderer.swift` (three edits shown below)
- Test: Modify `StickermineTests/StyleRendererTests.swift` (two tests added)

**Interfaces:**
- Consumes: M3's `StyleRenderer` (its `lock`, `inscribed` cache and `renderNow`).
- Produces (Contract changes item 4):

```text
added to final class StyleRenderer:
    func setInFlightMaster(_ image: CGImage?, for sticker: UUID)   // renders for that ID use `image` until nil; also forgets its inscribed radius
    var inFlightMasterCount: Int { get }                           // how many are registered (tests: the picker lets go of them)
```

- [ ] **Step 1: Write the failing tests**

In `StickermineTests/StyleRendererTests.swift`, add these two tests inside `struct StyleRendererTests`, after its last test (`onScreenParametersFollowPointsTimesBackingScale`), before the struct's closing brace:

```swift
    @Test func anInFlightMasterIsRenderedUntilItIsCleared() async throws {
        let renderer = self.renderer(nil)
        let square = request(points: CGSize(width: 50, height: 50), style: .none)
        await #expect(throws: StyleRenderer.RenderError.missingMaster) { _ = try await renderer.render(square) }
        renderer.setInFlightMaster(Masters.square(side: 100), for: id)
        #expect(renderer.inFlightMasterCount == 1)
        #expect(try await renderer.render(square).pixelSize == CGSize(width: 100, height: 100))
        renderer.setInFlightMaster(nil, for: id)
        #expect(renderer.inFlightMasterCount == 0)
        await #expect(throws: StyleRenderer.RenderError.missingMaster) { _ = try await renderer.render(square) }
    }

    @Test func anInFlightMasterIsMeasuredAgainWhenItChanges() async throws {
        let renderer = self.renderer(nil)
        let puffy = request(points: CGSize(width: 60, height: 60), style: .puffy)
        renderer.setInFlightMaster(Masters.disc(diameter: 120), for: id)
        _ = try await renderer.render(puffy)
        renderer.setInFlightMaster(Masters.disc(diameter: 120), for: id)
        _ = try await renderer.render(puffy)
        #expect(renderer.inscribedMeasurementCount == 2)
    }
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/StyleRendererTests
```

Expected: `** TEST FAILED **` with `error: value of type 'StyleRenderer' has no member 'setInFlightMaster'` and `error: value of type 'StyleRenderer' has no member 'inFlightMasterCount'`.

- [ ] **Step 3: Implement**

In `Stickermine/Capture/StyleRenderer.swift`, make three edits.

(a) Replace the stored properties under the lock:

```swift
    private let lock = NSLock()
    private var inscribed: [UUID: Inscribed] = [:]
    private var measurements = 0
    private var puffyPath: PuffyKernel.Path?
```

with:

```swift
    private let lock = NSLock()
    private var inscribed: [UUID: Inscribed] = [:]
    private var measurements = 0
    private var puffyPath: PuffyKernel.Path?
    /// Masters that aren't in the library (yet): the picker's cutouts.
    private var inFlight: [UUID: CGImage] = [:]
```

(b) Replace `invalidateCache(for:)` and its doc comment:

```swift
    /// Forgets what was measured for `sticker`; call it if a sticker's master
    /// ever changes under the same ID.
    func invalidateCache(for sticker: UUID) {
        lock.lock()
        inscribed[sticker] = nil
        lock.unlock()
    }
```

with the same function followed by the three new members:

```swift
    /// Forgets what was measured for `sticker`; call it if a sticker's master
    /// ever changes under the same ID.
    func invalidateCache(for sticker: UUID) {
        lock.lock()
        inscribed[sticker] = nil
        lock.unlock()
    }

    /// Renders for `sticker` use `image` instead of `masterProvider` until it is
    /// cleared with nil: the picker's previews and the placement render a
    /// cutout before (and while) its PNG is written. Setting or clearing it
    /// also forgets what was measured for that ID.
    func setInFlightMaster(_ image: CGImage?, for sticker: UUID) {
        lock.lock()
        inFlight[sticker] = image
        inscribed[sticker] = nil
        lock.unlock()
    }

    /// How many in-flight masters are registered (tests: the picker lets go of them).
    var inFlightMasterCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return inFlight.count
    }

    /// An in-flight master, else the provider's.
    private func master(for sticker: UUID) -> CGImage? {
        lock.lock()
        let image = inFlight[sticker]
        lock.unlock()
        return image ?? masterProvider(sticker)
    }
```

(c) In `renderNow(_:)`, replace its first line:

```swift
        guard let master = masterProvider(request.sticker) else { throw RenderError.missingMaster }
```

with:

```swift
        guard let master = master(for: request.sticker) else { throw RenderError.missingMaster }
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 239 tests in 30 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/StyleRenderer.swift StickermineTests/StyleRendererTests.swift
git commit -m "Let StyleRenderer render in-flight masters for the picker" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: PickerModel

**Files:**
- Create: `Stickermine/Picker/PickerModel.swift`
- Test: Create `StickermineTests/PickerModelTests.swift`

**Interfaces:**
- Consumes: `CutoutAnalysis`, `CutoutError` (Task 8), `StyleRenderer.setInFlightMaster` (Task 9), `StyleRenderer.render`, `RenderRequest.onScreenParameters(sourceLongSide:)`, `RenderedSticker`, `StyleParameters` (M2/M3), `StickerStyle.defaultFillHoles`, `StickerRecord` (M2).
- Produces:

```text
enum CutoutSource: Hashable { case wholeImage, subjects(Set<Int>, fillHoles: Bool), stored }
struct PickerState: Equatable {                                    // pure: spec 7's rules
    enum FillHolesDisplay: Equatable { case auto, on, off }
    let subjects: [Int]
    private(set) var selected: Set<Int>; private(set) var wholeImage: Bool
    private(set) var fillHolesChoice: Bool?; private(set) var hovered: StickerStyle?
    init(subjects: [Int])
    var wholeImageLocked: Bool { get }; var fillHolesEnabled: Bool { get }
    mutating func setWholeImage(_ on: Bool); mutating func click(subject: Int?)
    mutating func toggleFillHoles(); mutating func hover(_ style: StickerStyle, inside: Bool)
    func fillHoles(for style: StickerStyle) -> Bool; var fillHolesDisplay: FillHolesDisplay { get }
    func source(for style: StickerStyle) -> CutoutSource
}
@MainActor final class PickerModel: ObservableObject {
    enum Mode: Equatable { case capture, restyle(sticker: UUID, highlight: StickerStyle) }
    struct Preview { let request: RenderRequest; let rendered: RenderedSticker; let shadow: StyleParameters }
    struct Confirmation { let sticker: UUID; let style: StickerStyle; let image: CGImage?; let pixelsPerPoint: Double }
    struct Cut { let id: UUID; let pixelSize: CGSize; let image: CGImage? }
    typealias MakeCutout = @Sendable (CutoutSource) async throws -> CGImage
    static let debounce: TimeInterval                              // 0.1
    static let previewBox: CGSize                                  // 84 × 84 pt
    let mode: Mode; let pixelsPerPoint: Double; let displayImage: CGImage?; let highlightMasks: [Int: CGImage]
    @Published private(set) var state: PickerState
    @Published private(set) var previews: [StickerStyle: Preview]
    @Published private(set) var isConfirming: Bool
    private(set) var renderOrder: [StickerStyle]
    var onConfirm: ((Confirmation) -> Void)?
    init(mode:subjects:pixelsPerPoint:storedPixelSize:displayImage:highlightMasks:renderer:backingScale:subjectAt:makeCutout:)
    static func forCapture(_ analysis: CutoutAnalysis, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel
    static func forRestyle(_ record: StickerRecord, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel
    var highlightedStyle: StickerStyle? { get }
    func clickSubject(atUnitTopLeft p: CGPoint); func setWholeImage(_ on: Bool); func toggleFillHoles()
    func hover(_ style: StickerStyle, inside: Bool)
    func confirm(_ style: StickerStyle)                            // hands the style's cutout to onConfirm once ready
    func finish()                                                  // the picker closed: clears every in-flight master but the confirmed one;
                                                                   // a cutout still computing is dropped when it completes, a pending confirm never fires
}
```

A capture's cutouts are computed off the main actor (one per distinct source: until Fill holes is touched, Puffy and Outline share the filled one and Shadow and None the unfilled one), registered with the renderer under new IDs, and the previews render in UI order at their natural size fitted into 84 pt. The confirmed cutout's ID becomes the new sticker's ID. Re-placing renders the stored master under the sticker's own ID.

- [ ] **Step 1: Write the failing test**

`StickermineTests/PickerModelTests.swift`:

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

/// The picker's rules (spec section 7) and its previews.
@MainActor
struct PickerModelTests {
    // MARK: Selection

    @Test func subjectsStartSelectedWithWholeImageOff() {
        let state = PickerState(subjects: [1, 2, 3])
        #expect(state.selected == [1, 2, 3])
        #expect(!state.wholeImage)
        #expect(!state.wholeImageLocked)
    }

    @Test func withoutSubjectsWholeImageIsOnAndLocked() {
        var state = PickerState(subjects: [])
        #expect(state.wholeImage)
        #expect(state.wholeImageLocked)
        state.setWholeImage(false)
        #expect(state.wholeImage)
        state.click(subject: 1)
        #expect(state.wholeImage)
        #expect(state.selected.isEmpty)
    }

    @Test func turningWholeImageOnDeselectsEverySubject() {
        var state = PickerState(subjects: [1, 2])
        state.setWholeImage(true)
        #expect(state.wholeImage)
        #expect(state.selected.isEmpty)
    }

    @Test func turningWholeImageOffSelectsEverySubjectAgain() {
        var state = PickerState(subjects: [1, 2])
        state.setWholeImage(true)
        state.setWholeImage(false)
        #expect(!state.wholeImage)
        #expect(state.selected == [1, 2])
    }

    @Test func clickingASubjectWhileWholeImageIsOnSelectsOnlyThatSubject() {
        var state = PickerState(subjects: [1, 2, 3])
        state.setWholeImage(true)
        state.click(subject: 2)
        #expect(!state.wholeImage)
        #expect(state.selected == [2])
    }

    @Test func clickingTogglesAndDeselectingTheLastTurnsWholeImageOn() {
        var state = PickerState(subjects: [1, 2])
        state.click(subject: 1)
        #expect(state.selected == [2])
        state.click(subject: 1)
        #expect(state.selected == [1, 2])
        state.click(subject: 1)
        state.click(subject: 2)
        #expect(state.selected.isEmpty)
        #expect(state.wholeImage)
    }

    @Test func backgroundAndUnknownClicksChangeNothing() {
        var state = PickerState(subjects: [1, 2])
        state.click(subject: nil)
        state.click(subject: 7)
        #expect(state == PickerState(subjects: [1, 2]))
    }

    // MARK: Fill holes

    @Test func untouchedFillHolesUsesEachStylesDefault() {
        let state = PickerState(subjects: [1])
        #expect(state.fillHolesChoice == nil)
        #expect(state.fillHoles(for: .puffy))
        #expect(state.fillHoles(for: .outline))
        #expect(!state.fillHoles(for: .shadow))
        #expect(!state.fillHoles(for: .none))
        #expect(state.source(for: .puffy) == .subjects([1], fillHoles: true))
        #expect(state.source(for: .none) == .subjects([1], fillHoles: false))
    }

    @Test func theToggleShowsAutoOrTheHoveredPreviewsDefault() {
        var state = PickerState(subjects: [1])
        #expect(state.fillHolesDisplay == .auto)
        state.hover(.outline, inside: true)
        #expect(state.fillHolesDisplay == .on)
        state.hover(.shadow, inside: true)
        #expect(state.fillHolesDisplay == .off)
        state.hover(.outline, inside: false)     // a late exit from another preview
        #expect(state.fillHolesDisplay == .off)
        state.hover(.shadow, inside: false)
        #expect(state.fillHolesDisplay == .auto)
    }

    @Test func onceTouchedFillHolesAppliesToEveryStyle() {
        var state = PickerState(subjects: [1])
        state.toggleFillHoles()
        #expect(state.fillHolesChoice == true)
        #expect(StickerStyle.allCases.allSatisfy { state.fillHoles(for: $0) })
        state.hover(.none, inside: true)
        #expect(state.fillHolesDisplay == .on)
        state.toggleFillHoles()
        #expect(StickerStyle.allCases.allSatisfy { !state.fillHoles(for: $0) })
        #expect(state.fillHolesDisplay == .off)
    }

    @Test func fillHolesIsDisabledWhileWholeImageIsOn() {
        var state = PickerState(subjects: [1])
        state.setWholeImage(true)
        #expect(!state.fillHolesEnabled)
        state.toggleFillHoles()
        #expect(state.fillHolesChoice == nil)
        #expect(StickerStyle.allCases.allSatisfy { state.source(for: $0) == .wholeImage })
    }

    // MARK: Previews

    /// Records which cutouts were asked for.
    final class Calls: @unchecked Sendable {
        private let lock = NSLock()
        private var list: [CutoutSource] = []

        func add(_ source: CutoutSource) {
            lock.lock()
            list.append(source)
            lock.unlock()
        }

        var sources: [CutoutSource] {
            lock.lock()
            defer { lock.unlock() }
            return list
        }
    }

    static func model(subjects: [Int] = [1, 2], calls: Calls, renderer: StyleRenderer) -> PickerModel {
        PickerModel(mode: .capture, subjects: subjects, pixelsPerPoint: 2, renderer: renderer, backingScale: 2,
                    subjectAt: { $0.x < 0.5 ? 1 : 2 },
                    makeCutout: { source in
                        calls.add(source)
                        return Masters.disc(diameter: 200)
                    })
    }

    static func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            if Date() > deadline { return false }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return true
    }

    @Test func previewsRenderInUIOrderFromOneCutoutPerFillHolesValue() async {
        let calls = Calls()
        let model = Self.model(calls: calls, renderer: StyleRenderer(masterProvider: { _ in nil }))
        defer { model.finish() }
        #expect(await Self.waitUntil { model.previews.count == 4 })
        #expect(model.renderOrder == StickerStyle.allCases)
        #expect(Set(calls.sources) == [.subjects([1, 2], fillHoles: true), .subjects([1, 2], fillHoles: false)])
        #expect(calls.sources.count == 2)
        // Puffy and Outline share one cutout, Shadow and None the other.
        let ids = StickerStyle.allCases.map { model.previews[$0]?.request.sticker }
        #expect(ids[0] == ids[1] && ids[2] == ids[3] && ids[0] != ids[2])
        // 200 px at 2 px/pt is 100 pt, fitted into the 84 pt box.
        #expect(model.previews[.none]?.request.pointSize == CGSize(width: 84, height: 84))
    }

    @Test func confirmingUsesThatStylesCutoutAndID() async throws {
        let calls = Calls()
        let model = Self.model(calls: calls, renderer: StyleRenderer(masterProvider: { _ in nil }))
        defer { model.finish() }
        #expect(await Self.waitUntil { model.previews.count == 4 })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        model.confirm(.shadow)
        #expect(await Self.waitUntil { confirmed != nil })
        let confirmation = try #require(confirmed)
        #expect(confirmation.style == .shadow)
        #expect(confirmation.sticker == model.previews[.shadow]?.request.sticker)
        #expect(confirmation.image?.width == 200)
        #expect(confirmation.pixelsPerPoint == 2)
        #expect(model.isConfirming)
        model.confirm(.puffy)   // ignored: already confirming
        try? await Task.sleep(nanoseconds: 100_000_000)
        #expect(confirmed?.style == .shadow)
    }

    @Test func selectionChangesAreDebounced() async {
        let calls = Calls()
        let model = Self.model(calls: calls, renderer: StyleRenderer(masterProvider: { _ in nil }))
        defer { model.finish() }
        #expect(await Self.waitUntil { model.previews.count == 4 })
        let before = calls.sources.count
        model.clickSubject(atUnitTopLeft: CGPoint(x: 0.2, y: 0.5))   // deselect 1
        model.clickSubject(atUnitTopLeft: CGPoint(x: 0.2, y: 0.5))   // select 1 again
        model.clickSubject(atUnitTopLeft: CGPoint(x: 0.8, y: 0.5))   // deselect 2
        #expect(model.state.selected == [1])
        #expect(await Self.waitUntil { model.previews[.none]?.request.sticker != nil && calls.sources.count == before + 2 })
        try? await Task.sleep(nanoseconds: 300_000_000)
        // Only the final selection was cut out, once per Fill holes value.
        #expect(Array(calls.sources.dropFirst(before)).allSatisfy {
            $0 == .subjects([1], fillHoles: true) || $0 == .subjects([1], fillHoles: false)
        })
        #expect(calls.sources.count == before + 2)
    }

    @Test func finishingLetsGoOfEveryCutoutButTheConfirmedOne() async throws {
        let calls = Calls()
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let model = Self.model(calls: calls, renderer: renderer)
        #expect(await Self.waitUntil { model.previews.count == 4 })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        model.confirm(.outline)
        #expect(await Self.waitUntil { confirmed != nil })
        model.finish()
        let kept = try #require(confirmed?.sticker)
        let dropped = try #require(model.previews[.none]?.request.sticker)
        let size = CGSize(width: 20, height: 20)
        _ = try await renderer.render(RenderRequest(sticker: kept, style: .none, flipped: false, rotation: 0,
                                                    pointSize: size, backingScale: 1))
        await #expect(throws: StyleRenderer.RenderError.missingMaster) {
            _ = try await renderer.render(RenderRequest(sticker: dropped, style: .none, flipped: false, rotation: 0,
                                                        pointSize: size, backingScale: 1))
        }
        renderer.setInFlightMaster(nil, for: kept)
    }

    @Test func aCutoutThatFinishesAfterThePickerClosedIsNotKept() async {
        let calls = Calls()
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let model = PickerModel(mode: .capture, subjects: [1], pixelsPerPoint: 2, renderer: renderer, backingScale: 2,
                                makeCutout: { source in
                                    calls.add(source)
                                    try? await Task.sleep(nanoseconds: 300_000_000)
                                    return Masters.disc(diameter: 200)
                                })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        #expect(await Self.waitUntil { !calls.sources.isEmpty })
        model.confirm(.puffy)   // waits for the cutout still being computed
        model.finish()          // Esc before it is ready
        try? await Task.sleep(nanoseconds: 600_000_000)
        // Neither the preview's cutout nor the confirmed one stays registered,
        // and the session never hears of a confirmation after it ended.
        #expect(renderer.inFlightMasterCount == 0)
        #expect(confirmed == nil)

        // Pressing 1 while Shadow and None's cutout (Fill holes off) is still
        // computing: the session closes the picker on confirm, and only the
        // confirmed cutout stays registered.
        let slow = Calls()
        let otherRenderer = StyleRenderer(masterProvider: { _ in nil })
        let other = PickerModel(mode: .capture, subjects: [1], pixelsPerPoint: 2, renderer: otherRenderer, backingScale: 2,
                                makeCutout: { source in
                                    slow.add(source)
                                    if source == .subjects([1], fillHoles: false) {
                                        try? await Task.sleep(nanoseconds: 300_000_000)
                                    }
                                    return Masters.disc(diameter: 200)
                                })
        var placed: PickerModel.Confirmation?
        other.onConfirm = { [weak other] confirmation in
            placed = confirmation
            other?.finish()   // what SessionCoordinator's closePicker() does
        }
        #expect(await Self.waitUntil { slow.sources.contains(.subjects([1], fillHoles: false)) })
        other.confirm(.puffy)
        #expect(await Self.waitUntil { placed != nil })
        try? await Task.sleep(nanoseconds: 600_000_000)
        #expect(otherRenderer.inFlightMasterCount == 1)
        if let placed { otherRenderer.setInFlightMaster(nil, for: placed.sticker) }
        #expect(otherRenderer.inFlightMasterCount == 0)
    }

    @Test func rePlacingRendersTheStoredMasterUnderTheStickersID() async throws {
        let record = Fixtures.sticker(width: 50, height: 50)
        let renderer = StyleRenderer(masterProvider: { $0 == record.id ? Masters.square(side: 100) : nil })
        let model = PickerModel.forRestyle(record, renderer: renderer, backingScale: 2)
        defer { model.finish() }
        #expect(model.highlightedStyle == .outline)
        #expect(model.displayImage == nil)
        #expect(await Self.waitUntil { model.previews.count == 4 })
        #expect(StickerStyle.allCases.allSatisfy { model.previews[$0]?.request.sticker == record.id })
        var confirmed: PickerModel.Confirmation?
        model.onConfirm = { confirmed = $0 }
        model.confirm(.none)
        #expect(await Self.waitUntil { confirmed != nil })
        #expect(confirmed?.sticker == record.id)
        #expect(confirmed?.image == nil)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PickerModelTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'PickerState' in scope` and `error: cannot find 'PickerModel' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Picker/PickerModel.swift`:

```swift
import Combine
import CoreGraphics
import Foundation
import os

/// Where a preview's pixels, and the confirmed sticker's master, come from.
enum CutoutSource: Hashable {
    /// The whole capture, alpha kept, corners rounded.
    case wholeImage
    /// The selected subjects, with or without Fill holes.
    case subjects(Set<Int>, fillHoles: Bool)
    /// Re-placing from history: the sticker's own master in the library.
    case stored
}

/// The picker's selection and Fill holes rules (spec section 7), as a value.
/// Pure: the panel and the tests drive it the same way.
struct PickerState: Equatable {
    /// What the Fill holes control shows.
    enum FillHolesDisplay: Equatable {
        case auto, on, off
    }

    /// Vision's subject indices, ascending.
    let subjects: [Int]
    private(set) var selected: Set<Int>
    private(set) var wholeImage: Bool
    /// nil until the user touches Fill holes; then it applies to every preview.
    private(set) var fillHolesChoice: Bool?
    /// The style preview under the mouse.
    private(set) var hovered: StickerStyle?

    /// With subjects, all start selected and Whole image starts off; with none,
    /// Whole image is on and locked.
    init(subjects: [Int]) {
        self.subjects = subjects
        selected = Set(subjects)
        wholeImage = subjects.isEmpty
    }

    var wholeImageLocked: Bool { subjects.isEmpty }
    /// Fill holes is disabled while Whole image is on.
    var fillHolesEnabled: Bool { !wholeImage }

    /// Turning Whole image on deselects every subject; turning it off selects
    /// them all again (a selection can't be empty with Whole image off).
    mutating func setWholeImage(_ on: Bool) {
        guard !wholeImageLocked, on != wholeImage else { return }
        wholeImage = on
        selected = on ? [] : Set(subjects)
    }

    /// A click on the capture. While Whole image is on, a subject turns it off
    /// and becomes the only selection; otherwise it toggles, and deselecting
    /// the last subject turns Whole image on. nil (background) does nothing.
    mutating func click(subject: Int?) {
        guard let subject, subjects.contains(subject) else { return }
        if wholeImage {
            wholeImage = false
            selected = [subject]
        } else if selected.contains(subject) {
            selected.remove(subject)
            if selected.isEmpty { wholeImage = true }
        } else {
            selected.insert(subject)
        }
    }

    /// The first touch turns Fill holes on (out of Auto); later touches flip it.
    mutating func toggleFillHoles() {
        guard fillHolesEnabled else { return }
        fillHolesChoice = !(fillHolesChoice ?? false)
    }

    /// The mouse entered (`inside`) or left a style's preview.
    mutating func hover(_ style: StickerStyle, inside: Bool) {
        if inside {
            hovered = style
        } else if hovered == style {
            hovered = nil
        }
    }

    /// Until touched, each style uses its own default (on for Puffy and
    /// Outline, off for Shadow and None); once touched, the choice.
    func fillHoles(for style: StickerStyle) -> Bool {
        fillHolesChoice ?? style.defaultFillHoles
    }

    /// The choice once touched; until then the hovered preview's default, or Auto.
    var fillHolesDisplay: FillHolesDisplay {
        if let choice = fillHolesChoice { return choice ? .on : .off }
        if let hovered { return hovered.defaultFillHoles ? .on : .off }
        return .auto
    }

    /// The cutout a style's preview (and that style's result) uses.
    func source(for style: StickerStyle) -> CutoutSource {
        wholeImage ? .wholeImage : .subjects(selected, fillHoles: fillHoles(for: style))
    }
}

/// The picker's model: the rules above plus the cutouts and the four live
/// previews, rendered in UI order through the app's StyleRenderer (spec
/// section 7). A capture's cutouts get in-flight IDs (`StyleRenderer.
/// setInFlightMaster`); the confirmed one's ID becomes the sticker's ID, so the
/// preview is exactly what gets placed. Selection changes are debounced 100 ms.
@MainActor
final class PickerModel: ObservableObject {
    enum Mode: Equatable {
        /// A fresh capture: the capture, subjects, Whole image, Fill holes, styles.
        case capture
        /// Re-placing a sticker from history: only the style row, `highlight`
        /// (its `lastStyle`) highlighted.
        case restyle(sticker: UUID, highlight: StickerStyle)
    }

    /// One rendered preview and the shadow parameters to show it with.
    struct Preview {
        let request: RenderRequest
        let rendered: RenderedSticker
        let shadow: StyleParameters
    }

    /// What confirming a style hands to the session.
    struct Confirmation {
        /// The master's ID: the cutout's in-flight ID for a capture (the new
        /// sticker's ID), the sticker's own ID when re-placing.
        let sticker: UUID
        let style: StickerStyle
        /// The master to save; nil when re-placing.
        let image: CGImage?
        let pixelsPerPoint: Double
    }

    /// A computed cutout under its ID.
    struct Cut {
        let id: UUID
        let pixelSize: CGSize
        let image: CGImage?
    }

    typealias MakeCutout = @Sendable (CutoutSource) async throws -> CGImage

    static let debounce: TimeInterval = 0.1
    /// Previews fit in this box (points), enlarged or reduced.
    static let previewBox = CGSize(width: 84, height: 84)

    let mode: Mode
    let pixelsPerPoint: Double
    /// The capture as shown in the picker (capture mode only).
    let displayImage: CGImage?
    /// Each subject's coverage, for the highlight overlay.
    let highlightMasks: [Int: CGImage]

    @Published private(set) var state: PickerState
    @Published private(set) var previews: [StickerStyle: Preview] = [:]
    @Published private(set) var isConfirming = false
    /// The order previews were rendered in (tests).
    private(set) var renderOrder: [StickerStyle] = []

    var onConfirm: ((Confirmation) -> Void)?

    private let renderer: StyleRenderer
    private let backingScale: CGFloat
    private let storedPixelSize: CGSize
    private let makeCutout: MakeCutout
    private let subjectAt: (CGPoint) -> Int?
    private var cutouts: [CutoutSource: Cut] = [:]
    private var inProgress: [CutoutSource: Task<CGImage?, Never>] = [:]
    private var refreshTask: Task<Void, Never>?
    private var generation = 0
    private var confirmedID: UUID?
    /// Set by `finish()`: a cutout that completes afterwards is dropped, never
    /// registered with the renderer (nothing would clear it again).
    private var isFinished = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "picker")

    init(mode: Mode, subjects: [Int], pixelsPerPoint: Double, storedPixelSize: CGSize = .zero,
         displayImage: CGImage? = nil, highlightMasks: [Int: CGImage] = [:],
         renderer: StyleRenderer, backingScale: CGFloat,
         subjectAt: @escaping (CGPoint) -> Int? = { _ in nil },
         makeCutout: @escaping MakeCutout) {
        self.mode = mode
        self.pixelsPerPoint = pixelsPerPoint
        self.storedPixelSize = storedPixelSize
        self.displayImage = displayImage
        self.highlightMasks = highlightMasks
        self.renderer = renderer
        self.backingScale = backingScale
        self.subjectAt = subjectAt
        self.makeCutout = makeCutout
        state = PickerState(subjects: subjects)
        scheduleRefresh(debounced: false)
    }

    /// The picker for a fresh capture.
    static func forCapture(_ analysis: CutoutAnalysis, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel {
        var masks: [Int: CGImage] = [:]
        for index in analysis.subjectIndices {
            masks[index] = analysis.highlightMask(for: index)
        }
        return PickerModel(
            mode: .capture, subjects: analysis.subjectIndices, pixelsPerPoint: analysis.capture.pixelsPerPoint,
            displayImage: analysis.displayImage, highlightMasks: masks, renderer: renderer,
            backingScale: backingScale, subjectAt: { analysis.subject(atUnitTopLeft: $0) },
            makeCutout: { source in
                switch source {
                case .wholeImage:
                    return analysis.wholeImage()
                case .subjects(let selection, let fillHoles):
                    return try await analysis.cutout(selection: selection, fillHoles: fillHoles)
                case .stored:
                    throw CutoutError.emptySelection
                }
            })
    }

    /// The style-only picker for re-placing `record` from history.
    static func forRestyle(_ record: StickerRecord, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel {
        PickerModel(mode: .restyle(sticker: record.id, highlight: record.lastStyle), subjects: [],
                    pixelsPerPoint: record.pixelsPerPoint,
                    storedPixelSize: CGSize(width: record.pixelWidth, height: record.pixelHeight),
                    renderer: renderer, backingScale: backingScale,
                    makeCutout: { _ in throw CutoutError.emptySelection })
    }

    /// The style highlighted in the style row (re-placing only).
    var highlightedStyle: StickerStyle? {
        if case .restyle(_, let highlight) = mode { return highlight }
        return nil
    }

    // MARK: User actions

    /// A click on the capture at `p` (0–1, top-left origin).
    func clickSubject(atUnitTopLeft p: CGPoint) {
        let before = state
        state.click(subject: subjectAt(p))
        if state != before { scheduleRefresh(debounced: true) }
    }

    func setWholeImage(_ on: Bool) {
        let before = state
        state.setWholeImage(on)
        if state != before { scheduleRefresh(debounced: true) }
    }

    func toggleFillHoles() {
        let before = state
        state.toggleFillHoles()
        if state != before { scheduleRefresh(debounced: false) }
    }

    func hover(_ style: StickerStyle, inside: Bool) {
        state.hover(style, inside: inside)
    }

    /// Clicking a preview or pressing 1–4: hands the style's cutout to
    /// `onConfirm` once it is ready (at once when the preview showed it).
    func confirm(_ style: StickerStyle) {
        guard !isConfirming, !isFinished else { return }
        isConfirming = true
        let source = currentSource(for: style)
        Task { [weak self] in
            guard let self else { return }
            let cut = await self.cutout(for: source)
            // The picker closed (Esc or ×) while the cutout was computed.
            guard !self.isFinished else { return }
            guard let cut else {
                self.log.error("no cutout to confirm for \(style.rawValue, privacy: .public)")
                self.isConfirming = false
                return
            }
            self.confirmedID = cut.id
            self.onConfirm?(Confirmation(sticker: cut.id, style: style, image: cut.image,
                                         pixelsPerPoint: self.pixelsPerPoint))
        }
    }

    /// The picker closed: stops work and lets go of every in-flight master
    /// except the confirmed one (the session clears that after placement).
    /// Cutouts still computing are dropped when they complete.
    func finish() {
        isFinished = true
        generation += 1
        refreshTask?.cancel()
        refreshTask = nil
        for task in inProgress.values { task.cancel() }
        inProgress = [:]
        for cut in cutouts.values where cut.image != nil && cut.id != confirmedID {
            renderer.setInFlightMaster(nil, for: cut.id)
        }
        cutouts = [:]
    }

    // MARK: Previews

    private func currentSource(for style: StickerStyle) -> CutoutSource {
        if case .restyle = mode { return .stored }
        return state.source(for: style)
    }

    private func scheduleRefresh(debounced: Bool) {
        generation += 1
        let generation = self.generation
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(nanoseconds: UInt64(Self.debounce * 1_000_000_000))
            }
            guard !Task.isCancelled else { return }
            await self?.refresh(generation: generation)
        }
    }

    /// Renders the four previews in UI order, computing each cutout once, and
    /// lets go of cutouts no preview uses any more.
    private func refresh(generation: Int) async {
        let wanted = StickerStyle.allCases.map { ($0, currentSource(for: $0)) }
        let used = Set(wanted.map(\.1))
        for (source, cut) in cutouts where !used.contains(source) {
            if cut.image != nil { renderer.setInFlightMaster(nil, for: cut.id) }
            cutouts[source] = nil
        }
        for (style, source) in wanted {
            guard let cut = await cutout(for: source), generation == self.generation else { return }
            let request = previewRequest(for: cut, style: style)
            if previews[style]?.request == request { continue }
            do {
                let rendered = try await renderer.render(request)
                guard generation == self.generation else { return }
                let shadow = request.onScreenParameters(
                    sourceLongSide: Double(max(cut.pixelSize.width, cut.pixelSize.height)))
                previews[style] = Preview(request: request, rendered: rendered, shadow: shadow)
                renderOrder.append(style)
            } catch {
                log.error("preview \(style.rawValue, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A source's cutout, computed once (off the main actor) and registered
    /// with the renderer under a new in-flight ID. nil once the picker closed.
    private func cutout(for source: CutoutSource) async -> Cut? {
        guard !isFinished else { return nil }
        if let cut = cutouts[source] { return cut }
        if source == .stored, case .restyle(let sticker, _) = mode {
            let cut = Cut(id: sticker, pixelSize: storedPixelSize, image: nil)
            cutouts[source] = cut
            return cut
        }
        let task: Task<CGImage?, Never>
        if let running = inProgress[source] {
            task = running
        } else {
            let make = makeCutout
            task = Task.detached(priority: .userInitiated) { try? await make(source) }
            inProgress[source] = task
        }
        let image = await task.value
        // finish() ran while this cutout was computed (cancelling can't stop the
        // whole image, or a cutout past its last cancellation check): it has
        // already let go of every in-flight master, so this one must not be
        // registered.
        guard !isFinished else { return nil }
        inProgress[source] = nil
        if let cut = cutouts[source] { return cut }
        guard let image else { return nil }
        let cut = Cut(id: UUID(), pixelSize: CGSize(width: image.width, height: image.height), image: image)
        renderer.setInFlightMaster(image, for: cut.id)
        cutouts[source] = cut
        return cut
    }

    /// The preview's request: the cutout's natural size fitted into `previewBox`.
    private func previewRequest(for cut: Cut, style: StickerStyle) -> RenderRequest {
        let ppp = pixelsPerPoint > 0 ? pixelsPerPoint : 1
        let natural = CGSize(width: cut.pixelSize.width / ppp, height: cut.pixelSize.height / ppp)
        let scale = natural.width > 0 && natural.height > 0
            ? min(Self.previewBox.width / natural.width, Self.previewBox.height / natural.height) : 1
        return RenderRequest(sticker: cut.id, style: style, flipped: false, rotation: 0,
                             pointSize: CGSize(width: natural.width * scale, height: natural.height * scale),
                             backingScale: backingScale)
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 256 tests in 31 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Picker/PickerModel.swift StickermineTests/PickerModelTests.swift
git commit -m "Add the picker's selection and Fill holes rules and its live previews" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: PickerView and PickerPanel

**Files:**
- Create: `Stickermine/Picker/PickerView.swift`, `Stickermine/Picker/PickerPanel.swift`
- Test: Create `StickermineTests/PickerPanelTests.swift`

**Interfaces:**
- Consumes: `PickerModel` (Task 10), `StickerView.show(_:shadow:style:)` (M2/M3), `PanelPolicy.applyCommon(to:hidesOnDeactivate:)` (M1).
- Produces:

```text
extension StickerStyle { var displayName: String { get } }        // "Puffy", "Outline", "Shadow", "None"
struct PickerView: View {                                          // Picker/PickerView.swift
    @ObservedObject var model: PickerModel; let onCancel: () -> Void
    static let width: CGFloat; static let captureMaxSize: CGSize   // 476; 440 × 300
    static func fitted(_ size: CGSize, in box: CGSize) -> CGSize
}
@MainActor final class PreviewHost: NSView { func show(_ preview: PickerModel.Preview) }   // a StickerView that never takes clicks
@MainActor final class PickerPanel: NSPanel                       // Picker/PickerPanel.swift; canBecomeKey true, canBecomeMain false; [.borderless, .nonactivatingPanel]
@MainActor final class PickerController {
    static let cursorGap: CGFloat                                  // 16
    let model: PickerModel; let panel: PickerPanel
    var onCancel: (() -> Void)?                                    // Esc or ×
    init(model: PickerModel)
    static func makePanel() -> PickerPanel
    static func frame(size: CGSize, near cursor: CGPoint, visibleFrame: CGRect) -> CGRect
    static func style(forKey characters: String?) -> StickerStyle? // "1"–"4"
    func show(near cursor: CGPoint, visibleFrame: CGRect)          // activates the app, panel key
    func close()
}
```

The previews show through `StickerView`, the view placed stickers use, so the layer shadow and frame margin are the real ones; a container whose `hitTest` returns nil lets the SwiftUI button around each preview take the click. The panel is borderless (so it may become key through its override) and non-activating (so it is key and gets Esc and 1–4 even if the system turns down `NSApp.activate()` after the crosshair), `hidesOnDeactivate = false` and never cancels on losing key: the system's privacy alert lands on it right after a capture (spec section 5.9). Its look is checked by eye in Task 18.

- [ ] **Step 1: Write the failing test**

`StickermineTests/PickerPanelTests.swift`:

```swift
import AppKit
import Testing
@testable import Stickermine

@MainActor
struct PickerPanelTests {
    let visible = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let size = CGSize(width: 400, height: 300)

    @Test func thePanelSitsBelowTheCursorWhenItFits() {
        let frame = PickerController.frame(size: size, near: CGPoint(x: 500, y: 600), visibleFrame: visible)
        #expect(frame == CGRect(x: 300, y: 284, width: 400, height: 300))
    }

    @Test func itGoesAboveWhenThereIsNoRoomBelow() {
        let frame = PickerController.frame(size: size, near: CGPoint(x: 500, y: 100), visibleFrame: visible)
        #expect(frame == CGRect(x: 300, y: 116, width: 400, height: 300))
    }

    @Test func itFallsBackToTheCentreOfTheDisplay() {
        let short = CGRect(x: 0, y: 0, width: 1000, height: 400)
        let frame = PickerController.frame(size: size, near: CGPoint(x: 500, y: 200), visibleFrame: short)
        #expect(frame == CGRect(x: 300, y: 50, width: 400, height: 300))
    }

    @Test func itStaysInsideTheDisplaysSides() {
        let left = PickerController.frame(size: size, near: CGPoint(x: 40, y: 600), visibleFrame: visible)
        #expect(left.minX == 0)
        let right = PickerController.frame(size: size, near: CGPoint(x: 990, y: 600), visibleFrame: visible)
        #expect(right.maxX == 1000)
    }

    @Test func keysOneToFourPickTheStylesInOrder() {
        #expect(PickerController.style(forKey: "1") == .puffy)
        #expect(PickerController.style(forKey: "2") == .outline)
        #expect(PickerController.style(forKey: "3") == .shadow)
        #expect(PickerController.style(forKey: "4") == StickerStyle.none)
        #expect(PickerController.style(forKey: "5") == nil)
        #expect(PickerController.style(forKey: "0") == nil)
        #expect(PickerController.style(forKey: "a") == nil)
        #expect(PickerController.style(forKey: nil) == nil)
    }

    @Test func thePanelFollowsThePanelPolicyAndSurvivesLosingKey() {
        let panel = PickerController.makePanel()
        defer { panel.close() }
        #expect(panel.canBecomeKey)
        #expect(!panel.canBecomeMain)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.isFloatingPanel)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.borderless))
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isVisible)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PickerPanelTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'PickerController' in scope`.

- [ ] **Step 3: Implement the view**

`Stickermine/Picker/PickerView.swift`:

```swift
import AppKit
import SwiftUI

extension StickerStyle {
    /// The name the UI shows.
    var displayName: String {
        switch self {
        case .puffy: return "Puffy"
        case .outline: return "Outline"
        case .shadow: return "Shadow"
        case .none: return "None"
        }
    }
}

/// The picker's content (spec section 7): the capture with its subjects
/// highlighted, Whole image and Fill holes, and the four style previews in UI
/// order, each numbered for its key. Re-placing shows only the style row.
struct PickerView: View {
    @ObservedObject var model: PickerModel
    let onCancel: () -> Void

    static let width: CGFloat = 476
    static let captureMaxSize = CGSize(width: 440, height: 300)

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if model.mode == .capture {
                captureArea
                controls
            }
            styleRow
        }
        .padding(18)
        .frame(width: Self.width)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color.white.opacity(0.25)))
    }

    private var header: some View {
        HStack {
            Text(model.mode == .capture ? "New Sticker" : "Place Sticker")
                .font(.headline)
            Spacer()
            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Cancel (Esc)")
        }
    }

    @ViewBuilder
    private var captureArea: some View {
        if let image = model.displayImage {
            let size = Self.fitted(CGSize(width: image.width, height: image.height), in: Self.captureMaxSize)
            ZStack {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .interpolation(.high)
                // Every subject stays visible (spec section 7: "each subject
                // highlighted"); selected ones are tinted more strongly.
                ForEach(model.state.subjects, id: \.self) { index in
                    if let mask = model.highlightMasks[index] {
                        Color.accentColor.opacity(model.state.selected.contains(index) ? 0.35 : 0.12)
                            .mask(Image(decorative: mask, scale: 1).resizable())
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { value in
                model.clickSubject(atUnitTopLeft: CGPoint(x: value.location.x / size.width,
                                                          y: value.location.y / size.height))
            })
            .frame(maxWidth: .infinity)
        }
    }

    private var controls: some View {
        HStack(spacing: 18) {
            Toggle("Whole image", isOn: Binding(get: { model.state.wholeImage },
                                                set: { model.setWholeImage($0) }))
                .toggleStyle(.checkbox)
                .disabled(model.state.wholeImageLocked)
            Button(action: model.toggleFillHoles) {
                HStack(spacing: 5) {
                    Image(systemName: fillHolesSymbol)
                    Text("Fill holes: \(fillHolesText)")
                }
            }
            .buttonStyle(.borderless)
            .disabled(!model.state.fillHolesEnabled)
            Spacer()
            if model.state.wholeImageLocked {
                Text("No subject found")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fillHolesText: String {
        switch model.state.fillHolesDisplay {
        case .auto: return "Auto"
        case .on: return "On"
        case .off: return "Off"
        }
    }

    private var fillHolesSymbol: String {
        switch model.state.fillHolesDisplay {
        case .auto: return "a.square"
        case .on: return "checkmark.square.fill"
        case .off: return "square"
        }
    }

    private var styleRow: some View {
        HStack(spacing: 10) {
            ForEach(Array(StickerStyle.allCases.enumerated()), id: \.element) { offset, style in
                StylePreviewButton(style: style, number: offset + 1, preview: model.previews[style],
                                   highlighted: model.highlightedStyle == style,
                                   action: { model.confirm(style) })
                    .onHover { model.hover(style, inside: $0) }
            }
        }
        .disabled(model.isConfirming)
    }

    static func fitted(_ size: CGSize, in box: CGSize) -> CGSize {
        guard size.width > 0, size.height > 0 else { return box }
        let scale = min(box.width / size.width, box.height / size.height, 1)
        return CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
    }
}

/// One style's live preview, its number and name.
private struct StylePreviewButton: View {
    let style: StickerStyle
    let number: Int
    let preview: PickerModel.Preview?
    let highlighted: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(highlighted ? Color.accentColor.opacity(0.2) : Color.primary.opacity(0.05))
                    if let preview {
                        StickerPreview(preview: preview)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(width: 104, height: 104)
                .overlay(alignment: .topLeading) {
                    Text("\(number)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(highlighted ? Color.accentColor : Color.clear, lineWidth: 2))
                Text(style.displayName)
                    .font(.callout)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(style.displayName) (\(number))")
    }
}

/// A rendered preview shown through a StickerView, the same view a placed
/// sticker uses, so the preview is exactly what gets placed (layer shadow
/// included). Clicks pass through to the SwiftUI button around it.
private struct StickerPreview: NSViewRepresentable {
    let preview: PickerModel.Preview

    func makeNSView(context: Context) -> PreviewHost {
        PreviewHost()
    }

    func updateNSView(_ view: PreviewHost, context: Context) {
        view.show(preview)
    }
}

@MainActor
final class PreviewHost: NSView {
    private let sticker = StickerView(frame: .zero)

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        sticker.autoresizingMask = [.width, .height]
        sticker.frame = bounds
        addSubview(sticker)
    }

    required init?(coder: NSCoder) {
        fatalError("PreviewHost is only created in code")
    }

    func show(_ preview: PickerModel.Preview) {
        sticker.show(preview.rendered, shadow: preview.shadow, style: preview.request.style)
    }

    /// The preview never takes a click: the button around it does.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
```

- [ ] **Step 4: Implement the panel**

`Stickermine/Picker/PickerPanel.swift`:

```swift
import AppKit
import SwiftUI

/// The picker's window: borderless, floating, allowed to become key (so Esc
/// and 1–4 arrive), and never hidden or cancelled when it loses key: the
/// system's "bypass the private window picker" alert lands on it right after
/// a capture (spec sections 5.9 and 7).
@MainActor
final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// Shows a `PickerModel` in a `PickerPanel` near the cursor, activates
/// Stickermine and handles the keys. Only Esc or the × button cancel.
@MainActor
final class PickerController {
    /// Space between the cursor and the panel.
    static let cursorGap: CGFloat = 16

    let model: PickerModel
    let panel: PickerPanel
    private var keyMonitor: Any?

    /// Esc or the × button.
    var onCancel: (() -> Void)?

    init(model: PickerModel) {
        self.model = model
        panel = Self.makePanel()
        let host = NSHostingView(rootView: PickerView(model: model, onCancel: { [weak self] in self?.onCancel?() }))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
    }

    /// The panel policy (spec section 4): not released on close, never hidden
    /// on deactivation, the floating-panel flag untouched, the level last.
    /// Non-activating, so it becomes key (and Esc and 1–4 arrive) even when
    /// the system turns down `NSApp.activate()`: the last input went to
    /// `screencapture`'s crosshair, not to Stickermine.
    static func makePanel() -> PickerPanel {
        let panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: PickerView.width, height: 320),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.level = .floating  // last
        return panel
    }

    /// Below the cursor and centred on it; above it when there's no room
    /// below; centred on the display when it fits neither way. Always inside
    /// `visibleFrame`.
    static func frame(size: CGSize, near cursor: CGPoint, visibleFrame: CGRect) -> CGRect {
        var origin = CGPoint(x: cursor.x - size.width / 2, y: cursor.y - cursorGap - size.height)
        if origin.y < visibleFrame.minY {
            origin.y = cursor.y + cursorGap
        }
        if origin.y + size.height > visibleFrame.maxY || origin.y < visibleFrame.minY {
            origin = CGPoint(x: visibleFrame.midX - size.width / 2, y: visibleFrame.midY - size.height / 2)
        }
        origin.x = min(max(origin.x, visibleFrame.minX), max(visibleFrame.minX, visibleFrame.maxX - size.width))
        origin.y = min(max(origin.y, visibleFrame.minY), max(visibleFrame.minY, visibleFrame.maxY - size.height))
        return CGRect(origin: origin, size: size).integral
    }

    /// The style for a typed character: "1"–"4" in UI order.
    static func style(forKey characters: String?) -> StickerStyle? {
        guard let characters, characters.count == 1, let number = Int(characters),
              (1...StickerStyle.allCases.count).contains(number)
        else { return nil }
        return StickerStyle.allCases[number - 1]
    }

    /// Shows the panel near `cursor` inside `visibleFrame`, activates the app
    /// and makes the panel key.
    func show(near cursor: CGPoint, visibleFrame: CGRect) {
        panel.setFrame(Self.frame(size: panel.frame.size, near: cursor, visibleFrame: visibleFrame), display: true)
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            if event.keyCode == 53 {  // Esc
                self.onCancel?()
                return nil
            }
            if event.modifierFlags.intersection([.command, .control, .option]).isEmpty,
               let style = Self.style(forKey: event.charactersIgnoringModifiers) {
                self.model.confirm(style)
                return nil
            }
            return event
        }
    }

    /// Removes the panel for good.
    func close() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
        panel.orderOut(nil)
        panel.close()
        // The × button's action is still running inside the hosting view:
        // release it on the next turn of the run loop, not under its own feet.
        let panel = self.panel
        DispatchQueue.main.async { panel.contentView = nil }
    }
}
```

- [ ] **Step 5: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 262 tests in 32 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Stickermine/Picker/PickerView.swift Stickermine/Picker/PickerPanel.swift StickermineTests/PickerPanelTests.swift
git commit -m "Add the picker panel: capture, subjects, Whole image, Fill holes and four style previews" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: PlacementSession

**Files:**
- Create: `Stickermine/Picker/PlacementSession.swift`
- Test: Create `StickermineTests/PlacementSessionTests.swift`

**Interfaces:**
- Consumes: `StickerManager.place(sticker:style:centerOnScreen:pointSize:) -> UUID?`, `StickerManager.display(containing:in:)`, `StickerManager.panel(for:)` (M2), `StyleRenderer.render`, `StickerView` (M1–M3), `PanelPolicy.applyCommon` (M1), `ScreenProvider` (M2).
- Produces:

```text
@MainActor final class PlacementPanel: NSPanel                    // canBecomeKey true, canBecomeMain false
@MainActor final class PlacementView: NSView {                    // takes every mouse-down; holds `let sticker: StickerView`
    var onPlace: (() -> Void)?; var onCancel: (() -> Void)?        // left mouse-down; right mouse-down or Esc
}
@MainActor final class PlacementSession {                         // Picker/PlacementSession.swift
    enum Outcome: Equatable { case placed(UUID), cancelled }
    static let fitFraction: CGFloat; static let handOverTimeout: TimeInterval   // 0.5; 0.5 s
    let sticker: UUID; let style: StickerStyle; let natural: CGSize; let sourceLongSide: Double
    var onEnd: ((Outcome) -> Void)?
    private(set) var pointSize: CGSize
    init(sticker:style:natural:sourceLongSide:renderer:stickers:screens:mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation })
    static func fittedSize(natural: CGSize, in frame: CGRect) -> CGSize          // scaled down only, to half the width and height
    static func makePanel() -> PlacementPanel                                    // explicit ignoresMouseEvents = false, .floating last
    func start(); func follow(); func place(); func cancel()
}
```

Following uses a local and a global `.mouseMoved`/`.leftMouseDragged` monitor (global monitors don't see this app's own events). On another display the size is re-fitted and the sticker re-rendered at that display's scale. After a placement the panel stays until the new sticker's own panel shows its bitmap (at most 0.5 s), so the sticker never blinks out. The tests place without showing a window: their renderer has no masters, so the panel is never ordered in, and the one sticker panel `place` orders in (at x ≥ 40 000) is closed before the test returns.

- [ ] **Step 1: Write the failing test**

`StickermineTests/PlacementSessionTests.swift`:

```swift
import AppKit
import Testing
@testable import Stickermine

/// Displays sit at x ≥ 40 000 pt and nothing waits while a panel is ordered
/// in, so the test host never shows a window.
@MainActor
struct PlacementSessionTests {
    @Test func aStickerKeepsItsNaturalSizeWhenItFitsInHalfTheDisplay() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(PlacementSession.fittedSize(natural: CGSize(width: 400, height: 300), in: frame)
                == CGSize(width: 400, height: 300))
    }

    @Test func aLargeStickerIsScaledDownToHalfTheWidthOrHeight() {
        let frame = CGRect(x: 0, y: 0, width: 1920, height: 1080)
        #expect(PlacementSession.fittedSize(natural: CGSize(width: 2000, height: 500), in: frame)
                == CGSize(width: 960, height: 240))
        #expect(PlacementSession.fittedSize(natural: CGSize(width: 300, height: 1080), in: frame)
                == CGSize(width: 150, height: 540))
    }

    @Test func thePanelTakesClicksOnItsWholeRectAndCanBecomeKey() {
        let panel = PlacementSession.makePanel()
        defer { panel.close() }
        #expect(panel.canBecomeKey)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.ignoresMouseEvents)
        #expect(panel.acceptsMouseMovedEvents)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(!panel.isVisible)
    }

    @Test func theViewTakesEveryClickItself() throws {
        let view = PlacementView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        #expect(view.hitTest(NSPoint(x: 50, y: 50)) === view)
        #expect(view.hitTest(NSPoint(x: 150, y: 50)) == nil)
        #expect(view.acceptsFirstMouse(for: nil))
        var events: [String] = []
        view.onPlace = { events.append("place") }
        view.onCancel = { events.append("cancel") }
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [],
                                                   timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                   clickCount: 1, pressure: 1))
        view.mouseDown(with: down)
        let right = try #require(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [],
                                                    timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0,
                                                    clickCount: 1, pressure: 1))
        view.rightMouseDown(with: right)
        let escape = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                                   windowNumber: 0, context: nil, characters: "\u{1b}",
                                                   charactersIgnoringModifiers: "\u{1b}", isARepeat: false,
                                                   keyCode: 53))
        view.keyDown(with: escape)
        #expect(events == ["place", "cancel", "cancel"])
    }

    /// A library with one 400 × 200 pt sticker on a temporary store.
    static func harness() -> (folder: URL, library: LibraryController, stickers: StickerManager, sticker: StickerRecord) {
        let folder = Fixtures.temporaryDirectory()
        let library = LibraryController(store: LibraryStore(root: folder), saveDelay: 60)
        let sticker = Fixtures.sticker(width: 400, height: 200)
        library.mutate { $0.stickers.append(sticker) }
        let stickers = StickerManager(library: library, screens: FakeScreens([Fixtures.external()]),
                                      renderer: StyleRenderer(masterProvider: { _ in nil }))
        return (folder, library, stickers, sticker)
    }

    @Test func aClickPlacesOnTheDisplayUnderTheCursorAtTheFittedSize() throws {
        let h = Self.harness()
        defer { try? FileManager.default.removeItem(at: h.folder) }
        let display = Fixtures.external()
        let cursor = NSPoint(x: display.frame.midX, y: display.frame.midY)
        let session = PlacementSession(sticker: h.sticker.id, style: .puffy, natural: h.sticker.naturalPointSize,
                                       sourceLongSide: 800, renderer: StyleRenderer(masterProvider: { _ in nil }),
                                       stickers: h.stickers, screens: FakeScreens([display]),
                                       mouseLocation: { cursor })
        var outcome: PlacementSession.Outcome?
        session.onEnd = { outcome = $0 }
        session.start()
        #expect(session.pointSize == CGSize(width: 400, height: 200))
        session.place()
        h.stickers.closeAllPanels()
        guard case .placed(let id) = outcome else {
            Issue.record("expected a placement, got \(String(describing: outcome))")
            return
        }
        let placement = try #require(h.library.library.placement(id))
        #expect(placement.style == .puffy)
        #expect(!placement.flipped && !placement.onTop && placement.rotation == 0)
        // The panel's centre, which is the cursor give or take its rounding.
        let pose = try #require(placement.poses[display.size.key])
        #expect(abs(pose.x - 0.5) < 0.001 && abs(pose.y - 0.5) < 0.001)
        #expect(pose.scale == 1)
        #expect(placement.poses.count == 1)
        #expect(h.library.library.displays[display.uuid]?.placements.last?.id == id)
        session.place()   // a second click after the end does nothing
        #expect(h.library.library.displays[display.uuid]?.placements.count == 1)
    }

    @Test func cancellingPlacesNothing() {
        let h = Self.harness()
        defer { try? FileManager.default.removeItem(at: h.folder) }
        let display = Fixtures.external()
        let session = PlacementSession(sticker: h.sticker.id, style: .none, natural: h.sticker.naturalPointSize,
                                       sourceLongSide: 800, renderer: StyleRenderer(masterProvider: { _ in nil }),
                                       stickers: h.stickers, screens: FakeScreens([display]),
                                       mouseLocation: { NSPoint(x: display.frame.midX, y: display.frame.midY) })
        var outcome: PlacementSession.Outcome?
        session.onEnd = { outcome = $0 }
        session.start()
        session.cancel()
        session.place()
        #expect(outcome == .cancelled)
        #expect(h.library.library.displays.isEmpty)
        #expect(h.library.library.stickers.count == 1)   // the sticker stays in history
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PlacementSessionTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'PlacementSession' in scope` and `error: cannot find 'PlacementView' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Picker/PlacementSession.swift`:

```swift
import AppKit
import os

/// The transient panel that carries a new sticker under the cursor. It may
/// become key, so Esc arrives.
@MainActor
final class PlacementPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The placement panel's content: the styled sticker (a StickerView, exactly
/// as it will look once placed) under a view that takes every mouse-down.
@MainActor
final class PlacementView: NSView {
    let sticker = StickerView(frame: .zero)
    var onPlace: (() -> Void)?
    var onCancel: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        sticker.autoresizingMask = [.width, .height]
        sticker.frame = bounds
        addSubview(sticker)
    }

    required init?(coder: NSCoder) {
        fatalError("PlacementView is only created in code")
    }

    /// The sticker view below never sees a click: this view takes them all.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        onPlace?()
    }

    override func rightMouseDown(with event: NSEvent) {
        onCancel?()
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {  // Esc
            onCancel?()
        } else {
            super.keyDown(with: event)
        }
    }
}

/// The sticker following the cursor until a click places it (spec section 7).
///
/// Every new placement starts at rotation 0, unflipped, Float on top off, in
/// the chosen style, at its natural point size scaled down to fit within half
/// the width and height of the display under the cursor (recomputed when the
/// cursor moves to another display). A mouse-down on the panel places it on
/// that display, on top of its z-order, through `StickerManager.place`; clicks
/// on other windows are ignored; Esc or a right-click cancels.
@MainActor
final class PlacementSession {
    enum Outcome: Equatable {
        case placed(UUID)
        case cancelled
    }

    /// The sticker fits within this share of the display's width and height.
    static let fitFraction: CGFloat = 0.5
    /// After placing, the panel stays until the new sticker shows, at most this long.
    static let handOverTimeout: TimeInterval = 0.5

    let sticker: UUID
    let style: StickerStyle
    let natural: CGSize
    let sourceLongSide: Double
    var onEnd: ((Outcome) -> Void)?

    private let renderer: StyleRenderer
    private let stickers: StickerManager
    private let screens: ScreenProvider
    private let mouseLocation: () -> NSPoint
    private var panel: PlacementPanel?
    private var view: PlacementView?
    private var monitors: [Any] = []
    private var display: DisplayInfo?
    private var request: RenderRequest?
    private var ended = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "placement")

    /// The unrotated size the sticker is placed at, in points.
    private(set) var pointSize: CGSize = .zero

    init(sticker: UUID, style: StickerStyle, natural: CGSize, sourceLongSide: Double, renderer: StyleRenderer,
         stickers: StickerManager, screens: ScreenProvider,
         mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation }) {
        self.sticker = sticker
        self.style = style
        self.natural = natural
        self.sourceLongSide = sourceLongSide
        self.renderer = renderer
        self.stickers = stickers
        self.screens = screens
        self.mouseLocation = mouseLocation
    }

    /// `natural` scaled down (never up) to fit within half of `frame`.
    static func fittedSize(natural: CGSize, in frame: CGRect) -> CGSize {
        guard natural.width > 0, natural.height > 0 else { return natural }
        let scale = min(1, frame.width * fitFraction / natural.width, frame.height * fitFraction / natural.height)
        return CGSize(width: natural.width * scale, height: natural.height * scale)
    }

    /// The panel policy (spec section 4), plus the explicit
    /// `ignoresMouseEvents = false` this transient panel is allowed: its whole
    /// rectangle takes the click, transparent pixels included (spec section 7).
    static func makePanel() -> PlacementPanel {
        let panel = PlacementPanel(contentRect: NSRect(x: 0, y: 0, width: 1, height: 1),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.ignoresMouseEvents = false
        panel.acceptsMouseMovedEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.level = .floating  // last
        return panel
    }

    /// Creates the panel and starts following the cursor. The panel appears
    /// with the first render.
    func start() {
        let panel = Self.makePanel()
        let view = PlacementView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        panel.contentView = view
        view.onPlace = { [weak self] in self?.place() }
        view.onCancel = { [weak self] in self?.cancel() }
        self.panel = panel
        self.view = view
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            self?.follow()
            return event
        }) {
            monitors.append(local)
        }
        // Global monitors don't see events sent to this app; the local one does.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            self?.follow()
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            guard let self, event.keyCode == 53, !self.ended else { return event }
            self.cancel()
            return nil
        }) {
            monitors.append(local)
        }
        follow()
    }

    /// Centres the panel on the cursor; on another display, re-fits and re-renders.
    func follow() {
        guard !ended else { return }
        let point = mouseLocation()
        guard let current = StickerManager.display(containing: point, in: screens.currentDisplays()) else { return }
        if current != display {
            display = current
            pointSize = Self.fittedSize(natural: natural, in: current.frame)
            render(backingScale: current.backingScale)
        }
        guard let panel else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded()))
    }

    /// Esc, a right-click, or the session being cancelled: nothing is placed;
    /// a fresh sticker stays in history.
    func cancel() {
        end(.cancelled)
    }

    private func render(backingScale: CGFloat) {
        let request = RenderRequest(sticker: sticker, style: style, flipped: false, rotation: 0,
                                    pointSize: pointSize, backingScale: backingScale)
        guard request != self.request else { return }
        self.request = request
        let renderer = self.renderer
        Task { [weak self] in
            do {
                let rendered = try await renderer.render(request)
                self?.show(rendered, for: request)
            } catch {
                self?.log.error("placement render failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func show(_ rendered: RenderedSticker, for request: RenderRequest) {
        guard !ended, request == self.request, let panel, let view else { return }
        view.sticker.show(rendered, shadow: request.onScreenParameters(sourceLongSide: sourceLongSide), style: style)
        let margin = view.sticker.frameMargin
        let size = CGSize(width: rendered.pointBounds.width + 2 * margin,
                          height: rendered.pointBounds.height + 2 * margin)
        let point = mouseLocation()
        panel.setFrame(NSRect(x: (point.x - size.width / 2).rounded(), y: (point.y - size.height / 2).rounded(),
                              width: size.width, height: size.height), display: true)
        if !panel.isVisible {
            panel.orderFrontRegardless()
            panel.makeKey()
        }
    }

    /// A mouse-down on the panel (internal so tests can place without a click).
    func place() {
        guard !ended, let panel else { return }
        let center = NSPoint(x: panel.frame.midX, y: panel.frame.midY)
        guard let placement = stickers.place(sticker: sticker, style: style, centerOnScreen: center,
                                             pointSize: pointSize)
        else {
            log.error("placing \(self.sticker.uuidString, privacy: .public) failed")
            end(.cancelled)
            return
        }
        end(.placed(placement))
    }

    private func end(_ outcome: Outcome) {
        guard !ended else { return }
        ended = true
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        if let panel, let view {
            if case .placed(let placement) = outcome {
                Self.close(panel, view: view, whenStickerShows: placement, in: stickers,
                           deadline: Date().addingTimeInterval(Self.handOverTimeout))
            } else {
                Self.close(panel, view: view)
            }
        }
        panel = nil
        view = nil
        onEnd?(outcome)
    }

    /// Keeps the panel until the placed sticker's own panel has its bitmap (or
    /// the deadline passes), so the sticker never blinks out between the two.
    private static func close(_ panel: PlacementPanel, view: PlacementView, whenStickerShows placement: UUID,
                              in stickers: StickerManager, deadline: Date) {
        let shown = (stickers.panel(for: placement)?.contentView as? StickerView)?.contentLayer.contents != nil
        guard shown || Date() >= deadline else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) {
                MainActor.assumeIsolated {
                    close(panel, view: view, whenStickerShows: placement, in: stickers, deadline: deadline)
                }
            }
            return
        }
        close(panel, view: view)
    }

    private static func close(_ panel: PlacementPanel, view: PlacementView) {
        view.sticker.clearContents()
        panel.orderOut(nil)
        panel.close()
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 268 tests in 33 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Picker/PlacementSession.swift StickermineTests/PlacementSessionTests.swift
git commit -m "Add the placement session: the sticker follows the cursor until a click places it" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 13: HUD

**Files:**
- Create: `Stickermine/UI/HUD.swift`
- Test: Create `StickermineTests/HUDTests.swift`

**Interfaces:**
- Consumes: `PanelPolicy.applyCommon` (M1).
- Produces:

```text
@MainActor final class HUD {                                       // UI/HUD.swift; ported from Pullcord's showMessage
    static let shared: HUD
    static let controlHeldMessage: String     // "Let go of Control before releasing the mouse"
    static let couldNotStartMessage: String   // "Couldn’t start a capture"
    static let readOnlyMessage: String        // "This library was saved by a newer Stickermine. Update to make changes."
    static let saveFailedMessage: String      // "Couldn’t save the sticker"
    static let dwell: TimeInterval; static let height: CGFloat     // 2.2 s; 42 pt
    private(set) var lastMessage: String?
    static func makePanel() -> NSPanel                             // click-through, never key, .statusBar last
    static func frame(width: CGFloat, in visibleFrame: CGRect) -> CGRect   // top centre, 16 pt down
    func show(_ message: String, symbol: String = "exclamationmark.triangle.fill")
    func hide()
}
```

Unlike Pullcord's HUD, the panel never touches the floating-panel flag (the panel policy; `PanelPolicyTests` scans every app file for it) and sits on the display under the cursor.

- [ ] **Step 1: Write the failing test**

`StickermineTests/HUDTests.swift`:

```swift
import AppKit
import Testing
@testable import Stickermine

/// The HUD is never shown here: only its panel and geometry are checked.
@MainActor
struct HUDTests {
    @Test func theMessagesAreTheSpecs() {
        #expect(HUD.controlHeldMessage == "Let go of Control before releasing the mouse")
        #expect(HUD.couldNotStartMessage == "Couldn’t start a capture")
    }

    @Test func thePillSitsAtTheTopCentre() {
        let frame = HUD.frame(width: 300, in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        #expect(frame == CGRect(x: 350, y: 742, width: 300, height: 42))
    }

    @Test func thePanelNeverTakesFocusOrClicks() {
        let panel = HUD.makePanel()
        defer { panel.close() }
        #expect(panel.ignoresMouseEvents)
        #expect(!panel.canBecomeKey)
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(!panel.isFloatingPanel)
        #expect(panel.level == .statusBar)
        #expect(panel.styleMask.contains(.nonactivatingPanel))
        #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
        #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/HUDTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'HUD' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/UI/HUD.swift`:

```swift
import AppKit

/// A brief, non-interactive pill at the top centre of the display under the
/// cursor: an SF Symbol and a short message (spec section 5.7). It never
/// takes focus, never catches clicks, and fades itself out. One reused panel,
/// so a second message replaces the first. Ported from Pullcord's HUD
/// (`showMessage`), without its morphing.
@MainActor
final class HUD {
    static let shared = HUD()

    static let controlHeldMessage = "Let go of Control before releasing the mouse"
    static let couldNotStartMessage = "Couldn’t start a capture"
    static let readOnlyMessage = "This library was saved by a newer Stickermine. Update to make changes."
    static let saveFailedMessage = "Couldn’t save the sticker"

    /// How long a message stays before fading.
    static let dwell: TimeInterval = 2.2
    static let height: CGFloat = 42
    private static let padding: CGFloat = 18
    private static let gap: CGFloat = 10
    private static let iconSize: CGFloat = 18

    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    /// Bumped by every show and hide, so a fade that finishes late never
    /// orders out a newer message.
    private var generation = 0

    /// The message last shown (tests and logs).
    private(set) var lastMessage: String?

    /// The pill's panel: the panel policy (spec section 4), click-through,
    /// on every Space and over full-screen apps; the level last.
    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: height),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.level = .statusBar  // last
        return panel
    }

    /// Where a pill of `width` sits: centred, 16 pt below the top of `visibleFrame`.
    static func frame(width: CGFloat, in visibleFrame: CGRect) -> CGRect {
        CGRect(x: (visibleFrame.midX - width / 2).rounded(), y: visibleFrame.maxY - height - 16,
               width: width, height: height)
    }

    func show(_ message: String, symbol: String = "exclamationmark.triangle.fill") {
        lastMessage = message
        generation &+= 1
        hideWork?.cancel()
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        let textWidth = ceil((message as NSString).size(withAttributes: [.font: font]).width)
        let textHeight = ceil(font.ascender - font.descender)
        let width = Self.padding + Self.iconSize + Self.gap + textWidth + Self.padding

        let shell = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: Self.height))
        shell.material = .hudWindow
        shell.blendingMode = .behindWindow
        shell.state = .active
        shell.wantsLayer = true
        shell.layer?.cornerRadius = Self.height / 2
        shell.layer?.masksToBounds = true

        let icon = NSImageView(frame: NSRect(x: Self.padding, y: (Self.height - Self.iconSize) / 2,
                                             width: Self.iconSize, height: Self.iconSize))
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 15, weight: .semibold))
        icon.contentTintColor = .labelColor
        icon.imageScaling = .scaleProportionallyDown
        shell.addSubview(icon)

        let label = NSTextField(labelWithString: message)
        label.font = font
        label.textColor = .labelColor
        label.frame = NSRect(x: Self.padding + Self.iconSize + Self.gap, y: (Self.height - textHeight) / 2,
                             width: textWidth, height: textHeight)
        shell.addSubview(label)
        panel.contentView = shell

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.screens.first
        if let visible = screen?.visibleFrame {
            panel.setFrame(Self.frame(width: width, in: visible), display: false)
        }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            panel.animator().alphaValue = 1
        }
        let generation = self.generation
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.fadeOut(generation: generation) }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.dwell, execute: work)
    }

    func hide() {
        generation &+= 1
        hideWork?.cancel()
        hideWork = nil
        panel?.orderOut(nil)
    }

    private func fadeOut(generation: Int) {
        guard generation == self.generation, let panel else { return }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.35
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, generation == self.generation else { return }
                panel.orderOut(nil)
            }
        })
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 271 tests in 34 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/UI/HUD.swift StickermineTests/HUDTests.swift
git commit -m "Add the HUD for capture messages" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 14: PermissionPanel

**Files:**
- Create: `Stickermine/Onboarding/PermissionPanel.swift`
- Test: Create `StickermineTests/PermissionPanelTests.swift`

**Interfaces:**
- Consumes: `ScreenProvider`, `StickerManager.display(containing:in:)` (M2), `PanelPolicy.applyCommon` (M1); `CGPreflightScreenCaptureAccess`, `CGRequestScreenCaptureAccess`.
- Produces:

```text
protocol ScreenRecordingAccess { func preflight() -> Bool; @discardableResult func request() -> Bool }
struct LiveScreenRecordingAccess: ScreenRecordingAccess            // the CG calls
struct PermissionPanelState: Equatable {
    enum Action: Equatable { case requestAccess, openSettings, relaunch }
    var didRequest: Bool; var cameBackWithoutAccess: Bool
    var actions: [Action] { get }        // [.requestAccess] | [.openSettings] | [.openSettings, .relaunch]
    static func whenShown(didRequest: Bool, panelIsUp: Bool, previous: PermissionPanelState) -> PermissionPanelState
                                         // show()'s state: a re-trigger while the panel is up, or an offered Relaunch, keeps Relaunch
}
@MainActor final class PermissionPanel: NSObject, NSWindowDelegate {   // Onboarding/PermissionPanel.swift
    static let didRequestKey: String     // "didRequestScreenCapture" (spec 12)
    static let settingsURL: URL          // x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture
    final class Model: ObservableObject { @Published var state: PermissionPanelState }
    let model: Model
    var onGranted: (() -> Void)?
    var isVisible: Bool { get }
    init(access: ScreenRecordingAccess = LiveScreenRecordingAccess(), defaults: UserDefaults = .standard,
         screens: ScreenProvider, openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) })
    static func makePanel() -> NSPanel   // titled, closable, never hidden on deactivation, .floating last
    func show(); func close()
    func perform(_ action: PermissionPanelState.Action)
    func recheck()                       // after the user comes back: closes on access, else offers Relaunch
    static func relaunch()               // a detached shell reopens the app once this process is gone
}
```

The panel re-checks when it becomes key again after the user left it (Home's re-check is M6). A capture triggered again while the panel is up counts as coming back too (the user who granted access in System Settings most naturally presses ⌃⌥⌘S again), so `show()` offers Relaunch instead of resetting to Open System Settings. The tests never call the CG functions: a fake `ScreenRecordingAccess` answers.

- [ ] **Step 1: Write the failing test**

`StickermineTests/PermissionPanelTests.swift`:

```swift
import AppKit
import Testing
@testable import Stickermine

/// Never touches TCC: a fake answers the Screen Recording checks.
@MainActor
struct PermissionPanelTests {
    final class FakeAccess: ScreenRecordingAccess {
        var granted = false
        var requests = 0

        func preflight() -> Bool { granted }

        func request() -> Bool {
            requests += 1
            return granted
        }
    }

    static func defaults() -> (UserDefaults, String) {
        let name = "StickermineTests-\(UUID().uuidString)"
        return (UserDefaults(suiteName: name)!, name)
    }

    @Test func theFirstTimeItAsksAfterwardsItOpensSettingsAndThenOffersARelaunch() {
        #expect(PermissionPanelState(didRequest: false).actions == [.requestAccess])
        #expect(PermissionPanelState(didRequest: true).actions == [.openSettings])
        #expect(PermissionPanelState(didRequest: true, cameBackWithoutAccess: true).actions == [.openSettings, .relaunch])
        // Brought up by a capture: a trigger while the panel is up, after the
        // request, is coming back too, and an offered Relaunch stays.
        let fresh = PermissionPanelState(didRequest: false)
        let asked = PermissionPanelState(didRequest: true)
        let cameBack = PermissionPanelState(didRequest: true, cameBackWithoutAccess: true)
        #expect(PermissionPanelState.whenShown(didRequest: false, panelIsUp: true, previous: fresh).actions
                == [.requestAccess])
        #expect(PermissionPanelState.whenShown(didRequest: true, panelIsUp: false, previous: asked).actions
                == [.openSettings])
        #expect(PermissionPanelState.whenShown(didRequest: true, panelIsUp: true, previous: asked).actions
                == [.openSettings, .relaunch])
        #expect(PermissionPanelState.whenShown(didRequest: true, panelIsUp: false, previous: cameBack).actions
                == [.openSettings, .relaunch])
    }

    @Test func askingRequestsOnceAndRemembersIt() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let access = FakeAccess()
        let panel = PermissionPanel(access: access, defaults: defaults, screens: FakeScreens([]))
        #expect(panel.model.state.actions == [.requestAccess])
        panel.perform(.requestAccess)
        #expect(access.requests == 1)
        #expect(defaults.bool(forKey: PermissionPanel.didRequestKey))
        #expect(panel.model.state.actions == [.openSettings])
        // A later panel starts from the remembered flag.
        let later = PermissionPanel(access: access, defaults: defaults, screens: FakeScreens([]))
        #expect(later.model.state.actions == [.openSettings])
    }

    @Test func openSystemSettingsGoesToScreenRecording() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        var opened: [URL] = []
        let panel = PermissionPanel(access: FakeAccess(), defaults: defaults, screens: FakeScreens([]),
                                    openURL: { opened.append($0) })
        panel.perform(.openSettings)
        #expect(opened.map(\.absoluteString)
                == ["x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"])
    }

    @Test func comingBackWithoutAccessOffersARelaunchAndWithAccessCloses() {
        let (defaults, name) = Self.defaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: PermissionPanel.didRequestKey)
        let access = FakeAccess()
        let panel = PermissionPanel(access: access, defaults: defaults, screens: FakeScreens([]))
        var granted = 0
        panel.onGranted = { granted += 1 }
        panel.recheck()
        #expect(panel.model.state.actions == [.openSettings, .relaunch])
        #expect(granted == 0)
        access.granted = true
        panel.recheck()
        #expect(granted == 1)
        #expect(!panel.isVisible)
    }

    @Test func thePanelStaysWhileTheUserIsInSystemSettings() {
        let panel = PermissionPanel.makePanel()
        defer { panel.close() }
        #expect(!panel.hidesOnDeactivate)
        #expect(!panel.isReleasedWhenClosed)
        #expect(panel.level == .floating)
        #expect(panel.styleMask.contains(.closable))
        #expect(panel.canBecomeKey)
        #expect(!panel.isVisible)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/PermissionPanelTests
```

Expected: `** TEST FAILED **` with `error: cannot find type 'ScreenRecordingAccess' in scope` and `error: cannot find 'PermissionPanel' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Onboarding/PermissionPanel.swift`:

```swift
import AppKit
import CoreGraphics
import SwiftUI

/// The Screen Recording check, behind a protocol so tests never touch TCC.
protocol ScreenRecordingAccess {
    /// Whether access is granted; never prompts.
    func preflight() -> Bool
    /// Prompts only while the state is undetermined (a denied app isn't
    /// re-prompted); returns the current state.
    @discardableResult func request() -> Bool
}

struct LiveScreenRecordingAccess: ScreenRecordingAccess {
    func preflight() -> Bool { CGPreflightScreenCaptureAccess() }
    @discardableResult func request() -> Bool { CGRequestScreenCaptureAccess() }
}

/// What the permission panel offers (spec section 14). Pure.
struct PermissionPanelState: Equatable {
    enum Action: Equatable {
        /// First time: `CGRequestScreenCaptureAccess()` (preflight can't tell
        /// "denied" from "never asked").
        case requestAccess
        /// Privacy & Security › Screen & System Audio Recording.
        case openSettings
        /// Quit and reopen, in case the in-process preflight result is stale.
        case relaunch
    }

    /// `didRequestScreenCapture` (spec section 12).
    var didRequest: Bool
    /// The user left the panel and came back while access was still off.
    var cameBackWithoutAccess = false

    var actions: [Action] {
        guard didRequest else { return [.requestAccess] }
        return cameBackWithoutAccess ? [.openSettings, .relaunch] : [.openSettings]
    }

    /// The state the panel shows when a capture brings it up. A capture
    /// triggered again while the panel is up (after the request) is the user
    /// coming back without access too (spec section 14), and once Relaunch was
    /// offered it stays: neither resets to Open System Settings alone.
    static func whenShown(didRequest: Bool, panelIsUp: Bool, previous: PermissionPanelState) -> PermissionPanelState {
        PermissionPanelState(didRequest: didRequest,
                             cameBackWithoutAccess: didRequest && (panelIsUp || previous.cameBackWithoutAccess))
    }
}

/// Shown instead of a capture when Screen Recording is off (spec section 14):
/// a standalone floating panel centred on the cursor's display (there is
/// usually no Home window to hang a sheet on). Never shown at launch.
@MainActor
final class PermissionPanel: NSObject, NSWindowDelegate {
    static let didRequestKey = "didRequestScreenCapture"
    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!

    final class Model: ObservableObject {
        @Published var state: PermissionPanelState

        init(state: PermissionPanelState) {
            self.state = state
        }
    }

    private let access: ScreenRecordingAccess
    private let defaults: UserDefaults
    private let screens: ScreenProvider
    private let openURL: (URL) -> Void
    let model: Model
    private var panel: NSPanel?
    private var hasResignedKey = false

    /// Access turned out to be on when the user came back; the panel closed.
    var onGranted: (() -> Void)?

    init(access: ScreenRecordingAccess = LiveScreenRecordingAccess(), defaults: UserDefaults = .standard,
         screens: ScreenProvider, openURL: @escaping (URL) -> Void = { NSWorkspace.shared.open($0) }) {
        self.access = access
        self.defaults = defaults
        self.screens = screens
        self.openURL = openURL
        model = Model(state: PermissionPanelState(didRequest: defaults.bool(forKey: Self.didRequestKey)))
        super.init()
    }

    var isVisible: Bool { panel?.isVisible == true }

    /// The panel policy (spec section 4): titled (so it can be key and has a
    /// close button), never hidden on deactivation (the user goes to System
    /// Settings and back), floating; the level last.
    static func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 260),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        PanelPolicy.applyCommon(to: panel, hidesOnDeactivate: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.animationBehavior = .none
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.level = .floating  // last
        return panel
    }

    /// Shows (or brings forward) the panel, centred on the display under the cursor.
    func show() {
        model.state = PermissionPanelState.whenShown(didRequest: defaults.bool(forKey: Self.didRequestKey),
                                                     panelIsUp: panel != nil, previous: model.state)
        hasResignedKey = false
        let panel = self.panel ?? makeContent()
        self.panel = panel
        let mouse = NSEvent.mouseLocation
        if let display = StickerManager.display(containing: mouse, in: screens.currentDisplays()) {
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: (display.visibleFrame.midX - size.width / 2).rounded(),
                                         y: (display.visibleFrame.midY - size.height / 2).rounded()))
        }
        NSApp.activate()
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        guard let panel else { return }
        panel.delegate = nil
        panel.orderOut(nil)
        panel.close()
        self.panel = nil
    }

    func perform(_ action: PermissionPanelState.Action) {
        switch action {
        case .requestAccess:
            defaults.set(true, forKey: Self.didRequestKey)
            model.state.didRequest = true
            access.request()
        case .openSettings:
            openURL(Self.settingsURL)
        case .relaunch:
            Self.relaunch()
        }
    }

    /// The user came back: with access on, close; otherwise offer Relaunch too.
    func recheck() {
        if access.preflight() {
            close()
            onGranted?()
        } else if model.state.didRequest {
            model.state.cameBackWithoutAccess = true
        }
    }

    /// Quits, and a detached shell opens the app again once this process is gone.
    static func relaunch() {
        let pid = ProcessInfo.processInfo.processIdentifier
        let helper = Process()
        helper.executableURL = URL(fileURLWithPath: "/bin/sh")
        helper.arguments = ["-c", "while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"",
                            Bundle.main.bundlePath]
        do {
            try helper.run()
            NSApp.terminate(nil)
        } catch {
            NSSound.beep()
        }
    }

    // MARK: NSWindowDelegate

    func windowDidResignKey(_ notification: Notification) {
        hasResignedKey = true
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard hasResignedKey else { return }
        recheck()
    }

    func windowWillClose(_ notification: Notification) {
        panel?.delegate = nil
        panel = nil
    }

    private func makeContent() -> NSPanel {
        let panel = Self.makePanel()
        let host = NSHostingView(rootView: PermissionView(model: model,
                                                          perform: { [weak self] in self?.perform($0) },
                                                          dismiss: { [weak self] in self?.close() }))
        panel.contentView = host
        panel.setContentSize(host.fittingSize)
        panel.delegate = self
        return panel
    }
}

private struct PermissionView: View {
    @ObservedObject var model: PermissionPanel.Model
    let perform: (PermissionPanelState.Action) -> Void
    let dismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Allow Screen Recording")
                    .font(.title3.weight(.semibold))
            }
            Text("Stickermine uses the macOS screenshot crosshair, and macOS asks for Screen Recording permission before an app can start it. Everything you capture stays on this Mac.")
                .fixedSize(horizontal: false, vertical: true)
            Text("macOS will also check in from time to time and ask you to confirm that Stickermine can see your screen.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if model.state.didRequest {
                Text("Turn on Stickermine in System Settings › Privacy & Security › Screen & System Audio Recording, then make a sticker again.")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                Button("Not Now", action: dismiss)
                    .keyboardShortcut(.cancelAction)
                ForEach(model.state.actions, id: \.self) { action in
                    switch action {
                    case .requestAccess:
                        Button("Continue") { perform(.requestAccess) }
                            .keyboardShortcut(.defaultAction)
                    case .openSettings:
                        Button("Open System Settings") { perform(.openSettings) }
                            .keyboardShortcut(.defaultAction)
                    case .relaunch:
                        Button("Relaunch Stickermine") { perform(.relaunch) }
                    }
                }
            }
            .padding(.top, 4)
        }
        .padding(22)
        .padding(.top, 8)
        .frame(width: 420)
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 276 tests in 35 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Onboarding/PermissionPanel.swift StickermineTests/PermissionPanelTests.swift
git commit -m "Add the Screen Recording permission panel" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 15: The menu bar glyph and StatusItemController

**Files:**
- Create: `Stickermine/Assets.xcassets/MenuBarGlyph.imageset/Contents.json`, `Stickermine/Assets.xcassets/MenuBarGlyph.imageset/MenuBarGlyph.svg` (a copy of `design/menubar-glyph.svg`), `Stickermine/App/StatusItemController.swift`
- Test: Create `StickermineTests/StatusItemControllerTests.swift`

**Interfaces:**
- Consumes: `Shortcut` (Task 1); `NSStatusBar`, `NSStatusItem`, `NSMenu`.
- Produces:

```text
asset MenuBarGlyph: the SVG, template rendering intent, vector data preserved
@MainActor final class StatusItemController: NSObject {             // App/StatusItemController.swift
    static let glyphName: String                                    // "MenuBarGlyph"
    static let glyphSize: NSSize                                    // 18 × 18 pt
    var onCapture: (() -> Void)?                                    // left-click or New Sticker
    var onQuit: (() -> Void)?                                       // the menu's Quit
    var sessionActive: Bool                                         // disables New Sticker
    init(shortcut: Shortcut?)                                       // creates the NSStatusItem
    func setShortcut(_ shortcut: Shortcut?)
    static func glyph() -> NSImage?                                 // 18 × 18 template copy of the asset
    static func makeMenu(shortcut: Shortcut?) -> (menu: NSMenu, newSticker: NSMenuItem, quit: NSMenuItem)
    static func applyShortcut(_ shortcut: Shortcut?, to item: NSMenuItem)
    static func applySessionState(_ active: Bool, to item: NSMenuItem)
    static func modifierFlags(carbon: UInt32) -> NSEvent.ModifierFlags
    static func opensMenu(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool   // right-click or Control-click
}
```

The tests check the glyph, the asset, the menu and the click rules without creating a status item (it would appear in the real menu bar).

- [ ] **Step 1: Write the failing test**

`StickermineTests/StatusItemControllerTests.swift`:

```swift
import AppKit
import Carbon.HIToolbox
import Testing
@testable import Stickermine

/// No status item is created here (it would appear in the menu bar): the
/// glyph, the menu and the click rules are checked on their own.
@MainActor
struct StatusItemControllerTests {
    @Test func theGlyphIsAnEighteenPointTemplate() throws {
        let glyph = try #require(StatusItemController.glyph())
        #expect(glyph.size == NSSize(width: 18, height: 18))
        #expect(glyph.isTemplate)
        // The named asset itself is left at its own size.
        #expect(NSImage(named: StatusItemController.glyphName)?.size != NSSize(width: 18, height: 18))
    }

    @Test func theAssetIsTheDesignGlyphAsAVectorTemplate() throws {
        let folder = "Assets.xcassets/MenuBarGlyph.imageset/"
        let json = try SourceFiles.contents(of: folder + "Contents.json")
        #expect(json.contains(#""template-rendering-intent" : "template""#))
        #expect(json.contains(#""preserves-vector-representation" : true"#))
        #expect(json.contains(#""filename" : "MenuBarGlyph.svg""#))
        let asset = try Data(contentsOf: SourceFiles.appRoot.appendingPathComponent(folder + "MenuBarGlyph.svg"))
        let design = try Data(contentsOf: SourceFiles.repoRoot.appendingPathComponent("design/menubar-glyph.svg"))
        #expect(asset == design)
    }

    @Test func theMenuHasNewStickerWithTheShortcutAndQuit() {
        let built = StatusItemController.makeMenu(shortcut: .defaultCapture)
        #expect(built.menu.items.map(\.title) == ["New Sticker", "", "Quit Stickermine"])
        #expect(built.menu.items[1].isSeparatorItem)
        #expect(built.newSticker.keyEquivalent == "s")
        #expect(built.newSticker.keyEquivalentModifierMask == [.control, .option, .command])
        #expect(built.quit.keyEquivalent == "q")
        #expect(!built.menu.autoenablesItems)
        let none = StatusItemController.makeMenu(shortcut: nil)
        #expect(none.newSticker.keyEquivalent == "")
    }

    @Test func newStickerIsDisabledDuringASession() {
        let item = StatusItemController.makeMenu(shortcut: .defaultCapture).newSticker
        StatusItemController.applySessionState(true, to: item)
        #expect(!item.isEnabled)
        StatusItemController.applySessionState(false, to: item)
        #expect(item.isEnabled)
    }

    @Test func aRightClickOrControlClickOpensTheMenu() {
        #expect(StatusItemController.opensMenu(type: .rightMouseUp, modifiers: []))
        #expect(StatusItemController.opensMenu(type: .leftMouseUp, modifiers: [.control]))
        #expect(!StatusItemController.opensMenu(type: .leftMouseUp, modifiers: []))
        #expect(!StatusItemController.opensMenu(type: .leftMouseUp, modifiers: [.command]))
    }

    @Test func carbonModifiersMapToAppKitFlags() {
        #expect(StatusItemController.modifierFlags(carbon: UInt32(controlKey | optionKey | cmdKey))
                == [.control, .option, .command])
        #expect(StatusItemController.modifierFlags(carbon: UInt32(shiftKey)) == [.shift])
        #expect(StatusItemController.modifierFlags(carbon: 0) == [])
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/StatusItemControllerTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'StatusItemController' in scope`.

- [ ] **Step 3: Add the glyph to the asset catalog**

```bash
mkdir -p Stickermine/Assets.xcassets/MenuBarGlyph.imageset
cp design/menubar-glyph.svg Stickermine/Assets.xcassets/MenuBarGlyph.imageset/MenuBarGlyph.svg
```

`Stickermine/Assets.xcassets/MenuBarGlyph.imageset/Contents.json`:

```json
{
  "images" : [
    {
      "filename" : "MenuBarGlyph.svg",
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  },
  "properties" : {
    "preserves-vector-representation" : true,
    "template-rendering-intent" : "template"
  }
}
```

- [ ] **Step 4: Implement**

`Stickermine/App/StatusItemController.swift`:

```swift
import AppKit
import Carbon.HIToolbox

/// The menu bar icon (spec section 13): the pickaxe glyph from
/// `design/menubar-glyph.svg` (asset `MenuBarGlyph`, a template image drawn
/// white or black to match the menu bar). A left-click starts a capture; a
/// right-click or Control-click shows the menu: New Sticker (with the
/// shortcut; disabled during a session) and Quit. M6 adds Open Stickermine…
/// and hiding the icon. `MenuBarExtra` isn't used: it can't act on a plain click.
@MainActor
final class StatusItemController: NSObject {
    static let glyphName = "MenuBarGlyph"
    /// The SVG reports 200 × 200 pt; the menu bar wants 18 × 18.
    static let glyphSize = NSSize(width: 18, height: 18)

    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let newStickerItem: NSMenuItem

    /// A left-click or the menu's New Sticker.
    var onCapture: (() -> Void)?
    /// The menu's Quit.
    var onQuit: (() -> Void)?

    /// While a session runs, New Sticker is disabled (spec section 5.2).
    var sessionActive = false {
        didSet { Self.applySessionState(sessionActive, to: newStickerItem) }
    }

    init(shortcut: Shortcut?) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let built = Self.makeMenu(shortcut: shortcut)
        menu = built.menu
        newStickerItem = built.newSticker
        super.init()
        newStickerItem.target = self
        newStickerItem.action = #selector(newSticker(_:))
        built.quit.target = self
        built.quit.action = #selector(quit(_:))
        if let button = statusItem.button {
            button.image = Self.glyph()
            button.toolTip = "Stickermine"
            button.setAccessibilityLabel("Stickermine")
            button.target = self
            button.action = #selector(buttonClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    /// Shows the shortcut in the menu (nil: none).
    func setShortcut(_ shortcut: Shortcut?) {
        Self.applyShortcut(shortcut, to: newStickerItem)
    }

    /// The glyph from the asset catalog, as an 18 × 18 pt template image.
    static func glyph() -> NSImage? {
        guard let named = NSImage(named: glyphName), let image = named.copy() as? NSImage else { return nil }
        image.size = glyphSize
        image.isTemplate = true
        return image
    }

    /// The menu: New Sticker (with the shortcut), a separator, Quit Stickermine.
    static func makeMenu(shortcut: Shortcut?) -> (menu: NSMenu, newSticker: NSMenuItem, quit: NSMenuItem) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let newSticker = NSMenuItem(title: "New Sticker", action: nil, keyEquivalent: "")
        applyShortcut(shortcut, to: newSticker)
        menu.addItem(newSticker)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Stickermine", action: nil, keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        menu.addItem(quit)
        return (menu, newSticker, quit)
    }

    /// The item shows `shortcut` as its key equivalent (nothing when there is
    /// none or the key can't be shown in a menu).
    static func applyShortcut(_ shortcut: Shortcut?, to item: NSMenuItem) {
        guard let shortcut, let key = shortcut.menuKeyEquivalent else {
            item.keyEquivalent = ""
            item.keyEquivalentModifierMask = []
            return
        }
        item.keyEquivalent = key
        item.keyEquivalentModifierMask = modifierFlags(carbon: shortcut.modifiers)
    }

    static func applySessionState(_ active: Bool, to item: NSMenuItem) {
        item.isEnabled = !active
    }

    /// A Carbon modifier mask as AppKit modifier flags.
    static func modifierFlags(carbon: UInt32) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if carbon & UInt32(controlKey) != 0 { flags.insert(.control) }
        if carbon & UInt32(optionKey) != 0 { flags.insert(.option) }
        if carbon & UInt32(shiftKey) != 0 { flags.insert(.shift) }
        if carbon & UInt32(cmdKey) != 0 { flags.insert(.command) }
        return flags
    }

    /// A right-click or Control-click opens the menu; any other click captures.
    static func opensMenu(type: NSEvent.EventType, modifiers: NSEvent.ModifierFlags) -> Bool {
        type == .rightMouseUp || type == .rightMouseDown || modifiers.contains(.control)
    }

    @objc private func buttonClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if let event, Self.opensMenu(type: event.type, modifiers: event.modifierFlags) {
            showMenu()
        } else {
            onCapture?()
        }
    }

    private func showMenu() {
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func newSticker(_ sender: Any?) {
        onCapture?()
    }

    @objc private func quit(_ sender: Any?) {
        onQuit?()
    }
}
```

- [ ] **Step 5: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 282 tests in 36 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 6: Commit**

```bash
git add Stickermine/Assets.xcassets/MenuBarGlyph.imageset Stickermine/App/StatusItemController.swift StickermineTests/StatusItemControllerTests.swift
git commit -m "Add the menu bar icon: left-click captures, right-click shows the menu" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 16: SessionCoordinator

**Files:**
- Create: `Stickermine/App/SessionCoordinator.swift`
- Test: Create `StickermineTests/SessionCoordinatorTests.swift`

**Interfaces:**
- Consumes: `CaptureService` (Task 4), `MasterImage.load(url:)`/`pngData` (Task 5), `CutoutEngine`/`CutoutAnalysis` (Task 8), `StyleRenderer.setInFlightMaster`/`prewarm` (Task 9, M3), `PickerModel` (Task 10), `PickerController` (Task 11), `PlacementSession` (Task 12), `HUD` (Task 13), `ScreenRecordingAccess`, `PermissionPanel` (Task 14); M2's `StickerManager` (`endEditing(discardGesture:)`, `display(containing:in:)`), `LibraryController` (`mutate`, `isReadOnly`, `library`), `LibraryStore.writePNG`/`deletePNG`, `StickerRecord`, `ScreenProvider`/`LiveScreenProvider`.
- Produces (Contract changes items 2 and 3):

```text
@MainActor final class SessionCoordinator {                          // App/SessionCoordinator.swift
    enum Stage: Equatable { case idle, capturing, analyzing, picking, saving, placing }
    private(set) var stage: Stage
    var isActive: Bool { get }                                       // contract
    var onActiveChange: ((Bool) -> Void)?                            // contract
    var onPlaced: ((_ placement: UUID, _ sticker: UUID) -> Void)?    // a placement click (M6 counts them)
    private(set) var currentSticker: UUID?                           // the re-placed sticker, or a fresh one once saved
    init(capture: CaptureService, cutout: CutoutEngine, stickers: StickerManager, library: LibraryController,
         store: LibraryStore, renderer: StyleRenderer, screens: ScreenProvider? = nil,
         access: ScreenRecordingAccess = LiveScreenRecordingAccess(), showMessage: ((String) -> Void)? = nil,
         presentPermission: (() -> Void)? = nil, restoresFocus: Bool = true)
    func startCapture(orderingOut window: NSWindow? = nil)           // contract: startCapture()
    func startReplace(sticker: UUID)                                 // contract
    func cancel()                                                    // contract
}
```

A capture: refuse while active (and with a read-only library, with the HUD's notice); preflight, else the permission panel and no session; begin (end editing, remember the frontmost app, `onActiveChange(true)`); order `window` out; warm Vision and the Puffy kernel; capture; on success load the PNG and delete it off the main actor, analyse, and show the picker near the cursor; on confirm close the picker, release Vision, write the PNG off the main actor, then append the `StickerRecord` (`lastStyle` = the chosen style) on main, and start placement with the in-flight master still set; end (clear the in-flight master, hand focus back, `onActiveChange(false)`). A re-place starts at the style-only picker and skips saving. Cancel works at every stage; a PNG that finishes writing after a cancel is deleted again, since nothing indexed it. The tests stop at the capture's outcome, so no picker or panel ever shows.

- [ ] **Step 1: Write the failing test**

`StickermineTests/SessionCoordinatorTests.swift`:

```swift
import AppKit
import Testing
@testable import Stickermine

/// Sessions up to the capture's outcome. Never runs screencapture (a shell
/// command stands in), never shows a panel (the HUD and the permission panel
/// are replaced) and never moves focus.
@MainActor
struct SessionCoordinatorTests {
    final class Recorder {
        var messages: [String] = []
        var permissionPanels = 0
        var activity: [Bool] = []
    }

    final class FakeAccess: ScreenRecordingAccess {
        var granted: Bool
        init(granted: Bool) { self.granted = granted }
        func preflight() -> Bool { granted }
        func request() -> Bool { granted }
    }

    struct Harness {
        let folder: URL
        let session: SessionCoordinator
        let capture: CaptureService
        let recorder: Recorder
        let library: LibraryController
    }

    static func harness(script: String, granted: Bool = true, readOnly: Bool = false) throws -> Harness {
        let folder = Fixtures.temporaryDirectory()
        if readOnly {
            try Data(#"{"version": 99, "stickers": [], "displays": {}}"#.utf8)
                .write(to: folder.appendingPathComponent("library.json"))
        }
        let store = LibraryStore(root: folder)
        let library = LibraryController(store: store, saveDelay: 60)
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let screens = FakeScreens([Fixtures.external()])
        let stickers = StickerManager(library: library, screens: screens, renderer: renderer)
        let capture = CaptureService(command: CaptureServiceTests.shell(script), temporaryDirectory: folder,
                                     pasteboardChangeCount: { 7 }, modifiersHeld: { false })
        let recorder = Recorder()
        let session = SessionCoordinator(capture: capture, cutout: CutoutEngine(perform: { _ in nil }),
                                         stickers: stickers, library: library, store: store, renderer: renderer,
                                         screens: screens, access: FakeAccess(granted: granted),
                                         showMessage: { recorder.messages.append($0) },
                                         presentPermission: { recorder.permissionPanels += 1 },
                                         restoresFocus: false)
        session.onActiveChange = { recorder.activity.append($0) }
        return Harness(folder: folder, session: session, capture: capture, recorder: recorder, library: library)
    }

    static func waitUntilIdle(_ session: SessionCoordinator) async -> Bool {
        await PickerModelTests.waitUntil { !session.isActive }
    }

    @Test func withoutScreenRecordingThePermissionPanelShowsInsteadOfACapture() throws {
        let h = try Self.harness(script: #"printf png > "$1""#, granted: false)
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(h.recorder.permissionPanels == 1)
        #expect(!h.session.isActive)
        #expect(!h.capture.isRunning)
        #expect(h.recorder.activity.isEmpty)
    }

    @Test func oneSessionAtATimeAndCancelEndsIt() throws {
        let h = try Self.harness(script: "exec sleep 5")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(h.session.isActive)
        #expect(h.session.stage == .capturing)
        #expect(h.capture.isRunning)
        h.session.startCapture()
        h.session.startReplace(sticker: UUID())
        #expect(h.recorder.activity == [true])
        h.session.cancel()
        #expect(!h.session.isActive)
        #expect(!h.capture.isRunning)
        #expect(h.recorder.activity == [true, false])
        #expect(h.recorder.messages.isEmpty)
    }

    @Test func controlHeldAtMouseUpIsExplained() async throws {
        let h = try Self.harness(script: "exit 0")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        var count = 0
        let capture = CaptureService(command: CaptureServiceTests.shell("exit 0"), temporaryDirectory: h.folder,
                                     pasteboardChangeCount: { count += 1; return count }, modifiersHeld: { false })
        let recorder = Recorder()
        let library = LibraryController(store: LibraryStore(root: h.folder), saveDelay: 60)
        let renderer = StyleRenderer(masterProvider: { _ in nil })
        let screens = FakeScreens([Fixtures.external()])
        let session = SessionCoordinator(capture: capture, cutout: CutoutEngine(perform: { _ in nil }),
                                         stickers: StickerManager(library: library, screens: screens, renderer: renderer),
                                         library: library, store: library.store, renderer: renderer, screens: screens,
                                         access: FakeAccess(granted: true),
                                         showMessage: { recorder.messages.append($0) },
                                         presentPermission: { recorder.permissionPanels += 1 }, restoresFocus: false)
        session.startCapture()
        #expect(await Self.waitUntilIdle(session))
        #expect(recorder.messages == [HUD.controlHeldMessage])
    }

    @Test func aBusyCaptureIsExplained() async throws {
        let h = try Self.harness(script: "exit 1")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(await Self.waitUntilIdle(h.session))
        #expect(h.recorder.messages == [HUD.couldNotStartMessage])
        #expect(h.recorder.activity == [true, false])
    }

    @Test func aCancelledCaptureEndsSilently() async throws {
        let h = try Self.harness(script: "exit 0")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(await Self.waitUntilIdle(h.session))
        #expect(h.recorder.messages.isEmpty)
        #expect(h.recorder.activity == [true, false])
    }

    @Test func anUnreadableCaptureIsDeletedAndExplained() async throws {
        let h = try Self.harness(script: #"printf 'not a png' > "$1""#)
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startCapture()
        #expect(await Self.waitUntilIdle(h.session))
        #expect(h.recorder.messages == [HUD.couldNotStartMessage])
        let left = try FileManager.default.contentsOfDirectory(atPath: h.folder.path)
        #expect(!left.contains { $0.hasPrefix(CaptureService.filePrefix) })
    }

    @Test func aReadOnlyLibraryRefusesSessions() throws {
        let h = try Self.harness(script: #"printf png > "$1""#, readOnly: true)
        defer { try? FileManager.default.removeItem(at: h.folder) }
        #expect(h.library.isReadOnly)
        h.session.startCapture()
        h.session.startReplace(sticker: UUID())
        #expect(!h.session.isActive)
        #expect(!h.capture.isRunning)
        #expect(h.recorder.messages == [HUD.readOnlyMessage, HUD.readOnlyMessage])
    }

    @Test func rePlacingAnUnknownStickerDoesNothing() throws {
        let h = try Self.harness(script: "exit 0")
        defer { try? FileManager.default.removeItem(at: h.folder) }
        h.session.startReplace(sticker: UUID())
        #expect(!h.session.isActive)
        #expect(h.recorder.activity.isEmpty)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/SessionCoordinatorTests
```

Expected: `** TEST FAILED **` with `error: cannot find type 'SessionCoordinator' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/App/SessionCoordinator.swift`:

```swift
import AppKit
import os

/// One sticker session at a time (spec section 5.2): from a trigger until the
/// sticker is placed or cancelled. A capture runs the permission check,
/// `screencapture`, the cutout, the picker and placement; re-placing from
/// history starts at the picker. While a session is active every trigger is
/// ignored. Starting one first ends any sticker's editing (discarding a
/// gesture); a capture started from Home orders Home out before screencapture
/// runs. When it ends, focus returns to the app that was frontmost before.
@MainActor
final class SessionCoordinator {
    enum Stage: Equatable {
        case idle, capturing, analyzing, picking, saving, placing
    }

    private(set) var stage: Stage = .idle
    var isActive: Bool { stage != .idle }
    /// Called with true when a session starts and false when it ends.
    var onActiveChange: ((Bool) -> Void)?
    /// A placement click of `sticker` made `placement` (M6 counts these for
    /// the support ask).
    var onPlaced: ((_ placement: UUID, _ sticker: UUID) -> Void)?
    /// The sticker this session works on, once known: the re-placed sticker,
    /// or a fresh one once it is saved. Delete from History cancels the
    /// session when it is the one being deleted (M6).
    private(set) var currentSticker: UUID?

    private let capture: CaptureService
    private let cutout: CutoutEngine
    private let stickers: StickerManager
    private let library: LibraryController
    private let store: LibraryStore
    private let renderer: StyleRenderer
    private let screens: ScreenProvider
    private let access: ScreenRecordingAccess
    private let showMessage: (String) -> Void
    private let permissionOverride: (() -> Void)?
    private let restoresFocus: Bool
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "session")

    /// Bumped by every start and end, so late async results of an ended
    /// session are dropped.
    private var sessionID = 0
    private var previousApp: NSRunningApplication?
    private var analysis: CutoutAnalysis?
    private var picker: PickerController?
    private var placement: PlacementSession?
    private var inFlightSticker: UUID?
    private var permissionPanel: PermissionPanel?

    /// `screens` defaults to the live screens, `showMessage` to the HUD and
    /// `presentPermission` to the permission panel; tests replace them and
    /// turn `restoresFocus` off, so a test never activates another app.
    init(capture: CaptureService, cutout: CutoutEngine, stickers: StickerManager, library: LibraryController,
         store: LibraryStore, renderer: StyleRenderer, screens: ScreenProvider? = nil,
         access: ScreenRecordingAccess = LiveScreenRecordingAccess(),
         showMessage: ((String) -> Void)? = nil, presentPermission: (() -> Void)? = nil,
         restoresFocus: Bool = true) {
        self.capture = capture
        self.cutout = cutout
        self.stickers = stickers
        self.library = library
        self.store = store
        self.renderer = renderer
        self.screens = screens ?? LiveScreenProvider()
        self.access = access
        self.showMessage = showMessage ?? { HUD.shared.show($0) }
        permissionOverride = presentPermission
        self.restoresFocus = restoresFocus
    }

    // MARK: Triggers

    /// The shortcut, a left-click on the menu bar icon, New Sticker. `window`
    /// (Home, when started from there) is ordered out just before screencapture
    /// runs and isn't shown again.
    func startCapture(orderingOut window: NSWindow? = nil) {
        guard !isActive else {
            log.notice("capture ignored: a session is active")
            return
        }
        guard !library.isReadOnly else {
            showMessage(HUD.readOnlyMessage)
            return
        }
        guard access.preflight() else {
            // Never start screencapture without Screen Recording (spec 5.3).
            presentPermission()
            return
        }
        permissionPanel?.close()
        begin(.capturing)
        window?.orderOut(nil)
        cutout.prewarm()
        renderer.prewarm()
        let id = sessionID
        capture.capture { [weak self] outcome in
            self?.captureFinished(outcome, session: id)
        }
    }

    /// Re-placing a sticker from history: the style-only picker, then placement.
    func startReplace(sticker: UUID) {
        guard !isActive else {
            log.notice("re-place ignored: a session is active")
            return
        }
        guard !library.isReadOnly else {
            showMessage(HUD.readOnlyMessage)
            return
        }
        guard let record = library.library.sticker(sticker) else { return }
        begin(.picking)
        currentSticker = sticker
        let model = PickerModel.forRestyle(record, renderer: renderer, backingScale: cursorDisplay()?.backingScale ?? 2)
        showPicker(model, session: sessionID)
    }

    /// Ends the session wherever it is: terminates screencapture (deleting its
    /// file), closes the picker or the placement panel. Saves nothing new; a
    /// sticker already saved stays in history. Quit calls this first.
    func cancel() {
        guard isActive else { return }
        log.notice("session cancelled at \(String(describing: self.stage), privacy: .public)")
        capture.cancelRunning()
        end()
    }

    // MARK: Steps

    private func captureFinished(_ outcome: CaptureOutcome, session: Int) {
        guard session == sessionID, stage == .capturing else { return }
        switch outcome {
        case .success(let url):
            stage = .analyzing
            analyze(url, session: session)
        case .controlHeldToClipboard:
            showMessage(HUD.controlHeldMessage)
            end()
        case .busyOrBlocked:
            showMessage(HUD.couldNotStartMessage)
            end()
        case .cancelled:
            end()
        }
    }

    /// Loads the PNG and deletes it at once, then runs pass 1, off the main actor.
    private func analyze(_ url: URL, session: Int) {
        let engine = cutout
        Task { [weak self] in
            guard let loaded = await Self.load(url) else {
                self?.analysisFailed(session: session)
                return
            }
            let analysis = await engine.analyze(loaded)
            self?.analyzed(analysis, session: session)
        }
    }

    /// The capture with its colour profile and DPI; the temporary file is
    /// deleted right after (spec section 5.8). Runs off the main actor.
    nonisolated private static func load(_ url: URL) async -> LoadedCapture? {
        defer { try? FileManager.default.removeItem(at: url) }
        return try? MasterImage.load(url: url)
    }

    private func analysisFailed(session: Int) {
        guard session == sessionID else { return }
        log.error("the capture couldn't be read")
        showMessage(HUD.couldNotStartMessage)
        end()
    }

    private func analyzed(_ analysis: CutoutAnalysis, session: Int) {
        guard session == sessionID, stage == .analyzing else {
            analysis.release()
            return
        }
        stage = .picking
        self.analysis = analysis
        let model = PickerModel.forCapture(analysis, renderer: renderer,
                                           backingScale: cursorDisplay()?.backingScale ?? 2)
        showPicker(model, session: session)
    }

    private func showPicker(_ model: PickerModel, session: Int) {
        let picker = PickerController(model: model)
        picker.onCancel = { [weak self] in self?.cancel() }
        model.onConfirm = { [weak self] confirmation in self?.confirmed(confirmation, session: session) }
        self.picker = picker
        let mouse = NSEvent.mouseLocation
        let visible = cursorDisplay()?.visibleFrame ?? NSScreen.screens.first?.visibleFrame ?? .zero
        picker.show(near: mouse, visibleFrame: visible)
    }

    private func confirmed(_ confirmation: PickerModel.Confirmation, session: Int) {
        guard session == sessionID, stage == .picking else { return }
        closePicker()
        guard let image = confirmation.image else {
            // Re-placing: the master is already in the library.
            startPlacement(sticker: confirmation.sticker, style: confirmation.style)
            return
        }
        // A fresh capture: PNG first (off the main actor), then the index.
        stage = .saving
        inFlightSticker = confirmation.sticker
        currentSticker = confirmation.sticker
        let store = self.store
        Task { [weak self] in
            let succeeded = await Self.write(image, pixelsPerPoint: confirmation.pixelsPerPoint,
                                             as: confirmation.sticker, in: store)
            self?.saved(confirmation, image: image, succeeded: succeeded, session: session)
        }
    }

    /// The master PNG with its DPI, written atomically. Runs off the main actor.
    nonisolated private static func write(_ image: CGImage, pixelsPerPoint: Double, as sticker: UUID,
                                          in store: LibraryStore) async -> Bool {
        do {
            try store.writePNG(try MasterImage.pngData(image, pixelsPerPoint: pixelsPerPoint), for: sticker)
            return true
        } catch {
            return false
        }
    }

    private func saved(_ confirmation: PickerModel.Confirmation, image: CGImage, succeeded: Bool, session: Int) {
        guard session == sessionID, stage == .saving else {
            // Cancelled while the PNG was written: nothing was indexed, so the
            // PNG goes too (launch repair would adopt it otherwise).
            if succeeded { try? store.deletePNG(for: confirmation.sticker) }
            return
        }
        guard succeeded else {
            log.error("saving the master PNG failed")
            showMessage(HUD.saveFailedMessage)
            end()
            return
        }
        let record = StickerRecord(id: confirmation.sticker, created: Date(), pixelWidth: image.width,
                                   pixelHeight: image.height, pixelsPerPoint: confirmation.pixelsPerPoint,
                                   lastStyle: confirmation.style)
        library.mutate { $0.stickers.append(record) }
        startPlacement(sticker: record.id, style: confirmation.style)
    }

    private func startPlacement(sticker: UUID, style: StickerStyle) {
        guard let record = library.library.sticker(sticker) else {
            end()
            return
        }
        stage = .placing
        let session = PlacementSession(
            sticker: sticker, style: style, natural: record.naturalPointSize,
            sourceLongSide: Double(max(record.pixelWidth, record.pixelHeight)),
            renderer: renderer, stickers: stickers, screens: screens)
        let id = sessionID
        session.onEnd = { [weak self] outcome in
            guard let self, id == self.sessionID else { return }
            if case .placed(let placement) = outcome {
                self.onPlaced?(placement, sticker)
            }
            self.placement = nil
            self.end()
        }
        placement = session
        session.start()
    }

    // MARK: Start and end

    private func begin(_ stage: Stage) {
        sessionID += 1
        self.stage = stage
        stickers.endEditing(discardGesture: true)
        let frontmost = restoresFocus ? NSWorkspace.shared.frontmostApplication : nil
        previousApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : frontmost
        onActiveChange?(true)
    }

    private func end() {
        sessionID += 1
        closePicker()
        if let placement {
            self.placement = nil
            placement.onEnd = nil
            placement.cancel()
        }
        if let inFlightSticker {
            renderer.setInFlightMaster(nil, for: inFlightSticker)
            self.inFlightSticker = nil
        }
        currentSticker = nil
        stage = .idle
        if let previousApp, !previousApp.isTerminated, NSApp.isActive {
            previousApp.activate()
        }
        previousApp = nil
        onActiveChange?(false)
    }

    private func closePicker() {
        picker?.model.finish()
        picker?.close()
        picker = nil
        analysis?.release()
        analysis = nil
    }

    /// The permission panel (spec section 14), or the tests' stand-in.
    private func presentPermission() {
        if let permissionOverride {
            permissionOverride()
            return
        }
        let panel = permissionPanel ?? PermissionPanel(access: access, screens: screens)
        permissionPanel = panel
        panel.show()
    }

    private func cursorDisplay() -> DisplayInfo? {
        StickerManager.display(containing: NSEvent.mouseLocation, in: screens.currentDisplays())
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 290 tests in 37 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/App/SessionCoordinator.swift StickermineTests/SessionCoordinatorTests.swift
git commit -m "Add SessionCoordinator: one sticker session from trigger to placement" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 17: AppDelegate wiring; the Maple debug path goes

**Files:**
- Modify: `Stickermine/App/AppDelegate.swift` (whole file shown)
- Delete: `Stickermine/App/DebugMaple.swift`, `StickermineTests/DebugMapleTests.swift`
- Test: Modify `StickermineTests/AppDelegateTests.swift` (whole file shown)

**Interfaces:**
- Consumes: everything above; M3's `StyleGallery`.
- Produces: at launch (not in the test host, not with `-styleGallery`), leftovers deleted, the status item and the ⌃⌥⌘S hotkey wired to `SessionCoordinator.startCapture()`, New Sticker disabled during a session, Quit and `applicationWillTerminate` cancelling the session (terminating `screencapture` and deleting its file) before the library is flushed. `AppDelegate` gains the private `session`, `statusItem` and `hotkeys` properties and `startCapture()`/`quit()`.

- [ ] **Step 1: Write the failing test**

`StickermineTests/AppDelegateTests.swift` (complete file; it replaces M3's version: `theSpikeIsGoneAndOnlyTheDebugMaplePathRemains` becomes `theSpikeAndTheDebugMaplePathAreGone`, `theStyleGalleryRunsInsteadOfTheStickers` loses its `DebugMaple.styles(in: arguments)` line, and `launchWiresTheCaptureTriggersAndCleansUp` is new):

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

    @Test func theSpikeAndTheDebugMaplePathAreGone() throws {
        for file in ["Stickers/SpikeController.swift", "App/DebugMaple.swift"] {
            #expect(!FileManager.default.fileExists(atPath: SourceFiles.appRoot.appendingPathComponent(file).path))
        }
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(!delegate.contains("SpikeController"))
        #expect(!delegate.contains("DebugMaple"))
    }

    @Test func theStyleGalleryRunsInsteadOfTheStickers() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        let gallery = try #require(delegate.range(of: "StyleGallery.launchArgument"))
        let stickers = try #require(delegate.range(of: "startStickers()\n"))
        #expect(gallery.lowerBound < stickers.lowerBound)
        #expect(delegate.contains("StyleGallery.runAndQuit()"))
    }

    @Test func launchWiresTheCaptureTriggersAndCleansUp() throws {
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(delegate.contains("CaptureService.deleteLeftovers()"))
        #expect(delegate.contains("StatusItemController(shortcut: shortcut)"))
        #expect(delegate.contains("hotkeys.register(shortcut)"))
        #expect(delegate.contains("let shortcut = Shortcut.defaultCapture"))
        // Quit and termination cancel the session (terminating screencapture)
        // before the library is flushed.
        let terminate = try #require(delegate.range(of: "func applicationWillTerminate"))
        let cancel = try #require(delegate.range(of: "session?.cancel()", range: terminate.upperBound..<delegate.endIndex))
        let flush = try #require(delegate.range(of: "library?.flush()", range: terminate.upperBound..<delegate.endIndex))
        #expect(cancel.lowerBound < flush.lowerBound)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/AppDelegateTests
```

Expected: `** TEST FAILED **` with `Test theSpikeAndTheDebugMaplePathAreGone() recorded an issue` (DebugMaple.swift still exists) and `Test launchWiresTheCaptureTriggersAndCleansUp() recorded an issue` (no `CaptureService.deleteLeftovers()` yet): `Test run with 6 tests in 1 suite failed … with 7 issues`.

- [ ] **Step 3: Delete the debug path**

```bash
git rm Stickermine/App/DebugMaple.swift StickermineTests/DebugMapleTests.swift
```

- [ ] **Step 4: Implement**

Before overwriting, run `grep -o 'clickThroughFallbackByDefault = [a-z]*' Stickermine/App/AppDelegate.swift`. The value M2 Task 12 Step 5 chose from `design/spike-results.md` must survive: if it prints `= true`, write `static let clickThroughFallbackByDefault = true` in the block below.

`Stickermine/App/AppDelegate.swift` (complete file; it replaces M3's version: `applicationDidFinishLaunching` calls the new `startCapture()` after `startStickers()`, `applicationWillTerminate` cancels the session before flushing, `startStickers()` loses the `-debugPlaceMaple` lines and creates the `SessionCoordinator`, and `startCapture()` and `quit()` are new):

```swift
import AppKit
import os

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
    /// early.
    private(set) static var didRunStartup = false

    /// From design/spike-results.md, Decisions: "Alpha click-through works, or
    /// the fallback mode becomes the default?" (keep the value M2 chose). The
    /// hidden `clickThroughFallback` setting (spec section 12) overrides it either
    /// way.
    static let clickThroughFallbackByDefault = false

    private let log = Logger(subsystem: "com.ethan.stickermine", category: "app")
    private var library: LibraryController?
    private var stickers: StickerManager?
    private var session: SessionCoordinator?
    private var statusItem: StatusItemController?
    private var hotkeys: HotkeyCenter?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
        if ProcessInfo.processInfo.arguments.contains(StyleGallery.launchArgument) {
            // Debug: render the style gallery and quit, without touching the library.
            StyleGallery.runAndQuit()
            return
        }
        startStickers()
        startCapture()
    }

    /// SIGTERM skips this, so nothing may depend on it; the debounced save has
    /// usually run already. A running screencapture is terminated and its
    /// temporary file deleted first (spec section 5.10).
    func applicationWillTerminate(_ notification: Notification) {
        session?.cancel()
        library?.flush()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    /// Loads the library (with launch repair) and restores every sticker on the
    /// connected displays. Every launch does this (spec section 13).
    private func startStickers() {
        let root: URL
        do {
            root = try LibraryStore.defaultRoot()
        } catch {
            log.error("no Application Support folder: \(error.localizedDescription, privacy: .public)")
            return
        }
        let store = LibraryStore(root: root)
        let library = LibraryController(store: store)
        let renderer = StyleRenderer(masterProvider: { id in MasterImage.image(at: store.pngURL(for: id)) })
        let screens = LiveScreenProvider()
        let stickers = StickerManager(library: library, screens: screens, renderer: renderer)
        let defaults = UserDefaults.standard
        // Keys from spec section 12; M6's Settings enum takes these over.
        stickers.setSharingHidden(defaults.object(forKey: "hideFromSharing") as? Bool ?? true)
        if defaults.object(forKey: "clickThroughFallback") as? Bool ?? Self.clickThroughFallbackByDefault {
            stickers.enableClickThroughFallback()
        }
        stickers.startObservingDisplayChanges()
        stickers.restoreAll()
        renderer.prewarm()
        self.library = library
        self.stickers = stickers
        log.notice("library \(Self.describe(library.loadResult), privacy: .public): \(library.library.stickers.count) stickers")

        session = SessionCoordinator(capture: CaptureService(), cutout: CutoutEngine(), stickers: stickers,
                                     library: library, store: store, renderer: renderer, screens: screens)
    }

    /// The capture triggers: the menu bar icon and the global shortcut
    /// (default ⌃⌥⌘S; M6 reads the stored one and adds the recorder).
    private func startCapture() {
        // Leftovers from a run that was killed mid-capture (spec section 5.10).
        CaptureService.deleteLeftovers()
        guard let session else { return }
        let shortcut = Shortcut.defaultCapture
        let statusItem = StatusItemController(shortcut: shortcut)
        statusItem.onCapture = { [weak session] in session?.startCapture() }
        statusItem.onQuit = { [weak self] in self?.quit() }
        session.onActiveChange = { [weak statusItem] active in statusItem?.sessionActive = active }
        let hotkeys = HotkeyCenter()
        hotkeys.register(shortcut) { [weak session] in session?.startCapture() }
        self.statusItem = statusItem
        self.hotkeys = hotkeys
    }

    /// The menu's Quit: cancel the session, then quit (spec section 5.2).
    private func quit() {
        session?.cancel()
        NSApp.terminate(nil)
    }

    private static func describe(_ result: LibraryStore.LoadResult) -> String {
        switch result {
        case .fresh: return "fresh"
        case .loaded: return "loaded"
        case .readOnlyNewer: return "read-only (saved by a newer Stickermine)"
        case .recoveredFromCorrupt: return "recovered from a corrupt library.json"
        }
    }
}
```

- [ ] **Step 5: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 289 tests in 36 suites passed` and `** TEST SUCCEEDED **` (`DebugMapleTests`' two tests and its suite are gone).

- [ ] **Step 6: Commit**

First run `grep -o 'clickThroughFallbackByDefault = [a-z]*' Stickermine/App/AppDelegate.swift` again: it must print what it printed before the overwrite in Step 4 (the value in M2 Task 12's commit message). If it doesn't, fix that line and rerun Step 5 before committing. The commit message records the value, as M2 Task 12 Step 9 does:

```bash
git add Stickermine/App/AppDelegate.swift StickermineTests/AppDelegateTests.swift
FALLBACK=$(grep -o 'clickThroughFallbackByDefault = [a-z]*' Stickermine/App/AppDelegate.swift)
git commit -m "Wire the capture shortcut and the menu bar icon; remove the Maple debug path" -m "Spike decision kept: ${FALLBACK}." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 18: Capture checks on this Mac (Review Focus items 2 and 3, Ethan at the Mac)

**Files:**
- Create: `design/capture-checks.md`

**Interfaces:**
- Consumes: the whole capture flow (Tasks 1–17), built Developer ID-signed and installed with `install.sh`.
- Produces: `design/capture-checks.md` with every row's result: the evidence for the index's Review Focus items 2 and 3 and this plan's milestone-specific items.

- [ ] **Step 1: Write the checklist**

`design/capture-checks.md` (complete file; the Result cells start empty):

````markdown
# Capture checks (M4)

M4's capture flow (spec sections 5, 6, 7, 13 and 14) needs a person at the Mac: Screen Recording, the system's crosshair and privacy alert, real displays and real images. An agent executing the plan asks Ethan to do each action and writes down what he reports and the named log lines; it never fills in a Result itself, and never grants, resets or removes a permission itself.

## Setup

1. Keep the real library out of the way (every confirmed capture becomes a history entry): in bash or zsh, `LIB="$HOME/Library/Application Support/com.ethan.stickermine"`, then `pkill -x Stickermine || true; if [ -e "$LIB" ]; then mv "$LIB" "$LIB.before-m4"; fi`.
2. `./install.sh`. It must print `Signing with: DEA1A3749B06CF3619F72152EFC35A48E380C4E4` (Developer ID): Screen Recording attaches to that signature and survives rebuilds; an ad-hoc build would need a new grant every time (spec section 14). It launches `/Applications/Stickermine.app` with `open`.
3. In a second terminal: `log stream --style compact --predicate 'subsystem == "com.ethan.stickermine"'`.
4. For rows 3–8, Screen Recording must start off: Ethan opens System Settings › Privacy & Security › Screen & System Audio Recording and, if Stickermine is listed, selects it and removes it with "−" (or uses a fresh user account). Nobody runs `tccutil`. A forum report says a removed entry can need a restart before macOS prompts again: if row 4 shows no prompt, restart and repeat from row 3.

| Field | Value |
|---|---|
| Date | |
| macOS (`sw_vers -productVersion`, `sw_vers -buildVersion`) | |
| Mac model | |
| Displays (name, resolution, scale, which is main, which is P3) | |
| `install.sh` signing line | |
| Screen Recording at the start (listed / not listed) | |

## Checks

| # | Check | How | Expected | Result |
|---|---|---|---|---|
| 1 | Menu bar icon | Look at the menu bar in Light and in Dark appearance (System Settings › Appearance). | The pickaxe glyph, crisp, about the size of the clock's digits, black on a light menu bar and white on a dark one. | |
| 2 | The menu | Right-click the icon; Esc. Control-click it; Esc. | Both show **New Sticker ⌃⌥⌘S** and **Quit Stickermine**; Esc closes the menu. | |
| 3 | No permission | With Screen Recording off and another app frontmost, press ⌃⌥⌘S. | No crosshair. The "Allow Screen Recording" panel appears centred on the display under the cursor, with **Continue**. No `screencapture exited` log line. | |
| 4 | Continue | Click **Continue**. | macOS shows its Screen Recording prompt (or opens System Settings). The panel now offers **Open System Settings**. | |
| 5 | Coming back without access | Leave Screen Recording off; click back on the panel. | **Relaunch Stickermine** appears next to **Open System Settings**. | |
| 5b | Trigger again | Leave Screen Recording off and the panel up; press ⌃⌥⌘S. | No crosshair; the panel stays and still offers **Relaunch Stickermine** next to **Open System Settings**. | |
| 6 | Granting | **Open System Settings**, turn Stickermine on (if macOS offers "Quit & Reopen", choose **Later**), click back on the panel. | The panel closes by itself. If it stays (the in-process check is stale), click **Relaunch Stickermine**: the app quits and is back within about 2 s. Write down which happened. | |
| 7 | First capture | Press ⌃⌥⌘S with Safari frontmost. | The crosshair appears (no permission panel). | |
| 8 | The system alert on the picker | Drag over a photo; let go. | The picker opens near the cursor. If macOS shows "Stickermine is requesting to bypass the system private window picker…", write down whether it lands over the picker, then click its button: the picker stays, and after clicking it once 1–4 and Esc still work. (If the alert doesn't appear, write `no alert` and repeat on a later capture.) | |
| 9 | Esc in the crosshair | ⌃⌥⌘S, then Esc. | Nothing appears, no HUD. Log `screencapture exited 0: cancelled`. `ls "$TMPDIR"stickermine-*.png` finds nothing. | |
| 10 | Control at mouse-up | ⌃⌥⌘S, then press and hold Control, drag, let go of the mouse, then of Control. | HUD "Let go of Control before releasing the mouse". | |
| 11 | Busy | Press ⌘⇧5 (the system screenshot toolbar), then ⌃⌥⌘S. | HUD "Couldn’t start a capture"; log `screencapture exited 1`. (If macOS runs the second capture anyway, write that down.) Esc the toolbar. | |
| 12 | Subjects | Capture two separate objects (two app icons, or two photos side by side). | Both tinted; Whole image off; four previews in the order Puffy, Outline, Shadow, None, numbered 1–4. Click one object: its tint fades to a faint one, the previews update within about 0.2 s. Click the other: Whole image turns on, both objects faintly tinted. Click an object: Whole image off, only that object strongly tinted. | |
| 13 | Fill holes | In the same picker, hover each preview, then the capture; click Fill holes twice. | Hovering shows **On**, **On**, **Off**, **Off**; elsewhere **Auto**. First click: **On** for all four previews; second: **Off**. Disabled while Whole image is on. | |
| 14 | Confirm and place | Press Esc to close row 13's picker. With Safari frontmost, capture an object and press 2 as soon as the picker appears, without clicking it. Move the pointer (onto the other display too, if there is one); click. | The 2 reaches the picker (no beep, nothing typed into Safari). The Outline sticker under the cursor looks exactly like its preview; on the other display it re-fits to at most half that display. The click places it there; the app that was frontmost before is frontmost again (its menu bar is back). | |
| 15 | Quit mid-capture | ⌃⌥⌘S; while the crosshair is up, in a terminal: `osascript -e 'quit app "Stickermine"'`. Then `pgrep -x screencapture; ls "$TMPDIR"stickermine-*.png`; `open /Applications/Stickermine.app`. Then open a picker and use the menu bar icon's Quit. | The crosshair goes away with the app; `pgrep` prints nothing and `ls` finds nothing. Quit from the menu closes the picker and quits; that capture is not in `library.json`. | |
| 16 | P3 colours | On a P3 display, capture a saturated red or green photo region; place it in None. Compare with Digital Color Meter ("Display native values"). | The sticker's colours match the original's. | |
| 17 | Cancel placement | `grep -c '"lastStyle" : "shadow"' "$LIB/library.json"`; capture, press 3, then Esc; capture again, press 3, then right-click; wait a second and run the `grep` again. | Nothing is placed either time; the count went up by 2 (both stickers stay in history). | |
| 18 | Flat colour | Capture an area of plain wallpaper or an empty window background. | "No subject found"; Whole image on and locked; Fill holes disabled. Placing None shows rounded corners. | |
| 19 | Text | Capture a paragraph of text. | Same as row 18 (or a subject, if Vision finds one; write it down). | |
| 20 | Window capture | ⌃⌥⌘S, press Space, click a Finder window. | The picker shows the window without its shadow. Placed, the sticker's corners are transparent (no black or grey corners). | |
| 21 | Tiny selection | ⌃⌥⌘S, drag less than 10 pt. | Nothing appears (a cancel). | |
| 22 | Full screen and memory | `ps -o rss= -p $(pgrep -x Stickermine)` before; capture a whole display (the largest one, 5K if available); `ps …` while the picker is open; place it; `ps …` 10 s later. | No crash; the picker appears within about a second. Write the three numbers (KB): the last is within about 150 MB of the first. | |
| 23 | Busy capture | Capture a dense area (a grid of a dozen photos or icons). | Either several subjects or "No subject found"; Whole image works either way. | |
| 24 | Visual Intelligence | In the crosshair, look for a Visual Intelligence hint or key. | Write down what is offered; if using it takes the selection elsewhere, the session ends without a HUD and the next ⌃⌥⌘S still works. | |
| 25 | Another app's ⌃⌥⌘S | If any installed app uses ⌃⌥⌘S, press it there. | Write down which app and what happened (Stickermine is expected to take the chord). | |
| 26 | Control Center indicator (spec 5.9) | Right after a capture, open Control Center and look at the screen-recording indicator. | Record whether Stickermine is listed and for how long. | |
| 27 | Stickers in new captures | Capture an area that includes a placed sticker. | The sticker is not in the capture (stickers are hidden from screenshots by default). | |
| 28 | What was saved | `cat "$LIB/library.json"`; `ls "$LIB/stickers"`; `sips -g pixelWidth -g dpiWidth "$LIB/stickers/"*.png`. | One entry per confirmed capture, with its `pixelWidth`, `pixelHeight`, `pixelsPerPoint` (2.0 on a Retina display) and `lastStyle` = the style picked; PNGs at 144 dpi on a Retina display; each placed sticker in its display's `placements`. | |
| 29 | Relaunch | `pkill -x Stickermine; open /Applications/Stickermine.app`. | Every placed sticker comes back in place and style. | |
| 30 | × in the picker | `grep -c '"lastStyle"' "$LIB/library.json"`; capture an object, then click the picker's × (top right); run the `grep` again; press ⌃⌥⌘S, then Esc. | The picker closes at once; no crash; the count is unchanged (cancelling saves nothing); the next ⌃⌥⌘S shows the crosshair. | |

## Outcome

Fill in after the run: which rows failed (if any), what was fixed, and the commits that fixed them.
````

- [ ] **Step 2: Run the checks with Ethan**

Ask Ethan to do the Setup and then rows 1–30 in order (5b right after 5). For each row write in Result exactly what he reports, plus the named log lines from the `log stream` terminal. A row that can't be run gets `not run: <reason>`.

- [ ] **Step 3: Fix failures before moving on**

For a failed row: reproduce it in a unit test where the logic allows (`PickerState`, `CaptureClassifier`, `CaptureService` with a shell command, `CutoutEngine` on a generated image), fix it, run the whole suite, `./install.sh`, repeat the row, and write the fix into the Outcome section. If every row passed, write `All rows passed.` in Outcome.

- [ ] **Step 4: Commit**

```bash
git add design/capture-checks.md
git commit -m "Record the M4 capture checks on this Mac" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Put the real library back**

The test captures must not stay in Ethan's real library (M6's first run needs a `library.json` with no stickers).

```bash
pkill -x Stickermine || true
LIB="$HOME/Library/Application Support/com.ethan.stickermine"
mv "$LIB" "$LIB.m4-checks"
if [ -e "$LIB.before-m4" ]; then mv "$LIB.before-m4" "$LIB"; fi
ls "$HOME/Library/Application Support" | grep stickermine
```

Expected: `com.ethan.stickermine.m4-checks` (plus earlier milestones' folders), and `com.ethan.stickermine` only if a folder existed before M4. Screen Recording stays granted. Nothing to commit.

---

### Task 19: Final build, full test run, contract update and CI dry run

**Files:**
- Modify: `design/plans/2026-10-12-stickermine-v1-plan.md` (Interface Contract, and the M5 row of the milestone table)
- Modify: `design/ci-dry-runs.md` (append a row)

**Interfaces:**
- Consumes: everything above.
- Produces: a green local build and test run, the index's contract updated with this milestone's changes, and a recorded CI dry run on the M4 head (or a recorded reason why not).

- [ ] **Step 1: Build**

```bash
pkill -x Stickermine || true
./build.sh
```

Expected: `Type-checking against MacOSX26.5.sdk...`, then `Building Stickermine...`, and it ends with `Built ./build/Stickermine.app`.

- [ ] **Step 2: Run the whole test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 289 tests in 36 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 3: Update the index's Interface Contract**

In `design/plans/2026-10-12-stickermine-v1-plan.md`, the blocks below go inside the index's existing ```` ```swift ```` fences; they are fenced as text here only because they list declarations rather than compilable code.

(a) Under `### Capture, picker, session (M4)`, replace that section's code block contents, from the line `enum CaptureOutcome: Equatable { case success(URL), controlHeldToClipboard, busyOrBlocked, cancelled }` through the closing `}` of `@MainActor final class SessionCoordinator {` (M2 Task 14 already replaced its `MasterImage` lines), with:

```text
enum CaptureOutcome: Equatable { case success(URL), controlHeldToClipboard, busyOrBlocked, cancelled }
enum CaptureClassifier {
    static func classify(file url: URL, fileExists: Bool, fileSize: Int, exitStatus: Int32, pasteboardChanged: Bool) -> CaptureOutcome   // [M4] file: added
}
@MainActor final class CaptureService {
    func capture(completion: @escaping (CaptureOutcome) -> Void)   // waits for modifiers, runs screencapture
    func cancelRunning()
    var isRunning: Bool { get }
    static func deleteLeftovers()
    struct Command { let executable: URL; let arguments: (URL) -> [String]; static let screencapture: Command }   // [M4]
    static let filePrefix: String; static let modifierPollInterval: TimeInterval                                // [M4] "stickermine-", 0.02
    init(command: Command = .screencapture, temporaryDirectory: URL = URL(fileURLWithPath: NSTemporaryDirectory()),
         pasteboardChangeCount: @escaping () -> Int = …, modifiersHeld: @escaping () -> Bool = …,
         modifierWait: TimeInterval = 1.0)                                                                       // [M4] all defaulted
    @discardableResult static func deleteLeftovers(in directory: URL) -> Int                                     // [M4]
}
struct LoadedCapture { let image: CGImage; let pixelsPerPoint: Double }
enum MasterImage {
    static func load(url: URL) throws -> LoadedCapture                             // [M4] ICC kept, decoded at once, DPI → ppp (2 when absent)
    static func pngData(_ image: CGImage, pixelsPerPoint: Double) throws -> Data   // writes DPI = 72 × ppp   [created in M2]
    enum Failure: Error { case cannotEncode, unreadable }                          // [M2]; [M4] unreadable
    struct FileInfo: Equatable { let pixelWidth: Int; let pixelHeight: Int; let pixelsPerPoint: Double? }   // [M2]
    static func fileInfo(at url: URL) -> FileInfo?                                 // [M2] size and DPI without decoding
    static func pixelsPerPoint(fromDPI dpi: Double) -> Double?                     // [M2] DPI / 72, rounded to 0.01
    static func image(at url: URL) -> CGImage?                                     // [M2] thread-safe
    static let cropPadding: Int                                                    // [M4] 2
    static func alphaBounds(of image: CGImage) -> CGRect?                          // [M4] pixels, top-left origin
    static func croppedToAlpha(_ image: CGImage, padding: Int = cropPadding) -> CGImage?   // [M4] alpha bounds + 2 px
}
enum MaskSampler {
    static func subject(atUnitTopLeft p: CGPoint, masks: [(index: Int, mask: CVPixelBuffer)]) -> Int?
    static let threshold: Float                                                    // [M4] 0.5
    static func value(in buffer: CVPixelBuffer, atUnitTopLeft p: CGPoint) -> Float?   // [M4]
    static func bounds(of buffer: CVPixelBuffer) -> CGRect?                        // [M4] unit, top-left
}
enum HoleFiller {
    static func fill(alpha: inout [Float], width: Int, height: Int, edge: Int)
    static let defaultEdge: Int; static let threshold: Float                       // [M4] 3, 0.5
}
enum CutoutError: Error, Equatable { case emptySelection, released, emptyMask, renderFailed }   // [M4]
final class CutoutAnalysis: @unchecked Sendable {
    let capture: LoadedCapture; let subjectIndices: [Int]
    let displayImage: CGImage                                                      // [M4] at most 1024 px long, for the picker
    init(capture: LoadedCapture, handler: ImageRequestHandler?, observation: InstanceMaskObservation?,
         masks: [(index: Int, mask: CVPixelBuffer)], context: CIContext, perform: @escaping CutoutEngine.Perform)   // [M4]
    func subject(atUnitTopLeft p: CGPoint) -> Int?
    func highlightMask(for index: Int) -> CGImage?
    func cutout(selection: Set<Int>, fillHoles: Bool) async throws -> CGImage   // pass 2 when the bbox is small
    func wholeImage() -> CGImage                                 // alpha kept, corners rounded 4% of short side
    func bounds(of selection: Set<Int>) -> CGRect?; static func refines(_ unitBounds: CGRect, width: Int, height: Int) -> Bool   // [M4]
    var refinedCutoutCount: Int { get }; func release()                            // [M4] release: the picker closed
    static let refineBelow: Double; static let refineMargin: Double                // [M4] 0.6, 0.08
    static let cornerRadiusFraction: Double; static let displayLongSide: Int       // [M4] 0.04, 1024
}
final class CutoutEngine: @unchecked Sendable {
    func prewarm(); func analyze(_ capture: LoadedCapture) async -> CutoutAnalysis
    typealias Perform = @Sendable (ImageRequestHandler) async throws -> InstanceMaskObservation?   // [M4]
    static let vision: Perform; init(perform: @escaping Perform = CutoutEngine.vision); let context: CIContext   // [M4]
    static func warmUpImage() -> CGImage?                                          // [M4] the throwaway image prewarm() runs Vision on
}
enum CutoutSource: Hashable { case wholeImage, subjects(Set<Int>, fillHoles: Bool), stored }   // [M4] Picker/PickerModel.swift
struct PickerState: Equatable {                                                    // [M4] spec 7's rules, pure
    enum FillHolesDisplay: Equatable { case auto, on, off }
    let subjects: [Int]; private(set) var selected: Set<Int>; private(set) var wholeImage: Bool
    private(set) var fillHolesChoice: Bool?; private(set) var hovered: StickerStyle?
    init(subjects: [Int]); var wholeImageLocked: Bool { get }; var fillHolesEnabled: Bool { get }
    mutating func setWholeImage(_ on: Bool); mutating func click(subject: Int?); mutating func toggleFillHoles()
    mutating func hover(_ style: StickerStyle, inside: Bool); func fillHoles(for style: StickerStyle) -> Bool
    var fillHolesDisplay: FillHolesDisplay { get }; func source(for style: StickerStyle) -> CutoutSource
}
@MainActor final class PickerModel: ObservableObject {                            // [M4]
    enum Mode: Equatable { case capture, restyle(sticker: UUID, highlight: StickerStyle) }
    struct Preview { let request: RenderRequest; let rendered: RenderedSticker; let shadow: StyleParameters }
    struct Confirmation { let sticker: UUID; let style: StickerStyle; let image: CGImage?; let pixelsPerPoint: Double }
    static func forCapture(_ analysis: CutoutAnalysis, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel
    static func forRestyle(_ record: StickerRecord, renderer: StyleRenderer, backingScale: CGFloat) -> PickerModel
    @Published private(set) var state: PickerState; @Published private(set) var previews: [StickerStyle: Preview]
    var onConfirm: ((Confirmation) -> Void)?; func confirm(_ style: StickerStyle); func finish()   // finish: drops cutouts still computing
}
extension StickerStyle { var displayName: String { get } }                       // [M4] Picker/PickerView.swift: "Puffy" "Outline" "Shadow" "None"
@MainActor final class PreviewHost: NSView { func show(_ preview: PickerModel.Preview) }   // [M4] a StickerView that never takes clicks (M5's pill can reuse it)
@MainActor final class PickerPanel: NSPanel                                       // [M4] [.borderless, .nonactivatingPanel]; canBecomeKey true, canBecomeMain false
@MainActor final class PickerController {                                         // [M4] Picker/PickerPanel.swift
    init(model: PickerModel); var onCancel: (() -> Void)?                          // Esc or ×
    func show(near cursor: CGPoint, visibleFrame: CGRect); func close()
}
@MainActor final class PlacementPanel: NSPanel                                    // [M4] explicit ignoresMouseEvents = false; canBecomeKey true
@MainActor final class PlacementView: NSView { var onPlace: (() -> Void)?; var onCancel: (() -> Void)? }   // [M4] takes every mouse-down
@MainActor final class PlacementSession {                                         // [M4]
    enum Outcome: Equatable { case placed(UUID), cancelled }
    init(sticker: UUID, style: StickerStyle, natural: CGSize, sourceLongSide: Double, renderer: StyleRenderer,
         stickers: StickerManager, screens: ScreenProvider, mouseLocation: @escaping () -> NSPoint = { NSEvent.mouseLocation })
    var onEnd: ((Outcome) -> Void)?; func start(); func place(); func cancel()
    static func fittedSize(natural: CGSize, in frame: CGRect) -> CGSize           // half the display, scaled down only
}
protocol ScreenRecordingAccess { func preflight() -> Bool; @discardableResult func request() -> Bool }   // [M4]
struct LiveScreenRecordingAccess: ScreenRecordingAccess                           // [M4] CGPreflightScreenCaptureAccess / CGRequestScreenCaptureAccess
struct PermissionPanelState: Equatable {                                          // [M4] what the panel offers, pure
    enum Action: Equatable { case requestAccess, openSettings, relaunch }
    var didRequest: Bool; var cameBackWithoutAccess: Bool; var actions: [Action] { get }
    static func whenShown(didRequest: Bool, panelIsUp: Bool, previous: PermissionPanelState) -> PermissionPanelState
}
@MainActor final class PermissionPanel: NSObject, NSWindowDelegate {              // [M4] Onboarding/PermissionPanel.swift
    static let didRequestKey: String                                               // "didRequestScreenCapture"
    init(access: ScreenRecordingAccess = LiveScreenRecordingAccess(), defaults: UserDefaults = .standard,
         screens: ScreenProvider, openURL: @escaping (URL) -> Void = …)
    func show(); func close(); func recheck(); var onGranted: (() -> Void)?
}
@MainActor final class HUD { static let shared: HUD; func show(_ message: String, symbol: String = …); func hide()   // [M4] UI/HUD.swift
    static let controlHeldMessage: String; static let couldNotStartMessage: String   // [M4] spec 5.7's two HUD lines
    static let readOnlyMessage: String; static let saveFailedMessage: String }       // [M4] newer library; master PNG not written
@MainActor final class StatusItemController: NSObject {                           // [M4] App/StatusItemController.swift
    init(shortcut: Shortcut?); var onCapture: (() -> Void)?; var onQuit: (() -> Void)?
    var sessionActive: Bool; func setShortcut(_ shortcut: Shortcut?)
}
@MainActor final class SessionCoordinator {
    init(capture: CaptureService, cutout: CutoutEngine, stickers: StickerManager, library: LibraryController, store: LibraryStore, renderer: StyleRenderer,
         screens: ScreenProvider? = nil, access: ScreenRecordingAccess = LiveScreenRecordingAccess(),
         showMessage: ((String) -> Void)? = nil, presentPermission: (() -> Void)? = nil, restoresFocus: Bool = true)   // [M4] defaulted extras
    var isActive: Bool { get }                                                     // M5: while true, double-clicks on stickers don't enter editing (spec 5.2)
    var onActiveChange: ((Bool) -> Void)?
    func startCapture(orderingOut window: NSWindow? = nil)                         // [M4] window (Home) ordered out before screencapture
    func startReplace(sticker: UUID)
    func cancel()
    enum Stage: Equatable { case idle, capturing, analyzing, picking, saving, placing }; private(set) var stage: Stage   // [M4]
    var onPlaced: ((_ placement: UUID, _ sticker: UUID) -> Void)?                 // [M4] M6's support-ask counter
    private(set) var currentSticker: UUID?                                         // [M4] Delete from History cancels its session
}
```

(b) Under `### Hotkeys and settings`, replace the lines from `struct Shortcut: Codable, Equatable {` to its closing `}` with:

```text
struct Shortcut: Codable, Equatable {                            // [M4] App/Shortcut.swift; encoded as {"k", "m"}
    var keyCode: UInt32; var modifiers: UInt32                  // Carbon mask
    static let defaultCapture: Shortcut                         // keyCode 1, controlKey|optionKey|cmdKey
    var label: String { get }                                    // "⌃⌥⌘S", glyph order ⌃ ⌥ ⇧ ⌘
    var isAcceptable: Bool { get }                               // contains ⌘ or ⌃, or is an F-key
    static let fKeyCodes: [UInt32]; var menuKeyEquivalent: String? { get }; static func keyName(_ code: UInt32) -> String   // [M4]
}
```

and replace the line that starts with `@MainActor final class HotkeyCenter {` with:

```text
@MainActor final class HotkeyCenter { func register(_ s: Shortcut?, handler: @escaping () -> Void); func suspend(); func resume()
    init(); static let signature: OSType; private(set) var lastStatus: OSStatus; var isRegistered: Bool { get }; func invalidate(); func fire() }   // [M4] 'STKM'; register(nil) registers nothing
```

(c) Under `### Rendering (M3)`, insert directly below the line that starts with `    func invalidateCache(for sticker: UUID)` these two lines:

```text
    func setInFlightMaster(_ image: CGImage?, for sticker: UUID)                                    // [M4] the picker's cutouts before their PNG exists; also forgets the inscribed radius
    var inFlightMasterCount: Int { get }                                                            // [M4] tests: the picker lets go of them
```

(d) In the milestone table at the top, so M5 can't miss the session gate (spec section 5.2), replace the end of the M5 row:

```text
editing-end rules | M2, M3, M4 |
```

with:

```text
editing-end rules, no double-click editing while `SessionCoordinator.isActive` (spec 5.2; M4 note) | M2, M3, M4 |
```

Check:

```bash
grep -c '\[M4\]' design/plans/2026-10-12-stickermine-v1-plan.md
grep -c 'classify(file url: URL' design/plans/2026-10-12-stickermine-v1-plan.md
grep -c 'setInFlightMaster' design/plans/2026-10-12-stickermine-v1-plan.md
grep -c 'static func classify(fileExists' design/plans/2026-10-12-stickermine-v1-plan.md
grep -c 'no double-click editing while `SessionCoordinator.isActive`' design/plans/2026-10-12-stickermine-v1-plan.md
```

Expected: a number above `25`, then `1`, `1`, `0` and `1`.

- [ ] **Step 4: Commit locally**

```bash
git add design/plans/2026-10-12-stickermine-v1-plan.md
git commit -m "Record M4's contract changes in the plan index" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: CI dry run (needs Ethan's explicit yes now)**

If `git remote get-url origin` fails, the GitHub repo doesn't exist yet: append the "not run" row and stop here (go to Step 6):

```bash
REASON="no GitHub repo yet"
echo "| $(date +%F) | M4 end (Task 19) | $(git rev-parse --short HEAD) | none | not run | Ethan: $REASON |" >> design/ci-dry-runs.md
```

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
  echo "| $(date +%F) | M4 end (Task 19) | ${ROW} | |" >> design/ci-dry-runs.md
fi
```

Expected: `gh run watch` exits 0 and the appended row ends `| success | |`. If Ethan says no, append the "not run" row above with his reason in `REASON`. If it prints `error: the dispatched run never appeared`, nothing was recorded: check `gh run list --workflow release.yml` and rerun from `BEFORE=`. On a failed run, read `gh run view "$RUN_ID" --log-failed`. An unknown-symbol error means a macOS 27-only API slipped in (fix it, run the suite, commit, and ask before pushing again); an `actool` error about `MenuBarGlyph` means Xcode 26.6's asset compiler rejected the SVG (fall back to a PDF of the same glyph, which the asset keeps as vector the same way, and repeat); a project-format error means the project file changed from objectVersion 77.

- [ ] **Step 6: Commit the record**

```bash
git add design/ci-dry-runs.md
git commit -m "Record M4's CI dry run" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Push only with Ethan's yes (`git push`).

---

## Notes for later milestones

- **M5** gates double-click editing on the session: while `SessionCoordinator.isActive`, double-clicks on stickers don't enter editing (spec section 5.2); give the editor a `() -> Bool` that AppDelegate fills with `{ session.isActive }`. Starting a session already calls `stickers.endEditing(discardGesture: true)`, so M5's real gesture teardown runs there. The toolbar pill's Style row can reuse `StickerStyle.displayName` and `PreviewHost` (a `StickerView` behind a click-transparent container) with renders through the same `StyleRenderer`.
- **M6** stores the shortcut: `Shortcut`'s `CodingKeys` are already `k` and `m` (spec 12's `captureShortcut`). `AppDelegate.startCapture()` then registers the stored value (or nothing when cleared) instead of `Shortcut.defaultCapture` and calls `statusItem.setShortcut(_:)`; the recorder calls `hotkeys.suspend()`/`resume()`. `StatusItemController.makeMenu` gets **Open Stickermine…** between New Sticker and the separator (spec 13's order) and hiding uses the status item's `isVisible`. Home's New Sticker calls `session.startCapture(orderingOut: homeWindow)`; a history-grid click calls `session.startReplace(sticker:)`; Delete from History calls `session.cancel()` first when `session.currentSticker` is that sticker; the support-ask counter uses `session.onPlaced` (skipping tutorial stickers); `AppDelegate` sets `session.onActiveChange` for the status item, so Home must chain onto it, not replace it. The updater calls `session.cancel()` (it terminates `screencapture` and deletes its file) and `library.flush()` before spawning its helper. Home re-checks Screen Recording when it becomes key (spec 14) and can show the same `PermissionPanel`; `Settings.register(in:)` includes `PermissionPanel.didRequestKey`.
- **M7**'s README and PRIVACY describe the Screen Recording permission and the periodic system alert, using what `design/capture-checks.md` rows 3–8 recorded, and the README mentions that a capture can list Stickermine in Control Center's screen-recording indicator (spec 5.9), as row 26 recorded.
