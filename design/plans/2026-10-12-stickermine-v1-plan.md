# Stickermine v1 Implementation Plan (index)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Work the milestone plans in order; each one ends with working software and a CI dry run.

**Goal:** Build Stickermine v1, a macOS 26+ menu bar app that turns screenshot cutouts into live desktop stickers, plus its website and release pipeline.

**Architecture:** An Xcode project (format "Xcode 16.0") with SwiftUI views hosted in AppKit-owned windows. Each sticker is its own borderless `NSPanel` one level above the desktop icons. Pure logic (layout resolution, display identity, persistence, capture classification, style parameters) lives in AppKit-free types with Swift Testing coverage. Capture shells out to `screencapture -i`, cutout uses Vision's foreground instance masks, and styles render with Core Image. Release builds go through `build.sh` and the Pullcord-derived `release.yml`.

**Tech Stack:** Swift (language mode 5), SwiftUI + AppKit, Vision, Core Image (+ one runtime-compiled Metal CI kernel), ImageIO, Carbon hotkeys, ServiceManagement, Swift Testing, `xcodebuild`, GitHub Actions (`macos-26` runner, Xcode 26.6), static HTML for the site.

**Spec:** `design/specs/2026-10-12-stickermine-v1-design.md` (read it before any milestone; section numbers below refer to it).

## Milestones

| # | Plan file | Delivers | Depends on |
|---|---|---|---|
| M1 | `2026-10-12-m1-foundation.md` | Repo scaffold, Xcode project, `build.sh`/`install.sh`/`release.yml`, minimal LSUIElement app, hosted test target, first CI dry run, and the **sticker-window spike** (one hard-coded sticker you can double-click and drag) with recorded spike results | — |
| M2 | `2026-10-12-m2-model-displays.md` | Library model, `LibraryStore` (load/save/repair/versioning), `LibraryController` (debounced saves), `LayoutResolver`, `DisplayRegistry` + `ScreenProvider`, `StyleParameters` (pure), a **baseline `StyleRenderer`** (every style renders as an unstyled, size-capped bitmap with an `AlphaMask`; M3 replaces the per-style rendering), `StickerManager` restoring placements as panels and reconciling display changes, plus a temporary debug path to place the bundled Maple image | M1 |
| M3 | `2026-10-12-m3-styles.md` | Real style rendering inside `StyleRenderer` (Puffy kernel + fallback, Outline SDF, Shadow, None choke), layer shadow + padded frame in `StickerView`, IOSurface/CGImage contents, re-render on backing change, a debug style gallery | M2 |
| M4 | `2026-10-12-m4-capture-picker.md` | `StatusItemController` (glyph asset, left-click capture, right-click menu with New Sticker and Quit), `HotkeyCenter` with the default ⌃⌥⌘S, `CaptureService` + `CaptureClassifier`, `PermissionPanel`, `HUD`, `CutoutEngine` (pass 1/2, mask sampler, hole fill, whole image, master PNG with DPI), `PickerPanel`, `PlacementSession`, `SessionCoordinator` | M2, M3 |
| M5 | `2026-10-12-m5-editing.md` | `StickerEditor` (hit pad, drag, knob, pinch/rotate, limits, gesture lifecycle, re-bake), `ToolbarPill`, bring to front, Remove, cross-display drag, clamps, editing-end rules | M2, M3, M4 |
| M6 | `2026-10-12-m6-app-shell.md` | `Shortcut` storage + `ShortcutRecorder` + `SystemShortcuts`, `SingleInstance`, `LoginItem`, Home window (history grid, settings, About, Quit, update strip) and the menu's Open Stickermine…, `Updater`, delete from history, sharing toggle, hide-menu-bar-icon, first-run tutorials, support ask, termination cleanup, read-only (newer library) UI, app icon | M2–M5 |
| M7 | `2026-10-12-m7-site-release.md` | `docs/` website, README, PRIVACY, TERMS, CONTACT, cask file, release checklist through `v1.0` and Pages | M1–M6 |

## Global Constraints

Every task in every milestone implicitly includes these (values copied from the spec):

