# M2 Model, Persistence and Displays Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Stickermine its data model and its sticker windows: `library.json` and the master PNGs under Application Support (atomic writes, the version gate, corrupt-file recovery, launch repair), debounced saves, display identity (ghost, mirror and null-ID filtering, the fingerprint fallback), the closest-size layout rule, a baseline renderer, and a `StickerManager` that restores every sticker on launch and keeps panels in step with displays being unplugged, replugged, mirrored, resized, slept and woken, without ever writing the library because of a display event. A temporary `-debugPlaceMaple` launch argument puts the bundled Maple into the library as a real sticker, so all of it can be checked end to end before capture exists.

**Architecture:** Pure, AppKit-free types hold the rules: `Library` (the Codable model with lenient decoding), `LayoutResolver` (pose for a display size), `DisplayRegistry` (which displays count and how they are identified), `LibraryStore` (files on disk), `StyleParameters` (style math) and `StickerGeometry` (pose ↔ screen rect). `LibraryController` (main actor) owns the in-memory library and saves it 0.5 s after the last change. `StyleRenderer` renders a size-capped bitmap plus an `AlphaMask` off the main actor (every style draws the plain master in this milestone; M3 replaces the per-style drawing). `StickerManager` owns one `StickerPanel` per placement, reads displays through a `ScreenProvider` protocol (live: `NSScreen.screens`; tests: a fake), and runs one idempotent reconcile, debounced 450 ms, that always re-applies visibility and frames from the model and uses a snapshot diff only to skip re-resolving and re-rendering. `AppDelegate` loads the library, restores stickers and flushes on terminate. The M1 spike is deleted.

**Tech Stack:** Swift 5 language mode, AppKit, Core Graphics, ColorSync (`CGDisplayCreateUUIDFromDisplayID`), ImageIO, `os.Logger`, Swift Testing, `xcodebuild` (Xcode 27 beta locally, Xcode 26.6 on CI).

**Spec:** `design/specs/2026-10-12-stickermine-v1-design.md`. This milestone implements section 11 (all of it: identity, ignore rules, main display, fingerprint fallback, change handling, the hard rule and its exceptions, positions and clamping, disconnected/new displays, mirroring, backing-scale re-render; cross-display dragging is M5's gesture but its model operations exist here), section 12 (all of it: location, `library.json`, z-order, decoding, writes, launch repair, delete from history, and the two settings the sticker windows read, `hideFromSharing` and the hidden `clickThroughFallback`; Home's thumbnails and the other settings keys belong to M6), section 4 (testability; the panel policy for every panel created here), section 8 (`StyleParameters` only: the parameter math and `shadowMargin`), section 9 (the frame rule, the memory baseline, sharing type, the fallback click-through mode, the stale-window rebuild switch) and the section 18 unit tests for `LayoutResolver`, `LibraryStore`, `DisplayRegistry` and style parameters. The plan index with the Interface Contract is `design/plans/2026-10-12-stickermine-v1-plan.md`; M1's plan is `design/plans/2026-10-12-m1-foundation.md`.

## Contract changes

Signature changes (every existing call site still compiles):

1. `StickerManager.place(sticker:style:centerOnScreen:pointSize:)` returns `UUID?` (`@discardableResult`): the new placement's ID, or nil when the library is read-only, the sticker is unknown or there is no display. M4's placement session needs the ID for the support-ask counter and logging.
2. `PanelPolicy.makeStickerPanel(contentRect: NSRect, hideFromSharing: Bool = true) -> StickerPanel`. Verified while writing this plan (macOS 27.2, Xcode 27 beta test host): once a window's `sharingType` has been set to `.none`, a later `.readOnly` leaves the getter at `.none` whatever the window was created with (a panel created `.readOnly` switches to `.none` but not back). Research claim C1 saw capture follow a none→readOnly flip, so the window server may honour it and only the getter lag; recreating the panel is correct either way. So a panel must start with the right value, and `StickerManager.setSharingHidden(false)` recreates the panels that stay hidden. Re-checked 2026-10-22 on macOS 27.2 (Darwin 27.2.0): the getter still sticks. The tests accept either behaviour, so a macOS whose getter follows the setter only skips the recreation. M1's comment in `PanelPolicy` ("StickerManager switches live panels to .readOnly when it is off") was wrong on 27.2; Task 11 replaces it.
3. `DisplayInfo` gains `let inMirrorSet: Bool` (`CGDisplayIsInMirrorSet`), with an explicit initializer whose `inMirrorSet` parameter defaults to `false`: the reconcile snapshot is `[uuid: (frame, backingScaleFactor, mirror state)]` (spec section 11).
4. `LibraryController.init(store: LibraryStore, saveDelay: TimeInterval = 0.5)` and `StickerManager.init(library:screens:renderer:reconcileDelay: TimeInterval = 0.45)`: the delays are injectable for tests; the contract's calls are unchanged.

Moved earlier: `StyleParameters`, `RenderRequest`, `RenderedSticker`, `AlphaMask` and `StyleRenderer` (listed under "Rendering (M3)" in the index) are created here with their contract signatures, as the index's M2 row says ("a baseline StyleRenderer"). M3 keeps the signatures and replaces the drawing inside `render`.

Additions (Task 14 copies them into the index):

