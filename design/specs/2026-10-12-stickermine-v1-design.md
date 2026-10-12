# Stickermine v1: design spec

**Date:** 2026-10-12
**Status:** approved section by section in chat, revised after an independent four-lens review (58 verified findings applied); awaiting Ethan's review of this written spec
**Sources:** `design/stickermine-handoff.md` (product brief), the files in `design/` (icon, menu bar glyph, website mock, Maple), and a verified technical research pass (probes run on macOS 27.2, build 26B5101f, Apple M5, each finding checked by an independent verifier). Where this spec and the brief disagree, this spec wins; section 19 lists the differences.

---

## 1. What it is

A Mac menu bar app. You press a shortcut, drag over part of the screen with the system's own screenshot crosshair, Stickermine cuts out the subject on-device, you pick a style, and the sticker sticks to your desktop as a live floating object. It stays exactly where you left it until you move, restyle or remove it.

Tagline: "Turn quick screenshots into fun stickers that live on your desktop."

Images and isolated subjects only. Users can't make text stickers (the app's own tutorial stickers are the only text). Logos are treated like any other image. Styles never change on their own (no automatic seasonal changes).

### In v1

- Capture with a global shortcut or the menu bar icon, on-device subject cutout, a picker panel (toggle subjects, whole image, fill holes, four styles), then placement with the cursor.
- Four styles, in this order everywhere in the UI: **1 Puffy, 2 Outline** (thick white die-cut border + shadow), **3 Shadow, 4 None**. Each sticker has its own style.
- Live sticker windows above the desktop icons, on every desktop Space, with click-through on transparent pixels.
- Editing: double-click to activate, drag to move, corner knob to scale and rotate, trackpad pinch and rotate, toolbar pill (Style, Flip, Float on top, Remove).
- Per-display layouts with closest-size matching. Stickers on a disconnected display are hidden until it returns.
- Home window: history grid of every sticker made, settings, About, Quit.
- First-run tutorial stickers, a one-time support ask, a self-updater, launch at login.
- Website in `docs/`, release pipeline mirrored from Pullcord and Key54.

### Not in v1

Search, groups or saved layouts in history; more styles (B/W, retro, seasonal); per-Space stickers; stickers over full-screen apps; a global on/off switch (Quit is the off switch); click-to-refine segmentation; text stickers.

## 2. Decisions taken in the design conversation

| Question | Decision |
|---|---|
| Scope of this round | Full v1 spec, then an implementation plan |
| What Home shows besides settings | A grid of every sticker ever made; click to place again, right-click to delete |
| Active sticker controls | Corner knob (scale + rotate) plus a small toolbar pill under the sticker |
| When the style is chosen | A picker panel after the cutout, before the sticker attaches to the cursor |
| Several subjects / none | Click subjects in the picker to include or exclude them; "Whole image" when none are found or wanted |
| Capture mechanism | Shell out to the system `screencapture -i` |
| What to mirror from sibling apps | Only CI/release and the repo layout with the website in `docs/`; app architecture chosen fresh |
| App stack | Xcode project + SwiftUI views, hosted in AppKit-owned windows |
| `design/` folder | Committed to the repo |

## 3. Platform and repo

- **macOS 26.0 or later, Apple Silicon only.** `LSMinimumSystemVersion` in the root `Info.plist` decides the supported macOS: `build.sh` reads it for the deployment target, the release workflow writes it into the cask's `depends_on macos`, and the project's own `MACOSX_DEPLOYMENT_TARGET` is kept equal to it (`build.sh` fails if they differ).
- **API ceiling: the macOS 26 SDK and the Swift that ships with Xcode 26.6.** CI builds on the `macos-26` runner (Xcode 26.6, macOS 26.x SDKs, no macOS 27 SDK). Any macOS 27-only symbol fails the release build, even behind `if #available`. Locally, Xcode 27 beta's `xcodebuild` can only use its macOS 27 SDK and Swift 6.4 (it refuses the CommandLineTools `MacOSX26.5.sdk`). So **the authoritative check is a CI dry run**, run from the scaffold onward and at the end of every plan milestone (section 17). As an optional fast local pre-check, `build.sh` may run the CommandLineTools `swiftc -typecheck -sdk …/MacOSX26.5.sdk -target arm64-apple-macos$MIN_MACOS` over the sources when that SDK exists. Installing a released Xcode 26.x next to the beta would give exact local parity (whether it runs on macOS 27.2 is unverified).
- **Bundle ID** `com.ethan.stickermine`. `LSUIElement` = true (menu bar app, no Dock icon).
- **No third-party dependencies.** No App Sandbox, no entitlements file. Hardened runtime, Developer ID signed by certificate hash.

### Xcode project settings

Xcode 27 beta's new-project template defaults contradict this spec, so these are set explicitly:

- **Project format "Xcode 16.0"** (objectVersion 77, the oldest that supports folder-synchronized groups), never a 26.3 or 27.0 format, so Xcode 26.6 on CI can open it. Two synchronized root groups: `Stickermine/` and `StickermineTests/`.
- `ENABLE_APP_SANDBOX = NO`, no `CODE_SIGN_ENTITLEMENTS`, `CODE_SIGNING_ALLOWED = NO` for command-line builds (signing happens in `build.sh`).
- `MACOSX_DEPLOYMENT_TARGET = 26.0` at project level.
- **Info.plist:** `INFOPLIST_FILE = Info.plist`, `GENERATE_INFOPLIST_FILE = NO`, and no `MARKETING_VERSION`, `CURRENT_PROJECT_VERSION` or `INFOPLIST_KEY_*` settings at any level. These would silently override the root plist, so every release would ship as 1.0 and the updater would offer it forever. `PRODUCT_NAME = Stickermine`, `PRODUCT_BUNDLE_IDENTIFIER = com.ethan.stickermine`, matching the plist's literal values. The root `Info.plist` holds literal strings (never `$(…)` variables): `CFBundleName`/`CFBundleDisplayName`/`CFBundleExecutable` Stickermine, `CFBundleIdentifier`, `CFBundlePackageType` APPL, `CFBundleShortVersionString` and `CFBundleVersion` (a dev placeholder kept ahead of the newest release tag; CI stamps the real value from the tag), `LSMinimumSystemVersion` 26.0, `LSUIElement` true, `NSHumanReadableCopyright` "© 2026 Ethan Darling (grokcodile) — MIT License". No usage-description keys (none exists for Screen Recording).
- **Swift settings:** the plan picks the language mode and sets `SWIFT_VERSION`, `SWIFT_DEFAULT_ACTOR_ISOLATION` and `SWIFT_APPROACHABLE_CONCURRENCY` explicitly to match it. The template's MainActor default changes how the Carbon/CG C callbacks and the background render tasks compile.
- **A shared scheme** `Stickermine` is committed (`xcshareddata/xcschemes/Stickermine.xcscheme`), with `StickermineTests` in its Test action.

### Repo layout