- macOS **26.0** minimum, **Apple Silicon only** (`arm64`). `LSMinimumSystemVersion` = `26.0` in the root `Info.plist`; project `MACOSX_DEPLOYMENT_TARGET` = `26.0`.
- **API ceiling = macOS 26 SDK and Xcode 26.6's Swift.** No macOS 27-only symbol anywhere, even behind `#available`. Known 27-only traps: `NSApplication.DidChangeScreenParametersMessage`, `PixelBufferObservation.pixelBuffer`, `NSGlassEffectView.effectIsInteractive`, `GenerateIterativeSegmentationRequest`.
- Bundle ID **`com.ethan.stickermine`**; product name **`Stickermine`**; `LSUIElement` = true.
- **No third-party dependencies, no App Sandbox, no entitlements file.** Hardened runtime; Developer ID signing by SHA-1 `DEA1A3749B06CF3619F72152EFC35A48E380C4E4` in `build.sh` only.
- Swift settings: `SWIFT_VERSION = 5.0`, `SWIFT_STRICT_CONCURRENCY = minimal`, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`, `SWIFT_APPROACHABLE_CONCURRENCY = NO`. Mark AppKit-facing classes `@MainActor` explicitly.
- Project format **"Xcode 16.0"** (objectVersion 77). `GENERATE_INFOPLIST_FILE = NO` (the never-shipped `StickermineTests` bundle alone uses `YES`; pinned by `ProjectSettingsTests`); no `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` or `INFOPLIST_KEY_*` anywhere.
- Data lives in **`~/Library/Application Support/com.ethan.stickermine/`** (`library.json` + `stickers/<uuid>.png`). Tests never touch it or `UserDefaults.standard`.
- Style order everywhere in the UI: **1 Puffy, 2 Outline, 3 Shadow, 4 None**.
- Sticker window level: `CGWindowLevelForKey(.desktopIconWindow) + 1`; Float on top `.floating`; collection behaviour `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`. **Never write `ignoresMouseEvents` on a sticker panel** (except in the hidden fallback mode).
- **Only user actions write layout data** (spec section 11 hard rule and its listed exceptions).
- Default capture shortcut **⌃⌥⌘S** (keyCode 1, Carbon `controlKey|optionKey|cmdKey`).
- Ko-fi link **`https://ko-fi.com/grokcodile`**. Repo **`grokcodile/stickermine`**. Cask **`stickermine`** in **`grokcodile/homebrew-tap`**. Release asset name exactly **`Stickermine.dmg`**.
- **README never states a download or installed size;** the size appears only on the website.
- Outward-facing steps (creating the GitHub repo, pushing, tagging, editing the tap, enabling Pages) **require Ethan's explicit yes at the time**. Claude never handles CI secrets.
- Commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- Building on this Mac: `xcode-select` points at the CommandLineTools, so `xcodebuild` needs `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` (from M1, `build.sh` sets it automatically). Test command used throughout: `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcodebuild test -project Stickermine.xcodeproj -scheme Stickermine -destination 'platform=macOS,arch=arm64' -derivedDataPath build/DerivedData`.

## Review Focus

Failure modes the spec implies but unit tests can't fully pin down, most likely to bite first. Each owning milestone adds the named test or manual check.

1. **Display unplugged/replugged, lid closed/opened, sleep/wake with stickers on screen.** Expect: stickers vanish with their display and come back in exactly the same place; nothing jumps to another display; nothing is saved. Owner: M2 (reconcile unit tests with simulated snapshots + manual checklist run on real hardware).
2. **First capture ever** (permission undetermined, then the "bypass the private window picker" alert landing on the picker). Expect: the permission panel explains and requests; after granting, the next shortcut works; clicking the system alert never discards the capture. Owner: M4 (classifier/permission tests + manual run on a fresh user account or after `tccutil`-free reset by Ethan).
3. **Awkward captures:** flat colour, text-only, a window capture with transparent corners, a tiny selection, a 5K full-screen capture. Expect: "Whole image" path works, alpha preserved, no crash, memory falls back after the picker closes. Owner: M4 (CutoutEngine tests on generated images incl. flat colour and transparent corners).
4. **Many stickers** (50+, some from 5K captures). Expect: placement and launch stay fast; memory roughly linear in on-screen size, not capture size. Owner: M3 (render-size cap test) + M5/M6 manual check with 50 stickers.
5. **Losing the way back to Home:** menu bar icon hidden + shortcut cleared or conflicting. Expect: opening the app from Finder/Spotlight always opens Home; a cleared shortcut makes tutorial 1 say "Click the menu bar icon…" and the shortcut recorder refuses chords without ⌘ or ⌃. Owner: M6 (shortcut validation tests + lifecycle manual check).

## File Structure (whole app)

```
Stickermine/
  App/        StickermineApp.swift, AppDelegate.swift, SessionCoordinator.swift, StatusItemController.swift,
              HotkeyCenter.swift, Shortcut.swift, SystemShortcuts.swift, SingleInstance.swift, LoginItem.swift
  Capture/    CaptureService.swift, CaptureClassifier.swift, CutoutEngine.swift, MaskSampler.swift, HoleFiller.swift,
              StyleParameters.swift, StyleRenderer.swift, PuffyKernel.swift, MasterImage.swift
  Picker/     PickerPanel.swift, PickerModel.swift, PickerView.swift, PlacementSession.swift
  Stickers/   PanelPolicy.swift, StickerPanel.swift, StickerView.swift, StickerManager.swift, StickerEditor.swift,
              ToolbarPill.swift
  Model/      Library.swift, LibraryStore.swift, LibraryController.swift, LayoutResolver.swift, DisplayRegistry.swift,
              ScreenProvider.swift
  Home/       HomeWindowController.swift, HomeView.swift, HistoryGrid.swift, SettingsSection.swift,
              ShortcutRecorder.swift, AboutPopover.swift, UpdateStrip.swift
  Onboarding/ TutorialStickers.swift, PermissionPanel.swift, SupportAsk.swift
  Updater/    Updater.swift
  UI/         HUD.swift
  Assets.xcassets/ (AppIcon, MenuBarGlyph, Maple)
StickermineTests/  one <Unit>Tests.swift per tested unit + TestSupport.swift
```