- Model: memberwise-style initializers with defaults for `Placement`, `StickerRecord`, `DisplayRecord` and `Library`; `Library` helpers `sticker(_:)`, `placement(_:)`, `displayKey(containing:)`, `placementCount(of:)`, `removePlacement(_:)`, `removeSticker(_:)`, `moveDisplayRecord(from:to:)`; `enum LibraryCoding { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }`.
- `DisplaySize.isLandscape`, `DisplaySize.area`; `LayoutResolver.tieTolerance`, `closestStoredSize(in:to:)`, `distance(from:to:)`, `isCloser(_:than:to:)`.
- `DisplayRegistry.ghostVendor`, `ghostModel`, `sharedSerial`; `LiveScreenProvider.info(for:)`.
- `LibraryStore`: `LoadResult.library`, `StoreError.readOnly`, `root`, `libraryURL`, `stickersDirectory`, `root(inApplicationSupport:)`, `defaultPixelsPerPoint`, `corruptStamp(for:)`, `repair(_:)`. `LibraryController`: `store`, `loadResult`, `hasPendingSave`, `hasUnsavedChanges`, `refreshMetadata(_:)`.
- `MasterImage` (the contract's M4 type, started here): `pngData(_:pixelsPerPoint:)` (contract signature), `FileInfo`, `fileInfo(at:)`, `pixelsPerPoint(fromDPI:)`, `image(at:)`. M4 adds `load(url:)` and `LoadedCapture`.
- `StyleParameters` constants; `StyleRenderer.RenderError`, `maxMaskLongSide`, `alphaFloor`, `canvas(for:)`, `renderBaseline(master:request:)`, `clampAlphaAndBuildMask(pixels:width:height:)`.
- `enum StickerGeometry` (new): `reachableInset`, `Layout`, `boundingSize(of:rotation:)`, `center(of:in:)`, `pose(center:scale:in:)`, `reachableCenter(_:visibleFrame:)`, `clampedRect(size:center:within:)`, `layout(for:natural:on:)`.
- `@MainActor final class ClickThroughFallback` (new): the hidden fallback click-through mode.
- `StickerView.show(_:shadow:style:)` (M1 deferred it to M2): the baseline calls `showContents(rendered.contents, pointSize: rendered.pointBounds, shadow: nil)`.
- `StickerManager`: `DisplaySnapshot`, `rebuildsPanelsAfterSystemEvents`, `systemEventRecheckDelay`, `reconcileCount`, `renderRequestsIssued`, `placementsWithPanels`, `refreshPanel(for:)`, `closeAllPanels()`, `rebuildAllPanels()`, `commitRender(_:for:placement:)`, `recordKeyForUserEdit(on:)`, `enableClickThroughFallback()`, `isClickThroughFallbackEnabled`, `startObservingDisplayChanges()`, `systemEvent(recheckLater:)`, `ordersOutImmediately(for:)`, `displayReconfigured(_:flags:)`, `handleDisplayRemoved(displayID:)`, `recordAssignments(displays:records:)`, `display(containing:in:)`.
- `AppDelegate.clickThroughFallbackByDefault`.
- Test support: `enum Fixtures` (`StickermineTests/TestFixtures.swift`) and `final class FakeScreens: ScreenProvider` (`StickermineTests/FakeScreens.swift`).

Deleted (as M1's notes require): `Stickermine/Stickers/SpikeController.swift` and the `-spike` branch in `AppDelegate`.

Temporary: `Stickermine/App/DebugMaple.swift` and the `-debugPlaceMaple` branch in `AppDelegate`. M4 deletes both once real captures can be placed (and drops the `DebugMaple` lines from `AppDelegateTests.theSpikeIsGoneAndOnlyTheDebugMaplePathRemains`).

## Global Constraints

All constraints in the index apply. Milestone-specific ones, verbatim from the spec:

- "Guard against `nil` and `kCGNullDirectDisplay` first: a 0 ID silently returns the main display's UUID. Never persist display IDs; keep an in-memory ID → UUID map rebuilt on each change. CG functions return −1 / `0xFFFFFFFF` for a vanished ID, so never test them with `!= 0`." (section 11)
- "**"Main display"** means `NSScreen.screens[0]` (the one with the menu bar) everywhere in this spec, never `NSScreen.main`." (section 11)
- "observe `NSApplication.didChangeScreenParametersNotification` (not the macOS 27-only typed message)" (section 11)
- "Display events, `windowDidMove` and `windowDidChangeScreen` never write. Clamping happens when drawing and is saved only when it results from a user gesture." (section 11)
- "**Writes:** atomic (`Data.write(to:options: .atomic)`). Write the PNG before the index; for deletes, remove the PNG then save the index. Save 0.5 s after the last change (never per drag event) and flush in `applicationWillTerminate` and before the updater's helper runs. SIGTERM skips that hook, so nothing may depend on it. Encode and write the JSON on the main actor; write PNGs on a background queue and commit to the index on main." (section 12)
- "Every field added after v1 is optional (or decoded with `decodeIfPresent ?? default`). Enums are stored as strings and mapped leniently (unknown style → `puffy`). Size keys are strings." (section 12)
- "**Testability:** pure logic (`LayoutResolver`, `DisplayRegistry` filtering and fingerprinting, `LibraryStore` decoding and repair, style parameter scaling, click-to-subject mapping, shortcut storage, capture outcome classification) has no AppKit dependencies. `LibraryStore` takes its root directory and a `UserDefaults` instance as parameters." (section 4; pinned by `LibraryModelTests.pureLogicFilesStayFreeOfAppKit`. The index contract's `LibraryStore.init(root:)` is kept: nothing in the store reads a setting, so it takes no `UserDefaults`; M6's `Settings.register(in:)` is where an injected `UserDefaults` matters.)
- "Tests give `LibraryStore` a temporary directory and `UserDefaults(suiteName:)`, never the real Application Support or `.standard`." (section 18) In this milestone nothing under test reads `UserDefaults` at all: only `AppDelegate`, which tests never start, reads the two settings.
- "**Memory:** the bitmap is rendered at the on-screen pixel size, capped at 2048 px on the long side (above that, the layer scales the bitmap up). On removal, set contents to nil before `orderOut` and close" (section 9)
- Plan rule: every display a test builds sits at x ≥ 40 000 pt, off every real screen, and every test that orders a panel in closes it before the test suspends or returns, so the test host never shows a window and `AppDelegateTests.testHostShowsNoWindows` holds.
- As in M1: run every command from the repository root (`/Users/ethan/Developer/stickermine`) in bash or zsh, not fish. The test command is `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`, with `-only-testing:StickermineTests/<Suite>` for one suite. Ignore the harmless `com.apple.linkd.autoShortcut` lines the test host prints.

## Review Focus

Owned from the index: **item 1, display unplugged/replugged, lid closed/opened, sleep/wake with stickers on screen** ("stickers vanish with their display and come back in exactly the same place; nothing jumps to another display; nothing is saved"). Pinned by `StickerManagerTests` (`restoreCreatesPanelsOnlyForConnectedDisplays`, `aDisconnectedDisplaysPanelsAreOrderedOutKeptAndNothingIsWritten`, `aReconnectedDisplayGetsTheSamePanelsBackInPlace`, `noUsableDisplayChangesNothing`, `framesAreReappliedEvenWhenNothingChanged`, `aResolutionChangeBorrowsTheClosestSizeAndWritesNothing`, `aRemoveCallbackOrdersThatDisplayOutAtOnce`), and by the hardware checklist in Task 13 (`design/display-checks.md`), which compares `shasum` of `library.json` before and after every event.

Milestone-specific failure modes:

1. **A display event writes the library**, through AppKit moving a window, the `lastSeen` refresh or a fingerprint adoption. Expect: after any number of display events the file is byte-identical; only a user action writes. Pinned by `aDisconnectedDisplaysPanelsAreOrderedOutKeptAndNothingIsWritten`, `aReconnectedDisplayGetsTheSamePanelsBackInPlace` and `aResolutionChangeBorrowsTheClosestSizeAndWritesNothing` (each compares the file's bytes and `hasPendingSave`), `aFingerprintAdoptedDisplayShowsTheOldRecordUntilAUserEdit`, `LibraryControllerTests.metadataRefreshesWaitForTheNextSave`, and the hash column of Task 13's checklist.
2. **A newer or corrupt `library.json` is overwritten or lost.** Expect: a newer file is shown and never written, renamed or repaired; a corrupt file is renamed aside, never deleted. Pinned by `LibraryStoreTests.aNewerLibraryIsShownButNeverWritten`, `aNewerLibraryThisBuildCantReadIsStillNeverRenamed`, `aCorruptFileIsSetAsideAndHistoryRebuiltFromThePNGs`, `LibraryControllerTests.aReadOnlyLibraryIgnoresChanges`, `StickerManagerTests.aNewerLibraryIsShownButCantBeEdited`, and Task 12 Step 8, items 9–10.
3. **Turning "Hide stickers from screen sharing" off doesn't un-hide them** (the sticky `.none` above). Expect: after the setting goes off, every sticker panel reports `.readOnly` and is in the same place. Pinned by `StickerManagerTests.theSharingSettingAppliesToEveryPanelLive`, `StickerManagerTests.aPanelRecreatedForSharingKeepsItsBitmap` (the new panel shows the old bitmap at once, with no new render), `PanelPolicyTests.aPanelForVisibleSharingStartsReadOnly`, and Task 12 Step 8, item 8.

## Files

| Path | Action | Responsibility |
|---|---|---|
| `Stickermine/Model/Library.swift` | Create (Task 1) | `StickerStyle`, `Pose`, `Placement`, `StickerRecord`, `DisplayRecord`, `Library` with lenient decoding; library helpers; `LibraryCoding` |
| `Stickermine/Model/LayoutResolver.swift` | Create (Task 2) | `DisplaySize` and the closest-size pose rule with its tie-break |
| `Stickermine/Model/DisplayRegistry.swift` | Create (Task 3) | `DisplayInfo`; ghost, mirror, null and duplicate filtering; fingerprint fallback; UUID strings |
| `Stickermine/Capture/StyleParameters.swift` | Create (Task 4) | Style parameters per sticker pixel size; shadow margin |
| `Stickermine/Capture/MasterImage.swift` | Create (Task 5) | Master PNG bytes with DPI; PNG size and DPI without decoding; loading |
| `Stickermine/Model/LibraryStore.swift` | Create (Task 5) | Files on disk: load with version gate, corrupt recovery and launch repair; atomic saves; PNG paths |
| `Stickermine/Model/LibraryController.swift` | Create (Task 6) | In-memory library, 0.5 s debounced save, flush, quiet metadata refresh |
| `Stickermine/Stickers/StickerGeometry.swift` | Create (Task 7) | Pose ↔ screen point; clamps; the layout of one placement on one display |
| `Stickermine/Capture/StyleRenderer.swift` | Create (Task 8) | `RenderRequest`, `RenderedSticker`, `AlphaMask`; the baseline size-capped render |
| `Stickermine/Stickers/StickerView.swift` | Modify (Task 8) | Adds `show(_:shadow:style:)` |
| `Stickermine/Model/ScreenProvider.swift` | Create (Task 9) | `ScreenProvider` protocol; `LiveScreenProvider` over `NSScreen.screens` |
| `Stickermine/Stickers/ClickThroughFallback.swift` | Create (Task 10) | The hidden fallback click-through mode (the only writer of the mouse-event flag) |
| `Stickermine/Stickers/StickerManager.swift` | Create (Task 11) | Panels from the model; reconcile; display events; place, remove, delete; sharing; rebuild |
| `Stickermine/Stickers/PanelPolicy.swift` | Modify (Task 11) | `makeStickerPanel(contentRect:hideFromSharing:)` |
| `Stickermine/App/AppDelegate.swift` | Modify (Task 12) | Load the library, restore stickers, flush on terminate; spike removed; temporary Maple branch |
| `Stickermine/App/DebugMaple.swift` | Create (Task 12); M4 deletes | `-debugPlaceMaple`: Maple as a real library sticker |
| `Stickermine/Stickers/SpikeController.swift` | Delete (Task 12) | (the M1 spike) |
| `StickermineTests/TestFixtures.swift` | Create (Task 3) | Off-screen displays, records, temporary folders, test images and PNGs |
| `StickermineTests/FakeScreens.swift` | Create (Task 9) | A `ScreenProvider` the tests set |
| `StickermineTests/LibraryModelTests.swift` | Create (Task 1) | Style order, lenient decoding, field names, helpers, AppKit-free pure files |
| `StickermineTests/LayoutResolverTests.swift` | Create (Task 2) | Exact key, orientation, distance, both tie-breaks over shuffled dictionaries, scale, writes |
| `StickermineTests/DisplayRegistryTests.swift` | Create (Task 3) | Ghost, mirror, null ID, duplicates, UUID guard, fingerprint (serial 0, 0x01010101, connected twin) |
| `StickermineTests/StyleParametersTests.swift` | Create (Task 4) | Values at 800 px, linear scaling, choke, margins |
| `StickermineTests/LibraryStoreTests.swift` | Create (Task 5) | Round trip, newer, corrupt, missing PNG, stray PNG with DPI, tutorial flags, lenient file |
| `StickermineTests/LibraryControllerTests.swift` | Create (Task 6) | Debounce, flush, read-only, quiet metadata |
| `StickermineTests/StickerGeometryTests.swift` | Create (Task 7) | Centres, clamps, borrowed-pose reachability |
| `StickermineTests/StyleRendererTests.swift` | Create (Task 8) | Pixel size, 2048 cap, baked rotation and flip, mask, alpha floor, colour space |
| `StickermineTests/StickerViewTests.swift` | Modify (Task 8) | One test for `show(_:shadow:style:)` |
| `StickermineTests/LiveScreenProviderTests.swift` | Create (Task 9) | Real screens map to UUID-keyed `DisplayInfo`; main = `screens[0]` |
| `StickermineTests/ClickThroughFallbackTests.swift` | Create (Task 10) | Hit testing on masks; one sticker takes the mouse at a time |
| `StickermineTests/PanelPolicyTests.swift` | Modify (Tasks 10, 11) | Fallback file allowed to write the flag; a panel can start `.readOnly` |
| `StickermineTests/StickerManagerTests.swift` | Create (Task 11) | Restore, disconnect/reconnect, no display, frames, resolution and scale changes, CG remove, place, re-key, remove, delete, sharing, fallback, rebuild, renders, debounce, read-only |
| `StickermineTests/AppDelegateTests.swift` | Modify (Task 12) | The spike is gone; the Maple path is the only debug path |
| `design/display-checks.md` | Create (Task 13) | Hardware checks for displays, sleep, lock and mirroring, with results |
| `design/ci-dry-runs.md` | Modify (Task 14) | M2's dry-run row |
| `design/plans/2026-10-12-stickermine-v1-plan.md` | Modify (Task 14) | The contract changes and additions above |

---

### Task 1: The library model

**Files:**
- Create: `Stickermine/Model/Library.swift`
- Test: `StickermineTests/LibraryModelTests.swift`

**Interfaces:**
- Consumes: `SourceFiles` (M1, `StickermineTests/TestSupport.swift`).
- Produces:

```text
enum StickerStyle: String, Codable, CaseIterable {             // UI order: puffy, outline, shadow, none
    case puffy, outline, shadow, none
    init(from decoder: Decoder) throws                          // unknown raw value → .puffy
    var defaultFillHoles: Bool { get }                          // puffy/outline true, shadow/none false
}
struct Pose: Codable, Equatable { var x: Double; var y: Double; var scale: Double }
struct Placement: Codable, Equatable, Identifiable {
    let id: UUID; var sticker: UUID; var style: StickerStyle
    var flipped: Bool; var onTop: Bool; var rotation: Double; var poses: [String: Pose]
    init(id: UUID = UUID(), sticker: UUID, style: StickerStyle, flipped: Bool = false, onTop: Bool = false,
         rotation: Double = 0, poses: [String: Pose])
}
struct StickerRecord: Codable, Equatable, Identifiable {
    let id: UUID; var created: Date; var pixelWidth: Int; var pixelHeight: Int
    var pixelsPerPoint: Double; var lastStyle: StickerStyle; var tutorial: Bool
    init(id: UUID, created: Date, pixelWidth: Int, pixelHeight: Int, pixelsPerPoint: Double,
         lastStyle: StickerStyle, tutorial: Bool = false)
    var naturalPointSize: CGSize { get }
}
struct DisplayRecord: Codable, Equatable {
    var name: String; var vendor: UInt32; var model: UInt32; var serial: UInt32; var builtin: Bool
    var lastSeen: Date; var placements: [Placement]
    init(name: String, vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool, lastSeen: Date,
         placements: [Placement])
}
struct Library: Codable, Equatable {
    static let currentVersion = 1
    var version: Int; var stickers: [StickerRecord]; var displays: [String: DisplayRecord]
    init(version: Int = Library.currentVersion, stickers: [StickerRecord], displays: [String: DisplayRecord])
    static var empty: Library { get }
}
extension Library {
    func sticker(_ id: UUID) -> StickerRecord?
    func placement(_ id: UUID) -> Placement?
    func displayKey(containing placement: UUID) -> String?
    func placementCount(of sticker: UUID) -> Int
    @discardableResult mutating func removePlacement(_ id: UUID) -> Placement?
    mutating func removeSticker(_ id: UUID)
    mutating func moveDisplayRecord(from oldKey: String, to newKey: String)
}
enum LibraryCoding { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }
```

- [ ] **Step 1: Write the failing test**

`StickermineTests/LibraryModelTests.swift` (complete file):

```swift
import Foundation
import Testing
@testable import Stickermine

struct LibraryModelTests {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try LibraryCoding.decoder().decode(type, from: Data(json.utf8))
    }

    @Test func stylesAreInTheUIOrder() {
        #expect(StickerStyle.allCases == [.puffy, .outline, .shadow, .none])
        #expect(StickerStyle.allCases.map(\.rawValue) == ["puffy", "outline", "shadow", "none"])
    }

    @Test func fillHolesDefaultsOnOnlyForTheRimmedStyles() {
        #expect(StickerStyle.puffy.defaultFillHoles)
        #expect(StickerStyle.outline.defaultFillHoles)
        #expect(!StickerStyle.shadow.defaultFillHoles)
        #expect(!StickerStyle.none.defaultFillHoles)
    }

    @Test func anUnknownStyleDecodesAsPuffy() throws {
        #expect(try decode([StickerStyle].self, #"["glitter", "none", "outline"]"#) == [.puffy, .none, .outline])
    }

    @Test func missingOptionalFieldsTakeTheirDefaults() throws {
        let placement = try decode(Placement.self, """
            {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "sticker": "7F9619FF-8B86-D011-B42D-00C04FC964FF"}
            """)
        #expect(placement.style == .puffy)
        #expect(!placement.flipped)
        #expect(!placement.onTop)
        #expect(placement.rotation == 0)
        #expect(placement.poses.isEmpty)

        let sticker = try decode(StickerRecord.self, """
            {"id": "6F9619FF-8B86-D011-B42D-00C04FC964FF", "pixelWidth": 840, "pixelHeight": 620, "future": 1}
            """)
        #expect(sticker.pixelsPerPoint == 2)
        #expect(sticker.lastStyle == .puffy)
        #expect(!sticker.tutorial)

        let display = try decode(DisplayRecord.self, "{}")
        #expect(display.placements.isEmpty)
        #expect(display.serial == 0)

        let library = try decode(Library.self, #"{"version": 1}"#)
        #expect(library == .empty)
    }

    @Test func encodesTheSpecFieldNames() throws {
        let sticker = UUID()
        let placement = Placement(sticker: sticker, style: .puffy, poses: ["1920x1080": Pose(x: 0.81, y: 0.22, scale: 1)])
        let library = Library(
            stickers: [StickerRecord(id: sticker, created: Date(timeIntervalSince1970: 1_760_000_000),
                                     pixelWidth: 840, pixelHeight: 620, pixelsPerPoint: 2, lastStyle: .outline)],
            displays: ["25A19A46-A9B2-42B2-B1F8-389D978CBBC2": DisplayRecord(
                name: "LG UltraFine", vendor: 7789, model: 23305, serial: 0, builtin: false,
                lastSeen: Date(timeIntervalSince1970: 1_760_000_000), placements: [placement])])
        let data = try LibraryCoding.encoder().encode(library)
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(json["version"] as? Int == 1)
        let stickerJSON = try #require((json["stickers"] as? [[String: Any]])?.first)
        #expect(Set(stickerJSON.keys) == ["id", "created", "pixelWidth", "pixelHeight", "pixelsPerPoint", "lastStyle", "tutorial"])
        #expect(stickerJSON["created"] as? String == "2025-10-09T08:53:20Z")
        #expect(stickerJSON["lastStyle"] as? String == "outline")
        let displays = try #require(json["displays"] as? [String: [String: Any]])
        let display = try #require(displays["25A19A46-A9B2-42B2-B1F8-389D978CBBC2"])
        #expect(Set(display.keys) == ["name", "vendor", "model", "serial", "builtin", "lastSeen", "placements"])
        let placementJSON = try #require((display["placements"] as? [[String: Any]])?.first)
        #expect(Set(placementJSON.keys) == ["id", "sticker", "style", "flipped", "onTop", "rotation", "poses"])
        let poses = try #require(placementJSON["poses"] as? [String: [String: Double]])
        #expect(poses["1920x1080"] == ["x": 0.81, "y": 0.22, "scale": 1])
        #expect(try LibraryCoding.decoder().decode(Library.self, from: data) == library)
    }

    @Test func datesWithFractionalSecondsAreAccepted() throws {
        let record = try decode(DisplayRecord.self, #"{"lastSeen": "2026-10-12T09:30:00.250Z"}"#)
        #expect(record.lastSeen == Date(timeIntervalSince1970: 1_791_797_400.25))
    }

    @Test func naturalPointSizeIsPixelsOverPixelsPerPoint() {
        let record = StickerRecord(id: UUID(), created: Date(), pixelWidth: 840, pixelHeight: 620,
                                   pixelsPerPoint: 2, lastStyle: .none)
        #expect(record.naturalPointSize == CGSize(width: 420, height: 310))
    }

    @Test func libraryHelpersFindMoveAndRemove() {
        let kept = UUID()
        let deleted = UUID()
        let a = Placement(sticker: kept, style: .puffy, poses: [:])
        let b = Placement(sticker: deleted, style: .shadow, poses: [:])
        let c = Placement(sticker: deleted, style: .none, poses: [:])
        func record(_ placements: [Placement]) -> DisplayRecord {
            DisplayRecord(name: "", vendor: 1, model: 2, serial: 3, builtin: false, lastSeen: Date(), placements: placements)
        }
        func sticker(_ id: UUID) -> StickerRecord {
            StickerRecord(id: id, created: Date(), pixelWidth: 10, pixelHeight: 10, pixelsPerPoint: 1, lastStyle: .puffy)
        }
        var library = Library(stickers: [sticker(kept), sticker(deleted)],
                              displays: ["A": record([a, b]), "B": record([c])])
        #expect(library.placement(b.id) == b)
        #expect(library.displayKey(containing: c.id) == "B")
        #expect(library.placementCount(of: deleted) == 2)
        #expect(library.removePlacement(a.id) == a)
        #expect(library.displays["A"]?.placements == [b])
        library.removeSticker(deleted)
        #expect(library.stickers.map(\.id) == [kept])
        #expect(library.displays["A"]?.placements.isEmpty == true)
        #expect(library.displays["B"]?.placements.isEmpty == true)
        library.moveDisplayRecord(from: "B", to: "C")
        #expect(library.displays["B"] == nil)
        #expect(library.displays["C"] != nil)
    }

    @Test func pureLogicFilesStayFreeOfAppKit() throws {
        // Spec section 4: the pure logic has no AppKit dependency, so it is
        // tested without windows. Files that later tasks add are covered as
        // soon as they exist.
        let pure: Set<String> = ["Library.swift", "LayoutResolver.swift", "DisplayRegistry.swift",
                                 "LibraryStore.swift", "LibraryController.swift", "StyleParameters.swift",
                                 "StyleRenderer.swift", "MasterImage.swift", "StickerGeometry.swift"]
        let files = SourceFiles.swiftFiles().filter { pure.contains($0.lastPathComponent) }
        #expect(!files.isEmpty)
        for url in files {
            let text = try String(contentsOf: url, encoding: .utf8)
            #expect(!text.contains("import AppKit"), "\(url.lastPathComponent) imports AppKit")
            #expect(!text.contains("import SwiftUI"), "\(url.lastPathComponent) imports SwiftUI")
        }
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/LibraryModelTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'StickerStyle' in scope` (and the same for `Placement` and `StickerRecord`) in `LibraryModelTests.swift`.

- [ ] **Step 3: Implement**

```bash
mkdir -p Stickermine/Model
```

`Stickermine/Model/Library.swift` (complete file):

```swift
import CoreGraphics
import Foundation

/// The four sticker styles, in UI order (spec section 8). Stored as their raw
/// strings; a string this build doesn't know (written by a newer build)
/// decodes as `.puffy` instead of failing the whole library (spec section 12).
enum StickerStyle: String, Codable, CaseIterable {
    case puffy, outline, shadow, none

    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = StickerStyle(rawValue: raw) ?? .puffy
    }

    /// The picker's Fill holes default for this style (spec section 7).
    var defaultFillHoles: Bool {
        switch self {
        case .puffy, .outline: return true
        case .shadow, .none: return false
        }
    }
}

/// Where a placement sits at one display size: its centre as 0–1 of the
/// display's frame (Cocoa, y up) and a multiplier on the sticker's natural
/// point size (spec section 11).
struct Pose: Codable, Equatable {
    var x: Double
    var y: Double
    var scale: Double
}

/// One sticker on one display. Rotation (radians, counter-clockwise), style,
/// flip and Float on top are shared by every size; only the pose is per size.
struct Placement: Codable, Equatable, Identifiable {
    let id: UUID
    var sticker: UUID
    var style: StickerStyle
    var flipped: Bool
    var onTop: Bool
    var rotation: Double
    /// Keyed by `DisplaySize.key`, e.g. "1920x1080".
    var poses: [String: Pose]

    init(id: UUID = UUID(), sticker: UUID, style: StickerStyle, flipped: Bool = false,
         onTop: Bool = false, rotation: Double = 0, poses: [String: Pose]) {
        self.id = id
        self.sticker = sticker
        self.style = style
        self.flipped = flipped
        self.onTop = onTop
        self.rotation = rotation
        self.poses = poses
    }

    private enum CodingKeys: String, CodingKey {
        case id, sticker, style, flipped, onTop, rotation, poses
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        sticker = try c.decode(UUID.self, forKey: .sticker)
        style = try c.decodeIfPresent(StickerStyle.self, forKey: .style) ?? .puffy
        flipped = try c.decodeIfPresent(Bool.self, forKey: .flipped) ?? false
        onTop = try c.decodeIfPresent(Bool.self, forKey: .onTop) ?? false
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        poses = try c.decodeIfPresent([String: Pose].self, forKey: .poses) ?? [:]
    }
}

/// One entry in the history: a master PNG in `stickers/<id>.png`.
struct StickerRecord: Codable, Equatable, Identifiable {
    let id: UUID
    var created: Date
    var pixelWidth: Int
    var pixelHeight: Int
    var pixelsPerPoint: Double
    var lastStyle: StickerStyle
    var tutorial: Bool

    init(id: UUID, created: Date, pixelWidth: Int, pixelHeight: Int, pixelsPerPoint: Double,
         lastStyle: StickerStyle, tutorial: Bool = false) {
        self.id = id
        self.created = created
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.pixelsPerPoint = pixelsPerPoint
        self.lastStyle = lastStyle
        self.tutorial = tutorial
    }

    /// The size the sticker had on screen when it was captured: pixels divided
    /// by the capture's pixels per point (spec section 5.8).
    var naturalPointSize: CGSize {
        let ppp = pixelsPerPoint > 0 ? pixelsPerPoint : 1
        return CGSize(width: Double(pixelWidth) / ppp, height: Double(pixelHeight) / ppp)
    }

    private enum CodingKeys: String, CodingKey {
        case id, created, pixelWidth, pixelHeight, pixelsPerPoint, lastStyle, tutorial
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        created = try c.decodeIfPresent(Date.self, forKey: .created) ?? Date(timeIntervalSince1970: 0)
        pixelWidth = try c.decode(Int.self, forKey: .pixelWidth)
        pixelHeight = try c.decode(Int.self, forKey: .pixelHeight)
        pixelsPerPoint = try c.decodeIfPresent(Double.self, forKey: .pixelsPerPoint) ?? 2
        lastStyle = try c.decodeIfPresent(StickerStyle.self, forKey: .lastStyle) ?? .puffy
        tutorial = try c.decodeIfPresent(Bool.self, forKey: .tutorial) ?? false
    }
}

/// Everything known about one display (keyed by its UUID in `Library.displays`),
/// with its placements in z-order, back to front.
struct DisplayRecord: Codable, Equatable {
    var name: String
    var vendor: UInt32
    var model: UInt32
    var serial: UInt32
    var builtin: Bool
    var lastSeen: Date
    var placements: [Placement]

    init(name: String, vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool,
         lastSeen: Date, placements: [Placement]) {
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.builtin = builtin
        self.lastSeen = lastSeen
        self.placements = placements
    }

    private enum CodingKeys: String, CodingKey {
        case name, vendor, model, serial, builtin, lastSeen, placements
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        vendor = try c.decodeIfPresent(UInt32.self, forKey: .vendor) ?? 0
        model = try c.decodeIfPresent(UInt32.self, forKey: .model) ?? 0
        serial = try c.decodeIfPresent(UInt32.self, forKey: .serial) ?? 0
        builtin = try c.decodeIfPresent(Bool.self, forKey: .builtin) ?? false
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen) ?? Date(timeIntervalSince1970: 0)
        placements = try c.decodeIfPresent([Placement].self, forKey: .placements) ?? []
    }
}

/// The whole of `library.json` (spec section 12).
struct Library: Codable, Equatable {
    static let currentVersion = 1

    var version: Int
    var stickers: [StickerRecord]
    /// Keyed by display UUID (uppercase).
    var displays: [String: DisplayRecord]

    init(version: Int = Library.currentVersion, stickers: [StickerRecord], displays: [String: DisplayRecord]) {
        self.version = version
        self.stickers = stickers
        self.displays = displays
    }

    static var empty: Library { Library(stickers: [], displays: [:]) }

    private enum CodingKeys: String, CodingKey {
        case version, stickers, displays
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        stickers = try c.decodeIfPresent([StickerRecord].self, forKey: .stickers) ?? []
        displays = try c.decodeIfPresent([String: DisplayRecord].self, forKey: .displays) ?? [:]
    }
}

extension Library {
    func sticker(_ id: UUID) -> StickerRecord? {
        stickers.first { $0.id == id }
    }

    func placement(_ id: UUID) -> Placement? {
        for record in displays.values {
            if let placement = record.placements.first(where: { $0.id == id }) { return placement }
        }
        return nil
    }

    /// The display record (key) that holds the placement.
    func displayKey(containing placement: UUID) -> String? {
        displays.first { $0.value.placements.contains { $0.id == placement } }?.key
    }

    /// Placements of `sticker` on every display, connected or not (the
    /// delete-from-history confirmation states this number).
    func placementCount(of sticker: UUID) -> Int {
        displays.values.reduce(0) { $0 + $1.placements.filter { $0.sticker == sticker }.count }
    }

    @discardableResult
    mutating func removePlacement(_ id: UUID) -> Placement? {
        guard let key = displayKey(containing: id),
              let index = displays[key]?.placements.firstIndex(where: { $0.id == id })
        else { return nil }
        return displays[key]?.placements.remove(at: index)
    }

    /// Removes the sticker and every placement of it on every display.
    mutating func removeSticker(_ id: UUID) {
        stickers.removeAll { $0.id == id }
        for key in Array(displays.keys) {
            displays[key]?.placements.removeAll { $0.sticker == id }
        }
    }

    /// Re-keys a display record (the fingerprint fallback, spec section 11).
    /// The record keeps its placements; an existing record at `newKey` is replaced.
    mutating func moveDisplayRecord(from oldKey: String, to newKey: String) {
        guard oldKey != newKey, let record = displays.removeValue(forKey: oldKey) else { return }
        displays[newKey] = record
    }
}

/// The JSON coders for `library.json`: ISO-8601 dates (whole seconds are
/// written; fractional seconds are accepted when reading), sorted keys.
enum LibraryCoding {
    private static let plainDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let fractionalDates: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(plainDates.string(from: date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = plainDates.date(from: text) ?? fractionalDates.date(from: text) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO-8601 date: \(text)")
        }
        return decoder
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 41 tests in 8 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Model/Library.swift StickermineTests/LibraryModelTests.swift
git commit -m "Add the library model with lenient decoding" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 2: DisplaySize and LayoutResolver

**Files:**
- Create: `Stickermine/Model/LayoutResolver.swift`
- Test: `StickermineTests/LayoutResolverTests.swift`

**Interfaces:**
- Consumes: `Placement`, `Pose` (Task 1).
- Produces:

```text
struct DisplaySize: Hashable {
    let width: Int; let height: Int
    init(width: Int, height: Int); init?(key: String); init(_ size: CGSize)   // Int(w) × Int(h)
    var key: String { get }                                                   // "1920x1080"
    var isLandscape: Bool { get }                                             // width >= height
    var area: Double { get }
}
enum LayoutResolver {
    static let tieTolerance: Double                                           // 1e-9
    static func pose(for placement: Placement, at size: DisplaySize) -> Pose?
    static func closestStoredSize(in poses: [String: Pose], to size: DisplaySize) -> DisplaySize?
    static func distance(from source: DisplaySize, to target: DisplaySize) -> Double
    static func isCloser(_ a: DisplaySize, than b: DisplaySize, to target: DisplaySize) -> Bool
    static func writing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement
    static func placing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement
}
```

- [ ] **Step 1: Write the failing test**

`StickermineTests/LayoutResolverTests.swift` (complete file):

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct LayoutResolverTests {
    private func placement(_ poses: [String: Pose]) -> Placement {
        Placement(sticker: UUID(), style: .puffy, rotation: 0.3, poses: poses)
    }

    private func size(_ key: String) -> DisplaySize {
        DisplaySize(key: key)!
    }

    @Test func displaySizeKeys() {
        #expect(DisplaySize(width: 1920, height: 1080).key == "1920x1080")
        #expect(DisplaySize(CGSize(width: 1512.9, height: 982.2)).key == "1512x982")
        #expect(DisplaySize(key: "2560x1440") == DisplaySize(width: 2560, height: 1440))
        for bad in ["", "1920", "1920x", "x1080", "0x100", "100x-5", "1920x1080x1", "axb"] {
            #expect(DisplaySize(key: bad) == nil, "\(bad) should not parse")
        }
    }

    @Test func anExactKeyIsUsedAsIs() {
        let stored = Pose(x: 0.81, y: 0.22, scale: 1.3)
        let p = placement(["1920x1080": stored, "2560x1440": Pose(x: 0.1, y: 0.1, scale: 2)])
        #expect(LayoutResolver.pose(for: p, at: size("1920x1080")) == stored)
    }

    @Test func nothingStoredResolvesToNil() {
        #expect(LayoutResolver.pose(for: placement([:]), at: size("1920x1080")) == nil)
        #expect(LayoutResolver.pose(for: placement(["garbage": Pose(x: 0, y: 0, scale: 1)]), at: size("1920x1080")) == nil)
    }

    @Test func theSameOrientationWinsOverACloserSize() {
        // 1000x990 is far closer by log distance, but it is landscape and the target is portrait.
        let p = placement(["1000x990": Pose(x: 0.5, y: 0.5, scale: 1), "600x2000": Pose(x: 0.2, y: 0.8, scale: 1)])
        #expect(LayoutResolver.closestStoredSize(in: p.poses, to: size("1000x1100")) == size("600x2000"))
    }

    @Test func otherOrientationsAreUsedWhenNothingElseIsStored() throws {
        let p = placement(["1920x1080": Pose(x: 0.25, y: 0.75, scale: 1)])
        let pose = try #require(LayoutResolver.pose(for: p, at: size("1080x1920")))
        #expect(pose.x == 0.25)
        #expect(pose.y == 0.75)
        #expect(abs(pose.scale - 0.5625) < 1e-12)
    }

    @Test func theSmallestLogDistanceWins() {
        let p = placement([
            "1280x800": Pose(x: 0, y: 0, scale: 1),
            "2560x1440": Pose(x: 0, y: 0, scale: 1),
            "3840x2160": Pose(x: 0, y: 0, scale: 1),
        ])
        #expect(LayoutResolver.closestStoredSize(in: p.poses, to: size("2240x1260")) == size("2560x1440"))
    }

    @Test func aTieGoesToTheLargerAreaWhateverTheDictionaryOrder() throws {
        // The spec's example: 1920x1080 is exactly as far from 2304x1296 as from 1600x900.
        let a = Pose(x: 0.3, y: 0.4, scale: 1.2)
        let b = Pose(x: 0.7, y: 0.6, scale: 0.8)
        let entries = [("2304x1296", a), ("1600x900", b), ("800x600", Pose(x: 0, y: 0, scale: 1))]
        var generator = SystemRandomNumberGenerator()
        for round in 0..<200 {
            var poses = [String: Pose](minimumCapacity: round % 7 + 1)
            for (key, pose) in entries.shuffled(using: &generator) { poses[key] = pose }
            let resolved = try #require(LayoutResolver.pose(for: placement(poses), at: size("1920x1080")))
            #expect(resolved.x == 0.3 && resolved.y == 0.4, "round \(round) picked \(resolved)")
            #expect(abs(resolved.scale - 1.2 * (1920.0 / 2304.0)) < 1e-12)
        }
    }

    @Test func aTieOnDistanceAndAreaGoesToTheSmallerKey() {
        // 6000x1000 and 3000x2000 are both ln 2 from 3000x1000, both landscape,
        // both 6 000 000 pt²; "3000x2000" < "6000x1000".
        let poses = ["6000x1000": Pose(x: 0.9, y: 0.9, scale: 1), "3000x2000": Pose(x: 0.1, y: 0.1, scale: 1)]
        for _ in 0..<50 {
            var shuffled: [String: Pose] = [:]
            for (key, pose) in poses.shuffled() { shuffled[key] = pose }
            #expect(LayoutResolver.closestStoredSize(in: shuffled, to: size("3000x1000")) == size("3000x2000"))
        }
        #expect(LayoutResolver.pose(for: placement(poses), at: size("3000x1000"))?.scale == 0.5)
    }

    @Test func scaleIsMultipliedByTheSmallerRatio() throws {
        let p = placement(["2560x1440": Pose(x: 0.5, y: 0.5, scale: 2)])
        let pose = try #require(LayoutResolver.pose(for: p, at: size("2240x1260")))
        #expect(abs(pose.scale - 1.75) < 1e-12)
        // A wider display at the same height: the height ratio (1) is the smaller one.
        let wide = try #require(LayoutResolver.pose(for: p, at: size("3440x1440")))
        #expect(wide.scale == 2)
    }

    @Test func writingTouchesOnlyThisSize() {
        let original = placement(["1920x1080": Pose(x: 0.1, y: 0.2, scale: 1)])
        let moved = LayoutResolver.writing(Pose(x: 0.5, y: 0.5, scale: 1.5), to: original, at: size("2560x1440"))
        #expect(moved.poses == ["1920x1080": Pose(x: 0.1, y: 0.2, scale: 1),
                                "2560x1440": Pose(x: 0.5, y: 0.5, scale: 1.5)])
        #expect(moved.rotation == original.rotation)
        #expect(moved.id == original.id)
    }

    @Test func placingReplacesEveryPose() {
        let original = placement(["1920x1080": Pose(x: 0.1, y: 0.2, scale: 1), "2560x1440": Pose(x: 0.3, y: 0.3, scale: 1)])
        let placed = LayoutResolver.placing(Pose(x: 0.6, y: 0.4, scale: 0.9), to: original, at: size("1512x982"))
        #expect(placed.poses == ["1512x982": Pose(x: 0.6, y: 0.4, scale: 0.9)])
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/LayoutResolverTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'LayoutResolver' in scope` and `error: cannot find 'DisplaySize' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Model/LayoutResolver.swift` (complete file):

```swift
import CoreGraphics
import Foundation

/// A display's size in points, from `NSScreen.frame.size`. Its `key`
/// ("1920x1080") is how poses are stored (spec section 11).
struct DisplaySize: Hashable {
    let width: Int
    let height: Int

    init(width: Int, height: Int) {
        self.width = width
        self.height = height
    }

    /// Parses "WxH"; nil for anything else (including zero or negative sides).
    init?(key: String) {
        let parts = key.split(separator: "x", omittingEmptySubsequences: false)
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]),
              width > 0, height > 0
        else { return nil }
        self.init(width: width, height: height)
    }

    /// `Int(w)` × `Int(h)`, exactly as the spec writes the key.
    init(_ size: CGSize) {
        self.init(width: Int(size.width), height: Int(size.height))
    }

    var key: String { "\(width)x\(height)" }

    /// Square sizes count as landscape.
    var isLandscape: Bool { width >= height }

    var area: Double { Double(width) * Double(height) }
}

/// The pose-for-current-size rule (spec section 11). Pure: it never writes;
/// a borrowed pose is only saved when a user edit writes it.
enum LayoutResolver {
    /// Distances closer than this are a tie.
    static let tieTolerance = 1e-9

    /// `poses[size]` when stored; otherwise the pose of the closest stored size
    /// (same orientation first, then the smallest |ln(wB/wA)| + |ln(hB/hA)|; on a
    /// tie the larger area, then the lexicographically smaller key), keeping x and
    /// y and multiplying scale by min(wB/wA, hB/hA). nil when nothing is stored.
    static func pose(for placement: Placement, at size: DisplaySize) -> Pose? {
        if let exact = placement.poses[size.key] { return exact }
        guard let source = closestStoredSize(in: placement.poses, to: size),
              let pose = placement.poses[source.key]
        else { return nil }
        let factor = min(Double(size.width) / Double(source.width),
                         Double(size.height) / Double(source.height))
        return Pose(x: pose.x, y: pose.y, scale: pose.scale * factor)
    }

    /// The stored size `pose(for:at:)` borrows from (unparsable keys are ignored).
    /// Candidates are sorted by key first, so dictionary order never matters.
    static func closestStoredSize(in poses: [String: Pose], to size: DisplaySize) -> DisplaySize? {
        let candidates = poses.keys.sorted().compactMap(DisplaySize.init(key:))
        let sameOrientation = candidates.filter { $0.isLandscape == size.isLandscape }
        let pool = sameOrientation.isEmpty ? candidates : sameOrientation
        return pool.min { isCloser($0, than: $1, to: size) }
    }

    /// |ln(wB/wA)| + |ln(hB/hA)|.
    static func distance(from source: DisplaySize, to target: DisplaySize) -> Double {
        abs(log(Double(target.width) / Double(source.width)))
            + abs(log(Double(target.height) / Double(source.height)))
    }

    static func isCloser(_ a: DisplaySize, than b: DisplaySize, to target: DisplaySize) -> Bool {
        let da = distance(from: a, to: target)
        let db = distance(from: b, to: target)
        if abs(da - db) >= tieTolerance { return da < db }
        if a.area != b.area { return a.area > b.area }
        return a.key < b.key
    }

    /// A move or scale at `size`: writes only `poses[size]` (creating it when
    /// the pose was borrowed).
    static func writing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement {
        var result = placement
        result.poses[size.key] = pose
        return result
    }

    /// A placement (fresh, re-placed or dropped on another display): `poses = [size: pose]`.
    static func placing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement {
        var result = placement
        result.poses = [size.key: pose]
        return result
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 52 tests in 9 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Model/LayoutResolver.swift StickermineTests/LayoutResolverTests.swift
git commit -m "Add the closest-size layout rule with a deterministic tie-break" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 3: DisplayInfo, DisplayRegistry and the test fixtures

**Files:**
- Create: `Stickermine/Model/DisplayRegistry.swift`
- Test: `StickermineTests/TestFixtures.swift`, `StickermineTests/DisplayRegistryTests.swift`

**Interfaces:**
- Consumes: `DisplaySize` (Task 2), `DisplayRecord`, `StickerRecord`, `Placement` (Task 1).
- Produces:

```text
struct DisplayInfo: Equatable {
    let uuid: String; let displayID: UInt32; let frame: CGRect; let visibleFrame: CGRect
    let backingScale: CGFloat; let name: String
    let vendor: UInt32; let model: UInt32; let serial: UInt32; let builtin: Bool
    let mirrorsDisplayID: UInt32?                              // nil when not a mirror secondary
    let inMirrorSet: Bool                                      // contract change 3
    init(uuid: String, displayID: UInt32, frame: CGRect, visibleFrame: CGRect, backingScale: CGFloat,
         name: String, vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool,
         mirrorsDisplayID: UInt32?, inMirrorSet: Bool = false)
    var size: DisplaySize { get }
    var isGhost: Bool { get }                                  // vendor 0x756E6B6E && model 0x76697274
}
enum DisplayRegistry {
    static let ghostVendor: UInt32; static let ghostModel: UInt32; static let sharedSerial: UInt32   // 0x01010101
    static func usable(_ all: [DisplayInfo]) -> [DisplayInfo]
    static func fingerprintAdoption(for display: DisplayInfo, records: [String: DisplayRecord],
                                    connected: [DisplayInfo]) -> String?
    static func uuidString(for displayID: UInt32) -> String?
}
// Test target:
enum Fixtures {
    static func display(uuid: String, id: UInt32, frame: CGRect, visibleFrame: CGRect? = nil, scale: CGFloat = 2,
                        name: String = "Test Display", vendor: UInt32 = 7789, model: UInt32 = 23305,
                        serial: UInt32 = 848_464, builtin: Bool = false, mirrors: UInt32? = nil,
                        inMirrorSet: Bool = false) -> DisplayInfo
    static let externalUUID: String; static let mainUUID: String
    static func external(frame: CGRect = CGRect(x: 40_000, y: 0, width: 1920, height: 1080),
                         scale: CGFloat = 2) -> DisplayInfo                       // "LG UltraFine", ID 3
    static func main() -> DisplayInfo                                             // 1512 × 982 at x = 50 000, ID 1, built in, serial 0
    static func sticker(_ id: UUID = UUID(), width: Int = 200, height: Int = 100, tutorial: Bool = false) -> StickerRecord
    static func displayRecord(for display: DisplayInfo, placements: [Placement]) -> DisplayRecord
    static func temporaryDirectory() -> URL
    static func image(width: Int, height: Int, left: [UInt8] = [255, 0, 0, 255], right: [UInt8] = [0, 0, 255, 255],
                      colorSpace: CGColorSpace? = nil) -> CGImage                // RGBA halves; sRGB by default
    static func pngData(width: Int, height: Int, pixelsPerPoint: Double?) -> Data
}
```

`uuidString` asks Core Graphics, so it is the one non-pure function here; `CGDisplayCreateUUIDFromDisplayID` lives in ColorSync, which the file imports (not AppKit).

- [ ] **Step 1: Write the fixtures and the failing test**

`StickermineTests/TestFixtures.swift` (complete file):

```swift
import CoreGraphics
import Foundation
import ImageIO
@testable import Stickermine

/// Model, display and file fixtures for the M2 tests.
enum Fixtures {
    /// A display far off every real screen (x ≥ 40 000 pt), so panels ordered
    /// in by tests never appear on the developer's desktop.
    static func display(
        uuid: String, id: UInt32, frame: CGRect, visibleFrame: CGRect? = nil, scale: CGFloat = 2,
        name: String = "Test Display", vendor: UInt32 = 7789, model: UInt32 = 23305, serial: UInt32 = 848_464,
        builtin: Bool = false, mirrors: UInt32? = nil, inMirrorSet: Bool = false
    ) -> DisplayInfo {
        DisplayInfo(uuid: uuid, displayID: id, frame: frame, visibleFrame: visibleFrame ?? frame,
                    backingScale: scale, name: name, vendor: vendor, model: model, serial: serial,
                    builtin: builtin, mirrorsDisplayID: mirrors, inMirrorSet: inMirrorSet)
    }

    static let externalUUID = "25A19A46-A9B2-42B2-B1F8-389D978CBBC2"
    static let mainUUID = "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    /// 1920 × 1080 at x = 40 000.
    static func external(frame: CGRect = CGRect(x: 40_000, y: 0, width: 1920, height: 1080),
                         scale: CGFloat = 2) -> DisplayInfo {
        display(uuid: externalUUID, id: 3, frame: frame, scale: scale, name: "LG UltraFine")
    }

    /// 1512 × 982 at x = 50 000, built in.
    static func main() -> DisplayInfo {
        display(uuid: mainUUID, id: 1, frame: CGRect(x: 50_000, y: 0, width: 1512, height: 982),
                name: "Built-in Retina Display", vendor: 1552, model: 41_013, serial: 0, builtin: true)
    }

    /// A sticker record whose natural size is `width` × `height` points at 2 px/pt.
    static func sticker(_ id: UUID = UUID(), width: Int = 200, height: Int = 100, tutorial: Bool = false) -> StickerRecord {
        StickerRecord(id: id, created: Date(timeIntervalSince1970: 1_760_000_000), pixelWidth: width * 2,
                      pixelHeight: height * 2, pixelsPerPoint: 2, lastStyle: .outline, tutorial: tutorial)
    }

    static func displayRecord(for display: DisplayInfo, placements: [Placement]) -> DisplayRecord {
        DisplayRecord(name: display.name, vendor: display.vendor, model: display.model, serial: display.serial,
                      builtin: display.builtin, lastSeen: Date(timeIntervalSince1970: 1_760_000_000),
                      placements: placements)
    }

    /// A fresh, empty directory; delete it at the end of the test.
    static func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("StickermineTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An opaque sRGB image: the left half `left`, the right half `right` (RGBA, 0–255;
    /// alpha 0 makes that half transparent).
    static func image(width: Int, height: Int, left: [UInt8] = [255, 0, 0, 255],
                      right: [UInt8] = [0, 0, 255, 255], colorSpace: CGColorSpace? = nil) -> CGImage {
        let space = colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        func fill(_ rgba: [UInt8], _ rect: CGRect) {
            let a = CGFloat(rgba[3]) / 255
            context.setFillColor(CGColor(colorSpace: space, components: [
                CGFloat(rgba[0]) / 255, CGFloat(rgba[1]) / 255, CGFloat(rgba[2]) / 255, a])!)
            context.setBlendMode(.copy)
            context.fill(rect)
        }
        fill(left, CGRect(x: 0, y: 0, width: width / 2, height: height))
        fill(right, CGRect(x: width / 2, y: 0, width: width - width / 2, height: height))
        return context.makeImage()!
    }

    /// PNG data for a `width` × `height` px image with DPI = 72 × `pixelsPerPoint`
    /// (no DPI at all when it is nil). Written with ImageIO directly, so store
    /// tests don't depend on the app's own PNG writer.
    static func pngData(width: Int, height: Int, pixelsPerPoint: Double?) -> Data {
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, "public.png" as CFString, 1, nil)!
        let properties: [CFString: Any]? = pixelsPerPoint.map {
            [kCGImagePropertyDPIWidth: 72 * $0, kCGImagePropertyDPIHeight: 72 * $0]
        }
        CGImageDestinationAddImage(destination, image(width: width, height: height), properties as CFDictionary?)
        _ = CGImageDestinationFinalize(destination)
        return data as Data
    }
}
```

`StickermineTests/DisplayRegistryTests.swift` (complete file):

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct DisplayRegistryTests {
    private let frame = CGRect(x: 40_000, y: 0, width: 1920, height: 1080)

    private func display(_ uuid: String, id: UInt32, vendor: UInt32 = 7789, model: UInt32 = 23305,
                         serial: UInt32 = 848_464, builtin: Bool = false, mirrors: UInt32? = nil) -> DisplayInfo {
        Fixtures.display(uuid: uuid, id: id, frame: frame, vendor: vendor, model: model, serial: serial,
                         builtin: builtin, mirrors: mirrors)
    }

    private func record(vendor: UInt32 = 7789, model: UInt32 = 23305, serial: UInt32 = 848_464,
                        builtin: Bool = false) -> DisplayRecord {
        DisplayRecord(name: "LG UltraFine", vendor: vendor, model: model, serial: serial, builtin: builtin,
                      lastSeen: Date(timeIntervalSince1970: 0), placements: [])
    }

    @Test func theGhostDisplayIsIgnored() {
        let ghost = display("GHOST", id: 7, vendor: 0x756E6B6E, model: 0x76697274)
        #expect(ghost.isGhost)
        let real = display("REAL", id: 3)
        #expect(!real.isGhost)
        #expect(DisplayRegistry.usable([ghost, real]) == [real])
        // Only one of the two codes is not the ghost.
        #expect(!display("X", id: 8, vendor: 0x756E6B6E, model: 1).isGhost)
    }

    @Test func mirrorSecondariesAreIgnoredButThePrimaryStays() {
        let primary = Fixtures.display(uuid: "PRIMARY", id: 1, frame: frame, inMirrorSet: true)
        let secondary = Fixtures.display(uuid: "SECONDARY", id: 3, frame: frame, mirrors: 1, inMirrorSet: true)
        #expect(DisplayRegistry.usable([primary, secondary]) == [primary])
    }

    @Test func aNullDisplayIDOrMissingUUIDIsIgnored() {
        #expect(DisplayRegistry.usable([display("ZERO", id: 0), display("", id: 5)]).isEmpty)
    }

    @Test func aDuplicateUUIDKeepsTheFirstDisplay() {
        let first = display("SAME", id: 3)
        let second = display("SAME", id: 4)
        #expect(DisplayRegistry.usable([first, second]) == [first])
    }

    @Test func noUsableDisplayGivesAnEmptyList() {
        #expect(DisplayRegistry.usable([display("GHOST", id: 7, vendor: 0x756E6B6E, model: 0x76697274)]).isEmpty)
    }

    @Test func uuidStringRefusesTheNullAndUnknownIDs() {
        // CGDisplayCreateUUIDFromDisplayID(0) would answer with the main display's UUID.
        #expect(DisplayRegistry.uuidString(for: 0) == nil)
        #expect(DisplayRegistry.uuidString(for: UInt32.max) == nil)
        #expect(DisplayRegistry.uuidString(for: 0x7FFF_0001) == nil)
    }

    @Test func uuidStringOfTheMainDisplayIsUppercase() throws {
        let uuid = try #require(DisplayRegistry.uuidString(for: CGMainDisplayID()))
        #expect(uuid == uuid.uppercased())
        #expect(UUID(uuidString: uuid) != nil)
    }

    @Test func fingerprintAdoptsTheOneMatchingDisconnectedRecord() {
        let newcomer = display("NEW-UUID", id: 3)
        let records = ["OLD-UUID": record(), "OTHER": record(serial: 1234)]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == "OLD-UUID")
    }

    @Test func fingerprintRefusesSerialZero() {
        let newcomer = display("NEW-UUID", id: 3, serial: 0)
        let records = ["OLD-UUID": record(serial: 0)]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == nil)
    }

    @Test func fingerprintRefusesTheSharedSerial() {
        let newcomer = display("NEW-UUID", id: 3, serial: 0x01010101)
        let records = ["OLD-UUID": record(serial: 0x01010101)]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == nil)
    }

    @Test func fingerprintRefusesWhenAConnectedDisplaySharesIt() {
        let newcomer = display("NEW-UUID", id: 3)
        let twin = display("TWIN-UUID", id: 4)
        let records = ["OLD-UUID": record()]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer, twin]) == nil)
    }

    @Test func fingerprintRefusesTwoMatchingRecords() {
        let newcomer = display("NEW-UUID", id: 3)
        let records = ["OLD-1": record(), "OLD-2": record()]
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: records, connected: [newcomer]) == nil)
    }

    @Test func fingerprintNeedsEveryFieldAndADisconnectedUnknownDisplay() {
        let newcomer = display("NEW-UUID", id: 3)
        // Built-in flag differs.
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["OLD": record(builtin: true)],
                                                    connected: [newcomer]) == nil)
        // Model differs.
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["OLD": record(model: 1)],
                                                    connected: [newcomer]) == nil)
        // The display already has its own record.
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["NEW-UUID": record(), "OLD": record()],
                                                    connected: [newcomer]) == nil)
        // The only match is a record whose display is connected (under another fingerprint field set).
        let connectedOwner = display("OLD", id: 9, serial: 5)
        #expect(DisplayRegistry.fingerprintAdoption(for: newcomer, records: ["OLD": record()],
                                                    connected: [newcomer, connectedOwner]) == nil)
    }

    @Test func sizeComesFromTheFrame() {
        #expect(display("A", id: 3).size == DisplaySize(width: 1920, height: 1080))
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/DisplayRegistryTests
```

Expected: `** TEST FAILED **` with `error: cannot find type 'DisplayInfo' in scope` in `TestFixtures.swift`.

- [ ] **Step 3: Implement**

`Stickermine/Model/DisplayRegistry.swift` (complete file):

```swift
import ColorSync
import CoreGraphics
import Foundation

/// One connected display as Stickermine sees it (built by `LiveScreenProvider`
/// from an `NSScreen`, or by tests). Frames are Cocoa global coordinates.
struct DisplayInfo: Equatable {
    /// Uppercase `CGDisplayCreateUUIDFromDisplayID` string: the only identity
    /// that is persisted.
    let uuid: String
    /// Runtime handle only; never persisted (spec section 11).
    let displayID: UInt32
    let frame: CGRect
    let visibleFrame: CGRect
    let backingScale: CGFloat
    let name: String
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let builtin: Bool
    /// The display this one mirrors; nil when it is not a mirror secondary.
    let mirrorsDisplayID: UInt32?
    /// True for every member of a mirror set, the primary included.
    let inMirrorSet: Bool

    init(uuid: String, displayID: UInt32, frame: CGRect, visibleFrame: CGRect, backingScale: CGFloat,
         name: String, vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool,
         mirrorsDisplayID: UInt32?, inMirrorSet: Bool = false) {
        self.uuid = uuid
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScale = backingScale
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.builtin = builtin
        self.mirrorsDisplayID = mirrorsDisplayID
        self.inMirrorSet = inMirrorSet
    }

    var size: DisplaySize { DisplaySize(frame.size) }

    /// The placeholder display macOS adds around wake and while a display is
    /// off: vendor 'unkn', model 'virt' (spec section 11).
    var isGhost: Bool {
        vendor == DisplayRegistry.ghostVendor && model == DisplayRegistry.ghostModel
    }
}

/// Display identity rules (spec section 11). Pure, except `uuidString`, which
/// asks Core Graphics.
enum DisplayRegistry {
    static let ghostVendor: UInt32 = 0x756E6B6E   // 'unkn'
    static let ghostModel: UInt32 = 0x76697274    // 'virt'
    /// A serial some vendors flash onto every unit; it identifies nothing.
    static let sharedSerial: UInt32 = 0x01010101

    /// The displays stickers may use: no null IDs, no ghost, no mirror
    /// secondaries, one entry per UUID (the first one wins).
    static func usable(_ all: [DisplayInfo]) -> [DisplayInfo] {
        var seen = Set<String>()
        return all.filter { display in
            guard display.displayID != kCGNullDirectDisplay, !display.uuid.isEmpty,
                  !display.isGhost, display.mirrorsDisplayID == nil
            else { return false }
            return seen.insert(display.uuid).inserted
        }
    }

    /// The fingerprint fallback: the key of the one disconnected record whose
    /// vendor, model, serial and built-in flag match `display`, when `display`
    /// has no record of its own, its serial means something, and no other
    /// connected display shares that fingerprint. nil otherwise (it starts empty).
    static func fingerprintAdoption(for display: DisplayInfo, records: [String: DisplayRecord],
                                    connected: [DisplayInfo]) -> String? {
        guard records[display.uuid] == nil,
              display.serial != 0, display.serial != sharedSerial
        else { return nil }
        let twinConnected = connected.contains {
            $0.uuid != display.uuid && $0.vendor == display.vendor && $0.model == display.model
                && $0.serial == display.serial && $0.builtin == display.builtin
        }
        guard !twinConnected else { return nil }
        let connectedUUIDs = Set(connected.map(\.uuid))
        let matches = records.filter { key, record in
            !connectedUUIDs.contains(key) && record.vendor == display.vendor && record.model == display.model
                && record.serial == display.serial && record.builtin == display.builtin
        }
        guard matches.count == 1 else { return nil }
        return matches.first?.key
    }

    /// The uppercase UUID string for a live display ID. nil for 0
    /// (`kCGNullDirectDisplay`, which Core Graphics would silently answer with
    /// the main display's UUID), for 0xFFFFFFFF, and for IDs that aren't online.
    static func uuidString(for displayID: UInt32) -> String? {
        guard displayID != kCGNullDirectDisplay, displayID != UInt32.max,
              let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue(),
              let string = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        return string.uppercased()
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 66 tests in 10 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Model/DisplayRegistry.swift StickermineTests/TestFixtures.swift StickermineTests/DisplayRegistryTests.swift
git commit -m "Add display identity: ghost, mirror and null-ID filtering and the fingerprint fallback" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 4: StyleParameters

**Files:**
- Create: `Stickermine/Capture/StyleParameters.swift`
- Test: `StickermineTests/StyleParametersTests.swift`

**Interfaces:**
- Consumes: `StickerStyle` (Task 1).
- Produces (contract signatures, plus the constants):

```text
struct StyleParameters: Equatable {
    let rimRadius: Double; let closing: Double; let shadowRadius: Double; let shadowOffset: Double
    let shadowOpacity: Double; let chokeSigma: Double
    static let referenceLongSide: Double                       // 800
    static let rimRadiusPerReference: Double                   // 12
    static let closingPerReference: Double                     // 10
    static let shadowRadiusPerReference: Double                // 10
    static let shadowOffsetPerRadius: Double                   // 0.6
    static let shadowOpacityValue: Double                      // 0.35
    static let chokeSigmaPer512: Double                        // 0.5
    static func forStickerPixels(longSide: Double, sourceLongSide: Double) -> StyleParameters
    func shadowMargin(for style: StickerStyle) -> Double       // 0 for .none, else ceil(3 × shadowRadius) + |shadowOffset|
}
```

- [ ] **Step 1: Write the failing test**

`StickermineTests/StyleParametersTests.swift` (complete file):

```swift
import Testing
@testable import Stickermine

struct StyleParametersTests {
    @Test func theSpecValuesAt800Pixels() {
        let p = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 512)
        #expect(p.rimRadius == 12)
        #expect(p.closing == 10)
        #expect(p.shadowRadius == 10)
        #expect(p.shadowOffset == 6)
        #expect(p.shadowOpacity == 0.35)
        #expect(p.chokeSigma == 0.5)
    }

    @Test func sizesScaleLinearlyWithThePixelSize() {
        let base = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 1000)
        let double = StyleParameters.forStickerPixels(longSide: 1600, sourceLongSide: 1000)
        let half = StyleParameters.forStickerPixels(longSide: 400, sourceLongSide: 1000)
        #expect(double.rimRadius == 2 * base.rimRadius)
        #expect(double.closing == 2 * base.closing)
        #expect(double.shadowRadius == 2 * base.shadowRadius)
        #expect(double.shadowOffset == 2 * base.shadowOffset)
        #expect(half.rimRadius == base.rimRadius / 2)
        #expect(half.shadowRadius == base.shadowRadius / 2)
        // Opacity and the choke (which follows the source) don't change with on-screen size.
        #expect(double.shadowOpacity == base.shadowOpacity)
        #expect(double.chokeSigma == base.chokeSigma)
    }

    @Test func theChokeFollowsTheSourceLongSide() {
        #expect(StyleParameters.forStickerPixels(longSide: 300, sourceLongSide: 1024).chokeSigma == 1)
        #expect(StyleParameters.forStickerPixels(longSide: 300, sourceLongSide: 2048).chokeSigma == 2)
    }

    @Test func shadowMarginIsCeilThreeRadiiPlusTheOffsetExceptForNone() {
        let at800 = StyleParameters.forStickerPixels(longSide: 800, sourceLongSide: 512)
        #expect(at800.shadowMargin(for: .puffy) == 36)        // ceil(30) + 6
        #expect(at800.shadowMargin(for: .outline) == 36)
        #expect(at800.shadowMargin(for: .shadow) == 36)
        #expect(at800.shadowMargin(for: .none) == 0)
        let at1000 = StyleParameters.forStickerPixels(longSide: 1000, sourceLongSide: 512)
        #expect(at1000.shadowMargin(for: .shadow) == 45.5)    // ceil(37.5) + 7.5
    }

    @Test func aZeroSizedStickerHasZeroParameters() {
        let p = StyleParameters.forStickerPixels(longSide: 0, sourceLongSide: 0)
        #expect(p.rimRadius == 0)
        #expect(p.shadowMargin(for: .puffy) == 0)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/StyleParametersTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'StyleParameters' in scope`.

- [ ] **Step 3: Implement**

```bash
mkdir -p Stickermine/Capture
```

`Stickermine/Capture/StyleParameters.swift` (complete file):

```swift
import Foundation

/// Style parameters in pixels, scaled linearly with the sticker's pixel size
/// from the spec's values per 800 px (spec section 8). Pure math: M3's style
/// rendering and the layer shadow read these.
struct StyleParameters: Equatable {
    /// Outline/Puffy white rim radius r (12 px per 800).
    let rimRadius: Double
    /// SDF closing distance s for a smoother die-cut line (10 px per 800).
    let closing: Double
    /// Layer-shadow blur radius (10 px per 800).
    let shadowRadius: Double
    /// Downward layer-shadow offset (0.6 × the radius).
    let shadowOffset: Double
    /// Layer-shadow opacity (0.35 at every size).
    let shadowOpacity: Double
    /// None's edge choke blur σ = 0.5 × (source long side / 512).
    let chokeSigma: Double

    static let referenceLongSide = 800.0
    static let rimRadiusPerReference = 12.0
    static let closingPerReference = 10.0
    static let shadowRadiusPerReference = 10.0
    static let shadowOffsetPerRadius = 0.6
    static let shadowOpacityValue = 0.35
    static let chokeSigmaPer512 = 0.5

    /// `longSide`: the sticker's on-screen long side in pixels (points × scale ×
    /// backing scale). `sourceLongSide`: the master's long side in pixels.
    static func forStickerPixels(longSide: Double, sourceLongSide: Double) -> StyleParameters {
        let factor = max(longSide, 0) / referenceLongSide
        let shadowRadius = shadowRadiusPerReference * factor
        return StyleParameters(
            rimRadius: rimRadiusPerReference * factor,
            closing: closingPerReference * factor,
            shadowRadius: shadowRadius,
            shadowOffset: shadowOffsetPerRadius * shadowRadius,
            shadowOpacity: shadowOpacityValue,
            chokeSigma: chokeSigmaPer512 * max(sourceLongSide, 0) / 512
        )
    }

    /// The transparent padding on every side of the sticker's window, in
    /// pixels: ceil(3 × shadow radius) + |offset|, and 0 for None, which has no
    /// shadow (spec section 9).
    func shadowMargin(for style: StickerStyle) -> Double {
        switch style {
        case .none:
            return 0
        case .puffy, .outline, .shadow:
            return (3 * shadowRadius).rounded(.up) + abs(shadowOffset)
        }
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 71 tests in 11 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/StyleParameters.swift StickermineTests/StyleParametersTests.swift
git commit -m "Add style parameters scaled per sticker pixel size" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 5: MasterImage and LibraryStore

**Files:**
- Create: `Stickermine/Capture/MasterImage.swift`, `Stickermine/Model/LibraryStore.swift`
- Test: `StickermineTests/LibraryStoreTests.swift`

**Interfaces:**
- Consumes: `Library`, `LibraryCoding`, `StickerRecord` (Task 1); `Fixtures` (Task 3).
- Produces:

```text
enum MasterImage {
    enum Failure: Error { case cannotEncode }
    struct FileInfo: Equatable { let pixelWidth: Int; let pixelHeight: Int; let pixelsPerPoint: Double? }
    static func pngData(_ image: CGImage, pixelsPerPoint: Double) throws -> Data   // contract signature (M4)
    static func fileInfo(at url: URL) -> FileInfo?
    static func pixelsPerPoint(fromDPI dpi: Double) -> Double?                    // DPI / 72 rounded to 0.01
    static func image(at url: URL) -> CGImage?                                     // thread-safe
}
final class LibraryStore {
    enum LoadResult: Equatable {
        case fresh(Library), loaded(Library), readOnlyNewer(Library), recoveredFromCorrupt(Library)
        var library: Library { get }
    }
    enum StoreError: Error, Equatable { case readOnly }
    static let tutorialIDs: [UUID]                             // 5A1C0A00-7E57-4A11-8000-00000000000{1,2,3}
    static let defaultPixelsPerPoint: Double                   // 2.0
    let root: URL
    private(set) var isReadOnly: Bool
    init(root: URL)
    var libraryURL: URL { get }; var stickersDirectory: URL { get }
    static func defaultRoot() throws -> URL                    // ~/Library/Application Support/com.ethan.stickermine
    static func root(inApplicationSupport support: URL) -> URL
    func load() -> LoadResult
    static func corruptStamp(for date: Date) -> String         // "2026-10-15T21-02-33Z"
    func repair(_ library: Library) -> Library
    func save(_ library: Library) throws
    func pngURL(for sticker: UUID) -> URL                      // stickers/<UPPERCASE-UUID>.png
    func writePNG(_ data: Data, for sticker: UUID) throws
    func deletePNG(for sticker: UUID) throws
}
```

Decisions made here: `load()` writes nothing but the corrupt file's rename (the repaired library is saved with the next user change, so a launch never writes on its own); a newer file is never renamed or repaired, even when this build can't decode it (then it shows nothing); a missing `version` counts as corrupt; if the corrupt file can't be moved aside the store turns read-only rather than overwrite it.

- [ ] **Step 1: Write the failing test**

`StickermineTests/LibraryStoreTests.swift` (complete file):

```swift
import Foundation
import Testing
@testable import Stickermine

struct LibraryStoreTests {
    private let fileManager = FileManager.default

    private func sample(stickers: [UUID]) -> Library {
        let placements = stickers.map {
            Placement(sticker: $0, style: .outline, poses: ["1920x1080": Pose(x: 0.5, y: 0.5, scale: 1)])
        }
        return Library(stickers: stickers.map { Fixtures.sticker($0) },
                       displays: [Fixtures.externalUUID: Fixtures.displayRecord(for: Fixtures.external(), placements: placements)])
    }

    private func writePNGs(_ ids: [UUID], to store: LibraryStore, pixelsPerPoint: Double? = 2) throws {
        for id in ids {
            try store.writePNG(Fixtures.pngData(width: 400, height: 200, pixelsPerPoint: pixelsPerPoint), for: id)
        }
    }

    private func files(in directory: URL) -> [String] {
        ((try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []).sorted()
    }

    @Test func aFreshFolderLoadsAnEmptyLibrary() {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        #expect(store.load() == .fresh(.empty))
        #expect(!store.isReadOnly)
        #expect(fileManager.fileExists(atPath: store.stickersDirectory.path))
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path))
    }

    @Test func aSavedLibraryLoadsBackUnchanged() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let ids = [UUID(), UUID()]
        try writePNGs(ids, to: store)
        let library = sample(stickers: ids)
        try store.save(library)
        #expect(LibraryStore(root: root).load() == .loaded(library))
        // Atomic writes leave no temporary files behind.
        #expect(files(in: root) == ["library.json", "stickers"])
    }

    @Test func pngsLiveInStickersNamedByUppercaseUUID() {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let id = UUID()
        let url = LibraryStore(root: root).pngURL(for: id)
        #expect(url.lastPathComponent == "\(id.uuidString.uppercased()).png")
        #expect(url.deletingLastPathComponent().lastPathComponent == "stickers")
        #expect(LibraryStore.root(inApplicationSupport: URL(fileURLWithPath: "/tmp/Support")).path
                == "/tmp/Support/com.ethan.stickermine")
    }

    @Test func aNewerLibraryIsShownButNeverWritten() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store)
        var newer = sample(stickers: [id])
        newer.version = 2
        try store.save(newer)
        let before = try Data(contentsOf: store.libraryURL)

        let reopened = LibraryStore(root: root)
        let result = reopened.load()
        #expect(result == .readOnlyNewer(newer))
        #expect(reopened.isReadOnly)
        #expect(throws: LibraryStore.StoreError.readOnly) { try reopened.save(.empty) }
        #expect(throws: LibraryStore.StoreError.readOnly) { try reopened.writePNG(Data([1]), for: UUID()) }
        #expect(throws: LibraryStore.StoreError.readOnly) { try reopened.deletePNG(for: id) }
        #expect(try Data(contentsOf: reopened.libraryURL) == before)
        #expect(fileManager.fileExists(atPath: reopened.pngURL(for: id).path))
    }

    @Test func aNewerLibraryThisBuildCantReadIsStillNeverRenamed() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let json = Data(#"{"version": 7, "stickers": "a new shape"}"#.utf8)
        try json.write(to: store.libraryURL)
        #expect(store.load() == .readOnlyNewer(.empty))
        #expect(try Data(contentsOf: store.libraryURL) == json)
        #expect(files(in: root) == ["library.json", "stickers"])
    }

    @Test func aCorruptFileIsSetAsideAndHistoryRebuiltFromThePNGs() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let ids = [UUID(), UUID()]
        try writePNGs(ids, to: store)
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: store.libraryURL)

        let result = store.load()
        guard case .recoveredFromCorrupt(let library) = result else {
            Issue.record("expected recoveredFromCorrupt, got \(result)")
            return
        }
        #expect(Set(library.stickers.map(\.id)) == Set(ids))
        #expect(library.displays.isEmpty)
        #expect(!store.isReadOnly)
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path))
        let setAside = files(in: root).filter { $0.hasPrefix("library.corrupt-") && $0.hasSuffix(".json") }
        #expect(setAside.count == 1)
        #expect(try Data(contentsOf: root.appendingPathComponent(setAside[0])) == garbage)
    }

    @Test func aLibraryWithoutAVersionCountsAsCorrupt() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try Data(#"{"stickers": []}"#.utf8).write(to: store.libraryURL)
        #expect(store.load() == .recoveredFromCorrupt(.empty))
    }

    @Test func corruptStampHasNoColons() {
        #expect(LibraryStore.corruptStamp(for: Date(timeIntervalSince1970: 1_760_000_000)) == "2025-10-09T08-53-20Z")
    }

    @Test func anEntryWhosePNGIsMissingIsDroppedWithItsPlacements() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let kept = UUID()
        let lost = UUID()
        try writePNGs([kept], to: store)
        try store.save(sample(stickers: [kept, lost]))
        let library = LibraryStore(root: root).load().library
        #expect(library.stickers.map(\.id) == [kept])
        #expect(library.displays[Fixtures.externalUUID]?.placements.map(\.sticker) == [kept])
    }

    @Test func aStrayPNGIsAdoptedWithItsDPI() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let retina = UUID()
        let standard = UUID()
        try writePNGs([retina], to: store, pixelsPerPoint: 2)
        try writePNGs([standard], to: store, pixelsPerPoint: 1)
        try store.save(.empty)
        let library = LibraryStore(root: root).load().library
        let adoptedRetina = try #require(library.sticker(retina))
        let adoptedStandard = try #require(library.sticker(standard))
        #expect(adoptedRetina.pixelWidth == 400 && adoptedRetina.pixelHeight == 200)
        #expect(adoptedRetina.pixelsPerPoint == 2)
        #expect(adoptedStandard.pixelsPerPoint == 1)
        #expect(adoptedRetina.lastStyle == .puffy)
        #expect(!adoptedRetina.tutorial)
        #expect(library.displays.isEmpty)
        let fileDate = try #require(try store.pngURL(for: retina).resourceValues(forKeys: [.creationDateKey]).creationDate)
        #expect(adoptedRetina.created == fileDate)
    }

    @Test func aStrayPNGWithoutDPIGetsTwoPixelsPerPoint() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store, pixelsPerPoint: nil)
        #expect(store.load().library.sticker(id)?.pixelsPerPoint == 2)
    }

    @Test func aStrayFileThatIsntAnImageIsLeftAlone() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try store.writePNG(Data("not a png".utf8), for: id)
        try Data("notes".utf8).write(to: store.stickersDirectory.appendingPathComponent("readme.txt"))
        #expect(store.load() == .fresh(.empty))
        #expect(fileManager.fileExists(atPath: store.pngURL(for: id).path))
    }

    @Test func tutorialUUIDsAreFlaggedWhenAdoptedOrLoaded() throws {
        #expect(LibraryStore.tutorialIDs.count == 3)
        #expect(Set(LibraryStore.tutorialIDs).count == 3)
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let maple = LibraryStore.tutorialIDs[2]
        let card = LibraryStore.tutorialIDs[0]
        try writePNGs([maple, card], to: store)
        // The card's index entry lost its flag; Maple's entry is missing entirely.
        try store.save(Library(stickers: [Fixtures.sticker(card, tutorial: false)], displays: [:]))
        let library = LibraryStore(root: root).load().library
        #expect(library.sticker(card)?.tutorial == true)
        #expect(library.sticker(maple)?.tutorial == true)
    }

    @Test func deletingAPNGIgnoresOneThatIsAlreadyGone() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store)
        try store.deletePNG(for: id)
        #expect(!fileManager.fileExists(atPath: store.pngURL(for: id).path))
        try store.deletePNG(for: id)
    }

    @Test func lenientDecodingKeepsAnOlderOrOddFileUsable() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try writePNGs([id], to: store)
        let json = """
            {"version": 1, "stickers": [{"id": "\(id.uuidString)", "pixelWidth": 400, "pixelHeight": 200,
              "lastStyle": "holographic"}],
             "displays": {"\(Fixtures.externalUUID)": {"name": "LG", "placements": [
               {"id": "\(UUID().uuidString)", "sticker": "\(id.uuidString)", "style": "glitter",
                "poses": {"1920x1080": {"x": 0.5, "y": 0.5, "scale": 1}}}]}}}
            """
        try Data(json.utf8).write(to: store.libraryURL)
        guard case .loaded(let library) = store.load() else {
            Issue.record("expected the file to load")
            return
        }
        #expect(library.sticker(id)?.lastStyle == .puffy)
        let placement = try #require(library.displays[Fixtures.externalUUID]?.placements.first)
        #expect(placement.style == .puffy)
        #expect(!placement.flipped && !placement.onTop && placement.rotation == 0)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/LibraryStoreTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'LibraryStore' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/MasterImage.swift` (complete file):