```
stickermine/
├── Stickermine.xcodeproj          format "Xcode 16.0", folder-synchronized groups, shared scheme
├── Stickermine/                   app sources and Assets.xcassets (see section 4)
├── StickermineTests/              Swift Testing unit tests
├── Info.plist                     used directly by the app target (INFOPLIST_FILE)
├── build.sh                       xcodebuild (unsigned) + strip + pinned-hash codesign
├── install.sh                     Pullcord's, renamed
├── .github/workflows/release.yml  Pullcord's, with APP/CASK changed
├── docs/                          GitHub Pages website
├── design/                        source assets, brief, specs, icon script (committed)
├── LICENSE  README.md  PRIVACY.md  TERMS.md  CONTACT.md
└── .gitignore
```

- **LICENSE:** MIT, "Copyright (c) 2026 Ethan (grokcodile)", as in Pullcord.
- **README.md:** a user guide like the siblings' (pitch, Features, Install, Requirements, First run, How it works, Uninstall, License, Author). It states the design philosophy, "The app getting smaller as macOS gets better is a success, not a regression." It explains the Screen Recording permission and the periodic system alert (section 5). It never gives a download or installed size, and never says "no menu bar item".
- **PRIVACY.md:** adapts Pullcord's (short version; the app; what the permission is for; on-device processing; the website; third-party services; changes; contact). See section 14.
- **TERMS.md:** adapts Pullcord's (License, No warranty, Privacy, Updates, Payments via Ko-fi, What it depends on: `screencapture`, Vision subject lifting, window levels; Not affiliated with Apple, Changes, Contact).
- **CONTACT.md:** how to reach Ethan (email address to be decided, section 20) and the GitHub issues link.
- **.gitignore:** the siblings' union plus Xcode user state: `.DS_Store`, `build/`, `dist/`, `CLAUDE.md`, `junk/`, `.claude/`, `*.p8`, `*.p12`, `*.o`, `xcuserdata/`, `*.xcuserstate`. `CLAUDE.md` stays local-only as in the siblings; `junk/` is the drawer for anything that isn't part of the project.

## 4. Architecture

**Window ownership:** `StickermineApp` (`@main`) has only `Settings { EmptyView() }` as its body, so SwiftUI opens no window on its own. Home, the picker, placement, the toolbar pill, the permission panel, the support ask and the HUD are `NSWindow`/`NSPanel` instances owned by AppKit controllers, hosting SwiftUI content through `NSHostingView`. `AppDelegate` (via `@NSApplicationDelegateAdaptor`) owns the controllers.

| Folder | Units | Responsibility |
|---|---|---|
| `App/` | `StickermineApp`, `AppDelegate`, `StatusItemController`, `HotkeyCenter`, `SingleInstance`, `LoginItem`, `SessionCoordinator` | Lifecycle, reopen handling, the global shortcut (Carbon `RegisterEventHotKey`), the menu bar icon, the one-copy guard, launch at login, the one-session-at-a-time rule |
| `Capture/` | `CaptureService`, `CutoutEngine`, `StyleRenderer`, `PuffyKernel` | Run `screencapture`; Vision subject masks; render a styled bitmap for (cutout, style, transform, pixel size) |
| `Picker/` | `PickerPanel`, `PlacementSession` | The post-capture panel; the sticker following the cursor until a click places it |
| `Stickers/` | `StickerPanel`, `StickerView`, `StickerEditor`, `ToolbarPill`, `StickerManager` | One window per placed sticker; the active state; owning all windows and applying layouts |
| `Model/` | `Library`, `LibraryStore`, `DisplayRegistry`, `LayoutResolver` | The data model, load/save, display identity, the pose-for-current-size rule |
| `Home/` | `HomeWindowController`, `HistoryGrid`, `SettingsSection`, `ShortcutRecorder`, `AboutPopover`, `UpdateStrip` | The Home window |
| `Onboarding/` | `TutorialStickers`, `PermissionPanel`, `SupportAsk` | First run, the Screen Recording explainer, the one-time support ask |
| `Updater/` | `Updater` | GitHub releases + Homebrew self-update, ported from Pullcord |
| `UI/` | `HUD`, `PanelPolicy`, shared small views | Short status messages; the shared rules every panel follows |

**Testability:** pure logic (`LayoutResolver`, `DisplayRegistry` filtering and fingerprinting, `LibraryStore` decoding and repair, style parameter scaling, click-to-subject mapping, shortcut storage, capture outcome classification) has no AppKit dependencies. `LibraryStore` takes its root directory and a `UserDefaults` instance as parameters.