Milestone plans may add small private helper files inside these folders; they may not rename or move the types in the contract below.

## Interface Contract

The names and signatures every milestone codes against. A milestone that must deviate records the change here in the same commit.

### Model (M2)

```swift
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
}
struct StickerRecord: Codable, Equatable, Identifiable {
    let id: UUID; var created: Date; var pixelWidth: Int; var pixelHeight: Int
    var pixelsPerPoint: Double; var lastStyle: StickerStyle; var tutorial: Bool
    var naturalPointSize: CGSize { get }                       // pixel size / pixelsPerPoint
}
struct DisplayRecord: Codable, Equatable {
    var name: String; var vendor: UInt32; var model: UInt32; var serial: UInt32; var builtin: Bool
    var lastSeen: Date; var placements: [Placement]            // back-to-front z-order
}
struct Library: Codable, Equatable {
    static let currentVersion = 1
    var version: Int; var stickers: [StickerRecord]; var displays: [String: DisplayRecord]   // key = display UUID
    static var empty: Library { get }
}

struct DisplaySize: Hashable { let width: Int; let height: Int; var key: String { get }; init(width: Int, height: Int); init?(key: String); init(_ size: CGSize) }
enum LayoutResolver {
    static func pose(for placement: Placement, at size: DisplaySize) -> Pose?            // spec 11 rule incl. tie-break
    static func writing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement
    static func placing(_ pose: Pose, to placement: Placement, at size: DisplaySize) -> Placement   // poses = [size: pose]
}

struct DisplayInfo: Equatable {
    let uuid: String; let displayID: UInt32; let frame: CGRect; let visibleFrame: CGRect
    let backingScale: CGFloat; let name: String
    let vendor: UInt32; let model: UInt32; let serial: UInt32; let builtin: Bool
    let mirrorsDisplayID: UInt32?                               // nil when not a mirror secondary
    var size: DisplaySize { get }
    var isGhost: Bool { get }                                   // vendor 0x756E6B6E && model 0x76697274
}
enum DisplayRegistry {
    static func usable(_ all: [DisplayInfo]) -> [DisplayInfo]
    static func fingerprintAdoption(for display: DisplayInfo, records: [String: DisplayRecord], connected: [DisplayInfo]) -> String?   // record key to show on `display`, or nil
    static func uuidString(for displayID: UInt32) -> String?   // nil for 0 / kCGNullDirectDisplay / unknown
}
@MainActor protocol ScreenProvider: AnyObject {
    func currentDisplays() -> [DisplayInfo]                    // already filtered by DisplayRegistry.usable
    var mainDisplay: DisplayInfo? { get }                       // NSScreen.screens[0]
}
@MainActor final class LiveScreenProvider: ScreenProvider { init() }

final class LibraryStore {
    enum LoadResult: Equatable { case fresh(Library), loaded(Library), readOnlyNewer(Library), recoveredFromCorrupt(Library) }
    init(root: URL)
    static func defaultRoot() throws -> URL                     // ~/Library/Application Support/com.ethan.stickermine
    static let tutorialIDs: [UUID]                              // 3 fixed UUIDs, order = tutorial 1, 2, 3 (Maple)
    func load() -> LoadResult                                   // includes launch repair
    func save(_ library: Library) throws                        // atomic; refuses (throws) when read-only
    func pngURL(for sticker: UUID) -> URL
    func writePNG(_ data: Data, for sticker: UUID) throws       // atomic
    func deletePNG(for sticker: UUID) throws
    private(set) var isReadOnly: Bool
}
@MainActor final class LibraryController {
    init(store: LibraryStore)
    private(set) var library: Library
    var isReadOnly: Bool { get }
    func mutate(_ change: (inout Library) -> Void)              // schedules a save 0.5 s later
    func flush()                                                // synchronous save now
    var onChange: (() -> Void)?
}
```

### Rendering (M3)