```swift
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Master PNGs on disk (spec section 6.8): written with DPI = 72 × pixels per
/// point, so recovery can restore a sticker's natural size from the file alone.
/// M4 adds `load(url:)` and `LoadedCapture` for screenshots.
enum MasterImage {
    enum Failure: Error {
        case cannotEncode
    }

    /// What launch repair needs from a PNG without decoding its pixels.
    struct FileInfo: Equatable {
        let pixelWidth: Int
        let pixelHeight: Int
        /// From the file's DPI; nil when the file has none.
        let pixelsPerPoint: Double?
    }

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
}
```

`Stickermine/Model/LibraryStore.swift` (complete file):

```swift
import Foundation
import os

/// `library.json` and `stickers/<uuid>.png` under one root directory
/// (spec section 12). The app passes `defaultRoot()`; tests pass a temporary
/// directory, so they never touch the real Application Support.
///
/// Rules it enforces:
/// - every write is atomic (`Data.write(to:options: .atomic)`);
/// - a library written by a newer build is shown but never written (read-only);
/// - a library that doesn't decode is renamed `library.corrupt-<date>.json` and
///   history is rebuilt from the PNGs;
/// - launch repair drops entries whose PNG is missing and adopts stray PNGs.
///
/// Ordering (callers): write the PNG before the index that names it; to delete,
/// remove the PNG, then save the index.
final class LibraryStore {
    enum LoadResult: Equatable {
        /// No library.json yet (history may still hold adopted PNGs).
        case fresh(Library)
        case loaded(Library)
        /// Written by a newer Stickermine: shown, never written.
        case readOnlyNewer(Library)
        /// library.json didn't decode; it was set aside and history rebuilt.
        case recoveredFromCorrupt(Library)

        var library: Library {
            switch self {
            case .fresh(let library), .loaded(let library),
                 .readOnlyNewer(let library), .recoveredFromCorrupt(let library):
                return library
            }
        }
    }

    enum StoreError: Error, Equatable {
        case readOnly
    }

    /// The three tutorial stickers' fixed IDs, in order: tutorial 1 (the
    /// shortcut card), tutorial 2 (the double-click card), tutorial 3 (Maple).
    static let tutorialIDs: [UUID] = [
        UUID(uuidString: "5A1C0A00-7E57-4A11-8000-000000000001")!,
        UUID(uuidString: "5A1C0A00-7E57-4A11-8000-000000000002")!,
        UUID(uuidString: "5A1C0A00-7E57-4A11-8000-000000000003")!,
    ]

    /// Pixels per point for an adopted PNG that has no DPI.
    static let defaultPixelsPerPoint = 2.0

    let root: URL
    private(set) var isReadOnly = false
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "library")

    init(root: URL) {
        self.root = root
    }

    var libraryURL: URL { root.appendingPathComponent("library.json") }
    var stickersDirectory: URL { root.appendingPathComponent("stickers", isDirectory: true) }

    /// `~/Library/Application Support/com.ethan.stickermine`, created if needed.
    static func defaultRoot() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let root = root(inApplicationSupport: support)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    static func root(inApplicationSupport support: URL) -> URL {
        support.appendingPathComponent("com.ethan.stickermine", isDirectory: true)
    }

    // MARK: Loading

    private struct VersionProbe: Decodable {
        let version: Int
    }

    /// Reads library.json, applying the version gate, corrupt-file recovery and
    /// launch repair. It writes nothing except the corrupt file's rename; the
    /// repaired library is saved with the next user change.
    func load() -> LoadResult {
        isReadOnly = false
        let fileManager = FileManager.default
        try? fileManager.createDirectory(at: stickersDirectory, withIntermediateDirectories: true)
        guard fileManager.fileExists(atPath: libraryURL.path) else {
            return .fresh(repair(.empty))
        }
        let decoder = LibraryCoding.decoder()
        guard let data = try? Data(contentsOf: libraryURL),
              let probe = try? decoder.decode(VersionProbe.self, from: data)
        else {
            return .recoveredFromCorrupt(setAsideCorruptFile())
        }
        if probe.version > Library.currentVersion {
            isReadOnly = true
            log.notice("library.json is version \(probe.version); this build reads \(Library.currentVersion). Read-only.")
            // Whatever this build can read of it; never renamed, never repaired.
            return .readOnlyNewer((try? decoder.decode(Library.self, from: data)) ?? .empty)
        }
        guard let library = try? decoder.decode(Library.self, from: data) else {
            return .recoveredFromCorrupt(setAsideCorruptFile())
        }
        return .loaded(repair(library))
    }

    /// Renames library.json to `library.corrupt-<date>.json` and rebuilds
    /// history from the PNGs (placements are lost). If the rename fails, the
    /// store turns read-only so the unreadable file is never overwritten.
    private func setAsideCorruptFile() -> Library {
        let stamp = Self.corruptStamp(for: Date())
        var target = root.appendingPathComponent("library.corrupt-\(stamp).json")
        var counter = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = root.appendingPathComponent("library.corrupt-\(stamp)-\(counter).json")
            counter += 1
        }
        do {
            try FileManager.default.moveItem(at: libraryURL, to: target)
            log.error("library.json didn't decode; moved to \(target.lastPathComponent, privacy: .public)")
        } catch {
            isReadOnly = true
            log.error("library.json didn't decode and couldn't be moved aside: \(error.localizedDescription, privacy: .public)")
        }
        return repair(.empty)
    }

    /// "2026-10-15T21-02-33Z": ISO-8601 with dashes for colons, safe in Finder.
    static func corruptStamp(for date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date).replacingOccurrences(of: ":", with: "-")
    }

    /// Launch repair (spec section 12): drops entries whose PNG is missing (and
    /// their placements), adopts stray PNGs (pixel size from the image, pixels
    /// per point from its DPI or 2.0, created from the file's creation date,
    /// lastStyle puffy, no placements), and flags the fixed tutorial IDs.
    func repair(_ library: Library) -> Library {
        var result = library
        let onDisk = pngFiles()
        result.stickers.removeAll { onDisk[$0.id] == nil }
        let known = Set(result.stickers.map(\.id))
        let adopted = onDisk
            .filter { !known.contains($0.key) }
            .compactMap { adoptedRecord(id: $0.key, url: $0.value) }
            .sorted { ($0.created, $0.id.uuidString) < ($1.created, $1.id.uuidString) }
        result.stickers.append(contentsOf: adopted)
        for index in result.stickers.indices where Self.tutorialIDs.contains(result.stickers[index].id) {
            result.stickers[index].tutorial = true
        }
        let live = Set(result.stickers.map(\.id))
        for key in Array(result.displays.keys) {
            result.displays[key]?.placements.removeAll { !live.contains($0.sticker) }
        }
        return result
    }

    /// `stickers/<UUID>.png` files on disk, by sticker ID.
    private func pngFiles() -> [UUID: URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: stickersDirectory, includingPropertiesForKeys: [.creationDateKey])) ?? []
        var result: [UUID: URL] = [:]
        for url in urls where url.pathExtension.lowercased() == "png" {
            if let id = UUID(uuidString: url.deletingPathExtension().lastPathComponent) {
                result[id] = url
            }
        }
        return result
    }

    private func adoptedRecord(id: UUID, url: URL) -> StickerRecord? {
        guard let info = MasterImage.fileInfo(at: url) else {
            log.error("stray \(url.lastPathComponent, privacy: .public) isn't a readable image; not adopted")
            return nil
        }
        let created = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date()
        return StickerRecord(
            id: id,
            created: created,
            pixelWidth: info.pixelWidth,
            pixelHeight: info.pixelHeight,
            pixelsPerPoint: info.pixelsPerPoint ?? Self.defaultPixelsPerPoint,
            lastStyle: .puffy,
            tutorial: Self.tutorialIDs.contains(id)
        )
    }

    // MARK: Writing

    /// Writes library.json atomically. Throws `StoreError.readOnly` for a newer library.
    func save(_ library: Library) throws {
        guard !isReadOnly else { throw StoreError.readOnly }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = try LibraryCoding.encoder().encode(library)
        try data.write(to: libraryURL, options: .atomic)
    }

    func pngURL(for sticker: UUID) -> URL {
        stickersDirectory.appendingPathComponent("\(sticker.uuidString).png")
    }

    /// Writes a master PNG atomically (call off the main thread for real captures).
    func writePNG(_ data: Data, for sticker: UUID) throws {
        guard !isReadOnly else { throw StoreError.readOnly }
        try FileManager.default.createDirectory(at: stickersDirectory, withIntermediateDirectories: true)
        try data.write(to: pngURL(for: sticker), options: .atomic)
    }

    /// Removes a master PNG; a PNG that is already gone is not an error.
    func deletePNG(for sticker: UUID) throws {
        guard !isReadOnly else { throw StoreError.readOnly }
        let url = pngURL(for: sticker)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 86 tests in 12 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/MasterImage.swift Stickermine/Model/LibraryStore.swift StickermineTests/LibraryStoreTests.swift
git commit -m "Add LibraryStore: atomic saves, version gate, corrupt recovery and launch repair" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 6: LibraryController

**Files:**
- Create: `Stickermine/Model/LibraryController.swift`
- Test: `StickermineTests/LibraryControllerTests.swift`

**Interfaces:**
- Consumes: `LibraryStore` (Task 5); `Fixtures` (Task 3).
- Produces:

```text
@MainActor final class LibraryController {
    let store: LibraryStore
    let loadResult: LibraryStore.LoadResult
    private(set) var library: Library
    var onChange: (() -> Void)?
    private(set) var hasPendingSave: Bool
    private(set) var hasUnsavedChanges: Bool
    init(store: LibraryStore, saveDelay: TimeInterval = 0.5)  // loads the store (launch repair included)
    var isReadOnly: Bool { get }
    func mutate(_ change: (inout Library) -> Void)              // user change: save 0.5 s after the last one; ignored while read-only
    func refreshMetadata(_ change: (inout Library) -> Void)     // lastSeen/name: written with the next save, never schedules one
    func flush()                                                // save now if anything is unsaved
}
```

- [ ] **Step 1: Write the failing test**

`StickermineTests/LibraryControllerTests.swift` (complete file):

```swift
import Foundation
import Testing
@testable import Stickermine