**Panel policy (every `NSPanel` the app creates):** set `isReleasedWhenClosed = false` and an explicit `hidesOnDeactivate` (a plain `NSPanel` defaults to true and is then invisible and unclickable in an accessory app that isn't active); never touch `isFloatingPanel` (setting it rewrites the level); set `level` last.

## 5. Capture

1. **Trigger:** the global shortcut (default ⌃⌥⌘S, keyCode 1, Carbon mask `controlKey|optionKey|cmdKey`), a left-click on the menu bar icon, the menu's New Sticker, or Home's New Sticker button. The shortcut needs no Accessibility or Input Monitoring permission.
2. **One session at a time** (`SessionCoordinator`). A session runs from the trigger until the sticker is placed or cancelled: permission check, capture, cutout, picker, placement. Re-placing a sticker from history starts a session at the picker. While a session is active, every trigger (shortcut, menu bar click, New Sticker, history-grid clicks) is ignored, the menu's New Sticker item is disabled, and double-clicks on stickers don't enter editing. Starting a session first ends any sticker's editing, discarding an in-progress gesture. A capture started from Home orders Home out before `screencapture` runs; Home isn't reshown afterwards. The menu's Quit cancels the session, then quits.
3. **Permission gate:** call `CGPreflightScreenCaptureAccess()`. If false, don't start `screencapture`; show the permission panel (section 14). Never ask at launch.
4. **Wait for the modifiers to be released** (poll `NSEvent.modifierFlags`, up to about 1 s). If Control is still held at mouse-up, `screencapture -i` sends the image to the clipboard and writes no file.
5. **Warm up in the background:** start a throwaway foreground-mask request (loads the Vision model, about 100 ms cold) and compile the Puffy kernel if it isn't compiled yet. Record `NSPasteboard.general.changeCount`.
6. **Run** `/usr/sbin/screencapture -i -J selection -o -x -t png <NSTemporaryDirectory()/stickermine-<UUID>.png>` with `Process`. Space still toggles window capture; `-o` drops the window shadow. Never pass `-c`, `-u`, `-U`, `-p` or `-r`. Capture stdout and stderr for logging.
7. **Outcome, first match wins:**
   1. The file exists and is non-empty: success.
   2. No file and the pasteboard `changeCount` changed: HUD "Let go of Control before releasing the mouse".
   3. No file and exit status 1: HUD "Couldn't start a capture" (another capture is up, or an MDM restriction).
   4. Otherwise: a cancel (Esc, a click without a drag, a selection under 10 pt). Show nothing; the session ends.
8. **Load** with ImageIO, keeping the embedded ICC profile. The sticker's natural point size is pixels × 72 / DPI (from `kCGImagePropertyDPIWidth`), so mixed 1×/2× setups are correct. Delete the temp file right after loading.
9. **Expected system UI:** macOS shows an alert that Stickermine "is requesting to bypass the system private window picker" on the first capture and periodically after. It appears just after the capture is delivered, so it can land on top of the picker; the picker must survive it (section 7). The app can't suppress it; onboarding and the README mention it. Each capture may also list Stickermine in Control Center's screen-recording indicator.
10. **Termination and leftovers:** on `applicationWillTerminate`, the menu's Quit, and before the updater spawns its helper, terminate a running `screencapture` process, delete its temp file and flush the pending library save. At launch, delete any leftover `stickermine-*.png` in `NSTemporaryDirectory()`.

## 6. Cutout

Uses the Swift Vision API `GenerateForegroundInstanceMaskRequest` (macOS 15+, on the ANE or GPU; never force the CPU, which fails).

1. **Pass 1** on the full capture with `ImageRequestHandler(cgImage).perform(request)`. Treat `nil`, an empty `allInstances`, and any thrown error not caused by the app (it throws `requestCancelled` on flat colours) as "no subject". About 15 ms warm. Keep the handler alive while the picker is open; release the handler and observations when the picker closes (about 130 MB transient peak per capture).
2. **Subjects for the picker:** for each instance `i`, `generateMask(for: [i])` returns a 512×512 `OneComponent32Float` coverage mask (rows top-down, whatever the image's aspect ratio). Use it for highlight overlays and for mapping a click: lock the buffer, read the value at `row = Int(vTopLeft × 512)`, `col = Int(u × 512)` using `CVPixelBufferGetBytesPerRow`; the subject is the instance whose value is > 0.5, none means background. Don't use `instanceAtPoint`, `pixel(at:)` or `allInstancesMask` (their coordinate behaviour contradicts the documentation, and `allInstancesMask`'s pixel buffer is macOS 27-only).
3. **Never pass instance 0** (it selects the background) and never pass an empty set (empty mask / throws). "Whole image" uses the original image directly.
4. **Whenever the subject selection changes** (debounced about 100 ms): if the selected subjects' combined bounding box is under about 60% of the capture's long side, run **pass 2** on that box plus an 8% margin and use the union of pass-2 subjects intersected with a slightly dilated pass-1 mask. This sharpens edges and removes the light halo (about 15 ms). The picker's previews always render from this refined cutout, so a preview is exactly what gets placed.
5. **Build the cutout** with Core Image: `CIBlendWithMask(original, background: empty, mask: scaledMask)`, where the mask comes from `generateScaledMask(for:scaledToImageFrom:)` and is wrapped with `CIImage(cvPixelBuffer:options: [.colorSpace: NSNull()])` (otherwise Core Image linearises it and the edge shifts). Don't use `generateMaskedImage`: its buffer has no colour space (Display P3 colours shift) and no crop offset.
6. **Fill holes** (when on): flood-fill the outside of the mask where alpha < 0.5, then set alpha to 1 everywhere not within 2–3 px of the outside. This closes white-on-white gaps such as toggle knobs and calculator keys.
7. **Whole image:** the original capture, keeping its alpha (window captures have transparent corners), with corners rounded at about 4% of the short side.
8. **Master image:** crop to the alpha bounding box plus 2 px and save as PNG in the capture's colour space, with DPI metadata (`kCGImagePropertyDPIWidth`/`Height` = 72 × pixels-per-point) so recovery can restore the natural size. Record the pixel size and pixels-per-point in the library too.

**What to expect:** photos, objects, app icons and single controls cut out well. Full app windows, text, headings, wordmarks and landscapes usually give no subject; a logo with a wordmark keeps only the icon; busy captures with many objects can give no subject. Vision's confidence value is not a usable quality signal (0.24 for a perfect app icon).

## 7. Picker panel and placement

### Picker panel

A floating SwiftUI panel near the cursor (falls back to the centre of the cursor's display). It activates Stickermine and becomes key, so Esc and 1–4 arrive.

- The capture, scaled to fit, with each subject highlighted.
- **Selection rules:** when subjects are found, all of them start selected and Whole image starts off. Whole image and subject selection are mutually exclusive. Turning Whole image on deselects every subject. Clicking a subject while Whole image is on turns Whole image off and selects only that subject. Clicking a selected subject deselects it; deselecting the last subject turns Whole image on. With no subjects found, Whole image is on and locked.
- **Fill holes** toggle (disabled while Whole image is on). Until the user touches it, each style preview renders with its own default (on for Puffy and Outline, off for Shadow and None), the toggle shows the default of the hovered preview (or "Auto" when none is hovered), and confirming a style uses that style's default. Once touched, the toggle's value applies to all four previews and to the result.
- **Four live style previews** in the order Puffy, Outline, Shadow, None, rendered from the refined cutout (section 6.4).
- **Confirm:** clicking a preview or pressing 1–4 saves the master PNG, creates the history entry (`lastStyle` = the chosen style) and starts placement.
- **Cancel:** only Esc or the panel's own × button. Losing key status or a click outside never cancels, because the system alert (section 5.9) appears at this moment and clicking it must not discard the capture. Cancelling saves nothing.
- **Re-placing from history** opens the same panel with only the style row; the sticker's `lastStyle` preview is highlighted.

### Placement session

- A borderless panel at the floating level shows the styled sticker centred on the cursor. It sets an explicit `ignoresMouseEvents = false` (allowed for this transient panel), so its whole rectangle receives clicks even over transparent pixels, and it can become key so Esc arrives.
- It follows the cursor using both a local and a global `.mouseMoved`/`.leftMouseDragged` monitor (global monitors don't see events sent to the app itself), or by polling `NSEvent.mouseLocation` once per display frame.
- **Every new placement**, fresh or re-placed, starts at rotation 0, unflipped, Float on top off, in the chosen style, at its natural point size (pixel width / pixels-per-point), scaled down to fit within half the width and height of the display currently under the cursor (recomputed when the cursor moves to another display).
- **A mouse-down on the placement panel** places it on the display under the cursor, on top of that display's z-order. Clicks on other windows (such as the system alert) are ignored. **Esc** or a right-click cancels; the sticker stays in history.
- When the picker or placement ends (placed or cancelled), focus returns to the app that was frontmost before the session.

## 8. Styles

`StyleRenderer` produces one bitmap for (master cutout, style, flip, rotation, scale, backing scale factor) on a background task with one shared Metal-backed `CIContext` (plus an RGBAf context for Puffy). Create a `CIFilter` per render (not thread-safe); call `clearCaches()` after a bake. All style parameters scale with the sticker's pixel size (points × scale × backing scale), using roughly these values per 800 px of sticker:

| Style | Recipe |
|---|---|
| **Puffy** | Rim as in Outline; dome radius R = clamp(0.5 × max inscribed radius, 6, 300), computed once at master resolution and scaled linearly with size; height = mean of Gaussian blurs of the rim mask at σ = R/3, 2R/3, R, averaged explicitly inside the kernel (not through `CIAdditionCompositing`, which breaks if an intermediate is 8-bit); a runtime-compiled Metal Core Image kernel (`CIKernel.kernels(withMetalString:)`) computes normals and applies Lambert + Blinn-Phong lighting (ambient 0.35, diffuse 0.65, shininess 40, specular 0.55, light from the top-left at 135°, heightPx = 0.9R); plus the drop shadow. The kernel source is a Swift string literal in `PuffyKernel.swift`: no `.metal` files go in the target, because compiling them needs the separately downloaded Metal Toolchain. Compile once at launch off the main thread. If compilation throws, fall back to a built-in-filter Puffy (Sobel gradients + Lambert colour matrix + screen-blended specular). |
| **Outline** | A white rim from a signed distance field: `CIFilter.signedDistanceGradientFromRedMask()` (macOS 26+) on a white silhouette, coverage = clamp(r + 0.5 − red × D) with D = r + 4, r ≈ 12 px. Cutout over rim, plus the drop shadow. Optional SDF "closing" (grow by r + s, shrink by s, s ≈ 10 px) for a smoother die-cut line. |
| **Shadow** | None, plus the drop shadow. |
| **None** | The cutout with its edge choked to remove halo: blur σ ≈ 0.5 × (source long side / 512), then ramp alpha around 0.7 (width 0.35). |

**The drop shadow is a `CALayer` shadow, not baked pixels.** A blurred shadow baked into the bitmap would catch clicks across its whole faint tail; a layer shadow doesn't. Layer shadow: black, opacity about 0.35, radius about 10 px per 800, offset about 0.6 × radius downward in screen space. To avoid recomputing it every frame, either set `shouldRasterize = true` with `rasterizationScale = window.backingScaleFactor` (updated on backing changes; the default 1.0 blurs Retina content) or leave it unrasterized (the content is static between gestures). Baked bitmaps also clamp alpha below about 0.02 to 0, so faint fringes don't catch clicks.

Costs measured on M5: Outline 1.4–8.5 ms, Puffy 5–55 ms (up to about 1800 px), plus about 300 ms for the first-ever kernel compile.

## 9. Sticker windows

One `StickerPanel: NSPanel` per placed sticker, created by a single `makePanel` function that holds every window-policy constant (and follows the panel policy in section 4):

- Style mask `[.borderless, .nonactivatingPanel]`, backing `.buffered`.
- **Level:** `NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)`. Below this, Finder's desktop window catches every click, so the sticker could never be double-clicked. Above it is every app window. At exactly this level, ScreenCaptureKit window pickers that exclude desktop windows also leave stickers out.
- **Float on top:** `.floating`.
- **Collection behaviour:** `[.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenNone]`. On every desktop Space, not on full-screen Spaces (observed behaviour, not a documented contract), unaffected by Mission Control (documented for `.stationary`). Behaviour during Show Desktop and the click-wallpaper reveal is expected to be the same but is a spike item.
- `isOpaque = false`, `backgroundColor = .clear`, `hasShadow = false`, `isReleasedWhenClosed = false`, `hidesOnDeactivate = false`, `canHide = false`, `isExcludedFromWindowsMenu = true`, `animationBehavior = .none`, `isRestorable = false`.
- `sharingType = .none` when "Hide stickers from screen sharing and screenshots" is on (default on); `.readOnly` when off. Changes apply live.
- **Never write `ignoresMouseEvents`.** Left untouched, the window server hit-tests by the rendered alpha: alpha > 0 receives the click, alpha 0 passes through. Writing it, even `false`, switches the window to rectangle hit-testing permanently.
- **Fallback click-through mode** (hidden setting `clickThroughFallback`, section 12; read at launch): every sticker gets an explicit `ignoresMouseEvents = true`, and the sticker under the cursor is switched to `false` while the cursor is over its opaque pixels (global mouse-moved monitor plus each sticker's stored alpha mask). It exists because alpha hit-testing has regressed in past releases (a 26.3 release candidate). A change takes effect on relaunch, since live windows can't return to alpha hit-testing.
- **Frame:** the bitmap's bounding box plus a symmetric shadow margin of ceil(3 × shadow radius) + |shadow offset| on every side, backing-aligned (zero margin for None). The pose centre is the bitmap's centre, which is also the window's centre. Clamping and display ownership use the sticker rect, never the padded window rect. The margin is transparent and the layer shadow isn't hittable, so it doesn't affect click-through.
- **Content:** a layer-hosting view (`view.layer = CALayer()` before `wantsLayer = true`) with one content sublayer that we own; transforms go on that sublayer, never on the view's own layer. Contents are preferably IOSurface-backed (about 1× the bitmap's bytes instead of about 2× for a `CGImage`): render with `CIContext.render(_:to:bounds:colorSpace:)` in the capture's colour space and tag the surface with `kIOSurfaceColorSpace`. Fall back to `CGImage` contents if the spike shows a colour shift or broken alpha hit-testing with IOSurface contents.
- **Memory:** the bitmap is rendered at the on-screen pixel size, capped at 2048 px on the long side (above that, the layer scales the bitmap up). On removal, set contents to nil before `orderOut` and close (windows closed from timers or notifications otherwise stay alive until the next event).
- **Stale windows:** after wake, screen unlock (`com.apple.screenIsUnlocked`) or a display change, check that panels are still drawing; if the spike shows the Key54 stale-backing problem, rebuild all panels from the model on those events (ending any editing first, section 10).

**Accepted trade-offs:** stickers draw over desktop icons beneath them and catch files dropped onto their opaque pixels. They don't slide with the wallpaper during a Space switch.

## 10. Editing

- **Inactive** stickers ignore single clicks (their opaque pixels absorb them).
- **Double-click** (`clickCount == 2`, outside a session) enters editing. `StickerView.acceptsFirstMouse` returns true; `StickerPanel.canBecomeKey` returns true while editing. Make the panel key, move the placement to the end of its display's list (the front; this is saved), and activate the app so keys and trackpad gestures arrive. Gesture delivery to a key panel of an active accessory app is expected but unverified; the corner knob is the guaranteed path.
- **While editing:**
  - A subtle outline, and a full-bounds hit pad (alpha 1/255) covering the padded frame so the whole box and the knob can be grabbed.
  - **Drag** to move (also across displays; section 11).
  - **Corner knob** (bottom-right): one drag scales and rotates around the centre. Shift snaps rotation to 15°.
  - **Trackpad pinch and rotate.**
  - **Scale limits:** the sticker's long side stays between 48 pt and its display's long side; the knob and pinch stop at those limits.
  - **Toolbar pill:** a child panel that never becomes key (keep the borderless default `canBecomeKey == false`; controls accept first mouse), so using it never ends editing. It holds **Style** (the four previews expand inline inside the pill, never in a popover or menu), **Flip** (horizontal), **Float on top**, **Remove**. It sits centred under the sticker with an 8 pt gap, moves above it when there's no room on the sticker's display, follows the sticker during drags, and uses the sticker's level and collection behaviour.
  - **Delete** removes. **Esc**, or clicking elsewhere (the panel resigns key), ends editing and returns focus to the previously frontmost app.
- **During a gesture:** at gesture start, grow the window to a square of side = (the bitmap's diagonal × scale headroom) + the shadow margin. Apply an affine transform to the content sublayer inside `CATransaction.setDisableActions(true)`. Don't resize the window per event.
- **At gesture end:** re-render with rotation, flip and scale baked in (so the shadow points down and the Puffy light stays top-left in screen space), shrink the window to the padded bounding box (section 9) around the unchanged centre, reset the sublayer transform, and save the new pose.
- **Editing ending mid-gesture** (Esc, resigning key, the panel being ordered out by a display change, sleep, lock, a session starting, or a panel rebuild): discard the gesture. Reset the sublayer transform, restore the frame from the last saved pose, remove the hit pad and pill, and write nothing.
- **Remove** deletes the placement only; the sticker stays in history. Tutorial stickers are deleted outright (section 13).

## 11. Displays

- **Identity:** the uppercased string from `CGDisplayCreateUUIDFromDisplayID(screen.cgDirectDisplayID)` (`NSScreen.cgDirectDisplayID` is new in the macOS 26 SDK). Guard against `nil` and `kCGNullDirectDisplay` first: a 0 ID silently returns the main display's UUID. Never persist display IDs; keep an in-memory ID → UUID map rebuilt on each change. CG functions return −1 / `0xFFFFFFFF` for a vanished ID, so never test them with `!= 0`.
- **Ignore:** the ghost display (vendor `0x756E6B6E` 'unkn' and model `0x76697274` 'virt'), and mirror secondaries (`CGDisplayMirrorsDisplay(id) != kCGNullDirectDisplay`). If no real display remains, change nothing.
- **"Main display"** means `NSScreen.screens[0]` (the one with the menu bar) everywhere in this spec, never `NSScreen.main`.
- **Fingerprint fallback:** each display record stores vendor, model, serial and built-in. Only when an unknown UUID appears whose serial is nonzero and not `0x01010101`, exactly one disconnected record has the same vendor + model + serial + built-in, and no connected display shares that fingerprint: show that record's placements on the new display in memory. The re-key is saved only on the next user edit on that display. Otherwise the display starts empty.
- **Change handling:** observe `NSApplication.didChangeScreenParametersNotification` (not the macOS 27-only typed message), `NSWorkspace.didWakeNotification` and `screensDidWakeNotification` (re-check about 1.5 s after wake), and register a `CGDisplayRegisterReconfigurationCallback`. Every event restarts one 450 ms timer. When it fires, **always** re-apply visibility and frames from the model to every panel: order out panels whose display UUID is absent, order in panels whose display is present and set their frame (only if different). Use a snapshot diff (`[uuid: (frame, backingScaleFactor, mirror state)]`) only to skip the expensive work, pose re-resolution and re-rendering. In the CG callback, ignore calls whose flags include `kCGDisplayBeginConfigurationFlag` (that pass fires for every online display and says nothing about which one is leaving); act only on after-pass calls with `kCGDisplayRemoveFlag`, looking the ID up in the in-memory map and ordering out that UUID's panels immediately.
- **Hard rule: only user actions write layout data:** place, drag end, scale or rotate end, bring to front (entering editing), Style, Flip, Float on top, Remove, delete from history. Display events, `windowDidMove` and `windowDidChangeScreen` never write. Clamping happens when drawing and is saved only when it results from a user gesture. **Exceptions**, none of which change poses, z-order or style: `lastSeen` and `name` refreshed when a recorded display connects; launch repair; first-run tutorial placement; a fingerprint re-key saved on the next user edit.
- **Positions:** relative to `NSScreen.frame` (not `visibleFrame`), so the Dock and menu bar never move stickers. When drawing, clamp so the sticker stays inside its display's frame (with "Displays have separate Spaces" on, a window can't straddle displays). At drag or gesture end and when deriving a pose for a new size, also clamp so the sticker's centre lies inside `visibleFrame` inset by 8 pt, so a sticker never ends up unreachable under the menu bar or Dock.
- **Disconnected display:** order its panels out and keep them (reuse rather than close and recreate); order them in again when it returns. No indicator.
- **New display:** shows nothing; no record is created until the first placement on it.
- **Mirroring:** the mirror set's primary shows its own layout (using the closest-size rule if mirroring changed its size); poses derived only while mirrored aren't saved unless the user edits them.
- **Dragging across displays:** when a drag ends with the sticker's centre on another display (`NSMouseInRect(p, frame, false)`, else the nearest screen), it counts as a placement on that display: move the placement to that display's list (creating its record if needed), on top, with `poses = [B: pose]` and scale chosen so the sticker's on-screen point size is unchanged.
- **Backing scale changes:** re-render the bitmap (`windowDidChangeBackingProperties`); the scale factor isn't part of the layout key.
- **Known limits:** two identical monitors with identical EDIDs may swap layouts after a reconnect. Resetting the system's display preferences gives externals new UUIDs; the fingerprint fallback recovers some cases. The built-in display's UUID is the same on every MacBook, so a migrated Application Support folder carries the built-in layout over (resolved by closest size).

### Layout resolution (`LayoutResolver`)

- A display's point size key is `"\(Int(w))x\(Int(h))"` from `NSScreen.frame.size`.
- A placement stores `poses[sizeKey] = { x, y, scale }`: the normalized centre (0–1 of the frame, Cocoa y-up) and a multiplier on the sticker's natural point size.
- **To draw at size B:** use `poses[B]` if present. Otherwise pick the stored size A with the same orientation first, then the smallest |ln(wB/wA)| + |ln(hB/hA)|; on a tie (difference < 1e-9), prefer the larger area wA × hA, then the lexicographically smaller key. Exact ties happen (for example, 1920x1080 resolved from {2304x1296, 1600x900}), and dictionary order changes between launches, so the tie-break keeps stickers from jumping. Keep x and y; multiply scale by min(wB/wA, hB/hA).
- **Writes:** placing sets `poses = [B: pose]`. Moving or scaling writes only `poses[B]` (creating it if the pose was borrowed). Rotation, style, flip and float on top are shared across sizes.

## 12. Data model and storage

**Location:** `~/Library/Application Support/com.ethan.stickermine/` (created with `FileManager.url(for: .applicationSupportDirectory, …, create: true)`), which the cask's `zap` removes.

- `stickers/<sticker-uuid>.png`: the master cutout (with DPI metadata, section 6.8).
- `library.json`:

```json
{
  "version": 1,
  "stickers": [
    { "id": "UUID", "created": "ISO-8601", "pixelWidth": 840, "pixelHeight": 620,
      "pixelsPerPoint": 2.0, "lastStyle": "outline", "tutorial": false }
  ],
  "displays": {
    "25A19A46-…": {
      "name": "LG UltraFine", "vendor": 7789, "model": 23305, "serial": 0, "builtin": false,
      "lastSeen": "ISO-8601",
      "placements": [
        { "id": "UUID", "sticker": "UUID", "style": "puffy", "flipped": false, "onTop": false,
          "rotation": 0.0, "poses": { "1920x1080": { "x": 0.81, "y": 0.22, "scale": 1.0 } } }
      ]
    }
  }
}
```

Placement array order is the z-order, back to front. `lastStyle` is set when a sticker is first confirmed and whenever any of its placements is restyled; it only drives the highlight in the style-only picker.

**Rules**

- **Decoding:** decode `{ version }` first. If it is newer than this build supports, show the stored placements and write nothing (no PNGs, no index); capture, editing and history changes are disabled, and Home shows "This library was saved by a newer Stickermine. Update to make changes." If the file fails to decode, rename it to `library.corrupt-<date>.json` and rebuild history from the PNGs (all placements are lost; accepted). Every field added after v1 is optional (or decoded with `decodeIfPresent ?? default`). Enums are stored as strings and mapped leniently (unknown style → `puffy`). Size keys are strings.
- **Writes:** atomic (`Data.write(to:options: .atomic)`). Write the PNG before the index; for deletes, remove the PNG then save the index. Save 0.5 s after the last change (never per drag event) and flush in `applicationWillTerminate` and before the updater's helper runs. SIGTERM skips that hook, so nothing may depend on it. Encode and write the JSON on the main actor; write PNGs on a background queue and commit to the index on main.
- **Launch repair:** drop index entries whose PNG is missing; adopt stray PNGs back into history. Adopted or rebuilt entries take pixels-per-point from the PNG's DPI (2.0 if absent), pixel size from the image, `created` from the file's creation date, `lastStyle` = puffy, and no placements. A PNG whose UUID is one of the fixed tutorial UUIDs (section 13) is adopted with `tutorial: true`.
- **Delete from history:** cancels any open session for that sticker, ends editing of any of its placements (discarding a gesture), removes the sticker, its PNG and every placement on every display (including disconnected ones). The confirmation states the number of placements. Every render completion checks that its placement still exists before committing. Remove does the same for its one placement.
- **Thumbnails** for the history grid: `CGImageSourceCreateThumbnailAtIndex` (max 256 px) into an in-memory `NSCache`.
- **Settings** in `UserDefaults`: `captureShortcut` (`{k, m}`), `showMenuBarIcon` (true), `launchAtLogin` (true), `hideFromSharing` (true), `didFirstRun`, `didRequestScreenCapture`, `ownPlacementsCount`, `supportAskShown`, and the hidden `clickThroughFallback` (false; not shown in Home; set with `defaults write com.ethan.stickermine clickThroughFallback -bool true`; read at launch).

## 13. App shell

### Menu bar icon (`StatusItemController`)

- `NSStatusItem` showing the glyph from `design/menubar-glyph.svg`, stored in the asset catalog as `MenuBarGlyph.imageset` (template rendering intent, preserve vector data), loaded with `NSImage(named:)` and sized to 18×18 pt (the SVG reports 200×200 pt). It is drawn white or black to match the menu bar. SwiftUI's `MenuBarExtra` isn't used because it can't run an action on a plain click.
- **Left-click:** start a capture. **Right-click or Control-click:** a menu with New Sticker (showing the shortcut; disabled during a session), Open Stickermine…, Quit.
- **Hideable** in settings (`showMenuBarIcon`). Without it the app works through the shortcut; opening the app again brings up Home.

### Lifecycle

- **Single instance**, in `applicationWillFinishLaunching` before any window can appear: if another process with this bundle ID is running, the earlier launch wins. A user launch posts the distributed notification `com.ethan.stickermine.showHome` so the running copy opens Home, then exits. Ported from Pullcord's `yieldToRunningInstance`.
- **Launch at login:** `SMAppService.mainApp`, on by default (stickers only exist while the app runs). Register when on and `status != .enabled`; unregister when turned off. If `status == .requiresApproval`, the setting shows that and opens `SMAppService.openSystemSettingsLoginItems()`. Detect a login launch from the `kAEOpenApplication` Apple event's `keyAELaunchedAsLogInItem`, read inside `applicationDidFinishLaunching`.
- **What each launch does:** every launch restores stickers. **A launch that isn't a login launch** (double-clicking the app, Spotlight, Finder) also opens Home; on first run it also places the tutorial stickers. **A login launch** opens no windows, except that if the update check about 6 s later finds an update, Home opens to show the update strip (Pullcord's behaviour).
- **Reopen** (`applicationShouldHandleReopen`) and the distributed notification open Home.

### Home window (`HomeWindowController`)

- **History grid:** every non-tutorial sticker, newest first. Click → picker panel (style row only) → placement. Right-click → Delete from History (with confirmation). A **New Sticker** button at the top.
- **Settings section:**
  - **Capture shortcut** recorder. Every chord must include ⌘ or ⌃ (F-keys excepted). Bare Esc cancels recording, bare Delete clears. Hotkeys are unregistered while recording; recording is cancelled when Home closes or resigns key. Warn when the chord matches an enabled system shortcut (`CopySymbolicHotKeys()`); clashes with other apps can't be detected (Carbon hotkeys are non-exclusive and register successfully anyway). Help mentions that VoiceOver users may want to rebind (VO-⌘-S).
  - **Show menu bar icon.**
  - **Launch at login.**
  - **Hide stickers from screen sharing and screenshots** (described as best-effort; also hides them from your own screenshots).
  - **Screen Recording** status with a button to fix it. Re-checked when Home becomes key.
- **Footer:** an ⓘ About popover (icon, name, version line that doubles as Check for Updates, Website, Star on GitHub, Buy me a coffee → `https://ko-fi.com/grokcodile`, Report a Bug → GitHub issues) and **Quit**.
- **Update strip:** appears only when an update is available or failed.

### Updater

Ported from Pullcord (not Key54, which still has the name-based kill bug). It polls `api.github.com/repos/grokcodile/stickermine/releases/latest` only on Home open and once about 6 s after a login launch, and offers a release only if its assets include `Stickermine.dmg`. If installed by the Homebrew cask (Caskroom entry and running from `/Applications/Stickermine.app`), it upgrades through a detached helper that kills by PID, runs `brew upgrade --cask`, clears quarantine and relaunches; otherwise it downloads the DMG to `~/Downloads` (HTTP 200 only) and opens it. 180 s watchdog. Before spawning the helper, it runs the termination cleanup in section 5.10. Keep `Info.plist`'s version ahead of the newest tag.

### First run

Runs on a user launch when `didFirstRun` is false and `library.json` has no stickers. `TutorialStickers` renders three masters once, saves them as ordinary `stickers/<uuid>.png` entries under three fixed UUIDs defined in code, with `tutorial: true`, places them, and sets `didFirstRun` once the index is saved. They are never re-created after removal.

1. "Press ⌃⌥⌘S to make a sticker", rendered with the current shortcut (or "Click the menu bar icon to make a sticker" when none is set). When `captureShortcut` changes and this sticker still exists, its master is re-rendered in place and its placements re-baked.
2. "Double-click me to move, resize or remove."
3. Maple (`design/dog.png`, copied into the asset catalog), with the website's pink speech bubble composited beside her mouth: `#FF4F81` fill, 8 pt white border, white SF Pro Rounded text "Make your desktop make you smile!".

The text cards are SF Pro Rounded on a sticker-shaped card in the brand colours, with their own white border. All three use the **Shadow** style (their white borders are already in the image, so Outline or Puffy would add a second rim). Maple's master is about 315 pt wide like on the website. Automatic placement scales each tutorial sticker to fit within a third of the main display's height and places them on the main display clear of Home's initial (centred) frame: the text cards stacked top-right, Maple bottom-right. Exact positions are set in the plan.

Tutorial stickers don't appear in the history grid, don't count toward the support ask, and are deleted outright (PNG and entry) when removed.

### Support ask

`ownPlacementsCount` goes up by one on each placement click of a non-tutorial sticker, fresh or re-placed from history; cross-display drags don't count and nothing decrements it. The first time it is ≥ 5 and `supportAskShown` is false, show a small sticker-styled card near the menu bar icon (top-right of the main display if the icon is hidden), without activating the app or taking focus from the frontmost app: "Enjoying Stickermine? It's free and open source. If it made you smile, you can buy me a coffee." with **☕️ Buy me a coffee** (opens Ko-fi) and **Maybe later**. `supportAskShown` is set when the card appears; any dismissal (either button, Esc, clicking elsewhere, quitting) counts as declined. It never appears again.

## 14. Permissions and privacy

- **Screen Recording** is the only permission. TCC checks the responsible process (Stickermine), not `screencapture`. No `Info.plist` usage string exists for it.
- **Permission panel** (`PermissionPanel`, shown instead of a capture when preflight is false): a standalone floating panel centred on the cursor's display (not a sheet; there is usually no Home window). It explains that macOS requires the permission for the screenshot crosshair, that everything stays on the Mac, and that macOS will periodically confirm it.
  - The first time (`didRequestScreenCapture` false), its button calls `CGRequestScreenCaptureAccess()` and sets the flag (preflight can't tell "denied" from "never asked").
  - After that, it offers **Open System Settings** (Privacy & Security › Screen & System Audio Recording).
  - If preflight is still false when the user comes back (the panel or Home becomes key), it also offers **Relaunch Stickermine** (a detached `open` of the app after quitting), in case the in-process preflight result is stale. Pullcord relies on it updating live, but that is unverified for this app.
- **Dev builds must be Developer-ID signed** (the default in `build.sh`) and launched with `open` (via `install.sh`), so the grant attaches to Stickermine's designated requirement and survives rebuilds.
- **Privacy (PRIVACY.md):** no account, no telemetry, no network except the update check. Captures are processed on-device and the temporary screenshot is deleted. Sticker images and layouts stay in Application Support. Stickers are hidden from screen sharing by default, best-effort. Third parties: GitHub (releases, update check, Pages), Homebrew, Ko-fi.

## 15. Website (`docs/`)

- Port `design/index.html` to `docs/index.html` as a plain static page: colours as CSS custom properties from the tokens in section 16, `prefers-reduced-motion` respected, no tooltips.
- **Fredoka self-hosted** in `docs/fonts/` (OFL), so the site loads nothing from third parties.
- **Narrow widths:** the page works at phone width (16 px gutters, no horizontal scroll). Below about 640 px, the brief's fixed values may scale down or wrap (h1 80 px with its 16 px stroke, the description card's `nowrap`, the brew command). Maple is never allowed to cover content: below about 640 px she becomes smaller and non-fixed at the end of the page, and at every width the page has bottom padding so she never covers the footer. Her bubble shows on `:hover`, and also on `:focus-visible` and tap.
- **Content:**
  - Homebrew sticker: `brew install --cask grokcodile/tap/stickermine`. The copy button reads the command from one `data-copy` attribute that matches the visible text (port Pullcord's `.brew-copy[data-copy]` script: `writeText` with an `execCommand` fallback, swapping the aria-label to "Copied" during the 1.6 s checkmark).
  - Download line: "\<size\> download · macOS 26+ · Apple Silicon · Free", with no version number (matches the siblings and can't go stale). The size is measured from each release's published DMG and updated by hand; it is stated only on the site.
  - Download links to `https://github.com/grokcodile/stickermine/releases/latest/download/Stickermine.dmg`.
- **Demo card:** until the demo is recorded, the 16:10 card shows a still (stickers on a desktop) with no play button and no bracketed note. When it exists: muted, looping, `playsinline`, no native controls (the peeled corner would cut them), autoplay only when reduced motion isn't requested.
- **Footer (in order):** © Stickermine, GitHub (repo), Privacy (`PRIVACY.md` on GitHub), Terms (`TERMS.md` on GitHub), Contact (`CONTACT.md` on GitHub), then ☕️ Buy me a coffee (Ko-fi) last.
- **Assets:** `docs/icon.png` (from the app icon), favicon, an Open Graph image from the pickaxe, `docs/dog.png`.
- **Domain:** `docs/CNAME` = `stickermine.app` is added only once the domain is bought and resolves; until then the site, the og:image absolute URL and the About popover's Website link use `https://grokcodile.github.io/stickermine/`.
- **Light canvas only** (the design's single look); no dark mode in v1.

## 16. Brand tokens and assets

| Role | Hex |
|---|---|
| Page background | `#F3F0E8` |
| Ink / dark sticker | `#1F2340` |
| Blue (icon tile, Download, h1) | `#3D4BE0` |
| Mint (description) | `#8FE3BE` |
| Pink (Maple's bubble) | `#FF4F81` |
| Yellow (coffee) | `#FFD84D` |
| Sticker border | `#FFFFFF` |

Type: Fredoka 300–600 on the site; SF Pro Rounded in the app. Sticker rules: white border (8 px pills, 10 px cards), large radius, shadow `0 10px 24px rgba(31,35,64,0.22)`, slight rotation between −4° and +3°.

**App icon:** a classic `AppIcon.appiconset` in `Stickermine/Assets.xcassets` with the 10 mac slices (16–512 @1x/@2x), the rounded tile fitted to the 824/1024 grid like Pullcord and Key54. The slices are generated by a committed script, `design/make-icon.sh`, and the generated PNGs are committed (release.yml has no icon step). The script renders `design/icon-pickaxe.svg` with `qlmanage -t -s 1024` (WebKit keeps the SVG's drop shadow; NSImage/CoreSVG drops it), then `sips -z` for each slice. Switching to an Icon Composer `.icon` file (which the system masks itself) is a possible later improvement. Check the result in Finder, the Dock and Login Items on macOS 26.x. Rejected icon directions, not to revisit: mine cart, mining hat, peeling-sticker icon.

**Other bundled assets:** `MenuBarGlyph.imageset` (section 13) and Maple's `dog.png` are copied into the asset catalog; nothing in the app references `design/` directly.

## 17. Build, CI and release

- **`build.sh`:**
  - If `DEVELOPER_DIR` is unset and `xcode-select -p` points at the CommandLineTools, fall back to `/Applications/Xcode.app`, then `/Applications/Xcode-beta.app`.
  - Read `MIN_MACOS` from `Info.plist`; fail if the project's `MACOSX_DEPLOYMENT_TARGET` (`xcodebuild -showBuildSettings`) differs.
  - `xcodebuild -project Stickermine.xcodeproj -scheme Stickermine -configuration Release -derivedDataPath build/DerivedData ARCHS=arm64 MACOSX_DEPLOYMENT_TARGET=$MIN_MACOS CODE_SIGNING_ALLOWED=NO build`, then `ditto` the product from `build/DerivedData/Build/Products/Release/Stickermine.app` to `build/Stickermine.app`.
  - Fail unless the built app's `CFBundleShortVersionString`, `CFBundleVersion` and `LSMinimumSystemVersion` equal the root `Info.plist`'s.
  - Always `strip -x` the executable before signing (an `xcodebuild build` Release product isn't stripped; measured about −18%).
  - Then Pullcord's signing block verbatim: pinned SHA-1 `DEA1A3749B06CF3619F72152EFC35A48E380C4E4`, explicit-identity check, ad-hoc fallback only when the default identity is absent, `codesign --force --options runtime --timestamp`, verify, leaf-certificate fingerprint check. Pullcord's `mkdir`, `swiftc`, `cp Info.plist` and `cp icon/AppIcon.icns` lines are dropped (Xcode produces all of that).
- **`install.sh`:** Pullcord's, with `APP_NAME=Stickermine` and `BUNDLE_ID=com.ethan.stickermine` (quit the old copy, move the new one to `/Applications`, launch with `open`, check exactly one copy runs).
- **`release.yml`:** Pullcord's, with only `APP: Stickermine` and `CASK: stickermine` changed. On a `v*` tag it stamps `Info.plist` from the tag, builds via `build.sh`, notarizes and staples the app, builds and signs the DMG, notarizes and staples it, runs the Gatekeeper check, publishes the release with `Stickermine.dmg`, and bumps `Casks/stickermine.rb` in `grokcodile/homebrew-tap`. A manual run is a dry run that keeps the DMG as an artifact.
- **Early CI:** the repo is created (public or private, Ethan's choice) and a first manual dry run happens as soon as the scaffold builds (Info.plist, xcodeproj, build.sh, release.yml, a minimal LSUIElement app). The dry run repeats at the end of every plan milestone; it is the only check against CI's Xcode 26.6 project format, SDK, Swift and actool. The spike's window checks are also repeated on a dry-run DMG, which links the 26.x SDK.
- **Before the first tag** (each outward step confirmed with Ethan when it happens):
  1. Make the repo `grokcodile/stickermine` public if it isn't yet (the updater's unauthenticated API call and Pages need it public).
  2. Ethan sets the six secrets (`MACOS_CERT_P12_BASE64`, `MACOS_CERT_PASSWORD`, `AC_API_KEY_ID`, `AC_API_ISSUER_ID`, `AC_API_KEY_BASE64`, `TAP_PUSH_TOKEN`) with `gh secret set`. Claude never handles them.
  3. Commit `Casks/stickermine.rb` to `homebrew-tap`, copying `pullcord.rb`'s shape. It must contain the three lines the workflow rewrites and then re-checks: quoted placeholder `version "1.0"`, a 64-hex placeholder `sha256`, and `  depends_on macos: :tahoe` (two-space indent; without it the tap step fails after the release is already published). It also has `depends_on arch: :arm64`, `uninstall quit: "com.ethan.stickermine"` and `zap trash:` for `~/Library/Application Support/com.ethan.stickermine`, `~/Library/Caches/com.ethan.stickermine`, `~/Library/HTTPStorages/com.ethan.stickermine` and `~/Library/Preferences/com.ethan.stickermine.plist`. Add a Stickermine row to the tap README.
  4. Manual dry run; check the DMG with `codesign`, `spctl` and `stapler`; then tag `v1.0`.
  5. After the v1.0 release and cask bump succeed: enable Pages from `main:/docs`, and add `docs/CNAME` once `stickermine.app` is bought and resolves.

## 18. Testing

**Unit tests** (Swift Testing, `StickermineTests/`, run locally with `xcodebuild test`; the release workflow stays identical to the siblings and doesn't run them):

- **Test hosting:** the test bundle is hosted in the app. `AppDelegate` returns before any startup work (single-instance check, hotkey, status item, sticker restore, launch repair, `SMAppService`, updater) when `ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil`. Tests give `LibraryStore` a temporary directory and `UserDefaults(suiteName:)`, never the real Application Support or `.standard`.
- `LayoutResolver`: exact key, closest-size choice (orientation first, log-ratio distance), the tie-break (deterministic across shuffled dictionaries), scale adjustment, write rules.
- `LibraryStore`: round trip; newer version → read-only; corrupt file → set aside and rebuilt; missing PNG dropped; stray PNG adopted with its DPI; tutorial UUIDs re-flagged; lenient enums and optional fields.
- `DisplayRegistry`: ghost and mirror filtering, null-ID guard, fingerprint fallback (exactly one match, serial 0 and `0x01010101` refused, a connected display with the same fingerprint refused).
- Style parameter scaling with pixel size.
- Click → subject mapping on top-down 512×512 coverage masks.
- Capture outcome classification (the first-match order in section 5.7).
- Shortcut storage and system-shortcut conflict detection.

**Spike first** (before any capture UI): a sticker window at desktopIcon + 1 that can be double-clicked, dragged, pinched and rotated, with click-through on transparent pixels, checked against Spaces, Show Desktop (F11, gesture, wallpaper click: stickers stay put and clickable), Mission Control, Stage Manager (including "Show desktop items" off), display connect/disconnect, sleep/wake, screen lock and mirroring. Also: P3 colour and transparent-pixel click-through with IOSurface contents; the layer shadow drawing inside the padded frame without clipping; whether long-lived panels go stale. Whether the spike's code is kept in the real target is a plan decision.

**Manual checklist** (things code can't verify): screen-sharing exclusion in Zoom, Meet in Chrome, FaceTime SharePlay, QuickTime recording, Screen Sharing.app and AirPlay/Sidecar; stickers render normally on screen with `sharingType = .none`; behaviour on macOS 26.x itself (all research ran on 27.2); a fresh-permission run (denied, undetermined, granted without relaunch, the Relaunch fallback); the periodic system alert landing on the picker; whether `screencapture -i` on 27.x offers a Visual Intelligence path that could divert the selection; a third-party app's own ⌃⌥⌘S being taken over; the app icon in Finder, the Dock and Login Items on 26.x.

## 19. Differences from the handoff brief

| Brief | This spec | Why |
|---|---|---|
| macOS 14+ placeholder | macOS 26+, Apple Silicon only | Matches the siblings; CI runner and Vision APIs |
| `build.sh`, `install.sh`, `notarize.sh` | No `notarize.sh`; notarization only in CI | The siblings removed local notarization |
| `brew install --cask stickermine` | `brew install --cask grokcodile/tap/stickermine` | The cask lives in the grokcodile tap |
| Fredoka from Google Fonts | Self-hosted Fredoka | The sites promise no third-party requests |
| "v1.0 · 12 MB · macOS 14+ · Free" | "\<size\> download · macOS 26+ · Apple Silicon · Free" | No version number, like the siblings, so it can't go stale |
| Footer: ©, GitHub, Privacy, Contact, coffee | Adds Terms after Privacy | The repo has a TERMS.md, as in the siblings |
| Stickers "at desktop level" | One level above the desktop icons | Below the icons, stickers can't receive clicks |
| Stickers hide during screen sharing | Setting, default on, best-effort; also hides them from screenshots | Apple documents the API as legacy and gives no guarantee |
| Double-click shows a move icon and a remove icon | Drag anywhere to move; corner knob (scale + rotate); toolbar pill (Style, Flip, Float on top, Remove) | Decided in the design conversation (section 2) |
| Menu bar icon starts a capture | Left-click captures, right-click shows a small menu | Home must be reachable without the Dock |
| A history browser is a later idea | v1 Home shows a simple history grid | Decided in the design conversation; search and groups stay later |
| Placeholder links on the site | `github.io` URL until `stickermine.app` resolves | The domain isn't bought yet |

## 20. Open items for Ethan

- Buy `stickermine.app` (no DNS records as of 2026-10-11) and decide the contact address for `CONTACT.md` (the sibling pattern would be `stickermine@ethans.email`; unverified).
- Record the demo loop (capture, style, stick).
- Choose whether the GitHub repo starts private (early CI dry runs) or public.
- Set the six CI secrets when the repo exists.
- Optional: install a released Xcode 26.x next to the beta for exact local parity with CI.
