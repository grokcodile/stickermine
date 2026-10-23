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
| macOS (`sw_vers -productVersion`, `sw_vers -buildVersion`) | 27.2 (26B118) |
| Mac model | Mac17,4 |
| Displays (name, resolution, scale, which is main) | Color LCD, built-in Liquid Retina, 2880 × 1864 Retina, main (no external display connected at the start) |
| Stage Manager on or off at the start | off (`com.apple.WindowManager GloballyEnabled` = 0) |
| App under test (local `build/` or CI dry-run DMG, with the run URL) | local `build/Stickermine.app` at commit ca7d504, Developer ID signed |

## A. Editing basics

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 1 | Level: above icons, below apps | Put a file icon on the desktop under maple-cgimage's opaque pixels; then drag a TextEdit window over the sticker. | Maple covers the icon; the TextEdit window covers Maple. Log `level=-2147483602` (or desktopIcon+1 on this OS). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Keeps `PanelPolicy.stickerLevel` = desktopIcon + 1. If stickers can't be clicked or cover apps, switch to normal − 1 in `PanelPolicy` and repeat rows 1–5. |
| 2 | Inactive click is absorbed | With Safari (or any app) frontmost, single-click maple-cgimage's opaque pixels once. | Nothing happens: Safari stays frontmost (its menu bar stays), no desktop icon gets selected, no log line. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `acceptsFirstMouse` + non-activating panel. If the click activates Stickermine, M5 must restore focus after single clicks. |
| 3 | Double-click enters editing | With Safari frontmost, double-click maple-cgimage's opaque pixels. | Dashed outline appears; log `begin editing: key=true appActive=…` and `editing +0.5s: key=true appActive=true`; note what the menu bar shows (an `.accessory` app is documented to have no menu bar of its own, so Safari's menus may stay visible while Stickermine is active). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | `appActive=true` at +0.5 s confirms `NSApp.activate()` is enough for M5's editing entry. If `key=false`, M5 must call `makeKeyAndOrderFront` after activation instead. |
| 4 | Drag moves the sticker | While editing, drag from an opaque pixel, release. | Sticker follows the cursor without lag; log `performDrag returned: buttonsDown=0 frame=…`; note whether a `local leftMouseUp` line follows. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | `buttonsDown=0`: M5 treats `performDrag(with:)` returning as the drag end. `buttonsDown≠0` (returned early): if `local leftMouseUp` was logged, M5 ends the drag on a local `.leftMouseUp` monitor; if not, M5 ends it on `windowDidMove` plus polling `NSEvent.pressedMouseButtons == 0`. |
| 5 | Hit pad grabs transparent pixels | While editing, drag from a transparent pixel inside the dashed box (for example beside Maple's ear). | The sticker drags. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms the alpha 1/255 hit pad. If the click passes through, raise `StickerView.hitPadAlpha` to 2/255 and retest. |
| 6 | Drag to another display | With two displays: while editing, drag maple-cgimage onto the other display and release. | It lands where released; log `screen=<other display>`. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | M5's cross-display drag can read `panel.screen`/frame after the drag. |
| 7 | Esc ends editing | While editing (Safari was frontmost before), press Esc. | Outline disappears; Safari is frontmost again; log `end editing (escape)`. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms the focus hand-back in M5 (`previousApp.activate`). |
| 8 | Clicking elsewhere ends editing | While editing maple-cgimage, click a Finder window or the desktop. Re-enter editing, then single-click swatch-cgimage's opaque pixels once. | Outline disappears; log `end editing (resignKey)`. For the click on the other sticker, record whether Maple's editing ends (by design it may not: a non-editing sticker can't become key). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `resignKey` as M5's editing-end trigger. If the click on the other sticker doesn't end it, M5 ends editing on any mouse-down on a non-editing sticker. |
| 9 | Pinch while editing | While editing maple-cgimage, pinch on the trackpad over it. | Log `magnify phase=… editing=true`; Maple scales live around its centre; window grows once at the start and shrinks to fit at the end (`gesture end` log); no clipping. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Events arrive: M5 implements pinch. No events: M5 relies on the corner knob alone and the README drops pinch. |
| 10 | Rotate while editing | While editing, rotate two fingers on the trackpad over Maple. | Log `rotate phase=… editing=true`; Maple turns around its centre; the shadow turns with it (expected until M5 re-bakes); no clipping. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as row 9 for rotation. |
| 11 | Gestures when not editing | Without editing, pinch and rotate over Maple. | No visible change. Note whether `magnify`/`rotate` log lines appear with `editing=false`. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Lines appear: gestures reach non-key panels and M5 must keep ignoring them outside editing. No lines: key status is required, as designed. |
| 12 | Float on top | While editing, press F; click another app's window so it moves over the sticker area; press F again after re-entering editing. | First F: log `float on top=true level=3`, the sticker stays above app windows. Second F: back under app windows. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `.floating` for Float on top. |
| 13 | Float on top vs full-screen apps | With one sticker floated, switch to a full-screen app Space. | The sticker is not on the full-screen Space. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | v1 keeps `.fullScreenNone` for floated stickers (spec section 1: stickers over full-screen apps aren't in v1). |

## B. Click-through, contents and shadow

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 14 | Click-through, CGImage contents | Place a desktop file icon under a transparent corner of maple-cgimage's window (inside its frame, outside Maple). Click it, then double-click it. | The icon selects, then opens. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Alpha hit-testing works: keep it (no `ignoresMouseEvents`). Fails: turn on the fallback design (spec section 9, `clickThroughFallback`) by default in M2. |
| 15 | Click-through, IOSurface contents | Same as row 14 with maple-iosurface. | Same as row 14. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Passes: M3 may use IOSurface contents. Fails while row 14 passes: M3 uses CGImage contents. |
| 16 | P3 colour, IOSurface vs CGImage | On a P3 display (built-in MacBook display or a P3 external), compare swatch-cgimage with swatch-iosurface, and maple-cgimage with maple-iosurface. Optionally read values with Digital Color Meter set to "Display native values". | Each pair looks identical. On a P3 display each swatch's left half (P3 red) is visibly more saturated than its right half (sRGB red). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Identical: M3 renders to IOSurface in the capture's colour space tagged with `kIOSurfaceColorSpace`. Any shift: M3 uses CGImage contents. |
| 17 | Swatch corners click through | Click on a desktop icon placed under a swatch's rounded transparent corner, for both swatches. | The icon gets the click. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as rows 14–15. |
| 18 | Layer shadow fits the padded frame | Look at both Maples' shadows against a light wallpaper, especially at the bottom edge. | The shadow fades out fully, with no straight cut-off line; it falls downward. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Margin `ceil(3 × radius) + abs(offset)` is enough. A cut-off: M3 raises the factor in `LayerShadow.margin`. |
| 19 | Shadow isn't hittable | Put a desktop icon under the visible shadow just below Maple's paws; click it. | The icon gets the click. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms the layer shadow (not baked) decision in spec section 8. |
| 20 | Stickers render with sharing type none | Look at all four stickers. | All render normally on screen (they use `sharingType = .none`). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms the default-on "Hide from screen sharing" setting doesn't affect on-screen drawing. |

## C. Spaces, Show Desktop, Mission Control, Stage Manager

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 21 | Every desktop Space | Add a second desktop in Mission Control; switch with ⌃→ and ⌃←. | All stickers are on both desktops at the same place. They stay still while the wallpaper slides (accepted trade-off). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `.canJoinAllSpaces` + `.stationary`. |
| 22 | Not on full-screen Spaces | Make an app full screen (⌃⌘F); switch to it and back. | No sticker on the full-screen Space, none flashing during the transition. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `.fullScreenNone`. |
| 23 | Show Desktop (F11 / fn-F11) | Press the Show Desktop key. Then double-click a sticker. Press it again. | Windows move aside; stickers stay put and visible; the double-click enters editing. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | No Show Desktop handling in M2/M5. If stickers move or vanish, M2 must re-assert frames after the reveal. |
| 24 | Show Desktop gesture | Spread thumb and three fingers on the trackpad; double-click a sticker; pinch back. | Same as row 23. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as row 23. |
| 25 | Click wallpaper to reveal desktop | Desktop & Dock › "Click wallpaper to reveal desktop": Always (note the old value and restore it afterwards). Click a sticker's opaque pixels, then a transparent pixel, then the bare wallpaper. While the desktop is revealed, double-click a sticker. | Opaque pixel: no reveal. Transparent pixel or wallpaper: windows move aside; stickers stay put and visible. Record whether the double-click during the reveal enters editing (spec section 18: stickers stay put and clickable). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as row 23. |
| 26 | Mission Control | Open Mission Control (F3 or ⌃↑), then close it. Repeat with one sticker floated (F). | Stickers stay visible in place and are not listed as windows. The floated sticker doesn't draw over Mission Control's own UI. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `.stationary`. If the floated sticker covers Mission Control's UI, M2 tries `.transient` in place of `.stationary` for floated stickers only and repeats rows 21 and 26. |
| 27 | App Exposé and cycling | ⌃↓ in any app; ⌘Tab; ⌘\` in Finder. | Stickers stay in place; Stickermine isn't in ⌘Tab; ⌘\` never selects a sticker. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `.ignoresCycle` and the accessory policy. |
| 28 | Stage Manager | Turn Stage Manager on (Control Center). Open two apps; double-click a sticker; drag it. | Stickers stay in place behind the stage; editing and dragging work. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Works: README says Stickermine works with Stage Manager. Fails: M2 tests `.canJoinAllApplications` (only with `.fullScreenNone`) and the README states the limit. |
| 29 | Stage Manager, desktop items hidden | Desktop & Dock › Stage Manager "Show Items": uncheck "On Desktop" (restore afterwards). Repeat row 28. | Same as row 28: stickers stay above the hidden desktop's click-catcher and stay double-clickable. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as row 28. |
| 30 | Hide Others | In another app press ⌥⌘H. | Stickers stay visible (`canHide = false`). | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Confirms `canHide = false`. |

## D. Displays, sleep, lock and staleness

Keep the `log stream` running for this section; every event logs each sticker's `visible`, `occlusionVisible`, `windowServerOnscreen`, `screen` and `frame`, immediately and again 1.5 s later.

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 31 | Display disconnect | With an external display: move maple-iosurface onto it (edit, drag), stop editing, then unplug the display. | No crash. Record where macOS puts the sticker (moved to the remaining display, or gone) from the `didChangeScreenParameters +1.5s` lines. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | M2's reconcile must order out panels of a missing display itself and never let macOS's move be saved. |
| 32 | Display reconnect | Plug the display back in. | Record whether the sticker returns to the external display by itself. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | M2 re-applies frames from the model on every reconcile (expected: macOS doesn't restore it). |
| 33 | Lid closed with an external display (MacBook only) | Close the lid with an external display and keyboard attached; open it again. | No crash; record where the stickers are after each step. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as rows 31–32. |
| 34 | Sleep and wake | Apple menu › Sleep; wait 30 s; wake and unlock. Double-click each sticker. | All four draw; each enters editing; `didWake +1.5s` and `screensDidWake +1.5s` lines show `visible=true windowServerOnscreen=yes`. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Draw and click: no rebuild on wake. Missing or unclickable: M2 rebuilds every panel on wake (spec section 9), if row 39 shows the rebuild fixes it. |
| 35 | Screen lock and unlock | ⌃⌘Q; wait 10 s; unlock. Double-click each sticker. | Same as row 34 with `screenIsUnlocked` lines. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as row 34, for unlock. |
| 36 | Mirroring | Displays settings: mirror the built-in display to the external, then stop mirroring. | No crash; record where the stickers are while mirrored and afterwards. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | M2's mirror rules (spec section 11). |
| 37 | Resolution change | Displays settings: pick a different "Larger Text / More Space" option for the main display, then restore it. | Stickers stay on the main display; record whether any ends up off screen. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | M2's closest-size rule and draw-time clamping. |
| 38 | Long-lived panels | Runs last, in Task 12 Step 7, on the CI dry-run build (the local build when there is none). Leave the spike running overnight (at least 8 h, including a sleep). Next day, double-click each sticker. | All four draw and enter editing. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Same as row 34. |
| 39 | Rebuild as the fix (only if 34, 35 or 38 failed) | `pkill -x Stickermine`, then `open -g build/Stickermine.app --args -spike -spikeRebuild`; repeat the failed row. | Log `rebuilding every panel after …`; then all stickers draw and enter editing. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Rebuild fixes it: M2 closes and recreates all panels 1.5 s after wake, unlock and display changes, ending any editing first. |

## E. Builds and macOS versions

| # | Item | How to test | Expected | Result | Decision it drives |
|---|---|---|---|---|---|
| 40 | CI dry-run build | Download the `Stickermine-dry-run` artifact from the CI dry run (Task 12), open the DMG, copy the app to a temporary folder (not /Applications), `pkill -x Stickermine`, then `open -g <folder>/Stickermine.app --args -spike` and click another app's window so it is frontmost. Repeat rows 1–5, 7–10, 14–18 and 21–23. | Same results as the local build. `vtool -show-build <app>/Contents/MacOS/Stickermine` shows `sdk 26.x`. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Any difference: the behaviour depends on the linked SDK, so every later spike-style check runs on a dry-run build. |
| 41 | macOS 26.x | On a Mac running macOS 26.x (if one is available), run the dry-run build as in row 40 and repeat rows 1–5, 14–16 and 21–23. | Same results as on 27.x. | not run: hands-on spike skipped for now (Ethan, 2026-10-23); run before release | Differences become explicit 26.x workarounds (or raise `LSMinimumSystemVersion`). |

## Decisions

Fill this in from the rows above once the run is complete.

| Question | Rows | Outcome |
|---|---|---|
| Sticker level stays desktopIcon + 1? | 1–3 | Not tested (spike skipped). Default kept: desktopIcon + 1 (no change to `PanelPolicy`). |
| Alpha click-through works, or the fallback mode becomes the default? | 14, 15, 17 | Not tested (spike skipped). Default kept: alpha click-through; `clickThroughFallbackByDefault = false` (M2). |
| Contents type for M3: IOSurface or CGImage? | 15, 16, 40 | Not tested (spike skipped). Default kept: IOSurface contents (`StyleRenderer.defaultContents = .surface`, M3); CGImage stays the fallback if a later check shows a colour shift or broken click-through. |
| Do pinch and rotate reach the editing sticker? | 9–11 | Not tested (spike skipped). M5 implements pinch and rotate as planned, with the corner knob as the guaranteed path. |
| Does `performDrag(with:)` return at the drag's end? | 4 | Not tested (spike skipped). M5 keeps its planned default (performDrag returning = drag end). |
| Does clicking another sticker end editing? | 8 | Not tested (spike skipped). M5 keeps its planned default. |
| Do panels go stale, and does a rebuild fix it? | 34, 35, 38, 39 | Not tested (spike skipped). Default kept: no rebuild after system events (`rebuildsPanelsAfterSystemEvents = false`, M2) (row 38 pending). |
| Stage Manager supported as is? | 28, 29 | Not tested (spike skipped). No change to the collection behaviour. |
| Any difference between the local and the CI (26.x SDK) build? | 40, 41 | |