@MainActor
struct LibraryControllerTests {
    private let fileManager = FileManager.default

    private func saved(_ store: LibraryStore) throws -> Library {
        try LibraryCoding.decoder().decode(Library.self, from: Data(contentsOf: store.libraryURL))
    }

    @Test func loadsTheStoreWhenCreated() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let id = UUID()
        try store.writePNG(Fixtures.pngData(width: 40, height: 20, pixelsPerPoint: 2), for: id)
        let library = Library(stickers: [Fixtures.sticker(id)], displays: [:])
        try store.save(library)
        let controller = LibraryController(store: store)
        #expect(controller.loadResult == .loaded(library))
        #expect(controller.library == library)
        #expect(!controller.isReadOnly)
        #expect(controller.store === store)
    }

    @Test func changesAreSavedOnceAfterTheDelay() async throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let controller = LibraryController(store: store, saveDelay: 0.3)
        let first = Fixtures.sticker()
        let second = Fixtures.sticker()
        controller.mutate { $0.stickers.append(first) }
        try await Task.sleep(for: .milliseconds(100))
        controller.mutate { $0.stickers.append(second) }   // restarts the 0.3 s wait
        #expect(controller.hasPendingSave)
        try await Task.sleep(for: .milliseconds(150))
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path), "saved before the last change was 0.3 s old")
        try await Task.sleep(for: .milliseconds(450))
        #expect(!controller.hasPendingSave)
        #expect(!controller.hasUnsavedChanges)
        #expect(try saved(store).stickers == [first, second])
    }

    @Test func flushSavesNowAndCancelsThePendingSave() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let controller = LibraryController(store: store, saveDelay: 60)
        let sticker = Fixtures.sticker()
        controller.mutate { $0.stickers.append(sticker) }
        #expect(controller.hasPendingSave)
        controller.flush()
        #expect(!controller.hasPendingSave)
        #expect(try saved(store).stickers == [sticker])
        // Nothing unsaved: a second flush writes nothing.
        try fileManager.removeItem(at: store.libraryURL)
        controller.flush()
        #expect(!fileManager.fileExists(atPath: store.libraryURL.path))
    }

    @Test func aChangeThatChangesNothingSchedulesNothing() {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let controller = LibraryController(store: LibraryStore(root: root), saveDelay: 60)
        var calls = 0
        controller.onChange = { calls += 1 }
        controller.mutate { _ in }
        #expect(!controller.hasPendingSave)
        #expect(calls == 0)
        controller.mutate { $0.stickers.append(Fixtures.sticker()) }
        #expect(calls == 1)
    }

    @Test func aReadOnlyLibraryIgnoresChanges() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.save(Library(version: 2, stickers: [], displays: [:]))
        let controller = LibraryController(store: store, saveDelay: 0)
        #expect(controller.isReadOnly)
        controller.mutate { $0.stickers.append(Fixtures.sticker()) }
        controller.refreshMetadata { $0.stickers.append(Fixtures.sticker()) }
        #expect(controller.library.stickers.isEmpty)
        #expect(!controller.hasPendingSave)
        controller.flush()
        #expect(try saved(store).version == 2)
    }

    @Test func metadataRefreshesWaitForTheNextSave() throws {
        let root = Fixtures.temporaryDirectory()
        defer { try? fileManager.removeItem(at: root) }
        let store = LibraryStore(root: root)
        let display = Fixtures.external()
        try store.save(Library(stickers: [], displays: [display.uuid: Fixtures.displayRecord(for: display, placements: [])]))
        let before = try Data(contentsOf: store.libraryURL)
        let controller = LibraryController(store: store, saveDelay: 60)
        let seen = Date(timeIntervalSince1970: 1_800_000_000)
        controller.refreshMetadata { $0.displays[display.uuid]?.lastSeen = seen }
        #expect(!controller.hasPendingSave)
        #expect(controller.hasUnsavedChanges)
        #expect(try Data(contentsOf: store.libraryURL) == before)
        controller.flush()
        #expect(try saved(store).displays[display.uuid]?.lastSeen == seen)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/LibraryControllerTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'LibraryController' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Model/LibraryController.swift` (complete file):

```swift
import Foundation
import os

/// The in-memory library and its debounced saves (spec section 12): every
/// change schedules one save 0.5 s after the last change; `flush()` saves now
/// (applicationWillTerminate, and M6's updater before its helper runs). JSON is
/// encoded and written on the main actor.
@MainActor
final class LibraryController {
    let store: LibraryStore
    /// How the library was loaded (M6 shows the read-only notice for `.readOnlyNewer`).
    let loadResult: LibraryStore.LoadResult
    private(set) var library: Library
    /// Called after every change made through `mutate`.
    var onChange: (() -> Void)?
    /// A save is scheduled.
    private(set) var hasPendingSave = false
    /// Memory differs from what was last written.
    private(set) var hasUnsavedChanges = false

    private let saveDelay: TimeInterval
    private var saveWork: DispatchWorkItem?
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "library")

    init(store: LibraryStore, saveDelay: TimeInterval = 0.5) {
        self.store = store
        self.saveDelay = saveDelay
        let result = store.load()
        loadResult = result
        library = result.library
    }

    /// A library written by a newer Stickermine: shown, never changed.
    var isReadOnly: Bool { store.isReadOnly }

    /// Applies a user change and schedules a save. Ignored while read-only;
    /// a change that changes nothing schedules nothing.
    func mutate(_ change: (inout Library) -> Void) {
        guard !isReadOnly else {
            log.notice("change ignored: the library is read-only")
            return
        }
        var updated = library
        change(&updated)
        guard updated != library else { return }
        library = updated
        hasUnsavedChanges = true
        scheduleSave()
        onChange?()
    }

    /// For the spec's write exceptions that aren't user actions (a recorded
    /// display's `lastSeen` and `name`): kept in memory and written with the
    /// next save or flush, never scheduling one, so display events never write.
    func refreshMetadata(_ change: (inout Library) -> Void) {
        guard !isReadOnly else { return }
        var updated = library
        change(&updated)
        guard updated != library else { return }
        library = updated
        hasUnsavedChanges = true
    }

    /// Saves now if anything is unsaved, cancelling the scheduled save.
    func flush() {
        saveWork?.cancel()
        saveWork = nil
        hasPendingSave = false
        guard hasUnsavedChanges, !isReadOnly else { return }
        do {
            try store.save(library)
            hasUnsavedChanges = false
        } catch {
            log.error("saving library.json failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.flush() }
        }
        saveWork = work
        hasPendingSave = true
        DispatchQueue.main.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 92 tests in 13 suites passed` and `** TEST SUCCEEDED **`. `LibraryControllerTests.changesAreSavedOnceAfterTheDelay` sleeps about 0.7 s.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Model/LibraryController.swift StickermineTests/LibraryControllerTests.swift
git commit -m "Add LibraryController with debounced saves and flush" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 7: StickerGeometry

**Files:**
- Create: `Stickermine/Stickers/StickerGeometry.swift`
- Test: `StickermineTests/StickerGeometryTests.swift`

**Interfaces:**
- Consumes: `Pose`, `Placement` (Task 1); `LayoutResolver`, `DisplaySize` (Task 2); `DisplayInfo` (Task 3); `Fixtures` (Task 3).
- Produces:

```text
enum StickerGeometry {
    static let reachableInset: CGFloat                         // 8
    struct Layout: Equatable { let pose: Pose; let isBorrowed: Bool; let pointSize: CGSize; let stickerRect: CGRect }
    static func boundingSize(of size: CGSize, rotation: Double) -> CGSize
    static func center(of pose: Pose, in frame: CGRect) -> CGPoint
    static func pose(center: CGPoint, scale: Double, in frame: CGRect) -> Pose
    static func reachableCenter(_ center: CGPoint, visibleFrame: CGRect) -> CGPoint
    static func clampedRect(size: CGSize, center: CGPoint, within frame: CGRect) -> CGRect
    static func layout(for placement: Placement, natural: CGSize, on display: DisplayInfo) -> Layout?
}
```

The rules (spec section 11): positions are relative to `NSScreen.frame`; when drawing, the whole sticker is kept inside its display's frame; a borrowed (derived) pose also has its centre kept inside `visibleFrame` inset by 8 pt. None of this writes: `StickerManager` draws with it, and only a user action saves a pose. `boundingSize` is a non-isolated copy of `StickerView.boundingSize(of:scale:rotation:)` (which is main-actor isolated), so the renderer can use it off the main actor.

- [ ] **Step 1: Write the failing test**

`StickermineTests/StickerGeometryTests.swift` (complete file):

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct StickerGeometryTests {
    private let frame = CGRect(x: 40_000, y: 100, width: 1920, height: 1080)

    @Test func aPoseCentreIsRelativeToItsDisplaysFrame() {
        let center = StickerGeometry.center(of: Pose(x: 0.25, y: 0.5, scale: 1), in: frame)
        #expect(center == CGPoint(x: 40_480, y: 640))
        let pose = StickerGeometry.pose(center: center, scale: 1.5, in: frame)
        #expect(pose == Pose(x: 0.25, y: 0.5, scale: 1.5))
    }

    @Test func theStickerIsClampedInsideTheFrame() {
        let rect = StickerGeometry.clampedRect(size: CGSize(width: 200, height: 100),
                                               center: CGPoint(x: frame.maxX - 10, y: frame.minY + 5), within: frame)
        #expect(rect == CGRect(x: frame.maxX - 200, y: frame.minY, width: 200, height: 100))
    }

    @Test func aStickerLargerThanTheDisplayIsCentredOnThatAxis() {
        let rect = StickerGeometry.clampedRect(size: CGSize(width: 3000, height: 100),
                                               center: CGPoint(x: frame.minX, y: frame.midY), within: frame)
        #expect(rect.midX == frame.midX)
        #expect(rect.midY == frame.midY)
    }

    @Test func aCentreIsPulledInsideTheVisibleFrame() {
        let visible = CGRect(x: 40_000, y: 180, width: 1920, height: 970)   // Dock below, menu bar above
        #expect(StickerGeometry.reachableCenter(CGPoint(x: 40_000, y: 1180), visibleFrame: visible)
                == CGPoint(x: 40_008, y: 1142))
        #expect(StickerGeometry.reachableCenter(CGPoint(x: 41_000, y: 600), visibleFrame: visible)
                == CGPoint(x: 41_000, y: 600))
    }

    @Test func rotationGrowsTheBoundingBox() {
        let quarter = StickerGeometry.boundingSize(of: CGSize(width: 200, height: 100), rotation: .pi / 2)
        #expect(abs(quarter.width - 100) < 1e-9 && abs(quarter.height - 200) < 1e-9)
        let eighth = StickerGeometry.boundingSize(of: CGSize(width: 100, height: 100), rotation: .pi / 4)
        #expect(abs(eighth.width - 100 * 2.0.squareRoot()) < 1e-9)
    }

    @Test func aStoredPoseIsDrawnWhereItSays() throws {
        let display = Fixtures.display(uuid: "A", id: 3, frame: frame,
                                       visibleFrame: CGRect(x: 40_000, y: 100, width: 1920, height: 1050))
        // Near the top edge, under the menu bar: stored poses are not pulled in.
        let placement = Placement(sticker: UUID(), style: .shadow, poses: ["1920x1080": Pose(x: 0.5, y: 0.99, scale: 0.5)])
        let layout = try #require(StickerGeometry.layout(for: placement, natural: CGSize(width: 200, height: 100), on: display))
        #expect(!layout.isBorrowed)
        #expect(layout.pointSize == CGSize(width: 100, height: 50))
        // Clamped inside the frame: top edge at the frame's top.
        #expect(layout.stickerRect == CGRect(x: 40_910, y: 1130, width: 100, height: 50))
    }

    @Test func aBorrowedPoseHasItsCentreMadeReachable() throws {
        let display = Fixtures.display(uuid: "A", id: 3, frame: frame,
                                       visibleFrame: CGRect(x: 40_000, y: 100, width: 1920, height: 1050))
        let placement = Placement(sticker: UUID(), style: .shadow, poses: ["2560x1440": Pose(x: 0.5, y: 0.999, scale: 0.1)])
        let layout = try #require(StickerGeometry.layout(for: placement, natural: CGSize(width: 200, height: 100), on: display))
        #expect(layout.isBorrowed)
        #expect(layout.stickerRect.midY == 1142)   // visible maxY 1150 − 8
        #expect(abs(layout.pose.scale - 0.075) < 1e-12)
    }

    @Test func noPoseMeansNoLayout() {
        let display = Fixtures.display(uuid: "A", id: 3, frame: frame)
        let placement = Placement(sticker: UUID(), style: .shadow, poses: [:])
        #expect(StickerGeometry.layout(for: placement, natural: CGSize(width: 10, height: 10), on: display) == nil)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/StickerGeometryTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'StickerGeometry' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Stickers/StickerGeometry.swift` (complete file):

```swift
import CoreGraphics
import Foundation

/// Pure geometry between the model (normalized poses) and windows (screen
/// points). Drawing never writes: the clamps here only change where a sticker
/// is drawn (spec section 11).
enum StickerGeometry {
    /// A borrowed pose's centre stays this far inside the display's visible
    /// frame, so a sticker never ends up unreachable under the menu bar or Dock.
    static let reachableInset: CGFloat = 8

    struct Layout: Equatable {
        /// The pose used: stored for this size, or borrowed from the closest one.
        let pose: Pose
        let isBorrowed: Bool
        /// Unrotated on-screen size in points (natural size × pose scale).
        let pointSize: CGSize
        /// The rotated sticker's box in screen points, clamped inside the
        /// display's frame. The window is this plus the shadow margin.
        let stickerRect: CGRect
    }

    /// The axis-aligned box of `size` rotated by `rotation` radians.
    static func boundingSize(of size: CGSize, rotation: Double) -> CGSize {
        let c = abs(cos(rotation))
        let s = abs(sin(rotation))
        return CGSize(width: size.width * c + size.height * s, height: size.width * s + size.height * c)
    }

    /// The screen point a pose's normalized centre stands for.
    static func center(of pose: Pose, in frame: CGRect) -> CGPoint {
        CGPoint(x: frame.minX + CGFloat(pose.x) * frame.width, y: frame.minY + CGFloat(pose.y) * frame.height)
    }

    /// The pose for a screen-point centre on a display with `frame`.
    static func pose(center: CGPoint, scale: Double, in frame: CGRect) -> Pose {
        Pose(x: Double((center.x - frame.minX) / frame.width),
             y: Double((center.y - frame.minY) / frame.height),
             scale: scale)
    }

    /// `center` moved inside `visibleFrame` inset by `reachableInset`.
    static func reachableCenter(_ center: CGPoint, visibleFrame: CGRect) -> CGPoint {
        let area = visibleFrame.insetBy(dx: reachableInset, dy: reachableInset)
        guard !area.isNull, area.width >= 0, area.height >= 0 else {
            return CGPoint(x: visibleFrame.midX, y: visibleFrame.midY)
        }
        return CGPoint(x: min(max(center.x, area.minX), area.maxX),
                       y: min(max(center.y, area.minY), area.maxY))
    }

    /// A `size` box centred on `center`, moved fully inside `frame` (centred on
    /// an axis where it is larger than the frame).
    static func clampedRect(size: CGSize, center: CGPoint, within frame: CGRect) -> CGRect {
        func axis(_ c: CGFloat, _ length: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
            if length >= upper - lower { return (lower + upper - length) / 2 }
            return min(max(c - length / 2, lower), upper - length)
        }
        return CGRect(x: axis(center.x, size.width, frame.minX, frame.maxX),
                      y: axis(center.y, size.height, frame.minY, frame.maxY),
                      width: size.width, height: size.height)
    }

    /// Where `placement` of a sticker with `natural` point size is drawn on
    /// `display`; nil when the placement has no usable pose.
    static func layout(for placement: Placement, natural: CGSize, on display: DisplayInfo) -> Layout? {
        guard let pose = LayoutResolver.pose(for: placement, at: display.size),
              display.frame.width > 0, display.frame.height > 0
        else { return nil }
        let isBorrowed = placement.poses[display.size.key] == nil
        var center = center(of: pose, in: display.frame)
        if isBorrowed {
            center = reachableCenter(center, visibleFrame: display.visibleFrame)
        }
        let pointSize = CGSize(width: natural.width * CGFloat(pose.scale), height: natural.height * CGFloat(pose.scale))
        let box = boundingSize(of: pointSize, rotation: placement.rotation)
        return Layout(pose: pose, isBorrowed: isBorrowed, pointSize: pointSize,
                      stickerRect: clampedRect(size: box, center: center, within: display.frame))
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 100 tests in 14 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Stickers/StickerGeometry.swift StickermineTests/StickerGeometryTests.swift
git commit -m "Add sticker geometry: pose centres, clamps and layouts" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 8: The baseline StyleRenderer and StickerView.show

**Files:**
- Create: `Stickermine/Capture/StyleRenderer.swift`
- Modify: `Stickermine/Stickers/StickerView.swift` (one method added)
- Test: `StickermineTests/StyleRendererTests.swift`; Modify: `StickermineTests/StickerViewTests.swift` (one test added)

**Interfaces:**
- Consumes: `StickerStyle` (Task 1), `StickerGeometry.boundingSize(of:rotation:)` (Task 7), `StyleParameters` (Task 4); M1's `StickerView.showContents(_:pointSize:shadow:)`, `TestImages`.
- Produces (contract signatures plus the baseline's helpers):

```text
struct RenderRequest: Equatable {
    let sticker: UUID; let style: StickerStyle; let flipped: Bool; let rotation: Double
    let pointSize: CGSize; let backingScale: CGFloat
}
struct RenderedSticker { let contents: Any; let pixelSize: CGSize; let pointBounds: CGSize; let alphaMask: AlphaMask }
struct AlphaMask { let width: Int; let height: Int; let bytes: [UInt8]; func isOpaque(atUnit p: CGPoint) -> Bool }
final class StyleRenderer {
    enum RenderError: Error, Equatable { case missingMaster, emptySize, contextFailed }
    static let maxPixelLongSide: Double                        // 2048
    static let maxMaskLongSide: Int                            // 512
    static let alphaFloor: UInt8                               // 5 (≈ 0.02)
    init(masterProvider: @escaping (UUID) -> CGImage?)         // called off the main thread
    func render(_ request: RenderRequest) async throws -> RenderedSticker
    func prewarm()                                             // nothing to compile in the baseline
    static func canvas(for request: RenderRequest) -> (width: Int, height: Int, drawSize: CGSize, pointBounds: CGSize)
    static func renderBaseline(master: CGImage, request: RenderRequest) throws -> RenderedSticker
    static func clampAlphaAndBuildMask(pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> AlphaMask
}
// Added to M1's StickerView class:
//     func show(_ rendered: RenderedSticker, shadow: StyleParameters?, style: StickerStyle)
```

The baseline renders every style the same way: the master scaled to the on-screen pixel size (points × backing scale), capped at 2048 px on the long side, with flip and rotation baked in (flip in the sticker's own frame, then rotation counter-clockwise about the centre), in the master's colour space (sRGB for a non-RGB master), with alpha below 5/255 cleared and a coarse alpha mask (long side ≤ 512, each cell the largest alpha it covers) built in the same pass. The contents are a `CGImage`; M3 decides between IOSurface and CGImage (spike rows 15–16) and replaces the drawing per style.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/StyleRendererTests.swift` (complete file):

```swift
import CoreGraphics
import Foundation
import Testing
@testable import Stickermine

struct StyleRendererTests {
    private let id = UUID()

    private func request(points: CGSize, scale: CGFloat = 2, rotation: Double = 0, flipped: Bool = false,
                         style: StickerStyle = .outline) -> RenderRequest {
        RenderRequest(sticker: id, style: style, flipped: flipped, rotation: rotation, pointSize: points,
                      backingScale: scale)
    }

    private func renderer(_ master: CGImage?) -> StyleRenderer {
        StyleRenderer(masterProvider: { _ in master })
    }

    /// The baseline's contents are a CGImage.
    private func image(_ rendered: RenderedSticker) throws -> CGImage {
        let contents = rendered.contents as AnyObject
        try #require(CFGetTypeID(contents) == CGImage.typeID)
        return contents as! CGImage
    }

    @Test func rendersAtTheOnScreenPixelSize() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50)))
        #expect(rendered.pixelSize == CGSize(width: 200, height: 100))
        #expect(rendered.pointBounds == CGSize(width: 100, height: 50))
        let bitmap = try image(rendered)
        #expect(bitmap.width == 200)
        #expect(bitmap.height == 100)
    }

    @Test func theLongSideIsCappedAt2048Pixels() async throws {
        let master = Fixtures.image(width: 800, height: 400)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 2000, height: 1000)))
        #expect(rendered.pixelSize == CGSize(width: 2048, height: 1024))
        // The layer scales the capped bitmap back up to the full point size.
        #expect(rendered.pointBounds == CGSize(width: 2000, height: 1000))
        #expect(StyleRenderer.maxPixelLongSide == 2048)
    }

    @Test func rotationIsBakedIntoTheBoundingBox() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let quarter = try await renderer(master).render(request(points: CGSize(width: 100, height: 50), rotation: .pi / 2))
        #expect(quarter.pixelSize == CGSize(width: 100, height: 200))
        #expect(abs(quarter.pointBounds.width - 50) < 1e-9)
        #expect(abs(quarter.pointBounds.height - 100) < 1e-9)
        // A quarter turn counter-clockwise puts the master's left (red) half at the bottom.
        let bitmap = try image(quarter)
        let bottom = TestImages.rgba(of: bitmap, x: 50, y: 190)
        let top = TestImages.rgba(of: bitmap, x: 50, y: 10)
        #expect(bottom[0] > 200 && bottom[2] < 50)
        #expect(top[2] > 200 && top[0] < 50)
    }

    @Test func flipIsBakedIn() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50), flipped: true))
        let bitmap = try image(rendered)
        let left = TestImages.rgba(of: bitmap, x: 10, y: 50)
        let right = TestImages.rgba(of: bitmap, x: 190, y: 50)
        #expect(left[2] > 200 && left[0] < 50)    // blue now on the left
        #expect(right[0] > 200 && right[2] < 50)  // red on the right
    }

    @Test func theAlphaMaskMarksOpaquePixelsOnly() async throws {
        let master = Fixtures.image(width: 400, height: 200, left: [0, 200, 0, 255], right: [0, 0, 0, 0])
        let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50)))
        let mask = rendered.alphaMask
        #expect(mask.width == 200 && mask.height == 100)
        #expect(mask.isOpaque(atUnit: CGPoint(x: 0.25, y: 0.5)))
        #expect(!mask.isOpaque(atUnit: CGPoint(x: 0.75, y: 0.5)))
        #expect(!mask.isOpaque(atUnit: CGPoint(x: 1.5, y: 0.5)))
    }

    @Test func faintAlphaIsClearedSoItNeverCatchesClicks() async throws {
        // Alpha 3/255 on the right half: below the 0.02 floor.
        let master = Fixtures.image(width: 400, height: 200, left: [255, 255, 255, 255], right: [3, 3, 3, 3])
        let rendered = try await renderer(master).render(request(points: CGSize(width: 200, height: 100), scale: 1))
        let bitmap = try image(rendered)
        #expect(TestImages.rgba(of: bitmap, x: 150, y: 50) == [0, 0, 0, 0])
        #expect(TestImages.rgba(of: bitmap, x: 50, y: 50)[3] == 255)
        #expect(!rendered.alphaMask.isOpaque(atUnit: CGPoint(x: 0.75, y: 0.5)))
    }

    @Test func theMaskStaysSmallForLargeBitmaps() async throws {
        let master = Fixtures.image(width: 800, height: 400)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 1000, height: 500)))
        #expect(rendered.pixelSize == CGSize(width: 2000, height: 1000))
        #expect(rendered.alphaMask.width == 512)
        #expect(rendered.alphaMask.height == 256)
        #expect(rendered.alphaMask.isOpaque(atUnit: CGPoint(x: 0.5, y: 0.5)))
    }

    @Test func theMastersColourSpaceIsKept() async throws {
        let p3 = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let master = Fixtures.image(width: 40, height: 20, colorSpace: p3)
        let rendered = try await renderer(master).render(request(points: CGSize(width: 20, height: 10)))
        #expect(try image(rendered).colorSpace?.name == CGColorSpace.displayP3)
    }

    @Test func everyStyleRendersTheBaselineBitmap() async throws {
        let master = Fixtures.image(width: 400, height: 200)
        for style in StickerStyle.allCases {
            let rendered = try await renderer(master).render(request(points: CGSize(width: 100, height: 50), style: style))
            #expect(rendered.pixelSize == CGSize(width: 200, height: 100), "\(style)")
        }
    }

    @Test func aMissingMasterThrows() async {
        await #expect(throws: StyleRenderer.RenderError.missingMaster) {
            _ = try await renderer(nil).render(request(points: CGSize(width: 10, height: 10)))
        }
    }
}
```

In `StickermineTests/StickerViewTests.swift`, add this test as the last member of `struct StickerViewTests` (directly above the struct's final closing `}`, after `contentTransformScalesAndRotatesAroundTheCentre()`):

```swift
    @Test func showingARenderedStickerUsesItsPointBounds() {
        let view = makeView()
        let image = TestImages.bands(width: 300, height: 120, top: (0, 255, 0), bottom: (0, 0, 255))
        let rendered = RenderedSticker(contents: image, pixelSize: CGSize(width: 300, height: 120),
                                       pointBounds: CGSize(width: 150, height: 60),
                                       alphaMask: AlphaMask(width: 1, height: 1, bytes: [255]))
        view.show(rendered, shadow: nil, style: .outline)
        #expect(view.contentPointSize == CGSize(width: 150, height: 60))
        #expect((view.contentLayer.contents as AnyObject?) === image)
        // The M2 baseline draws no shadow; M3 adds it.
        #expect(view.layerShadow == nil)
        #expect(view.contentLayer.shadowOpacity == 0)
    }
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/StyleRendererTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'StyleRenderer' in scope`, `error: cannot find type 'RenderRequest' in scope` and `error: cannot find type 'RenderedSticker' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Capture/StyleRenderer.swift` (complete file):

```swift
import CoreGraphics
import Foundation

/// Everything a sticker's bitmap depends on. Two equal requests give the same bitmap.
struct RenderRequest: Equatable {
    let sticker: UUID
    let style: StickerStyle
    let flipped: Bool
    /// Radians, counter-clockwise on screen.
    let rotation: Double
    /// The unrotated on-screen size in points (natural size × pose scale).
    let pointSize: CGSize
    let backingScale: CGFloat
}

struct RenderedSticker {
    /// A CGImage (the M2 baseline) or an IOSurface, set as `CALayer.contents`.
    let contents: Any
    /// The bitmap's size in pixels (long side at most `StyleRenderer.maxPixelLongSide`).
    let pixelSize: CGSize
    /// The rotated bounding box of the sticker in points, without shadow margin.
    let pointBounds: CGSize
    let alphaMask: AlphaMask
}

/// A coarse copy of the bitmap's alpha (long side at most 512): a cell is the
/// largest alpha among the pixels it covers, so any visible pixel marks it.
struct AlphaMask {
    let width: Int
    let height: Int
    /// Row-major, row 0 at the top.
    let bytes: [UInt8]

    /// `p` in 0–1 with the origin at the top-left of the bitmap.
    func isOpaque(atUnit p: CGPoint) -> Bool {
        guard width > 0, height > 0, bytes.count == width * height,
              p.x >= 0, p.x <= 1, p.y >= 0, p.y <= 1
        else { return false }
        let x = min(width - 1, Int(p.x * CGFloat(width)))
        let y = min(height - 1, Int(p.y * CGFloat(height)))
        return bytes[y * width + x] > 0
    }
}

/// Renders a sticker's bitmap for a request, off the main actor.
///
/// M2 baseline: every style draws the master unstyled, scaled to the on-screen
/// pixel size (capped at 2048 px on the long side; above that the layer scales
/// it up), with flip and rotation baked in and alpha below about 0.02 cleared,
/// so faint fringes never catch clicks (spec sections 8 and 9). M3 replaces the
/// per-style drawing inside `render` and adds the Puffy kernel to `prewarm`.
final class StyleRenderer {
    enum RenderError: Error, Equatable {
        case missingMaster
        case emptySize
        case contextFailed
    }

    static let maxPixelLongSide: Double = 2048
    static let maxMaskLongSide = 512
    /// Alpha below this (about 0.02 × 255) becomes 0.
    static let alphaFloor: UInt8 = 5

    private let masterProvider: (UUID) -> CGImage?

    /// `masterProvider` loads a sticker's master image. It is called off the
    /// main thread and must be thread-safe.
    init(masterProvider: @escaping (UUID) -> CGImage?) {
        self.masterProvider = masterProvider
    }

    func render(_ request: RenderRequest) async throws -> RenderedSticker {
        guard let master = masterProvider(request.sticker) else { throw RenderError.missingMaster }
        return try Self.renderBaseline(master: master, request: request)
    }

    /// The baseline has nothing to compile; M3 compiles the Puffy kernel here.
    func prewarm() {}

    /// The canvas for a request: the rotated bounding box in pixels, capped at
    /// `maxPixelLongSide`, and the size the unrotated master is drawn at.
    static func canvas(for request: RenderRequest) -> (width: Int, height: Int, drawSize: CGSize, pointBounds: CGSize) {
        let pixelSize = CGSize(width: request.pointSize.width * request.backingScale,
                               height: request.pointSize.height * request.backingScale)
        let box = StickerGeometry.boundingSize(of: pixelSize, rotation: request.rotation)
        let longSide = max(box.width, box.height)
        let cap = longSide > maxPixelLongSide ? maxPixelLongSide / longSide : 1
        // The tiny allowance keeps 100.000000001 from becoming 101 after rotation.
        let width = max(1, Int((box.width * cap - 0.001).rounded(.up)))
        let height = max(1, Int((box.height * cap - 0.001).rounded(.up)))
        let drawSize = CGSize(width: pixelSize.width * cap, height: pixelSize.height * cap)
        return (width, height, drawSize, StickerGeometry.boundingSize(of: request.pointSize, rotation: request.rotation))
    }

    static func renderBaseline(master: CGImage, request: RenderRequest) throws -> RenderedSticker {
        guard request.pointSize.width > 0, request.pointSize.height > 0, request.backingScale > 0 else {
            throw RenderError.emptySize
        }
        let canvas = canvas(for: request)
        let rgbSpace = master.colorSpace.flatMap { $0.model == .rgb ? $0 : nil }
        guard let colorSpace = rgbSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: canvas.width, height: canvas.height, bitsPerComponent: 8,
                  bytesPerRow: canvas.width * 4, space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { throw RenderError.contextFailed }
        context.interpolationQuality = .high
        // Flip in the sticker's own frame, then rotate, around the canvas centre.
        context.translateBy(x: CGFloat(canvas.width) / 2, y: CGFloat(canvas.height) / 2)
        context.rotate(by: CGFloat(request.rotation))
        if request.flipped { context.scaleBy(x: -1, y: 1) }
        let draw = canvas.drawSize
        context.draw(master, in: CGRect(x: -draw.width / 2, y: -draw.height / 2, width: draw.width, height: draw.height))

        guard let data = context.data else { throw RenderError.contextFailed }
        let mask = clampAlphaAndBuildMask(
            pixels: data.bindMemory(to: UInt8.self, capacity: canvas.width * canvas.height * 4),
            width: canvas.width, height: canvas.height)
        guard let image = context.makeImage() else { throw RenderError.contextFailed }
        return RenderedSticker(
            contents: image,
            pixelSize: CGSize(width: canvas.width, height: canvas.height),
            pointBounds: canvas.pointBounds,
            alphaMask: mask
        )
    }

    /// One pass over premultiplied RGBA rows (row 0 at the top): clears pixels
    /// whose alpha is below `alphaFloor` and records the largest alpha per mask cell.
    static func clampAlphaAndBuildMask(pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> AlphaMask {
        let longSide = max(width, height)
        let factor = longSide > maxMaskLongSide ? Double(maxMaskLongSide) / Double(longSide) : 1
        let maskWidth = max(1, Int((Double(width) * factor).rounded(.up)))
        let maskHeight = max(1, Int((Double(height) * factor).rounded(.up)))
        var bytes = [UInt8](repeating: 0, count: maskWidth * maskHeight)
        bytes.withUnsafeMutableBufferPointer { mask in
            for y in 0..<height {
                let maskRow = min(maskHeight - 1, y * maskHeight / height) * maskWidth
                let row = pixels + y * width * 4
                for x in 0..<width {
                    let pixel = row + x * 4
                    let alpha = pixel[3]
                    if alpha < alphaFloor {
                        if alpha != 0 { pixel[0] = 0; pixel[1] = 0; pixel[2] = 0; pixel[3] = 0 }
                        continue
                    }
                    let cell = maskRow + min(maskWidth - 1, x * maskWidth / width)
                    if alpha > mask[cell] { mask[cell] = alpha }
                }
            }
        }
        return AlphaMask(width: maskWidth, height: maskHeight, bytes: bytes)
    }
}
```

In `Stickermine/Stickers/StickerView.swift`, insert this method directly above the line `    /// Drops the bitmap. Call before ordering out and closing a panel for good:` (that is, right after the closing brace of `func showContents(_ contents: Any, pointSize: CGSize, shadow: LayerShadow?)`). Nothing else in the file changes:

```swift
    /// Shows a rendered sticker at its point bounds. The M2 baseline renders no
    /// shadow and M3 adds the layer shadow (built from `shadow`, nil for None),
    /// so this passes no `LayerShadow` yet.
    func show(_ rendered: RenderedSticker, shadow: StyleParameters?, style: StickerStyle) {
        showContents(rendered.contents, pointSize: rendered.pointBounds, shadow: nil)
    }
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 111 tests in 15 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Capture/StyleRenderer.swift Stickermine/Stickers/StickerView.swift StickermineTests/StyleRendererTests.swift StickermineTests/StickerViewTests.swift
git commit -m "Add the baseline StyleRenderer: size-capped bitmaps with an alpha mask" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 9: ScreenProvider and LiveScreenProvider

**Files:**
- Create: `Stickermine/Model/ScreenProvider.swift`
- Test: `StickermineTests/FakeScreens.swift`, `StickermineTests/LiveScreenProviderTests.swift`

**Interfaces:**
- Consumes: `DisplayInfo`, `DisplayRegistry` (Task 3).
- Produces:

```text
@MainActor protocol ScreenProvider: AnyObject {
    func currentDisplays() -> [DisplayInfo]                    // already filtered by DisplayRegistry.usable
    var mainDisplay: DisplayInfo? { get }                       // NSScreen.screens[0]
}
@MainActor final class LiveScreenProvider: ScreenProvider {
    init()
    static func info(for screen: NSScreen) -> DisplayInfo?     // nil without a display ID or UUID
}
// Test target:
@MainActor final class FakeScreens: ScreenProvider { var all: [DisplayInfo]; init(_ all: [DisplayInfo]) }
```

Presence comes from `NSScreen.screens` only (a sleeping display stays in it; `CGGetActiveDisplayList` drops it). `NSScreen.cgDirectDisplayID` is in the macOS 26 SDK. Boolean CG calls are compared with `== 1` because they return −1 for a vanished ID.

- [ ] **Step 1: Write the fake and the failing test**

`StickermineTests/FakeScreens.swift` (complete file):

```swift
@testable import Stickermine

/// A ScreenProvider whose displays a test sets, to simulate unplugging,
/// replugging, mirroring and resolution changes.
@MainActor
final class FakeScreens: ScreenProvider {
    var all: [DisplayInfo]

    init(_ all: [DisplayInfo]) {
        self.all = all
    }

    func currentDisplays() -> [DisplayInfo] {
        DisplayRegistry.usable(all)
    }

    var mainDisplay: DisplayInfo? {
        currentDisplays().first
    }
}
```

`StickermineTests/LiveScreenProviderTests.swift` (complete file):

```swift
import AppKit
import Testing
@testable import Stickermine

@MainActor
struct LiveScreenProviderTests {
    @Test func everyRealScreenIsReportedWithItsUUID() throws {
        let displays = LiveScreenProvider().currentDisplays()
        try #require(!displays.isEmpty)
        for display in displays {
            #expect(display.uuid == display.uuid.uppercased())
            #expect(display.uuid == DisplayRegistry.uuidString(for: display.displayID))
            #expect(!display.isGhost)
            #expect(display.mirrorsDisplayID == nil)
            let screen = try #require(NSScreen.screens.first { $0.cgDirectDisplayID == display.displayID })
            #expect(display.frame == screen.frame)
            #expect(display.visibleFrame == screen.visibleFrame)
            #expect(display.backingScale == screen.backingScaleFactor)
            #expect(display.name == screen.localizedName)
        }
        #expect(Set(displays.map(\.uuid)).count == displays.count)
    }

    @Test func theMainDisplayIsTheMenuBarScreen() throws {
        let main = try #require(LiveScreenProvider().mainDisplay)
        #expect(main.frame == NSScreen.screens[0].frame)
        #expect(main.frame.origin == .zero)
    }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/LiveScreenProviderTests
```

Expected: `** TEST FAILED **` with `error: cannot find type 'ScreenProvider' in scope` in `FakeScreens.swift`.

- [ ] **Step 3: Implement**

`Stickermine/Model/ScreenProvider.swift` (complete file):

```swift
import AppKit

/// Where StickerManager learns which displays exist. The live one reads
/// `NSScreen.screens`; tests substitute a fake to simulate unplugging,
/// mirroring and resolution changes.
@MainActor
protocol ScreenProvider: AnyObject {
    /// Connected displays, already filtered by `DisplayRegistry.usable`.
    func currentDisplays() -> [DisplayInfo]
    /// `NSScreen.screens[0]` (the menu-bar display), never `NSScreen.main`.
    var mainDisplay: DisplayInfo? { get }
}

@MainActor
final class LiveScreenProvider: ScreenProvider {
    init() {}

    /// Presence comes from `NSScreen.screens` only: a sleeping display stays in
    /// it, while `CGGetActiveDisplayList` drops it.
    func currentDisplays() -> [DisplayInfo] {
        DisplayRegistry.usable(NSScreen.screens.compactMap(Self.info(for:)))
    }

    var mainDisplay: DisplayInfo? {
        guard let first = NSScreen.screens.first, let id = first.cgDirectDisplayID else { return nil }
        return currentDisplays().first { $0.displayID == id }
    }

    /// nil for a screen without a display ID or UUID (both mean "no display").
    static func info(for screen: NSScreen) -> DisplayInfo? {
        guard let id = screen.cgDirectDisplayID, id != kCGNullDirectDisplay,
              let uuid = DisplayRegistry.uuidString(for: id)
        else { return nil }
        let mirrored = CGDisplayMirrorsDisplay(id)
        return DisplayInfo(
            uuid: uuid,
            displayID: id,
            frame: screen.frame,
            visibleFrame: screen.visibleFrame,
            backingScale: screen.backingScaleFactor,
            name: screen.localizedName,
            vendor: CGDisplayVendorNumber(id),
            model: CGDisplayModelNumber(id),
            serial: CGDisplaySerialNumber(id),
            // Boolean CG calls return -1 for a vanished ID: compare with 1.
            builtin: CGDisplayIsBuiltin(id) == 1,
            mirrorsDisplayID: mirrored == kCGNullDirectDisplay ? nil : mirrored,
            inMirrorSet: CGDisplayIsInMirrorSet(id) == 1
        )
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 113 tests in 16 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Model/ScreenProvider.swift StickermineTests/FakeScreens.swift StickermineTests/LiveScreenProviderTests.swift
git commit -m "Add ScreenProvider over NSScreen.screens and a fake for tests" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 10: The fallback click-through mode

**Files:**
- Create: `Stickermine/Stickers/ClickThroughFallback.swift`
- Test: `StickermineTests/ClickThroughFallbackTests.swift`; Modify: `StickermineTests/PanelPolicyTests.swift` (one function replaced)

**Interfaces:**
- Consumes: `AlphaMask` (Task 8); M1's `PanelPolicy.makeStickerPanel(contentRect:)`.
- Produces:

```text
@MainActor final class ClickThroughFallback {
    struct Target { let panel: NSPanel; let contentRect: CGRect; let mask: AlphaMask?; let wholeFrame: Bool }
    struct Candidate { let contentRect: CGRect; let frame: CGRect; let mask: AlphaMask?; let wholeFrame: Bool }
    private(set) weak var activePanel: NSPanel?
    init(targets: @escaping () -> [Target])                    // front to back
    func prepare(_ panel: NSPanel)                             // ignoresMouseEvents = true; adds a mouse-moved tracking area
    func forget(_ panel: NSPanel)
    func start(); func stop()                                  // global + local mouse-moved/dragged monitors
    func update(at point: NSPoint)
    nonisolated static func hitIndex(at p: CGPoint, in candidates: [Candidate]) -> Int?
}
```

Spec section 9: in this hidden mode (`clickThroughFallback`, read at launch) every sticker gets an explicit `ignoresMouseEvents = true`, and the sticker whose opaque pixels are under the cursor is switched to `false`. Mouse-move monitors need no permission. Once a sticker takes the mouse, moves over its rectangle go to this app, which the global monitor never sees, so `prepare` also gives each sticker view an always-active mouse-moved tracking area that feeds the local monitor. This file is the only one allowed to write the flag, so M1's source scan names it.

- [ ] **Step 1: Write the failing tests**

`StickermineTests/ClickThroughFallbackTests.swift` (complete file):

```swift
import AppKit
import Testing
@testable import Stickermine

@MainActor
struct ClickThroughFallbackTests {
    /// A 2 × 2 mask whose left column is opaque.
    private let leftHalf = AlphaMask(width: 2, height: 2, bytes: [255, 0, 255, 0])
    private let rect = CGRect(x: 40_000, y: 0, width: 200, height: 100)

    private func candidate(_ rect: CGRect, mask: AlphaMask?, editing: Bool = false) -> ClickThroughFallback.Candidate {
        ClickThroughFallback.Candidate(contentRect: rect, frame: rect.insetBy(dx: -20, dy: -20), mask: mask,
                                       wholeFrame: editing)
    }

    @Test func onlyOpaquePixelsTakeTheClick() {
        let candidates = [candidate(rect, mask: leftHalf)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: candidates) == 0)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_150, y: 50), in: candidates) == nil)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 39_990, y: 50), in: candidates) == nil)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: [candidate(rect, mask: nil)]) == nil)
    }

    @Test func theFrontMostStickerWins() {
        let candidates = [candidate(rect, mask: leftHalf), candidate(rect, mask: leftHalf)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: candidates) == 0)
        let behind = [candidate(rect, mask: AlphaMask(width: 1, height: 1, bytes: [0])), candidate(rect, mask: leftHalf)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_050, y: 50), in: behind) == 1)
    }

    @Test func anEditingStickerTakesItsWholeFrame() {
        let candidates = [candidate(rect, mask: leftHalf, editing: true)]
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 40_150, y: 50), in: candidates) == 0)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 39_985, y: -15), in: candidates) == 0)
        #expect(ClickThroughFallback.hitIndex(at: CGPoint(x: 39_970, y: 50), in: candidates) == nil)
    }

    @Test func theStickerUnderTheCursorIsTheOnlyOneTakingTheMouse() {
        let front = PanelPolicy.makeStickerPanel(contentRect: rect)
        let back = PanelPolicy.makeStickerPanel(contentRect: rect.offsetBy(dx: 100, dy: 0))
        defer { front.close(); back.close() }
        let fallback = ClickThroughFallback(targets: { [front, back, rect, leftHalf] in
            [ClickThroughFallback.Target(panel: front, contentRect: rect, mask: leftHalf, wholeFrame: false),
             ClickThroughFallback.Target(panel: back, contentRect: rect.offsetBy(dx: 100, dy: 0), mask: leftHalf,
                                         wholeFrame: false)]
        })
        fallback.prepare(front)
        fallback.prepare(back)
        #expect(front.ignoresMouseEvents && back.ignoresMouseEvents)
        // Moves over a sticker that has taken the mouse reach the local monitor only through this.
        for panel in [front, back] {
            #expect(panel.contentView?.trackingAreas.contains { $0.options.contains([.mouseMoved, .activeAlways]) } == true)
        }
        fallback.update(at: CGPoint(x: 40_050, y: 50))
        #expect(!front.ignoresMouseEvents)
        #expect(back.ignoresMouseEvents)
        #expect(fallback.activePanel === front)
        // x = 40 150 is the front sticker's transparent half but the back one's opaque half.
        fallback.update(at: CGPoint(x: 40_150, y: 50))
        #expect(front.ignoresMouseEvents)
        #expect(!back.ignoresMouseEvents)
        fallback.update(at: CGPoint(x: 41_000, y: 50))
        #expect(front.ignoresMouseEvents && back.ignoresMouseEvents)
        #expect(fallback.activePanel == nil)
    }
}
```

`StickermineTests/PanelPolicyTests.swift` needs **no change** here. M1's final review (ledger `Final: fixed`) widened `stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag` to scan every app file in every folder, with the allowed writers listed by path in `PanelPolicyTests.mouseFlagWriters` (`Stickers/ClickThroughFallback.swift`, `Picker/PlacementSession.swift`, `UI/HUD.swift`, `Stickers/StickerPanel.swift`), so `ClickThroughFallback.swift` is already allowed. Every test count from this point in M2–M7 is **2 higher** than the plan states (M1's final review added `theMouseFlagPatternCatchesEveryWayOfWritingIt` and `aStickerPanelCountsEveryWriteOfTheTwoFlags`).

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/ClickThroughFallbackTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'ClickThroughFallback' in scope`.

- [ ] **Step 3: Implement**

`Stickermine/Stickers/ClickThroughFallback.swift` (complete file):

```swift
import AppKit

/// The hidden fallback click-through mode (spec section 9; `defaults write
/// com.ethan.stickermine clickThroughFallback -bool true`, read at launch).
/// It exists because the window server's alpha hit-testing has regressed in
/// past releases. Every sticker panel ignores the mouse, and the one sticker
/// whose opaque pixels are under the cursor is switched to receive it, using
/// each sticker's alpha mask. This is the only file that may write the panels'
/// mouse-event flag: once written, a window never returns to alpha hit-testing,
/// which is why the mode only changes on relaunch.
@MainActor
final class ClickThroughFallback {
    struct Target {
        let panel: NSPanel
        /// The sticker bitmap's rect in screen points (the panel minus its margin).
        let contentRect: CGRect
        let mask: AlphaMask?
        /// While editing, the whole padded frame takes clicks (the hit pad).
        let wholeFrame: Bool
    }

    struct Candidate {
        let contentRect: CGRect
        let frame: CGRect
        let mask: AlphaMask?
        let wholeFrame: Bool
    }

    /// Targets front to back.
    private let targets: () -> [Target]
    private var monitors: [Any] = []
    private(set) weak var activePanel: NSPanel?

    init(targets: @escaping () -> [Target]) {
        self.targets = targets
    }

    /// Every sticker panel starts out ignoring the mouse. Its view also gets an
    /// always-active mouse-moved tracking area: once a sticker takes the mouse,
    /// moves over its own rectangle belong to this app, so the global monitor
    /// no longer sees them and only these events reach the local monitor.
    func prepare(_ panel: NSPanel) {
        panel.ignoresMouseEvents = true
        if let view = panel.contentView {
            view.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                                owner: view, userInfo: nil))
        }
    }

    func forget(_ panel: NSPanel) {
        if activePanel === panel { activePanel = nil }
    }

    /// Global monitors see moves over other apps' windows (every sticker
    /// ignores the mouse until one is switched on); local ones see moves over
    /// our own. Mouse-move monitors need no permission.
    func start() {
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .rightMouseDragged]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.update(at: NSEvent.mouseLocation) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            MainActor.assumeIsolated { self?.update(at: NSEvent.mouseLocation) }
            return event
        }) {
            monitors.append(local)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    /// Lets the front-most sticker with an opaque pixel under `point` take the
    /// mouse, and every other sticker ignore it.
    func update(at point: NSPoint) {
        let current = targets()
        let candidates = current.map {
            Candidate(contentRect: $0.contentRect, frame: $0.panel.frame, mask: $0.mask, wholeFrame: $0.wholeFrame)
        }
        let hit = Self.hitIndex(at: point, in: candidates).map { current[$0].panel }
        guard hit !== activePanel else { return }
        activePanel?.ignoresMouseEvents = true
        hit?.ignoresMouseEvents = false
        activePanel = hit
    }

    /// The index of the first (front-most) candidate that takes a click at `p`.
    nonisolated static func hitIndex(at p: CGPoint, in candidates: [Candidate]) -> Int? {
        for (index, candidate) in candidates.enumerated() {
            if candidate.wholeFrame {
                if candidate.frame.contains(p) { return index }
                continue
            }
            let rect = candidate.contentRect
            guard let mask = candidate.mask, rect.width > 0, rect.height > 0, rect.contains(p) else { continue }
            let unit = CGPoint(x: (p.x - rect.minX) / rect.width, y: (rect.maxY - p.y) / rect.height)
            if mask.isOpaque(atUnit: unit) { return index }
        }
        return nil
    }
}
```

- [ ] **Step 4: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 117 tests in 17 suites passed` and `** TEST SUCCEEDED **`. `PanelPolicyTests.stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag` still passes: `ClickThroughFallback.swift` is the one file in `Stickers/` that may write the flag.

- [ ] **Step 5: Commit**

```bash
git add Stickermine/Stickers/ClickThroughFallback.swift StickermineTests/ClickThroughFallbackTests.swift StickermineTests/PanelPolicyTests.swift
git commit -m "Add the hidden fallback click-through mode" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 11: StickerManager

**Files:**
- Create: `Stickermine/Stickers/StickerManager.swift`
- Modify: `Stickermine/Stickers/PanelPolicy.swift` (one function replaced)
- Test: `StickermineTests/StickerManagerTests.swift`; Modify: `StickermineTests/PanelPolicyTests.swift` (one test added)

**Interfaces:**
- Consumes: everything from Tasks 1–10; M1's `PanelPolicy`, `StickerPanel`, `StickerView` (`clearContents`, `setEditingChrome`, `setContentTransform`, `layerShadow`, `contentPointSize`).
- Produces:

```text
// Replaces M1's PanelPolicy.makeStickerPanel(contentRect:) (contract change 2):
//     static func makeStickerPanel(contentRect: NSRect, hideFromSharing: Bool = true) -> StickerPanel
@MainActor final class StickerManager {
    static let rebuildsPanelsAfterSystemEvents: Bool           // false; set from the spike results in Task 12 Step 5
    static let systemEventRecheckDelay: TimeInterval           // 1.5
    struct DisplaySnapshot: Equatable { let frame: CGRect; let backingScale: CGFloat; let inMirrorSet: Bool; init(_ display: DisplayInfo) }
    init(library: LibraryController, screens: ScreenProvider, renderer: StyleRenderer, reconcileDelay: TimeInterval = 0.45)
    private(set) var editingPlacement: UUID?
    private(set) var reconcileCount: Int
    private(set) var renderRequestsIssued: Int
    var placementsWithPanels: Set<UUID> { get }
    var isClickThroughFallbackEnabled: Bool { get }
    func restoreAll()
    func scheduleReconcile()                                    // 450 ms debounce
    func reconcileNow()
    func panel(for placement: UUID) -> StickerPanel?
    func refreshPanel(for placement: UUID)                     // re-resolve one placement after a model change
    func closeAllPanels()
    func rebuildAllPanels()
    func commitRender(_ rendered: RenderedSticker, for request: RenderRequest, placement id: UUID)
    @discardableResult func place(sticker: UUID, style: StickerStyle, centerOnScreen: NSPoint, pointSize: CGSize) -> UUID?
    func remove(placement id: UUID)
    func deleteSticker(_ sticker: UUID)
    func recordKeyForUserEdit(on display: DisplayInfo) -> String
    func setSharingHidden(_ hidden: Bool)
    func enableClickThroughFallback()
    func endEditing(discardGesture: Bool)
    func startObservingDisplayChanges()
    func systemEvent(recheckLater: Bool)
    nonisolated static func ordersOutImmediately(for flags: CGDisplayChangeSummaryFlags) -> Bool
    nonisolated static func displayReconfigured(_ displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags)
    func handleDisplayRemoved(displayID: UInt32)
    static func recordAssignments(displays: [DisplayInfo], records: [String: DisplayRecord]) -> [String: String]
    static func display(containing point: NSPoint, in displays: [DisplayInfo]) -> DisplayInfo?
}
```

How it works (spec sections 9 and 11):

- **Reconcile** (`reconcileNow`): reads the usable displays; if there are none (only a ghost, or a moment mid-change) it changes nothing. Otherwise it rebuilds the in-memory ID → UUID map and which record each display shows (its own, or a fingerprint adoption, in memory only), diffs a `[uuid: DisplaySnapshot]` against the last one, closes panels whose placement left the model, orders out (and keeps) panels whose display is gone, creates missing panels for present displays, re-resolves a placement's layout only when its display's snapshot changed (or the panel is new, or its placement now shows on another display), and **always** re-applies level and frame (only when different) and orders panels in, back to front, when any of a display's panels isn't visible. It asks for a render only when the `RenderRequest` changed. A returning recorded display gets its `lastSeen` and `name` refreshed quietly (written with the next save).
- **Display events**: `didChangeScreenParametersNotification` restarts the 450 ms timer; wake, screens-did-wake and `com.apple.screenIsUnlocked` restart it and do so again 1.5 s later; the Core Graphics callback ignores every Begin pass and acts only on an after-pass with the Remove flag, ordering out that display's panels at once. With `rebuildsPanelsAfterSystemEvents` on, every panel is also closed and recreated (ending editing first) 1.5 s after a wake or unlock, and 1.5 s after a reconcile that finds a display added, removed or changed. A screen-parameters notification alone never rebuilds, because the Dock and EDR-headroom changes post it too (research D7/D8); a rebuild's own reconcile starts from an empty snapshot, so it never schedules another.
- **User actions**: `place` creates the display's record on its first placement (or saves a fingerprint adoption as a re-key) and appends the placement on top with `poses = [size: pose]`; `remove` deletes one placement (a tutorial sticker is deleted outright); `deleteSticker` closes the sticker's panels, deletes its PNG, then removes the entry and every placement of it on every display from the index (PNG first, then the index). A read-only (newer) library refuses all three. Every render completion checks that its placement still exists and that it is the newest request.
- **Sharing**: `setSharingHidden(true)` applies live; `setSharingHidden(false)` recreates the panels that stay hidden (contract change 2).

- [ ] **Step 1: Write the failing tests**

`StickermineTests/StickerManagerTests.swift` (complete file):

```swift
import AppKit
import Testing
@testable import Stickermine

/// A library on disk, a fake set of displays and a StickerManager over them.
/// Every display sits far off the real screens, so panels ordered in here
/// never appear on the desktop; `finish()` closes them before the test returns.
@MainActor
private final class Harness {
    let root: URL
    let store: LibraryStore
    let library: LibraryController
    let screens: FakeScreens
    let manager: StickerManager
    let master = Fixtures.image(width: 400, height: 200)

    init(_ model: Library, displays: [DisplayInfo], pngs: [UUID]? = nil) throws {
        root = Fixtures.temporaryDirectory()
        store = LibraryStore(root: root)
        for id in pngs ?? model.stickers.map(\.id) {
            try store.writePNG(Fixtures.pngData(width: 400, height: 200, pixelsPerPoint: 2), for: id)
        }
        try store.save(model)
        // Saves would only happen after a minute: a test sees exactly what was scheduled.
        library = LibraryController(store: store, saveDelay: 60)
        screens = FakeScreens(displays)
        let master = self.master
        manager = StickerManager(library: library, screens: screens,
                                 renderer: StyleRenderer(masterProvider: { _ in master }), reconcileDelay: 0.05)
    }

    func savedBytes() throws -> Data {
        try Data(contentsOf: store.libraryURL)
    }

    func finish() {
        manager.closeAllPanels()
        try? FileManager.default.removeItem(at: root)
    }
}

@MainActor
struct StickerManagerTests {
    private let sticker = UUID()
    private let absentUUID = "0F0F0F0F-1111-4222-8333-444444444444"

    private func placement(_ sticker: UUID, x: Double = 0.5, y: Double = 0.5, scale: Double = 1,
                           onTop: Bool = false) -> Placement {
        Placement(sticker: sticker, style: .outline, onTop: onTop, poses: ["1920x1080": Pose(x: x, y: y, scale: scale)])
    }

    /// One sticker placed on the external display (and optionally on a display that isn't connected).
    private func model(_ onExternal: [Placement], absent: [Placement] = [], stickers: [StickerRecord]? = nil) -> Library {
        var displays = [Fixtures.externalUUID: Fixtures.displayRecord(for: Fixtures.external(), placements: onExternal)]
        if !absent.isEmpty {
            let other = Fixtures.display(uuid: absentUUID, id: 9, frame: .zero, name: "Studio Display",
                                         vendor: 1552, model: 44_828, serial: 77)
            displays[absentUUID] = Fixtures.displayRecord(for: other, placements: absent)
        }
        return Library(stickers: stickers ?? [Fixtures.sticker(sticker)], displays: displays)
    }

    @Test func restoreCreatesPanelsOnlyForConnectedDisplays() throws {
        let here = placement(sticker)
        let away = placement(sticker)
        let h = try Harness(model([here], absent: [away]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        #expect(h.manager.placementsWithPanels == [here.id])
        let panel = try #require(h.manager.panel(for: here.id))
        #expect(panel.isVisible)
        #expect(panel.placementID == here.id)
        // 200 × 100 pt centred on the 1920 × 1080 display at x = 40 000.
        #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        #expect(panel.level == PanelPolicy.stickerLevel)
        #expect(panel.sharingType == .none)
        #expect(h.manager.panel(for: away.id) == nil)
        // A display without a record shows nothing and gets no record (spec section 11).
        #expect(h.library.library.displays[Fixtures.mainUUID] == nil)
    }

    @Test func floatOnTopPlacementsUseTheFloatingLevel() throws {
        let floating = placement(sticker, onTop: true)
        let h = try Harness(model([floating]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        #expect(h.manager.panel(for: floating.id)?.level == .floating)
    }

    @Test func aDisconnectedDisplaysPanelsAreOrderedOutKeptAndNothingIsWritten() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let frame = panel.frame
        let saved = try h.savedBytes()

        h.screens.all = [Fixtures.main()]
        h.manager.reconcileNow()
        #expect(h.manager.panel(for: here.id) === panel)
        #expect(!panel.isVisible)
        #expect(panel.frame == frame)
        #expect(!h.library.hasPendingSave)
        #expect(try h.savedBytes() == saved)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements == [here])
    }

    @Test func aReconnectedDisplayGetsTheSamePanelsBackInPlace() throws {
        let back = placement(sticker, x: 0.2, y: 0.3)
        let front = placement(sticker, x: 0.7, y: 0.6)
        let h = try Harness(model([back, front]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panels = try [back, front].map { try #require(h.manager.panel(for: $0.id)) }
        let frames = panels.map(\.frame)
        let saved = try h.savedBytes()
        let seenBefore = try #require(h.library.library.displays[Fixtures.externalUUID]?.lastSeen)

        h.screens.all = [Fixtures.main()]
        h.manager.reconcileNow()
        h.screens.all = [Fixtures.main(), Fixtures.external()]
        h.manager.reconcileNow()

        for (index, panel) in panels.enumerated() {
            #expect(h.manager.panel(for: [back, front][index].id) === panel)
            #expect(panel.isVisible)
            #expect(panel.frame == frames[index])
        }
        // Nothing is written; lastSeen is refreshed in memory for the next save.
        #expect(!h.library.hasPendingSave)
        #expect(try h.savedBytes() == saved)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements == [back, front])
        #expect((h.library.library.displays[Fixtures.externalUUID]?.lastSeen ?? .distantPast) >= seenBefore)
    }

    @Test func noUsableDisplayChangesNothing() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let ghost = Fixtures.display(uuid: "GHOST", id: 7, frame: CGRect(x: 60_000, y: 0, width: 1, height: 1),
                                     vendor: 0x756E6B6E, model: 0x76697274)
        for displays in [[], [ghost]] {
            h.screens.all = displays
            h.manager.reconcileNow()
            #expect(panel.isVisible)
            #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        }
    }

    @Test func framesAreReappliedEvenWhenNothingChanged() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let renders = h.manager.renderRequestsIssued
        // As if AppKit had moved the window to another screen.
        panel.setFrame(CGRect(x: 52_000, y: 300, width: 200, height: 100), display: false)
        h.manager.reconcileNow()
        #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        // The snapshot didn't change: no re-resolution, no re-render.
        #expect(h.manager.renderRequestsIssued == renders)
    }

    @Test func aPlacementChangedInTheModelIsRedrawnOnRefresh() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        // What M5 does at a drag's end: write the pose, then refresh the panel.
        h.library.mutate { library in
            library.displays[Fixtures.externalUUID]?.placements[0].poses["1920x1080"] = Pose(x: 0.25, y: 0.25, scale: 1)
        }
        h.manager.reconcileNow()
        #expect(h.manager.panel(for: here.id)?.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100),
                "a plain reconcile keeps the cached layout")
        h.manager.refreshPanel(for: here.id)
        #expect(h.manager.panel(for: here.id)?.frame == CGRect(x: 40_380, y: 220, width: 200, height: 100))
    }

    @Test func aResolutionChangeBorrowsTheClosestSizeAndWritesNothing() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let renders = h.manager.renderRequestsIssued
        let saved = try h.savedBytes()
        h.screens.all = [Fixtures.external(frame: CGRect(x: 40_000, y: 0, width: 2560, height: 1440))]
        h.manager.reconcileNow()
        let frame = try #require(h.manager.panel(for: here.id)?.frame)
        // scale × min(2560/1920, 1440/1080) = 4/3, centred on the bigger display.
        #expect(abs(frame.width - 800.0 / 3) <= 1)
        #expect(abs(frame.height - 400.0 / 3) <= 1)
        #expect(abs(frame.midX - 41_280) <= 1)
        #expect(abs(frame.midY - 720) <= 1)
        #expect(h.manager.renderRequestsIssued == renders + 1)
        #expect(!h.library.hasPendingSave)
        #expect(try h.savedBytes() == saved)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements == [here])
    }

    @Test func aBackingScaleChangeReRendersAtTheSameFrame() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external(scale: 2)])
        defer { h.finish() }
        h.manager.restoreAll()
        let frame = try #require(h.manager.panel(for: here.id)?.frame)
        let renders = h.manager.renderRequestsIssued
        h.screens.all = [Fixtures.external(scale: 1)]
        h.manager.reconcileNow()
        #expect(h.manager.renderRequestsIssued == renders + 1)
        #expect(h.manager.panel(for: here.id)?.frame == frame)
    }

    @Test func aRemoveCallbackOrdersThatDisplayOutAtOnce() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        h.manager.handleDisplayRemoved(displayID: 99)   // unknown ID: nothing happens
        #expect(panel.isVisible)
        h.manager.handleDisplayRemoved(displayID: 3)    // the external display's runtime ID
        #expect(!panel.isVisible)
        #expect(h.manager.panel(for: here.id) === panel)
    }

    @Test func onlyAnAfterPassWithTheRemoveFlagActs() {
        #expect(StickerManager.ordersOutImmediately(for: [.removeFlag]))
        #expect(StickerManager.ordersOutImmediately(for: [.removeFlag, .disabledFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.beginConfigurationFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.beginConfigurationFlag, .removeFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.addFlag]))
        #expect(!StickerManager.ordersOutImmediately(for: [.setModeFlag, .movedFlag]))
    }

    @Test func placingCreatesTheDisplayRecordAndOnePoseForThisSize() throws {
        let h = try Harness(Library(stickers: [Fixtures.sticker(sticker)], displays: [:]),
                            displays: [Fixtures.external(), Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let id = try #require(h.manager.place(sticker: sticker, style: .shadow,
                                              centerOnScreen: NSPoint(x: 40_480, y: 270),
                                              pointSize: CGSize(width: 100, height: 50)))
        let record = try #require(h.library.library.displays[Fixtures.externalUUID])
        #expect(record.name == "LG UltraFine")
        #expect(record.vendor == 7789 && record.model == 23305 && record.serial == 848_464 && !record.builtin)
        #expect(record.placements.count == 1)
        let placed = record.placements[0]
        #expect(placed.id == id)
        #expect(placed.sticker == sticker)
        #expect(placed.style == .shadow)
        #expect(!placed.flipped && !placed.onTop && placed.rotation == 0)
        #expect(placed.poses == ["1920x1080": Pose(x: 0.25, y: 0.25, scale: 0.5)])
        #expect(h.library.hasPendingSave)
        let panel = try #require(h.manager.panel(for: id))
        #expect(panel.isVisible)
        #expect(panel.frame == CGRect(x: 40_430, y: 245, width: 100, height: 50))
    }

    @Test func aNewPlacementGoesOnTopOfItsDisplay() throws {
        let existing = placement(sticker)
        let h = try Harness(model([existing]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let id = try #require(h.manager.place(sticker: sticker, style: .none, centerOnScreen: NSPoint(x: 41_000, y: 500),
                                              pointSize: CGSize(width: 200, height: 100)))
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.map(\.id) == [existing.id, id])
    }

    @Test func aFingerprintAdoptedDisplayShowsTheOldRecordUntilAUserEdit() throws {
        // The external display came back with a new UUID; its old record matches its fingerprint.
        let old = placement(sticker)
        let renamed = Fixtures.display(uuid: "NEW-UUID-0000-4000-8000-000000000000", id: 3,
                                       frame: CGRect(x: 40_000, y: 0, width: 1920, height: 1080), name: "LG UltraFine")
        let h = try Harness(model([old]), displays: [renamed, Fixtures.main()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: old.id))
        #expect(panel.isVisible)
        #expect(panel.frame == CGRect(x: 40_860, y: 490, width: 200, height: 100))
        #expect(!h.library.hasPendingSave)
        #expect(h.library.library.displays[Fixtures.externalUUID] != nil)

        let added = try #require(h.manager.place(sticker: sticker, style: .puffy, centerOnScreen: NSPoint(x: 40_200, y: 200),
                                                 pointSize: CGSize(width: 100, height: 50)))
        #expect(h.library.library.displays[Fixtures.externalUUID] == nil)
        #expect(h.library.library.displays[renamed.uuid]?.placements.map(\.id) == [old.id, added])
        #expect(h.library.hasPendingSave)
    }

    @Test func removeDeletesOnlyThePlacement() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let panel = try #require(h.manager.panel(for: here.id))
        let view = try #require(panel.contentView as? StickerView)
        h.manager.remove(placement: here.id)
        #expect(h.manager.panel(for: here.id) == nil)
        #expect(!panel.isVisible)
        #expect(view.contentLayer.contents == nil)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.isEmpty == true)
        #expect(h.library.library.sticker(sticker) != nil)
        #expect(FileManager.default.fileExists(atPath: h.store.pngURL(for: sticker).path))
        #expect(h.library.hasPendingSave)
    }

    @Test func removingATutorialStickerDeletesItOutright() throws {
        let maple = LibraryStore.tutorialIDs[2]
        let here = placement(maple)
        let h = try Harness(model([here], stickers: [Fixtures.sticker(maple, tutorial: true)]),
                            displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.remove(placement: here.id)
        #expect(h.library.library.sticker(maple) == nil)
        #expect(h.library.library.displays[Fixtures.externalUUID]?.placements.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: h.store.pngURL(for: maple).path))
    }

    @Test func deletingAStickerRemovesEveryPlacementEverywhereAndItsPNG() throws {
        let other = UUID()
        let here = placement(sticker)
        let away = placement(sticker)
        let kept = placement(other, x: 0.1, y: 0.1)
        let h = try Harness(model([here, kept], absent: [away], stickers: [Fixtures.sticker(sticker), Fixtures.sticker(other)]),
                            displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        #expect(h.library.library.placementCount(of: sticker) == 2)
        h.manager.deleteSticker(sticker)
        #expect(h.manager.placementsWithPanels == [kept.id])
        #expect(h.library.library.sticker(sticker) == nil)
        #expect(h.library.library.placementCount(of: sticker) == 0)
        #expect(h.library.library.displays[absentUUID]?.placements.isEmpty == true)
        #expect(!FileManager.default.fileExists(atPath: h.store.pngURL(for: sticker).path))
        #expect(FileManager.default.fileExists(atPath: h.store.pngURL(for: other).path))
    }

    @Test func theSharingSettingAppliesToEveryPanelLive() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let hidden = try #require(h.manager.panel(for: here.id))
        #expect(hidden.sharingType == .none)
        h.manager.setSharingHidden(false)
        // On macOS 27.2 a panel once set to .none keeps reporting .none: it is recreated in place.
        let shown = try #require(h.manager.panel(for: here.id))
        #expect(shown.sharingType == .readOnly)
        #expect(shown.isVisible)
        #expect(shown.frame == hidden.frame)
        let added = try #require(h.manager.place(sticker: sticker, style: .none, centerOnScreen: NSPoint(x: 41_000, y: 500),
                                                 pointSize: CGSize(width: 100, height: 50)))
        #expect(h.manager.panel(for: added)?.sharingType == .readOnly)
        // Hiding applies to the existing windows.
        h.manager.setSharingHidden(true)
        #expect(h.manager.panel(for: here.id) === shown)
        #expect(shown.sharingType == .none)
        #expect(h.manager.panel(for: added)?.sharingType == sharingNone)
    }

    @Test func aPanelRecreatedForSharingKeepsItsBitmap() async throws {
        let here = placement(sticker)
        let request = RenderRequest(sticker: sticker, style: .outline, flipped: false, rotation: 0,
                                    pointSize: CGSize(width: 200, height: 100), backingScale: 2)
        let rendered = try await StyleRenderer(masterProvider: { _ in Fixtures.image(width: 400, height: 200) })
            .render(request)
        // From here on nothing suspends, so no other test sees these panels.
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        h.manager.commitRender(rendered, for: request, placement: here.id)
        let renders = h.manager.renderRequestsIssued
        let old = try #require(h.manager.panel(for: here.id))
        h.manager.setSharingHidden(false)
        // On macOS 27.2 the old panel keeps reporting .none, so it is replaced; on
        // a macOS whose getter follows the setter, the same panel simply stays.
        let new = try #require(h.manager.panel(for: here.id))
        #expect((new !== old) == (old.sharingType != .readOnly))
        #expect(new.sharingType == .readOnly)
        let view = try #require(new.contentView as? StickerView)
        #expect(view.contentLayer.contents != nil)
        #expect(view.contentPointSize == CGSize(width: 200, height: 100))
        #expect(h.manager.renderRequestsIssued == renders)
    }

    @Test func fallbackModePanelsIgnoreTheMouseUntilHovered() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        #expect(!h.manager.isClickThroughFallbackEnabled)
        h.manager.enableClickThroughFallback()
        #expect(h.manager.isClickThroughFallbackEnabled)
        h.manager.restoreAll()
        #expect(h.manager.panel(for: here.id)?.ignoresMouseEvents == true)
    }

    @Test func rebuildRecreatesEveryPanelInPlace() throws {
        let here = placement(sticker)
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let old = try #require(h.manager.panel(for: here.id))
        h.manager.rebuildAllPanels()
        let new = try #require(h.manager.panel(for: here.id))
        #expect(new !== old)
        #expect(!old.isVisible)
        #expect(new.isVisible)
        #expect(new.frame == old.frame)
    }

    @Test func onlyTheNewestRenderIsShown() async throws {
        let here = placement(sticker)
        let current = RenderRequest(sticker: sticker, style: .outline, flipped: false, rotation: 0,
                                    pointSize: CGSize(width: 200, height: 100), backingScale: 2)
        let stale = RenderRequest(sticker: sticker, style: .outline, flipped: false, rotation: 0,
                                  pointSize: CGSize(width: 200, height: 100), backingScale: 1)
        let rendered = try await StyleRenderer(masterProvider: { _ in Fixtures.image(width: 400, height: 200) })
            .render(current)
        // From here on nothing suspends, so no other test sees these panels.
        let h = try Harness(model([here]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.restoreAll()
        let view = try #require(h.manager.panel(for: here.id)?.contentView as? StickerView)
        h.manager.commitRender(rendered, for: stale, placement: here.id)
        #expect(view.contentLayer.contents == nil)
        h.manager.commitRender(rendered, for: current, placement: here.id)
        #expect(view.contentLayer.contents != nil)
        #expect(view.contentPointSize == CGSize(width: 200, height: 100))
        h.manager.remove(placement: here.id)
        h.manager.commitRender(rendered, for: current, placement: here.id)   // placement gone: ignored
    }

    @Test func displayEventsAreDebounced() async throws {
        let h = try Harness(Library(stickers: [], displays: [:]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.scheduleReconcile()
        h.manager.scheduleReconcile()
        h.manager.scheduleReconcile()
        #expect(h.manager.reconcileCount == 0)
        try await Task.sleep(for: .milliseconds(400))
        #expect(h.manager.reconcileCount == 1)
    }

    @Test func screenWakeAndUnlockEventsShareTheDebounce() async throws {
        let h = try Harness(Library(stickers: [], displays: [:]), displays: [Fixtures.external()])
        defer { h.finish() }
        h.manager.systemEvent(recheckLater: false)
        h.manager.scheduleReconcile()
        h.manager.systemEvent(recheckLater: false)
        try await Task.sleep(for: .milliseconds(400))
        #expect(h.manager.reconcileCount == 1)
    }

    @Test func aNewerLibraryIsShownButCantBeEdited() throws {
        let here = placement(sticker)
        var newer = model([here])
        newer.version = 2
        let h = try Harness(newer, displays: [Fixtures.external()])
        defer { h.finish() }
        #expect(h.library.isReadOnly)
        h.manager.restoreAll()
        #expect(h.manager.panel(for: here.id)?.isVisible == true)
        #expect(h.manager.place(sticker: sticker, style: .none, centerOnScreen: NSPoint(x: 41_000, y: 500),
                                pointSize: CGSize(width: 100, height: 50)) == nil)
        h.manager.remove(placement: here.id)
        h.manager.deleteSticker(sticker)
        #expect(h.manager.panel(for: here.id) != nil)
        #expect(h.library.library.placementCount(of: sticker) == 1)
        #expect(FileManager.default.fileExists(atPath: h.store.pngURL(for: sticker).path))
    }

    @Test func theDisplayUnderAPointOrTheNearestOne() {
        let external = Fixtures.external()
        let main = Fixtures.main()
        #expect(StickerManager.display(containing: NSPoint(x: 40_100, y: 100), in: [main, external])?.uuid == external.uuid)
        #expect(StickerManager.display(containing: NSPoint(x: 50_100, y: 100), in: [main, external])?.uuid == main.uuid)
        // In the gap between them: the external display's right edge is nearer.
        #expect(StickerManager.display(containing: NSPoint(x: 42_000, y: 100), in: [main, external])?.uuid == external.uuid)
        #expect(StickerManager.display(containing: .zero, in: []) == nil)
    }
}

/// `.none` next to an Optional reads as `Optional.none`; spell the sharing type out.
private let sharingNone = NSWindow.SharingType.none
```

In `StickermineTests/PanelPolicyTests.swift`, add this test as the last member of `struct PanelPolicyTests` (directly above the struct's final closing `}`, after `stickerCodeNeverWritesTheMouseEventFlagOrTheFloatingFlag()`):

```swift
    @Test func aPanelForVisibleSharingStartsReadOnly() {
        let panel = PanelPolicy.makeStickerPanel(contentRect: NSRect(x: 40_000, y: 0, width: 10, height: 10),
                                                 hideFromSharing: false)
        defer { panel.close() }
        #expect(panel.sharingType == .readOnly)
        #expect(panel.level == PanelPolicy.stickerLevel)
    }