```swift
struct StyleParameters: Equatable {
    let rimRadius: Double; let closing: Double; let shadowRadius: Double; let shadowOffset: Double
    let shadowOpacity: Double; let chokeSigma: Double
    static func forStickerPixels(longSide: Double, sourceLongSide: Double) -> StyleParameters   // values per 800 px from spec 8
    func shadowMargin(for style: StickerStyle) -> Double        // 0 for .none, else ceil(3 × shadowRadius) + |shadowOffset|
}
struct RenderRequest: Equatable {
    let sticker: UUID; let style: StickerStyle; let flipped: Bool; let rotation: Double
    let pointSize: CGSize                                       // unrotated on-screen size in points
    let backingScale: CGFloat
}
struct RenderedSticker {
    let contents: Any                                           // IOSurface or CGImage, set as CALayer.contents
    let pixelSize: CGSize; let pointBounds: CGSize               // rotated bounding box of the sticker (no margin)
    let alphaMask: AlphaMask                                     // for the fallback click-through mode and hit tests
}
struct AlphaMask { let width: Int; let height: Int; let bytes: [UInt8]; func isOpaque(atUnit p: CGPoint) -> Bool }   // p in 0–1, top-left origin
final class StyleRenderer {
    init(masterProvider: @escaping (UUID) -> CGImage?)
    static let maxPixelLongSide: Double = 2048
    func render(_ request: RenderRequest) async throws -> RenderedSticker
    func prewarm()                                              // compiles the Puffy kernel off-main
}
```

### Stickers (M1 spike → M2/M3/M5)

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

### Capture, picker, session (M4)

```swift
enum CaptureOutcome: Equatable { case success(URL), controlHeldToClipboard, busyOrBlocked, cancelled }
enum CaptureClassifier { static func classify(fileExists: Bool, fileSize: Int, exitStatus: Int32, pasteboardChanged: Bool) -> CaptureOutcome }
@MainActor final class CaptureService {
    func capture(completion: @escaping (CaptureOutcome) -> Void)   // waits for modifiers, runs screencapture
    func cancelRunning()
    var isRunning: Bool { get }
    static func deleteLeftovers()
}
struct LoadedCapture { let image: CGImage; let pixelsPerPoint: Double }
enum MasterImage {
    static func load(url: URL) throws -> LoadedCapture
    static func pngData(_ image: CGImage, pixelsPerPoint: Double) throws -> Data   // writes DPI = 72 × ppp
}
enum MaskSampler { static func subject(atUnitTopLeft p: CGPoint, masks: [(index: Int, mask: CVPixelBuffer)]) -> Int? }
enum HoleFiller { static func fill(alpha: inout [Float], width: Int, height: Int, edge: Int) }
final class CutoutAnalysis {
    let capture: LoadedCapture; let subjectIndices: [Int]
    func subject(atUnitTopLeft p: CGPoint) -> Int?
    func highlightMask(for index: Int) -> CGImage?
    func cutout(selection: Set<Int>, fillHoles: Bool) async throws -> CGImage   // pass 2 when the bbox is small
    func wholeImage() -> CGImage                                 // alpha kept, corners rounded 4% of short side
}
final class CutoutEngine { func prewarm(); func analyze(_ capture: LoadedCapture) async -> CutoutAnalysis }
@MainActor final class SessionCoordinator {
    init(capture: CaptureService, cutout: CutoutEngine, stickers: StickerManager, library: LibraryController, store: LibraryStore, renderer: StyleRenderer)
    var isActive: Bool { get }
    var onActiveChange: ((Bool) -> Void)?
    func startCapture()
    func startReplace(sticker: UUID)
    func cancel()
}
```

### Hotkeys and settings (`Shortcut` + `HotkeyCenter` in M4; `SystemShortcuts`, `Settings`, recorder in M6)

```swift
struct Shortcut: Codable, Equatable {
    var keyCode: UInt32; var modifiers: UInt32                  // Carbon mask
    static let defaultCapture: Shortcut                         // keyCode 1, controlKey|optionKey|cmdKey
    var label: String { get }                                    // "⌃⌥⌘S", glyph order ⌃ ⌥ ⇧ ⌘
    var isAcceptable: Bool { get }                               // contains ⌘ or ⌃, or is an F-key
}
enum SystemShortcuts { static func conflicts(with s: Shortcut) -> Bool }   // CopySymbolicHotKeys
@MainActor final class HotkeyCenter { func register(_ s: Shortcut?, handler: @escaping () -> Void); func suspend(); func resume() }
enum Settings {                                                  // UserDefaults keys and typed accessors (spec 12)
    static func register(in defaults: UserDefaults)
}
```

## How each milestone plan is laid out

Each `m<N>` file has the standard header, its own **Files** map, then tasks of 2–5 minute TDD steps with complete code, exact commands and expected output, and a commit step. Every milestone's final task is: build with `build.sh`, run the full test suite, then (once the GitHub repo exists) trigger the CI dry run (`gh workflow run release.yml --ref main`) and confirm it passes on Xcode 26.6.