```

- [ ] **Step 2: Run them to see them fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/StickerManagerTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'StickerManager' in scope` in `StickerManagerTests.swift` and `error: extra argument 'hideFromSharing' in call` in `PanelPolicyTests.swift`.

- [ ] **Step 3: Let a sticker panel start visible to screen capture**

In `Stickermine/Stickers/PanelPolicy.swift`, replace the whole function from its doc comment line `    /// The only way a sticker window is created.` down to its closing brace (M1's version: `static func makeStickerPanel(contentRect: NSRect) -> StickerPanel {`, ending `        panel.level = stickerLevel  // last` / `        return panel` / `    }`) with this complete version. It drops M1's wrong comment about switching live panels to `.readOnly`:

```swift
    /// The only way a sticker window is created. `hideFromSharing` is the
    /// "Hide stickers from screen sharing and screenshots" setting (default on)
    /// at creation time. A panel must start with the right value: on macOS 27.2
    /// a window that was once set to `.none` keeps reporting `.none` after a
    /// later `.readOnly`, so StickerManager recreates panels when the setting
    /// is turned off.
    static func makeStickerPanel(contentRect: NSRect, hideFromSharing: Bool = true) -> StickerPanel {
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
        panel.sharingType = hideFromSharing ? .none : .readOnly
        panel.collectionBehavior = stickerBehavior
        panel.level = stickerLevel  // last
        return panel
    }
```

- [ ] **Step 4: Implement StickerManager**

`Stickermine/Stickers/StickerManager.swift` (complete file):

```swift
import AppKit
import os

/// Core Graphics calls this for every display reconfiguration pass (a global
/// function, so it carries no actor isolation into the C callback).
private func stickerDisplayReconfigured(_ display: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags,
                                        _ userInfo: UnsafeMutableRawPointer?) {
    StickerManager.displayReconfigured(display, flags: flags)
}

/// Owns every sticker panel and keeps them in step with the library and the
/// connected displays (spec sections 9 and 11).
///
/// - The model is the only source of truth. Every reconcile re-applies
///   visibility and frames from it to every panel; a snapshot diff of the
///   displays only decides whether poses are re-resolved.
/// - Panels of a display that is gone are ordered out and kept, and ordered in
///   again when it returns. A display event never writes the library.
/// - Only `place`, `remove` and `deleteSticker` (user actions) write, plus the
///   spec's exceptions: a returning display's lastSeen and name (quietly, with
///   the next save) and a fingerprint re-key on the next user edit.
@MainActor
final class StickerManager {
    /// Set from design/spike-results.md, Decisions: "Do panels go stale, and
    /// does a rebuild fix it?". When true, every panel is closed and recreated
    /// from the model 1.5 s after wake, unlock and display changes.
    static let rebuildsPanelsAfterSystemEvents = false
    /// Wake and unlock are checked again this long after the event.
    static let systemEventRecheckDelay: TimeInterval = 1.5

    /// What a display change must alter to re-resolve poses (spec section 11).
    struct DisplaySnapshot: Equatable {
        let frame: CGRect
        let backingScale: CGFloat
        let inMirrorSet: Bool

        init(_ display: DisplayInfo) {
            frame = display.frame
            backingScale = display.backingScale
            inMirrorSet = display.inMirrorSet
        }
    }

    private final class Entry {
        let panel: StickerPanel
        let view: StickerView
        /// The display the cached layout was resolved for.
        var displayUUID: String?
        var layout: StickerGeometry.Layout?
        /// The newest render asked for; a result for any other request is dropped.
        var request: RenderRequest?
        var alphaMask: AlphaMask?

        init(panel: StickerPanel, view: StickerView) {
            self.panel = panel
            self.view = view
        }
    }

    private let library: LibraryController
    private let screens: ScreenProvider
    private let renderer: StyleRenderer
    private let reconcileDelay: TimeInterval
    private let log = Logger(subsystem: "com.ethan.stickermine", category: "stickers")

    private var entries: [UUID: Entry] = [:]
    private var lastSnapshot: [String: DisplaySnapshot] = [:]
    /// Rebuilt on every reconcile; display IDs are never persisted.
    private var displayIDToUUID: [UInt32: String] = [:]
    private var presentDisplays: [String: DisplayInfo] = [:]
    /// Connected display UUID → the record it shows (itself, or a fingerprint adoption).
    private var recordForDisplay: [String: String] = [:]
    private var reconcileWork: DispatchWorkItem?
    private var rebuildWork: DispatchWorkItem?
    private var observers: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var sharingHidden = true
    private var fallback: ClickThroughFallback?

    /// The instance the Core Graphics callback reaches (the app has one).
    private static weak var observing: StickerManager?

    /// The placement being edited (M5's StickerEditor sets it; nothing does in M2).
    private(set) var editingPlacement: UUID?
    /// Diagnostics for logs and tests.
    private(set) var reconcileCount = 0
    private(set) var renderRequestsIssued = 0

    init(library: LibraryController, screens: ScreenProvider, renderer: StyleRenderer,
         reconcileDelay: TimeInterval = 0.45) {
        self.library = library
        self.screens = screens
        self.renderer = renderer
        self.reconcileDelay = reconcileDelay
    }

    // MARK: Panels from the model

    /// Creates panels for every placement on a connected display (launch).
    func restoreAll() {
        lastSnapshot = [:]
        reconcileNow()
    }

    /// Every display event restarts one timer; the reconcile runs when it fires.
    func scheduleReconcile() {
        reconcileWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reconcileNow() }
        }
        reconcileWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + reconcileDelay, execute: work)
    }

    func reconcileNow() {
        reconcileWork?.cancel()
        reconcileWork = nil
        reconcileCount += 1
        let displays = screens.currentDisplays()
        guard !displays.isEmpty else {
            // No real display (only a ghost, or a moment mid-change): change nothing.
            log.notice("reconcile #\(self.reconcileCount): no usable display; nothing changed")
            return
        }
        let model = library.library
        let previouslyPresent = Set(presentDisplays.keys)
        displayIDToUUID = Dictionary(displays.map { ($0.displayID, $0.uuid) }, uniquingKeysWith: { first, _ in first })
        presentDisplays = Dictionary(displays.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        recordForDisplay = Self.recordAssignments(displays: displays, records: model.displays)
        let snapshot = presentDisplays.mapValues(DisplaySnapshot.init)
        let changed = Set(snapshot.keys.filter { lastSnapshot[$0] != snapshot[$0] })
        // A display was added, changed or removed (the count drops). lastSnapshot is
        // empty after launch, closeAllPanels() and rebuildAllPanels(): those never
        // schedule a rebuild, so a rebuild can't loop.
        let displaysChanged = !lastSnapshot.isEmpty && (!changed.isEmpty || lastSnapshot.count != snapshot.count)
        lastSnapshot = snapshot
        if Self.rebuildsPanelsAfterSystemEvents, displaysChanged { scheduleRebuild() }

        var displayForRecord: [String: DisplayInfo] = [:]
        for (displayUUID, recordKey) in recordForDisplay {
            displayForRecord[recordKey] = presentDisplays[displayUUID]
        }

        let livePlacements = Set(model.displays.values.flatMap { $0.placements.map(\.id) })
        for id in Array(entries.keys) where !livePlacements.contains(id) {
            tearDown(id)
        }

        for (recordKey, record) in model.displays {
            guard let display = displayForRecord[recordKey] else {
                // Its display is gone: order out, keep the panels for its return.
                for placement in record.placements {
                    if let entry = entries[placement.id], entry.panel.isVisible {
                        entry.panel.orderOut(nil)
                        log.notice("ordered out \(Self.short(placement.id), privacy: .public): display \(recordKey, privacy: .public) is gone")
                    }
                }
                continue
            }
            var needsOrdering = false
            for placement in record.placements {
                guard let sticker = model.sticker(placement.sticker) else { continue }
                let entry = entries[placement.id] ?? makeEntry(for: placement)
                if entry.layout == nil || entry.displayUUID != display.uuid || changed.contains(display.uuid) {
                    entry.layout = StickerGeometry.layout(for: placement, natural: sticker.naturalPointSize, on: display)
                    entry.displayUUID = display.uuid
                }
                guard let layout = entry.layout else {
                    if entry.panel.isVisible { entry.panel.orderOut(nil) }
                    continue
                }
                let level = PanelPolicy.level(onTop: placement.onTop)
                if entry.panel.level != level { entry.panel.level = level }
                applyFrame(entry, layout: layout)
                requestRender(entry, placement: placement, layout: layout, backingScale: display.backingScale)
                if !entry.panel.isVisible { needsOrdering = true }
            }
            if needsOrdering {
                // Back to front, so the record's order is the z-order.
                for placement in record.placements {
                    if let entry = entries[placement.id], entry.layout != nil {
                        entry.panel.orderFrontRegardless()
                        log.notice("ordered in \(Self.short(placement.id), privacy: .public) at \(NSStringFromRect(entry.panel.frame), privacy: .public)")
                    }
                }
            }
        }

        refreshDisplayMetadata(newlyPresent: Set(presentDisplays.keys).subtracting(previouslyPresent))
        log.notice("reconcile #\(self.reconcileCount): \(displays.count) displays, \(changed.count) changed, \(self.entries.count) panels")
    }

    func panel(for placement: UUID) -> StickerPanel? {
        entries[placement]?.panel
    }

    /// Placements that currently have a panel (visible or ordered out).
    var placementsWithPanels: Set<UUID> {
        Set(entries.keys)
    }

    /// Re-resolves one placement from the model after a change to it.
    func refreshPanel(for placement: UUID) {
        entries[placement]?.layout = nil
        reconcileNow()
    }

    /// Closes every panel; the next reconcile recreates them from the model.
    func closeAllPanels() {
        for id in Array(entries.keys) { tearDown(id) }
        lastSnapshot = [:]
    }

    /// Closes and recreates every panel from the model (the stale-window fix,
    /// spec section 9), ending any editing first.
    func rebuildAllPanels() {
        endEditing(discardGesture: true)
        closeAllPanels()
        reconcileNow()
    }

    /// Shows a finished render if it is still the newest one asked for and its
    /// placement still exists.
    func commitRender(_ rendered: RenderedSticker, for request: RenderRequest, placement id: UUID) {
        guard let entry = entries[id], entry.request == request, library.library.placement(id) != nil else { return }
        entry.view.show(rendered, shadow: nil, style: request.style)
        entry.alphaMask = rendered.alphaMask
        if let layout = entry.layout { applyFrame(entry, layout: layout) }
    }

    // MARK: User actions

    /// A user placement on the display under `centerOnScreen`, on top of its
    /// z-order: `poses = [size: pose]`, rotation 0, unflipped, not on top.
    /// Returns the new placement's ID (nil when read-only or the sticker is unknown).
    @discardableResult
    func place(sticker: UUID, style: StickerStyle, centerOnScreen: NSPoint, pointSize: CGSize) -> UUID? {
        guard !library.isReadOnly, let record = library.library.sticker(sticker) else { return nil }
        let natural = record.naturalPointSize
        guard natural.width > 0, pointSize.width > 0,
              let display = Self.display(containing: centerOnScreen, in: screens.currentDisplays())
        else { return nil }
        let center = StickerGeometry.reachableCenter(centerOnScreen, visibleFrame: display.visibleFrame)
        let pose = StickerGeometry.pose(center: center, scale: Double(pointSize.width / natural.width),
                                        in: display.frame)
        let placement = LayoutResolver.placing(pose, to: Placement(sticker: sticker, style: style, poses: [:]),
                                               at: display.size)
        let key = recordKeyForUserEdit(on: display)
        library.mutate { $0.displays[key]?.placements.append(placement) }
        reconcileNow()
        return placement.id
    }

    /// Removes one placement; the sticker stays in history. A tutorial sticker
    /// is deleted outright (spec section 13).
    func remove(placement id: UUID) {
        guard !library.isReadOnly else { return }
        let model = library.library
        guard let key = model.displayKey(containing: id), let placement = model.placement(id) else { return }
        if editingPlacement == id { endEditing(discardGesture: true) }
        if model.sticker(placement.sticker)?.tutorial == true {
            deleteSticker(placement.sticker)
            return
        }
        if let adopter = recordForDisplay.first(where: { $0.value == key && $0.key != key }),
           let display = presentDisplays[adopter.key] {
            _ = recordKeyForUserEdit(on: display)
        }
        tearDown(id)
        library.mutate { _ = $0.removePlacement(id) }
    }

    /// Delete from history: every placement on every display (connected or
    /// not), the PNG, then the entry (spec section 12).
    func deleteSticker(_ sticker: UUID) {
        guard !library.isReadOnly, library.library.sticker(sticker) != nil else { return }
        let placementIDs = library.library.displays.values.flatMap { record in
            record.placements.filter { $0.sticker == sticker }.map(\.id)
        }
        if let editing = editingPlacement, placementIDs.contains(editing) { endEditing(discardGesture: true) }
        placementIDs.forEach(tearDown)
        do {
            try library.store.deletePNG(for: sticker)
        } catch {
            log.error("deleting the PNG of \(sticker.uuidString, privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
        library.mutate { $0.removeSticker(sticker) }
    }

    /// The record key a user edit on `display` writes to. Creates the record on
    /// the first placement; saves a fingerprint adoption as a re-key (spec section 11).
    func recordKeyForUserEdit(on display: DisplayInfo) -> String {
        let model = library.library
        if model.displays[display.uuid] != nil { return display.uuid }
        if let adopted = DisplayRegistry.fingerprintAdoption(
            for: display, records: model.displays, connected: screens.currentDisplays()) {
            library.mutate { library in
                library.moveDisplayRecord(from: adopted, to: display.uuid)
                library.displays[display.uuid]?.name = display.name
                library.displays[display.uuid]?.lastSeen = Date()
            }
            log.notice("re-keyed display record \(adopted, privacy: .public) as \(display.uuid, privacy: .public)")
        } else {
            library.mutate { library in
                library.displays[display.uuid] = DisplayRecord(
                    name: display.name, vendor: display.vendor, model: display.model, serial: display.serial,
                    builtin: display.builtin, lastSeen: Date(), placements: [])
            }
        }
        recordForDisplay[display.uuid] = display.uuid
        return display.uuid
    }

    // MARK: Settings

    /// "Hide stickers from screen sharing and screenshots", applied live.
    /// Hiding is set on each panel. A panel that keeps reporting `.none` after
    /// `.readOnly` (macOS 27.2, on a window once set to `.none`) is replaced by
    /// a new panel created with the new setting, which takes over the old one's
    /// bitmap, layout and render request, so the sticker never shows empty while
    /// a render runs.
    func setSharingHidden(_ hidden: Bool) {
        sharingHidden = hidden
        let wanted: NSWindow.SharingType = hidden ? .none : .readOnly
        var stuck: [UUID] = []
        for (id, entry) in entries {
            entry.panel.sharingType = wanted
            if entry.panel.sharingType != wanted { stuck.append(id) }
        }
        guard !stuck.isEmpty else { return }
        if let editing = editingPlacement, stuck.contains(editing) { endEditing(discardGesture: true) }
        let model = library.library
        for id in stuck {
            guard let old = entries[id], let placement = model.placement(id) else {
                tearDown(id)
                continue
            }
            let contents = old.view.contentLayer.contents
            let pointSize = old.view.contentPointSize
            let shadow = old.view.layerShadow
            let frame = old.panel.frame
            tearDown(id)
            let fresh = makeEntry(for: placement)
            fresh.displayUUID = old.displayUUID
            fresh.layout = old.layout
            fresh.request = old.request
            fresh.alphaMask = old.alphaMask
            if let contents { fresh.view.showContents(contents, pointSize: pointSize, shadow: shadow) }
            fresh.panel.setFrame(frame, display: false)
        }
        log.notice("recreated \(stuck.count) panels to change their sharing type")
        // Orders the new panels in, back to front; nothing is re-resolved or re-rendered.
        reconcileNow()
    }

    /// The hidden `clickThroughFallback` setting, read at launch (spec section 9).
    func enableClickThroughFallback() {
        guard fallback == nil else { return }
        let fallback = ClickThroughFallback(targets: { [weak self] in self?.fallbackTargets() ?? [] })
        for entry in entries.values { fallback.prepare(entry.panel) }
        fallback.start()
        self.fallback = fallback
    }

    var isClickThroughFallbackEnabled: Bool { fallback != nil }

    // MARK: Editing (M5 owns entering it)

    /// Ends editing, if any. M2 never enters editing (M5 adds StickerEditor);
    /// this clears the state so delete, remove and rebuild already end editing first.
    func endEditing(discardGesture: Bool) {
        guard let id = editingPlacement else { return }
        editingPlacement = nil
        guard let entry = entries[id] else { return }
        entry.panel.isEditing = false
        entry.view.setEditingChrome(false)
        entry.view.setContentTransform(scale: 1, rotation: 0)
        if let layout = entry.layout { applyFrame(entry, layout: layout) }
    }

    // MARK: System events

    /// Observes screen changes, wake, unlock and the Core Graphics display
    /// callback. The app calls it once; tests drive `reconcileNow()` directly.
    func startObservingDisplayChanges() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification, recheckLater: false)
        observe(workspace, NSWorkspace.didWakeNotification, recheckLater: true)
        observe(workspace, NSWorkspace.screensDidWakeNotification, recheckLater: true)
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked"),
                recheckLater: true)
        Self.observing = self
        let status = CGDisplayRegisterReconfigurationCallback(stickerDisplayReconfigured, nil)
        if status != .success {
            log.error("CGDisplayRegisterReconfigurationCallback failed: \(status.rawValue)")
        }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, recheckLater: Bool) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemEvent(recheckLater: recheckLater) }
        }
        observers.append((center, token))
    }

    /// A screen change, wake or unlock: restart the reconcile timer. After wake
    /// and unlock, check again 1.5 s later and, if the spike said so, rebuild.
    /// A screen-parameters notification alone never rebuilds: the Dock and EDR
    /// headroom changes post it too. The reconcile schedules the rebuild when it
    /// finds a display added, removed or changed.
    func systemEvent(recheckLater: Bool) {
        scheduleReconcile()
        guard recheckLater else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.systemEventRecheckDelay) { [weak self] in
            MainActor.assumeIsolated { self?.scheduleReconcile() }
        }
        if Self.rebuildsPanelsAfterSystemEvents { scheduleRebuild() }
    }

    /// Closes and recreates every panel 1.5 s from now (restarted by each call).
    private func scheduleRebuild() {
        rebuildWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rebuildAllPanels() }
        }
        rebuildWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.systemEventRecheckDelay, execute: work)
    }

    /// Only an after-pass with the Remove flag acts: the Begin pass fires for
    /// every online display and says nothing about which one is leaving.
    nonisolated static func ordersOutImmediately(for flags: CGDisplayChangeSummaryFlags) -> Bool {
        !flags.contains(.beginConfigurationFlag) && flags.contains(.removeFlag)
    }

    nonisolated static func displayReconfigured(_ displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags) {
        guard ordersOutImmediately(for: flags) else { return }
        if Thread.isMainThread {
            MainActor.assumeIsolated { observing?.handleDisplayRemoved(displayID: displayID) }
        } else {
            DispatchQueue.main.async {
                MainActor.assumeIsolated { observing?.handleDisplayRemoved(displayID: displayID) }
            }
        }
    }

    /// Orders out the removed display's panels at once (looked up in the
    /// in-memory ID map), then lets the debounced reconcile settle the rest.
    func handleDisplayRemoved(displayID: UInt32) {
        guard let uuid = displayIDToUUID[displayID] else { return }
        if let recordKey = recordForDisplay[uuid], let record = library.library.displays[recordKey] {
            for placement in record.placements {
                entries[placement.id]?.panel.orderOut(nil)
            }
        }
        log.notice("display \(uuid, privacy: .public) removed; its stickers are ordered out")
        scheduleReconcile()
    }

    // MARK: Helpers

    /// The first 8 characters of an ID, for log lines.
    private static func short(_ id: UUID) -> String {
        String(id.uuidString.prefix(8))
    }

    /// Which record each connected display shows: its own, else the one the
    /// fingerprint fallback adopts (in memory only).
    static func recordAssignments(displays: [DisplayInfo], records: [String: DisplayRecord]) -> [String: String] {
        var result: [String: String] = [:]
        for display in displays {
            if records[display.uuid] != nil {
                result[display.uuid] = display.uuid
            } else if let adopted = DisplayRegistry.fingerprintAdoption(for: display, records: records, connected: displays) {
                result[display.uuid] = adopted
            }
        }
        return result
    }

    /// The display containing `point` (`NSMouseInRect`), else the nearest one.
    static func display(containing point: NSPoint, in displays: [DisplayInfo]) -> DisplayInfo? {
        if let hit = displays.first(where: { NSMouseInRect(point, $0.frame, false) }) { return hit }
        func distance(_ rect: CGRect) -> CGFloat {
            hypot(max(rect.minX - point.x, 0, point.x - rect.maxX), max(rect.minY - point.y, 0, point.y - rect.maxY))
        }
        return displays.min { distance($0.frame) < distance($1.frame) }
    }

    private func makeEntry(for placement: Placement) -> Entry {
        let start = NSRect(x: 0, y: 0, width: 1, height: 1)
        let panel = PanelPolicy.makeStickerPanel(contentRect: start, hideFromSharing: sharingHidden)
        let view = StickerView(frame: start)
        panel.contentView = view
        panel.placementID = placement.id
        fallback?.prepare(panel)
        panel.level = PanelPolicy.level(onTop: placement.onTop)  // last
        let entry = Entry(panel: panel, view: view)
        entries[placement.id] = entry
        return entry
    }

    private func applyFrame(_ entry: Entry, layout: StickerGeometry.Layout) {
        let margin = entry.view.layerShadow?.margin ?? 0
        let rect = layout.stickerRect.insetBy(dx: -margin, dy: -margin)
        let target = entry.panel.backingAlignedRect(rect, options: .alignAllEdgesNearest)
        if entry.panel.frame != target {
            entry.panel.setFrame(target, display: false)
        }
    }

    private func requestRender(_ entry: Entry, placement: Placement, layout: StickerGeometry.Layout,
                               backingScale: CGFloat) {
        let request = RenderRequest(sticker: placement.sticker, style: placement.style, flipped: placement.flipped,
                                    rotation: placement.rotation, pointSize: layout.pointSize,
                                    backingScale: backingScale)
        guard request != entry.request else { return }
        entry.request = request
        renderRequestsIssued += 1
        let renderer = self.renderer
        let placementID = placement.id
        Task { [weak self] in
            do {
                let rendered = try await renderer.render(request)
                self?.commitRender(rendered, for: request, placement: placementID)
            } catch {
                self?.log.error("render of \(placementID.uuidString, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// A returning recorded display refreshes its lastSeen and name in memory;
    /// they are written with the next save, never on their own.
    private func refreshDisplayMetadata(newlyPresent: Set<String>) {
        let model = library.library
        let returning = newlyPresent.compactMap { uuid in model.displays[uuid] != nil ? presentDisplays[uuid] : nil }
        guard !returning.isEmpty else { return }
        let now = Date()
        library.refreshMetadata { library in
            for display in returning {
                library.displays[display.uuid]?.lastSeen = now
                library.displays[display.uuid]?.name = display.name
            }
        }
    }

    private func tearDown(_ id: UUID) {
        guard let entry = entries.removeValue(forKey: id) else { return }
        fallback?.forget(entry.panel)
        entry.view.clearContents()
        entry.panel.orderOut(nil)
        entry.panel.close()
    }

    /// Visible stickers front to back, for the fallback click-through mode.
    private func fallbackTargets() -> [ClickThroughFallback.Target] {
        let order = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue)
        var rank: [Int: Int] = [:]
        for (index, number) in order.enumerated() where rank[number] == nil { rank[number] = index }
        return entries.values
            .filter { $0.panel.isVisible }
            .sorted { (rank[$0.panel.windowNumber] ?? Int.max) < (rank[$1.panel.windowNumber] ?? Int.max) }
            .map { entry in
                let size = entry.view.contentPointSize
                let frame = entry.panel.frame
                let content = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2,
                                     width: size.width, height: size.height)
                return ClickThroughFallback.Target(panel: entry.panel, contentRect: content,
                                                   mask: entry.alphaMask, wholeFrame: entry.panel.isEditing)
            }
    }
}
```

- [ ] **Step 5: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 144 tests in 18 suites passed` and `** TEST SUCCEEDED **`. No window appears on screen during the run: every test display sits at x ≥ 40 000 pt.

- [ ] **Step 6: Commit**

```bash
git add Stickermine/Stickers/StickerManager.swift Stickermine/Stickers/PanelPolicy.swift StickermineTests/StickerManagerTests.swift StickermineTests/PanelPolicyTests.swift
git commit -m "Add StickerManager: restore, reconcile display changes, place, remove and delete" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

---

### Task 12: AppDelegate wiring, the Maple debug path and removing the spike

**Files:**
- Create: `Stickermine/App/DebugMaple.swift` (temporary; M4 deletes it)
- Modify: `Stickermine/App/AppDelegate.swift` (whole file replaced)
- Delete: `Stickermine/Stickers/SpikeController.swift`
- Test: Modify `StickermineTests/AppDelegateTests.swift` (one test added)

**Interfaces:**
- Consumes: `LibraryStore`, `LibraryController`, `StyleRenderer`, `MasterImage`, `LiveScreenProvider`, `StickerManager` (Tasks 5–11); M1's `BundledImages`.
- Produces:

```text
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    nonisolated static var isRunningTests: Bool { get }        // M1, unchanged
    private(set) static var didRunStartup: Bool                // M1, still set on the line right after the test-host guard
    static let clickThroughFallbackByDefault: Bool             // from the spike results (Step 5)
    func applicationDidFinishLaunching(_ notification: Notification)   // loads the library, restores stickers
    func applicationWillTerminate(_ notification: Notification)        // library.flush()
}
enum DebugMaple {                                              // temporary
    static let launchArgument: String                          // "-debugPlaceMaple"
    @MainActor static func place(library: LibraryController, stickers: StickerManager, screens: ScreenProvider)
}
```

Every launch now loads `~/Library/Application Support/com.ethan.stickermine/` (with launch repair) and restores the stickers on the connected displays (spec section 13: "every launch restores stickers"). The settings keys `hideFromSharing` (default on) and `clickThroughFallback` (hidden) are read by their spec names; M6's `Settings` enum takes them over. Login-launch detection, Home, the single-instance guard and leftover-capture cleanup belong to M4/M6.

- [ ] **Step 1: Write the failing test**

In `StickermineTests/AppDelegateTests.swift`, add this test as the last member of `struct AppDelegateTests` (directly above the struct's final closing `}`, after `testHostShowsNoWindows()`):

```swift
    @Test func theSpikeIsGoneAndOnlyTheDebugMaplePathRemains() throws {
        let spike = SourceFiles.appRoot.appendingPathComponent("Stickers/SpikeController.swift")
        #expect(!FileManager.default.fileExists(atPath: spike.path))
        let delegate = try SourceFiles.contents(of: "App/AppDelegate.swift")
        #expect(!delegate.contains("SpikeController"))
        #expect(delegate.contains("DebugMaple.launchArgument"))
        #expect(DebugMaple.launchArgument == "-debugPlaceMaple")
    }
```

- [ ] **Step 2: Run it to see it fail**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData -only-testing:StickermineTests/AppDelegateTests
```

Expected: `** TEST FAILED **` with `error: cannot find 'DebugMaple' in scope`.

- [ ] **Step 3: Delete the spike**

```bash
git rm Stickermine/Stickers/SpikeController.swift
```

Expected: `rm 'Stickermine/Stickers/SpikeController.swift'`. (The spike's findings live on in `design/spike-results.md`.)

- [ ] **Step 4: Implement**

`Stickermine/App/DebugMaple.swift` (complete file):

```swift
import AppKit
import os

/// Temporary (M2): `open Stickermine.app --args -debugPlaceMaple` saves the
/// bundled Maple into the library as an ordinary sticker (PNG first, then the
/// index) and places her, Shadow style, centred on the mouse pointer and fitted
/// within half of that display, so restore, persistence and display changes can
/// be checked end to end before capture exists. M4 deletes this file and its
/// branch in AppDelegate once real captures can be placed.
enum DebugMaple {
    static let launchArgument = "-debugPlaceMaple"
    private static let log = Logger(subsystem: "com.ethan.stickermine", category: "debug")

    @MainActor
    static func place(library: LibraryController, stickers: StickerManager, screens: ScreenProvider) {
        guard !library.isReadOnly else {
            log.error("library is read-only; Maple not placed")
            return
        }
        guard let maple = BundledImages.cgImage(named: BundledImages.mapleName) else {
            log.error("Maple asset missing")
            return
        }
        let id = UUID()
        let pixelsPerPoint = 2.0  // Maple.png is stored @2x
        let store = library.store
        Task.detached {
            do {
                let data = try MasterImage.pngData(maple, pixelsPerPoint: pixelsPerPoint)
                try store.writePNG(data, for: id)
            } catch {
                log.error("writing Maple's PNG failed: \(error.localizedDescription, privacy: .public)")
                return
            }
            await MainActor.run {
                commit(id: id, image: maple, pixelsPerPoint: pixelsPerPoint,
                       library: library, stickers: stickers, screens: screens)
            }
        }
    }

    @MainActor
    private static func commit(id: UUID, image: CGImage, pixelsPerPoint: Double, library: LibraryController,
                               stickers: StickerManager, screens: ScreenProvider) {
        let record = StickerRecord(id: id, created: Date(), pixelWidth: image.width, pixelHeight: image.height,
                                   pixelsPerPoint: pixelsPerPoint, lastStyle: .shadow)
        library.mutate { $0.stickers.append(record) }
        let pointer = NSEvent.mouseLocation
        guard let display = StickerManager.display(containing: pointer, in: screens.currentDisplays()) else { return }
        let natural = record.naturalPointSize
        let fit = min(1, display.frame.width / 2 / natural.width, display.frame.height / 2 / natural.height)
        let size = CGSize(width: natural.width * fit, height: natural.height * fit)
        let placement = stickers.place(sticker: id, style: .shadow, centerOnScreen: pointer, pointSize: size)
        log.notice("placed Maple \(id.uuidString, privacy: .public) as \(placement?.uuidString ?? "nothing", privacy: .public)")
    }
}
```

`Stickermine/App/AppDelegate.swift` (complete new version; replaces M1 Task 10's whole file: the `spike` property and the `if arguments.contains(SpikeController.launchArgument) { … }` block are gone, `Self.didRunStartup = true` stays the first line after the test-host guard):

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
    /// the fallback mode becomes the default?". The hidden `clickThroughFallback`
    /// setting (spec section 12) overrides it either way.
    static let clickThroughFallbackByDefault = false

    private let log = Logger(subsystem: "com.ethan.stickermine", category: "app")
    private var library: LibraryController?
    private var stickers: StickerManager?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !Self.isRunningTests else { return }
        Self.didRunStartup = true
        // LSUIElement already makes this an agent app; saying so in code keeps it
        // true even for a launch whose Info.plist was not the one we built.
        NSApp.setActivationPolicy(.accessory)
        startStickers()
    }

    /// SIGTERM skips this, so nothing may depend on it; the debounced save has
    /// usually run already.
    func applicationWillTerminate(_ notification: Notification) {
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

        if ProcessInfo.processInfo.arguments.contains(DebugMaple.launchArgument) {
            DebugMaple.place(library: library, stickers: stickers, screens: screens)
        }
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

- [ ] **Step 5: Apply the spike's decisions**

Open `design/spike-results.md` and read its **Decisions** table (filled in M1 Tasks 11–12):

1. "Do panels go stale, and does a rebuild fix it?" If the outcome says panels went stale and the rebuild fixed it, change `static let rebuildsPanelsAfterSystemEvents = false` to `static let rebuildsPanelsAfterSystemEvents = true` in `Stickermine/Stickers/StickerManager.swift`. Otherwise leave it `false`.
2. "Alpha click-through works, or the fallback mode becomes the default?" If the outcome says the fallback becomes the default, change `static let clickThroughFallbackByDefault = false` to `static let clickThroughFallbackByDefault = true` in `Stickermine/App/AppDelegate.swift`. Otherwise leave it `false`. M4 Task 17 and M6 Tasks 1 and 14 rewrite this line; each of them keeps the value chosen here.
3. "Stage Manager supported as is?" and rows 23–26 (Show Desktop, Mission Control). If any of them failed, stop and ask Ethan before going on: the fixes the spike table suggests (`.canJoinAllApplications`, `.transient` for floated stickers) change the collection behaviour that spec section 9 fixes and `PanelPolicyTests.stickerBehaviorIsExactlyTheSpecSet` pins, so they are a spec change for him to decide. If they passed, nothing changes.

Step 9 writes the two values into the commit message.

- [ ] **Step 6: Run the whole suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 145 tests in 18 suites passed` and `** TEST SUCCEEDED **`; no sticker appears on screen (the test host skips startup).

- [ ] **Step 7: Build**

```bash
pkill -x Stickermine || true
./build.sh
```

Expected: ends with `Built ./build/Stickermine.app` (after `Type-checking against MacOSX26.5.sdk...`, which proves the new code stays within the macOS 26 SDK).

- [ ] **Step 8: MANUAL VERIFICATION (Ethan at the Mac; record what was seen, never assume)**

This build writes the real library at `~/Library/Application Support/com.ethan.stickermine/`. Setup, in bash or zsh:

```bash
LIB="$HOME/Library/Application Support/com.ethan.stickermine"
if [ -e "$LIB" ]; then mv "$LIB" "$LIB.before-m2"; fi
```

(Any earlier folder is kept as `com.ethan.stickermine.before-m2`; Task 13 Step 5 puts it back.) In a second terminal: `log stream --style compact --predicate 'subsystem == "com.ethan.stickermine"'`. Quitting with `pkill` sends SIGTERM, which skips `applicationWillTerminate`; the 0.5 s debounced save has long run by then, which is exactly the spec's point that nothing may depend on that hook.

1. Put the pointer in the middle of the main display (the one with the menu bar), then run `open build/Stickermine.app --args -debugPlaceMaple`. Expected: within about a second Maple appears centred on the pointer at 310 × 455 pt (smaller only on a display under 910 pt tall, where she is fitted to half its height), with no shadow (M3 adds styles) and no Dock icon. Log, in this order: `reconcile #1: N displays, N changed, 0 panels` (N = the number of connected displays), `library fresh: 0 stickers`, `ordered in` followed by 8 hex digits and `at {{x, y}, {310, 455}}`, `reconcile #2: N displays, 0 changed, 1 panels`, then `placed Maple` with two UUIDs.
2. After 2 s: `ls "$LIB/stickers"` shows one `<UUID>.png`; `sips -g dpiWidth "$LIB"/stickers/*.png` shows `dpiWidth: 144.000`; `cat "$LIB/library.json"` shows `"version" : 1`, one sticker with `"pixelWidth" : 620`, `"pixelHeight" : 910`, `"pixelsPerPoint" : 2` and `"lastStyle" : "shadow"`, and under `"displays"` one record (the main display's UUID, its name, vendor, model, serial) holding one placement with `"style" : "shadow"`, `"rotation" : 0` and a `"poses"` object with exactly one key, the main display's point size (for example `"1512x982"`).
3. With another app frontmost, click Maple's opaque pixels once, then double-click them. Expected: nothing happens and the other app stays frontmost (editing arrives in M5).
4. Put a desktop file icon under a transparent part of Maple's window (beside her ear, inside the window's rectangle) and click it. Expected: the icon is selected.
5. Run `shasum "$LIB/library.json"`, then `pkill -x Stickermine`. Expected: Maple disappears. Run `open build/Stickermine.app` (no argument). Expected: Maple reappears exactly where she was; log `library loaded: 1 stickers` and one `ordered in` line with the same frame as in item 1; `shasum "$LIB/library.json"` prints the same hash as before.
6. With a second display: move the pointer onto it, then `pkill -x Stickermine; open build/Stickermine.app --args -debugPlaceMaple`. Expected: the first Maple is restored on the main display and a second appears on the other display at the pointer; `library.json` now has two display records with one placement each. (Without a second display write `not run: one display` in the commit body.)
7. Run `pkill -x Stickermine; open build/Stickermine.app` once more. Expected: every Maple restored in place, nothing else on screen.
8. Sharing (Review Focus 3). With the default setting, press ⌘⇧3 and open the screenshot. Expected: no Maple in it. Then run `defaults write com.ethan.stickermine hideFromSharing -bool false; pkill -x Stickermine; open build/Stickermine.app` and press ⌘⇧3 again. Expected: Maple is in the new screenshot. Then `defaults delete com.ethan.stickermine hideFromSharing; pkill -x Stickermine; open build/Stickermine.app`. (Turning the setting off while running has no UI until M6; `StickerManagerTests.theSharingSettingAppliesToEveryPanelLive` covers that path.)
9. Newer library (Review Focus 2):
   ```bash
   pkill -x Stickermine
   cp "$LIB/library.json" "$LIB/library.backup.json"
   sed -i '' 's/"version" : 1/"version" : 2/' "$LIB/library.json"
   grep '"version"' "$LIB/library.json"; shasum "$LIB/library.json"; ls "$LIB/stickers" | wc -l
   open build/Stickermine.app --args -debugPlaceMaple
   ```
   Expected: `"version" : 2`; every Maple restored as before; log `library read-only (saved by a newer Stickermine): …` and `library is read-only; Maple not placed`. After 2 s, `shasum "$LIB/library.json"` and `ls "$LIB/stickers" | wc -l` print the same values as before launching. Restore: `pkill -x Stickermine; mv "$LIB/library.backup.json" "$LIB/library.json"`.
10. Corrupt library (Review Focus 2):
    ```bash
    cp "$LIB/library.json" "$LIB/library.backup.json"
    printf 'not json' >> "$LIB/library.json"
    open build/Stickermine.app
    ```
    Expected: no Maple on screen (a corrupt file loses its placements, by design); log `library recovered from a corrupt library.json: N stickers` (N = the number of PNGs); `ls "$LIB"` shows `library.corrupt-<date>.json` and `library.backup.json` but no `library.json` (nothing changed, so nothing was saved). Restore: `pkill -x Stickermine; rm "$LIB"/library.corrupt-*.json; mv "$LIB/library.backup.json" "$LIB/library.json"; open build/Stickermine.app`. Expected: every Maple is back.
11. Fallback click-through: `defaults write com.ethan.stickermine clickThroughFallback -bool true; pkill -x Stickermine; open build/Stickermine.app`. Repeat item 4. Expected: the icon under the transparent part is selected. Then put an icon under Maple's opaque pixels and click her there. Expected: the icon is not selected. Then move the pointer onto Maple's opaque pixels, slide it (without leaving her window) onto the transparent part beside her ear where an icon sits, and click. Expected: the icon is selected (the sticker released the mouse when the pointer left her opaque pixels). Finally `defaults delete com.ethan.stickermine clickThroughFallback; pkill -x Stickermine; open build/Stickermine.app`.
12. Leave Stickermine running with its Maples for Task 13.

If anything differs, stop and debug it (superpowers:systematic-debugging) before committing; fixes get a failing unit test first where one can be written.

- [ ] **Step 9: Commit**

```bash
git add Stickermine/App/AppDelegate.swift Stickermine/App/DebugMaple.swift Stickermine/Stickers/StickerManager.swift StickermineTests/AppDelegateTests.swift
git status --short
REBUILD=$(grep -o 'rebuildsPanelsAfterSystemEvents = [a-z]*' Stickermine/Stickers/StickerManager.swift)
FALLBACK=$(grep -o 'clickThroughFallbackByDefault = [a-z]*' Stickermine/App/AppDelegate.swift)
git commit -m "Restore stickers at launch, flush on quit, add -debugPlaceMaple, remove the spike" -m "Spike decisions applied: ${REBUILD}; ${FALLBACK}." -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

`git status --short` must show the deletion `D  Stickermine/Stickers/SpikeController.swift` staged and nothing unstaged in `Stickermine/` or `StickermineTests/`. Any manual item that differed was fixed before this commit (Step 8's last paragraph); a manual item that couldn't be run (item 6 without a second display) is noted in `design/display-checks.md` in Task 13.

---

### Task 13: Display checks on real hardware (Review Focus item 1)

**Files:**
- Create: `design/display-checks.md`

**Interfaces:**
- Consumes: the Task 12 build, running with one Maple per display (Task 12 Step 8 items 1 and 6).
- Produces: `design/display-checks.md` with every row's result, the evidence for the index's Review Focus item 1.

- [ ] **Step 1: Write the checklist**

`design/display-checks.md` (complete file; the Result cells start empty):

````markdown
# Display checks (M2)

M2's `StickerManager` keeps sticker windows in step with displays (spec section 11). Expected everywhere: stickers vanish with their display and come back in exactly the same place; nothing jumps to another display; nothing is saved. These checks need real hardware and a person at the Mac. An agent executing the plan asks Ethan to do each action and writes down what he reports and the named log lines; it never fills in a Result itself.

## Setup

1. `pkill -x Stickermine || true`, then `./build.sh`.
2. In a second terminal: `log stream --style compact --predicate 'subsystem == "com.ethan.stickermine" AND category == "stickers"'`.
3. In bash or zsh: `LIB="$HOME/Library/Application Support/com.ethan.stickermine"`.
4. One Maple per display: with the pointer on the main display, `open build/Stickermine.app --args -debugPlaceMaple`; then wait 2 s (the debounced save), then `pkill -x Stickermine`, move the pointer onto the external display and run the same command again. (Task 12 left this state behind if it ran item 6.) Without an external display, place the one Maple only; rows 1–4 and 8–12 are then `not run: no external display`.
5. `pkill -x Stickermine; open build/Stickermine.app`. Copy the `ordered in <id> at {{x, y}, {w, h}}` lines into the Frames table below: they are the reference for "the same place".
6. Wait 2 s, then `shasum "$LIB/library.json"` and write the hash below. Every row ends with the same command; the hash must never change.

| Field | Value |
|---|---|
| Date | |
| macOS (`sw_vers -productVersion`, `sw_vers -buildVersion`) | |
| Mac model | |
| Displays (name, resolution, scale, which is main) | |
| `StickerManager.rebuildsPanelsAfterSystemEvents` | |
| Baseline `shasum` of library.json | |

| Placement (8 hex) | Display | Frame at setup |
|---|---|---|
| | | |
| | | |

## Checks

| # | Event | How | Expected | Result | Hash unchanged? |
|---|---|---|---|---|---|
| 1 | Unplug the external display | Unplug its cable. | Its Maple vanishes and does not stay on the remaining display (a flash of under half a second while macOS rearranges windows is tolerable; write it down if seen). Log: `display <UUID> removed; its stickers are ordered out` (Core Graphics callback) or, if that callback didn't fire, `ordered out <id>: display <UUID> is gone`; then a `reconcile #n` line within about 0.5 s. | | |
| 2 | Replug it | Plug the same cable back into the same port. | The Maple returns. Log: `ordered in <id> at …` with its setup frame. | | |
| 3 | Replug on another port | Unplug, then plug into a different port. | Same as row 2 (the display UUID is expected to stay the same; if the Maple doesn't return, note the new UUID from `reconcile` and `library.json`). | | |
| 4 | Lid closed (MacBook with external display, keyboard and mouse) | Close the lid; wait 10 s; open it. | While closed: the built-in display's Maple is ordered out; the external one doesn't move. After opening: the built-in Maple is back with its setup frame. | | |
| 5 | Sleep and wake | Apple menu › Sleep; wait 30 s; wake and unlock. | Both Maples drawn at their setup frames. A desktop icon under a Maple's opaque pixels can't be clicked (she still absorbs clicks). Log: a `reconcile` shortly after wake and another about 1.5 s later; with the rebuild switch on, new `ordered in` lines about 1.5 s after wake. | | |
| 6 | Lock and unlock | ⌃⌘Q; wait 10 s; unlock. | Same as row 5. | | |
| 7 | Resolution change | System Settings › Displays: pick another "Larger Text / More Space" option for the main display; then restore the original. | While changed: the main display's Maple stays on that display at the same relative position, scaled with the display and fully on screen (a `reconcile` line with at least `1 changed`; no `ordered in` line, except that with the rebuild switch on every Maple is recreated about 1.5 s later and logs one). After restoring: back at the setup frame. | | |
| 8 | Mirroring on | Displays: mirror one display onto the other. | Only the mirror primary's own Maple shows (on both panels); the other Maple is ordered out; nothing lands on the wrong display. | | |
| 9 | Mirroring off | Stop mirroring. | Both Maples at their setup frames. | | |
| 10 | Arrangement change | Displays › Arrange: drag the external display to the other side; then put it back. | Each Maple stays on its own display at the same spot on that display (its global frame origin changes with the arrangement, its place on the display doesn't). | | |
| 11 | Main display change | Displays › Arrange: drag the menu bar onto the external display; then back. | Same as row 10. | | |
| 12 | Display powered off | Turn the external display off with its power button (or let it sleep); wait 1 min; turn it on. | While off: its Maple either stays put (a sleeping display still counts as connected) or is ordered out as in row 1, and nothing moves to the remaining display; no flood of log lines (one `reconcile` per burst of events) and Activity Monitor shows Stickermine near 0 % CPU. After: the Maple is at its setup frame. | | |
| 13 | Library untouched | After all rows: `shasum "$LIB/library.json"`. | The baseline hash. | | |

## Outcome

Fill in after the run: which rows failed (if any), what was fixed, and the commits that fixed them.
````

- [ ] **Step 2: Run the checks with Ethan**

Ask Ethan to do the Setup and then rows 1–13 in order. For each row write in Result exactly what he reports, plus the named log lines copied from the `log stream` terminal, and the hash check. A row that can't be run gets `not run: <reason>`.

- [ ] **Step 3: Fix failures before moving on**

For a failed row: reproduce it in `StickerManagerTests` with `FakeScreens` first (a failing test that changes `h.screens.all` the way the hardware did), fix `StickerManager`, run the whole suite, rebuild, repeat the row, and write the fix into the Outcome section. If every row passed, write `All rows passed.` in Outcome.

- [ ] **Step 4: Commit**

```bash
git add design/display-checks.md
git commit -m "Record the M2 display checks on real hardware" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: Put the real library back**

The debug Maples must not stay in Ethan's real library: once M4 deletes `DebugMaple` they would be ordinary history stickers, and M6's first run (which needs a `library.json` with no stickers) would never happen on this Mac.

```bash
pkill -x Stickermine || true
LIB="$HOME/Library/Application Support/com.ethan.stickermine"
mv "$LIB" "$LIB.m2-checks"
if [ -e "$LIB.before-m2" ]; then mv "$LIB.before-m2" "$LIB"; fi
ls "$HOME/Library/Application Support" | grep stickermine
```

Expected: `com.ethan.stickermine.m2-checks`, plus `com.ethan.stickermine` only if a folder existed before M2. Nothing to commit.

---

### Task 14: Final build, full test run, contract update and CI dry run

**Files:**
- Modify: `design/plans/2026-10-12-stickermine-v1-plan.md` (Interface Contract)
- Modify: `design/ci-dry-runs.md` (append a row)

**Interfaces:**
- Consumes: everything above.
- Produces: a green local build and test run, the index's contract updated with this milestone's changes, and a recorded CI dry run on the M2 head (or a recorded reason why not).

- [ ] **Step 1: Build**

```bash
pkill -x Stickermine || true
./build.sh
```

Expected: `Type-checking against MacOSX26.5.sdk...`, then `Building Stickermine...`, and it ends with `Signed by certificate DEA1A3749B06CF3619F72152EFC35A48E380C4E4` and `Built ./build/Stickermine.app`.

- [ ] **Step 2: Run the whole test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData
```

Expected: `Test run with 145 tests in 18 suites passed` and `** TEST SUCCEEDED **`.

- [ ] **Step 3: Update the index's Interface Contract**

In `design/plans/2026-10-12-stickermine-v1-plan.md` (each replacement goes inside the index's existing ```` ```swift ```` fence; the blocks below are fenced as text only because they are declarations, not compilable code):

(a) Under `### Model (M2)`, replace the whole code block (from the line `enum StickerStyle: String, Codable, CaseIterable {` to the closing `}` of `LibraryController`) with:

```text
enum StickerStyle: String, Codable, CaseIterable {          // CaseIterable order == UI order
    case puffy, outline, shadow, none
    // init(from:) decodes unknown raw values as .puffy
    var defaultFillHoles: Bool { get }                         // puffy/outline true, shadow/none false
}
struct Pose: Codable, Equatable { var x: Double; var y: Double; var scale: Double }   // normalized centre (Cocoa y-up), scale × natural size
struct Placement: Codable, Equatable, Identifiable {
    let id: UUID; var sticker: UUID; var style: StickerStyle
    var flipped: Bool; var onTop: Bool; var rotation: Double   // radians
    var poses: [String: Pose]                                  // key = DisplaySize.key
    init(id: UUID = UUID(), sticker: UUID, style: StickerStyle, flipped: Bool = false, onTop: Bool = false,
         rotation: Double = 0, poses: [String: Pose])                                              // [M2]
}
struct StickerRecord: Codable, Equatable, Identifiable {
    let id: UUID; var created: Date; var pixelWidth: Int; var pixelHeight: Int
    var pixelsPerPoint: Double; var lastStyle: StickerStyle; var tutorial: Bool
    init(id: UUID, created: Date, pixelWidth: Int, pixelHeight: Int, pixelsPerPoint: Double,
         lastStyle: StickerStyle, tutorial: Bool = false)                                          // [M2]
    var naturalPointSize: CGSize { get }                       // pixel size / pixelsPerPoint
}
struct DisplayRecord: Codable, Equatable {
    var name: String; var vendor: UInt32; var model: UInt32; var serial: UInt32; var builtin: Bool
    var lastSeen: Date; var placements: [Placement]            // back-to-front z-order
    init(name: String, vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool, lastSeen: Date,
         placements: [Placement])                                                                  // [M2]
}
struct Library: Codable, Equatable {
    static let currentVersion = 1
    var version: Int; var stickers: [StickerRecord]; var displays: [String: DisplayRecord]   // key = display UUID
    init(version: Int = Library.currentVersion, stickers: [StickerRecord], displays: [String: DisplayRecord])   // [M2]
    static var empty: Library { get }
}
extension Library {                                            // [M2]
    func sticker(_ id: UUID) -> StickerRecord?; func placement(_ id: UUID) -> Placement?
    func displayKey(containing placement: UUID) -> String?; func placementCount(of sticker: UUID) -> Int
    @discardableResult mutating func removePlacement(_ id: UUID) -> Placement?
    mutating func removeSticker(_ id: UUID)                    // every placement on every display too
    mutating func moveDisplayRecord(from oldKey: String, to newKey: String)   // fingerprint re-key
}
enum LibraryCoding { static func encoder() -> JSONEncoder; static func decoder() -> JSONDecoder }   // ISO-8601, sorted keys   [M2]

struct DisplaySize: Hashable { let width: Int; let height: Int; var key: String { get }; init(width: Int, height: Int); init?(key: String); init(_ size: CGSize)
    var isLandscape: Bool { get }; var area: Double { get } }                                     // [M2] isLandscape, area
enum LayoutResolver {
    static func pose(for placement: Placement, at size: DisplaySize) -> Pose?            // spec 11 rule incl. tie-break
    static func writing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement
    static func placing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement   // poses = [size: pose]
    static let tieTolerance: Double                                                       // [M2] 1e-9
    static func closestStoredSize(in poses: [String: Pose], to size: DisplaySize) -> DisplaySize?   // [M2]
    static func distance(from source: DisplaySize, to target: DisplaySize) -> Double     // [M2]
    static func isCloser(_ a: DisplaySize, than b: DisplaySize, to target: DisplaySize) -> Bool   // [M2]
}

struct DisplayInfo: Equatable {
    let uuid: String; let displayID: UInt32; let frame: CGRect; let visibleFrame: CGRect
    let backingScale: CGFloat; let name: String
    let vendor: UInt32; let model: UInt32; let serial: UInt32; let builtin: Bool
    let mirrorsDisplayID: UInt32?                               // nil when not a mirror secondary
    let inMirrorSet: Bool                                       // [M2] CGDisplayIsInMirrorSet; part of the reconcile snapshot
    init(uuid: String, displayID: UInt32, frame: CGRect, visibleFrame: CGRect, backingScale: CGFloat, name: String,
         vendor: UInt32, model: UInt32, serial: UInt32, builtin: Bool, mirrorsDisplayID: UInt32?,
         inMirrorSet: Bool = false)                                                                // [M2]
    var size: DisplaySize { get }
    var isGhost: Bool { get }                                   // vendor 0x756E6B6E && model 0x76697274
}
enum DisplayRegistry {
    static let ghostVendor: UInt32; static let ghostModel: UInt32; static let sharedSerial: UInt32   // [M2]
    static func usable(_ all: [DisplayInfo]) -> [DisplayInfo]   // also drops duplicate UUIDs (first wins)
    static func fingerprintAdoption(for display: DisplayInfo, records: [String: DisplayRecord], connected: [DisplayInfo]) -> String?   // record key to show on `display`, or nil
    static func uuidString(for displayID: UInt32) -> String?   // nil for 0 / kCGNullDirectDisplay / unknown
}
@MainActor protocol ScreenProvider: AnyObject {
    func currentDisplays() -> [DisplayInfo]                    // already filtered by DisplayRegistry.usable
    var mainDisplay: DisplayInfo? { get }                       // NSScreen.screens[0]
}
@MainActor final class LiveScreenProvider: ScreenProvider { init(); static func info(for screen: NSScreen) -> DisplayInfo? }   // [M2] info(for:)

final class LibraryStore {
    enum LoadResult: Equatable { case fresh(Library), loaded(Library), readOnlyNewer(Library), recoveredFromCorrupt(Library)
        var library: Library { get } }                          // [M2] library
    enum StoreError: Error, Equatable { case readOnly }         // [M2]
    init(root: URL)                                             // takes no UserDefaults: the store reads no settings
    let root: URL; var libraryURL: URL { get }; var stickersDirectory: URL { get }                 // [M2]
    static func defaultRoot() throws -> URL                     // ~/Library/Application Support/com.ethan.stickermine
    static func root(inApplicationSupport support: URL) -> URL // [M2]
    static let tutorialIDs: [UUID]                              // 5A1C0A00-7E57-4A11-8000-00000000000{1,2,3} = tutorial 1, 2, 3 (Maple)
    static let defaultPixelsPerPoint: Double                    // [M2] 2.0 for an adopted PNG without DPI
    func load() -> LoadResult                                   // includes launch repair; writes nothing but a corrupt file's rename
    func repair(_ library: Library) -> Library                  // [M2]
    static func corruptStamp(for date: Date) -> String          // [M2] "2026-10-15T21-02-33Z"
    func save(_ library: Library) throws                        // atomic; refuses (throws) when read-only
    func pngURL(for sticker: UUID) -> URL                       // stickers/<UPPERCASE-UUID>.png
    func writePNG(_ data: Data, for sticker: UUID) throws       // atomic
    func deletePNG(for sticker: UUID) throws                    // a PNG that is already gone is not an error
    private(set) var isReadOnly: Bool
}
@MainActor final class LibraryController {
    init(store: LibraryStore, saveDelay: TimeInterval = 0.5)    // [M2] saveDelay (tests)
    let store: LibraryStore; let loadResult: LibraryStore.LoadResult                               // [M2]
    private(set) var library: Library
    var isReadOnly: Bool { get }
    func mutate(_ change: (inout Library) -> Void)              // schedules a save 0.5 s later; ignored while read-only
    func refreshMetadata(_ change: (inout Library) -> Void)     // [M2] lastSeen/name: written with the next save, never schedules one
    func flush()                                                // synchronous save now
    var onChange: (() -> Void)?
    private(set) var hasPendingSave: Bool; private(set) var hasUnsavedChanges: Bool                // [M2]
}
```

(b) Under `### Rendering (M3)` (keep the heading: later plans anchor on it), replace its whole code block (from `struct StyleParameters: Equatable {` to the closing `}` of `StyleRenderer`) with:

```text
struct StyleParameters: Equatable {                             // created in M2
    let rimRadius: Double; let closing: Double; let shadowRadius: Double; let shadowOffset: Double
    let shadowOpacity: Double; let chokeSigma: Double
    static let referenceLongSide: Double; static let rimRadiusPerReference: Double; static let closingPerReference: Double
    static let shadowRadiusPerReference: Double; static let shadowOffsetPerRadius: Double
    static let shadowOpacityValue: Double; static let chokeSigmaPer512: Double                     // [M2] 800, 12, 10, 10, 0.6, 0.35, 0.5
    static func forStickerPixels(longSide: Double, sourceLongSide: Double) -> StyleParameters   // values per 800 px from spec 8
    func shadowMargin(for style: StickerStyle) -> Double        // 0 for .none, else ceil(3 × shadowRadius) + |shadowOffset|
}
struct RenderRequest: Equatable {                               // created in M2
    let sticker: UUID; let style: StickerStyle; let flipped: Bool; let rotation: Double
    let pointSize: CGSize                                       // unrotated on-screen size in points
    let backingScale: CGFloat
}
struct RenderedSticker {                                        // created in M2
    let contents: Any                                           // IOSurface or CGImage (CGImage in the M2 baseline)
    let pixelSize: CGSize; let pointBounds: CGSize               // rotated bounding box of the sticker (no margin)
    let alphaMask: AlphaMask                                     // for the fallback click-through mode and hit tests
}
struct AlphaMask { let width: Int; let height: Int; let bytes: [UInt8]; func isOpaque(atUnit p: CGPoint) -> Bool }   // p in 0–1, top-left origin; long side ≤ 512
final class StyleRenderer {                                     // M2 baseline: every style draws the plain master
    init(masterProvider: @escaping (UUID) -> CGImage?)         // called off the main thread
    static let maxPixelLongSide: Double = 2048
    func render(_ request: RenderRequest) async throws -> RenderedSticker
    func prewarm()                                              // compiles the Puffy kernel off-main (M3)
    enum RenderError: Error, Equatable { case missingMaster, emptySize, contextFailed }           // [M2]
    static let maxMaskLongSide: Int; static let alphaFloor: UInt8                                  // [M2] 512, 5
    static func canvas(for request: RenderRequest) -> (width: Int, height: Int, drawSize: CGSize, pointBounds: CGSize)   // [M2]
    static func renderBaseline(master: CGImage, request: RenderRequest) throws -> RenderedSticker   // [M2]
    static func clampAlphaAndBuildMask(pixels: UnsafeMutablePointer<UInt8>, width: Int, height: Int) -> AlphaMask   // [M2]
}
```

(c) In the code block under `### Stickers (M1 spike → M2/M3/M5)`, replace the line `    static func makeStickerPanel(contentRect: NSRect) -> StickerPanel` with `    static func makeStickerPanel(contentRect: NSRect, hideFromSharing: Bool = true) -> StickerPanel   // [M2] once .none, the getter stays .none on 27.2`, and replace the lines from `@MainActor final class StickerManager {` to its closing `}` with:

```text
@MainActor final class StickerManager {
    init(library: LibraryController, screens: ScreenProvider, renderer: StyleRenderer,
         reconcileDelay: TimeInterval = 0.45)                   // [M2] reconcileDelay (tests)
    func restoreAll()
    func scheduleReconcile()                                    // 450 ms debounce
    func reconcileNow()
    @discardableResult
    func place(sticker: UUID, style: StickerStyle, centerOnScreen: NSPoint, pointSize: CGSize) -> UUID?   // a user placement; [M2] returns its ID
    func remove(placement: UUID)
    func deleteSticker(_ sticker: UUID)
    func panel(for placement: UUID) -> StickerPanel?
    func setSharingHidden(_ hidden: Bool)                       // turning hiding off recreates the panels that stay hidden
    var editingPlacement: UUID? { get }
    func endEditing(discardGesture: Bool)
    static let rebuildsPanelsAfterSystemEvents: Bool            // [M2] from the spike results
    static let systemEventRecheckDelay: TimeInterval            // [M2] 1.5
    struct DisplaySnapshot: Equatable { let frame: CGRect; let backingScale: CGFloat; let inMirrorSet: Bool }   // [M2]
    var placementsWithPanels: Set<UUID> { get }; var reconcileCount: Int { get }; var renderRequestsIssued: Int { get }   // [M2]
    func refreshPanel(for placement: UUID)                      // [M2] re-resolve one placement after a model write
    func closeAllPanels(); func rebuildAllPanels()              // [M2]
    func commitRender(_ rendered: RenderedSticker, for request: RenderRequest, placement id: UUID)   // [M2]
    func recordKeyForUserEdit(on display: DisplayInfo) -> String   // [M2] creates the record or saves a fingerprint re-key
    func enableClickThroughFallback(); var isClickThroughFallbackEnabled: Bool { get }             // [M2]
    func startObservingDisplayChanges(); func systemEvent(recheckLater: Bool)                      // [M2]
    nonisolated static func ordersOutImmediately(for flags: CGDisplayChangeSummaryFlags) -> Bool   // [M2]
    nonisolated static func displayReconfigured(_ displayID: CGDirectDisplayID, flags: CGDisplayChangeSummaryFlags)   // [M2]
    func handleDisplayRemoved(displayID: UInt32)                // [M2]
    static func recordAssignments(displays: [DisplayInfo], records: [String: DisplayRecord]) -> [String: String]   // [M2]
    static func display(containing point: NSPoint, in displays: [DisplayInfo]) -> DisplayInfo?   // [M2]
}
enum StickerGeometry {                                          // [M2] pure pose ↔ screen geometry
    static let reachableInset: CGFloat                          // 8
    struct Layout: Equatable { let pose: Pose; let isBorrowed: Bool; let pointSize: CGSize; let stickerRect: CGRect }
    static func boundingSize(of size: CGSize, rotation: Double) -> CGSize
    static func center(of pose: Pose, in frame: CGRect) -> CGPoint
    static func pose(center: CGPoint, scale: Double, in frame: CGRect) -> Pose
    static func reachableCenter(_ center: CGPoint, visibleFrame: CGRect) -> CGPoint
    static func clampedRect(size: CGSize, center: CGPoint, within frame: CGRect) -> CGRect
    static func layout(for placement: Placement, natural: CGSize, on display: DisplayInfo) -> Layout?
}
@MainActor final class ClickThroughFallback {                   // [M2] the only writer of ignoresMouseEvents
    struct Target { let panel: NSPanel; let contentRect: CGRect; let mask: AlphaMask?; let wholeFrame: Bool }
    struct Candidate { let contentRect: CGRect; let frame: CGRect; let mask: AlphaMask?; let wholeFrame: Bool }
    init(targets: @escaping () -> [Target]); func prepare(_ panel: NSPanel); func forget(_ panel: NSPanel)
    func start(); func stop(); func update(at point: NSPoint); private(set) weak var activePanel: NSPanel?
    nonisolated static func hitIndex(at p: CGPoint, in candidates: [Candidate]) -> Int?
}
extension AppDelegate { static let clickThroughFallbackByDefault: Bool }   // [M2] from the spike results
```

(d) In the code block under `### Capture, picker, session (M4)`, replace the four lines from `enum MasterImage {` to its closing `}` with:

```text
enum MasterImage {
    static func load(url: URL) throws -> LoadedCapture
    static func pngData(_ image: CGImage, pixelsPerPoint: Double) throws -> Data   // writes DPI = 72 × ppp   [created in M2]
    enum Failure: Error { case cannotEncode }                                      // [M2]
    struct FileInfo: Equatable { let pixelWidth: Int; let pixelHeight: Int; let pixelsPerPoint: Double? }   // [M2]
    static func fileInfo(at url: URL) -> FileInfo?                                 // [M2] size and DPI without decoding
    static func pixelsPerPoint(fromDPI dpi: Double) -> Double?                     // [M2] DPI / 72, rounded to 0.01
    static func image(at url: URL) -> CGImage?                                     // [M2] thread-safe
}
```

Check:

```bash
grep -c 'hideFromSharing: Bool = true' design/plans/2026-10-12-stickermine-v1-plan.md
grep -c '\[M2\]' design/plans/2026-10-12-stickermine-v1-plan.md
grep -c 'created in M2' design/plans/2026-10-12-stickermine-v1-plan.md
```

Expected: `1`, a number above `30`, and `4` (StyleParameters, RenderRequest, RenderedSticker, and the MasterImage `pngData` line).

- [ ] **Step 4: Commit locally**

```bash
git add design/plans/2026-10-12-stickermine-v1-plan.md
git commit -m "Record M2's contract changes in the plan index" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

- [ ] **Step 5: CI dry run (needs Ethan's explicit yes now)**

If `git remote get-url origin` fails, the GitHub repo doesn't exist yet: append the "not run" row and stop here (go to Step 6):

```bash
REASON="no GitHub repo yet"
echo "| $(date +%F) | M2 end (Task 14) | $(git rev-parse --short HEAD) | none | not run | Ethan: $REASON |" >> design/ci-dry-runs.md
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
  echo "| $(date +%F) | M2 end (Task 14) | ${ROW} | |" >> design/ci-dry-runs.md
fi
```

Expected: `gh run watch` exits 0 and the appended row ends `| success | |`. If Ethan says no, append the "not run" row above with his reason in `REASON`. If it prints `error: the dispatched run never appeared`, nothing was recorded: check `gh run list --workflow release.yml` and rerun from `BEFORE=`. On a failed run, `gh run view "$RUN_ID" --log-failed`: an unknown-symbol error means a macOS 27-only API slipped in (fix it, run the suite, commit, ask before pushing again); a project-format error means the project file changed from objectVersion 77.

- [ ] **Step 6: Commit the record**

```bash
git add design/ci-dry-runs.md
git commit -m "Record M2's CI dry run" -m "Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>"
```

Push only with Ethan's yes (`git push`).

## Notes for later milestones

- **M3** replaces the drawing inside `StyleRenderer.render` per style (keeping `canvas(for:)`'s 2048 px cap and `clampAlphaAndBuildMask`), compiles the Puffy kernel in `prewarm()`, decides IOSurface or CGImage contents (spike rows 15–16), and makes `StickerView.show(_:shadow:style:)` build a `LayerShadow` from `shadow` (pixel values divided by the panel's backing scale; nil for `.none`). `StickerManager.commitRender` then passes `StyleParameters.forStickerPixels(longSide:sourceLongSide:)` instead of `nil`; `applyFrame` already adds `view.layerShadow?.margin`, so frames grow by the margin as soon as a shadow is shown. Re-render on `windowDidChangeBackingProperties` (a reconcile already re-renders when a display's backing scale changes).
- **M4** deletes `Stickermine/App/DebugMaple.swift`, the `-debugPlaceMaple` branch in `AppDelegate` and the `DebugMaple` lines of `AppDelegateTests.theSpikeIsGoneAndOnlyTheDebugMaplePathRemains` (keep its spike checks). It adds `MasterImage.load(url:)` and `LoadedCapture` next to M2's members, writes a new master with `library.store.writePNG` off the main thread and then `library.mutate` on main (PNG before index), sets `lastStyle`, and gets the new placement's ID from `StickerManager.place`.
- **M5** adds editing to `StickerManager` (it sets `editingPlacement`; replace the body of `endEditing(discardGesture:)` with the real gesture teardown). A user edit writes through `LayoutResolver.writing` (or `placing` for a cross-display drop) inside `library.mutate`, after `recordKeyForUserEdit(on:)` for the display it lands on (that saves a fingerprint re-key), then calls `refreshPanel(for:)`: reconcile keeps a cached layout until told. In the fallback mode an editing panel takes its whole frame (`panel.isEditing`), which `ClickThroughFallback` already honours. `reconcileNow()` must not fight a live gesture: while `editingPlacement` has a gesture in progress, skip `applyFrame` for that entry; when a reconcile, `handleDisplayRemoved` or `rebuildAllPanels` orders out or closes the editing panel, call `endEditing(discardGesture: true)` first (spec section 10, "Editing ending mid-gesture").
- **M6** moves the `hideFromSharing` and `clickThroughFallback` keys into `Settings`; its sharing toggle calls `setSharingHidden` (turning hiding off recreates the panels with their bitmaps, ending any editing). Home shows the read-only notice when `library.loadResult` is `.readOnlyNewer`, uses `deleteSticker` for Delete from History with `library.library.placementCount(of:)` in the confirmation, flushes before the updater's helper, and builds tutorials under `LibraryStore.tutorialIDs`.
