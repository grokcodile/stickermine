````markdown
# Editing checks (M5)

M5's editing (spec sections 10 and 11) needs a person at the Mac: a trackpad, real displays, focus moving between real apps, sleep and lock. An agent executing the plan asks Ethan to do each action and writes down what he reports and the named log lines; it never fills in a Result itself. Rows that need hardware that isn't there (a second display, a trackpad) get `not run: <reason>`.

## Setup

Run these in bash or zsh, not fish.

1. Keep the real library out of the way (the checks create, move and remove stickers):

   ```bash
   LIB="$HOME/Library/Application Support/com.ethan.stickermine"
   pkill -x Stickermine || true
   if [ -e "$LIB" ]; then mv "$LIB" "$LIB.before-m5"; fi
   ```

2. `./install.sh`. It must print `Signing with: DEA1A3749B06CF3619F72152EFC35A48E380C4E4` (Screen Recording stays granted for that signature). It launches `/Applications/Stickermine.app` with `open`.
3. In a second terminal: `log stream --style compact --predicate 'subsystem == "com.ethan.stickermine"'`.
4. In the first terminal, define three helpers (the library is saved 0.5 s after a change: wait a second before using them):

   ```bash
   LIB="$HOME/Library/Application Support/com.ethan.stickermine"
   libsum() { shasum "$LIB/library.json" | cut -c1-12; }
   order() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); [print(k[:8], [p["id"][:8] for p in r["placements"]]) for k, r in d["displays"].items()]' "$LIB/library.json"; }
   counts() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print("stickers", len(d["stickers"]), "placements", sum(len(r["placements"]) for r in d["displays"].values()))' "$LIB/library.json"; }
   ```

5. With ⌃⌥⌘S, make three stickers on the main display (the one with the menu bar), away from its edges: **A**, a photo subject in **Puffy** (something with a clear top, so the highlight shows); **B**, an app icon in **Outline**, placed so it overlaps A a little (B is newer, so it is in front); **C**, anything, in **None**, away from both.
6. Before every row, click a Safari (or TextEdit) window so that app is frontmost, unless the row says otherwise.

| Field | Value |
|---|---|
| Date | |
| macOS (`sw_vers -productVersion`, `sw_vers -buildVersion`) | |
| Mac model, trackpad (built-in / Magic Trackpad / none) | |
| Displays (name, resolution, scale, which is main) | |
| `install.sh` signing line | |

## Checks

| # | Check | How | Expected | Result |
|---|---|---|---|---|
| 1 | Inactive click | Single-click A's opaque pixels once. | Nothing happens: Safari stays frontmost, no outline, no `editing` log line. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 2 | Double-click enters editing | Double-click A where B doesn't cover it. | A comes in front of B (the overlap now shows A). A dashed outline around A, a round white knob on the outline's bottom-right corner, and the pill centred 8 pt under A's knob with **Style**, **Flip**, **Float on top**, **Remove**. Log `editing <A's first 8 ID characters>` and `editing focus +0.5s: appActive=true key=true` (record the values exactly as logged). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 3 | Bring to front is saved | Press Esc, wait a second, run `order`. | A's ID from row 2 is the last one in its display's list. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 4 | Esc hands focus back | Double-click A, then press Esc. | Outline, knob and pill disappear; Safari is frontmost again (typing goes to it). Log `editing … ended` and `focus returned to com.apple.Safari`. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 5 | A click elsewhere | Double-click A, then click a Finder window. | Editing ends; Finder stays frontmost. Log `focus stays with com.apple.finder`. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 6 | A click on another sticker | Double-click A, then single-click C's opaque pixels once. | A's editing ends (log `editing … ended`); C doesn't start editing; Safari is frontmost again about half a second later (the double-click interval). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 7 | Switching stickers | Double-click A, then double-click C, then press Esc. | A's outline and pill go as C's appear; after Esc, Safari (frontmost before A) is frontmost again. Between the two clicks Safari never comes forward (its windows don't flash active). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 8 | Drag | Double-click A. Drag it from an opaque pixel about 200 pt to the right and release; then drag it from a transparent spot inside the dashed box (beside the subject) and release. Run `libsum` before and after. | It follows the cursor without lag both times and the pill follows every step; after each release A is still being edited. The two sums differ (a drag end is a write). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 9 | Drop under the menu bar | Drag A so its centre is under the menu bar; release. | A moves back down so it is fully on the display, with its centre below the menu bar. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 10 | The pill goes above | Drag A down until it sits just above the Dock (or the bottom edge); release. | The pill moves above A. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 11 | Drag to another display | With a second display: drag A onto it and release; then drag it back. | It lands where released at the same size on screen; the pill moves to that display with it; log `dropped <id> on display <uuid>`. If that display has another scale (Retina vs not), A is sharp a moment after the drop. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 12 | Knob: scale | Drag the knob straight out from A's centre to about twice the distance; release. Then drag it back in; release. | A grows, then shrinks, around its unchanged centre with the knob under the cursor, without flicker while dragging; at each release it is re-rendered sharp in the same place. Log `gesture end: scale ×…`. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 13 | Knob: rotate, Shift, re-bake | Drag the knob about 40° around the centre, counter-clockwise; release. Then drag it again holding Shift. | A turns with the knob; with Shift it moves in 15° steps. After each release A's shadow still falls straight down and Puffy's highlight is still at the top-left (re-rendered, not just turned). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 14 | Scale limits | Drag the knob far out, past the display's edge; release. Then drag it almost onto the centre; release. | Growing stops when A's long side equals the display's long side; shrinking stops when its long side is 48 pt (about a default Dock icon). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 15 | Pinch | Pinch out, then in, with two fingers on the trackpad while A is being edited. | A scales live around its centre and is re-rendered at the end; log `gesture end`. If nothing happens, write `no pinch` (spike row 9; the knob is the guaranteed path). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 16 | Trackpad rotate | Rotate two fingers on the trackpad. | As row 15, for rotation. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 17 | Esc mid-gesture | Run `libsum`. Double-click A; press the mouse button on the knob and move it; while still holding the button, press Esc; then let go. Run `libsum`. | A snaps back to the size and angle it had before the knob drag; editing ends; both sums are equal. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 18 | Delete | Double-click C; press Delete (⌫). Run `counts`. | C disappears; Safari is frontmost again; `stickers 3 placements 2` (C stays in history). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 19 | Pill: Style | Double-click B; click **Style**. Click the **Puffy** preview. Then press Esc. | Four previews appear inside the pill (no popover, no menu) in the order Puffy, Outline, Shadow, None, with Outline highlighted. After the click B is Puffy, the highlight moves, the row stays open and B is still being edited. Esc ends editing (the pill never took key). || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 20 | Pill: Flip | Double-click B; click **Flip**. | B is mirrored left to right; the button shows as on. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 21 | Pill: Float on top | Click **Float on top**, then drag a Safari window over B. Then double-click B, click **Float on top** again, and drag Safari over it. | First B stays above the Safari window; afterwards Safari covers it. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 22 | Pill: Remove | Double-click B; click **Remove**. Run `counts`. | B disappears; Safari is frontmost again; `stickers 3 placements 1`. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 23 | Looking writes nothing | Run `libsum`. Double-click A (the only sticker left on its display, so already in front), wait 2 s, press Esc, wait 2 s, run `libsum`. | Both sums are equal. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 24 | Sessions | Double-click A; press ⌃⌥⌘S; press Esc at the crosshair. Then press ⌃⌥⌘S, drag over something and, with the picker open, double-click A; press Esc to close the picker. | The first ⌃⌥⌘S ends A's editing as the crosshair appears; after Esc, Safari is frontmost again. With the picker open, the double-click on A does nothing. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 25 | Lock and sleep | Run `libsum`. Double-click A; press ⌃⌘Q; unlock. Then double-click A; Apple menu › Sleep; wake and unlock. Run `libsum`. | After each, A is no longer being edited and is in the same place; both sums are equal. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 26 | Display unplugged while editing | With a second display: drag A onto it; run `libsum`; double-click A; unplug that display; plug it back in; run `libsum`. Then drag A back onto the main display. | No crash; A and its pill disappear with the display; once it is back, A is in the same place and not being edited; both sums are equal. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 27 | Fallback click-through mode | Put a file icon on the desktop under a transparent corner of A's box. `pkill -x Stickermine; defaults write com.ethan.stickermine clickThroughFallback -bool true; open /Applications/Stickermine.app`. Click the icon through A's corner. Double-click A; drag it from a transparent spot inside the box and release; drag the knob a little; press Esc; click the icon through the corner again (without moving the mouse first). Then `pkill -x Stickermine; defaults delete com.ethan.stickermine clickThroughFallback; open /Applications/Stickermine.app`. | The icon gets both clicks through the transparent corner. Editing, the drag from the transparent spot and the knob work as in rows 8 and 12. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 28 | 50 stickers: launch | Make the 50-sticker library (below), then `open /Applications/Stickermine.app` while watching the log. | All 51 stickers (A and the 50 new ones) appear within about 2 s: compare the time of the log line `library loaded: 4 stickers` with the last `ordered in` line, and record both times. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 29 | 50 stickers: editing among them | Double-click one in the middle of the grid; drag it, scale it with the knob, restyle it from the pill; Esc. | Each edit is as smooth as with three stickers; no other sticker moves or flickers. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |
| 30 | 50 stickers: memory | `ps -o rss= -p "$(pgrep -x Stickermine)"` with only A on screen (before making the 50-sticker library) and again after row 29. | Record both numbers (KB). The growth is in the order of the 50 on-screen bitmaps (each at most 160 pt: about 160 × 160 × backing scale² × 4 bytes), not of the captures: if each D copy kept a capture-sized bitmap, those 12–13 copies alone would add several hundred MB. Above 1 GB is a failure to investigate. || not run: hands-on checks deferred by Ethan (2026-10-23); run before release |

## The 50-sticker library (rows 28–30)

After row 27: press ⌃⌥⌘S, drag over the whole of the largest display (a 5K display if one is attached), choose **Whole image**, place it, then double-click it and click **Remove** in the pill. This sticker, **D**, stays in history without a placement, so only A is on screen. Take row 30's first reading, then:

```bash
pkill -x Stickermine || true
python3 - "$LIB/library.json" <<'PY'
import json, sys, uuid
path = sys.argv[1]
library = json.load(open(path))
stickers = [s for s in library["stickers"] if not s.get("tutorial")]
key, record = max(library["displays"].items(), key=lambda item: len(item[1]["placements"]))
size = next(iter(record["placements"][-1]["poses"]))
styles = ["puffy", "outline", "shadow", "none"]
for i in range(50):
    s = stickers[i % len(stickers)]
    long_side = max(s["pixelWidth"], s["pixelHeight"]) / s["pixelsPerPoint"]
    record["placements"].append({
        "id": str(uuid.uuid4()).upper(), "sticker": s["id"], "style": styles[(i // len(stickers)) % 4],
        "flipped": False, "onTop": False, "rotation": 0.0,
        "poses": {size: {"x": 0.08 + 0.84 * (i % 10) / 9, "y": 0.2 + 0.6 * (i // 10) / 4,
                         "scale": min(0.5, 160 / long_side)}}})
json.dump(library, open(path, "w"), indent=2)
print(len(record["placements"]), "placements on", key[:8], "at", size, "from", len(stickers), "stickers")
PY
```

Expected: `51 placements on <8 characters> at <the main display's size key> from 4 stickers` (A plus 50 copies of A, B, C and D, each sticker in all four styles, each at most 160 pt on its long side, in a 10 × 5 grid; the D copies are full-display captures shown small).

## Outcome

Fill this in once every row has a result: which rows failed, what was fixed (with the commit), and which rows were not run and why.

Not run yet (2026-10-28): Ethan deferred the hands-on checks; every row is to be run before release, with the Setup above (move the real library aside first, and put it back afterwards as M5 Task 10 Step 6 says). Spike rows 3 (key and activation on a double-click) and 5 (the 1/255 hit pad) are also still open, so `LiveEditingFocus.takeFocus(for:)` keeps `panel.makeKey()` and `StickerView.hitPadAlpha` stays 1/255 until rows 2, 4 and 8 here say otherwise. Until then, unit tests cover part of what these rows exercise, driving `StickerManager` and `StickerEditor` directly with a focus recorder that never activates anything: `StickerEditingTests` (rows 1–7, 18–23: entering, bring to front saved or not, Esc, every end trigger handing focus back once, a click on another sticker waiting for the double-click interval, switching stickers, the pill's Style, Flip, Float on top and Remove, Delete on the next turn, the fallback mode), `StickerDragTests` (rows 8–11, 26: the window and pill following, a reconcile mid-drag, this size's pose only, a borrowed pose, the menu-bar clamp, a drop on another display at the same size, a display without a record, a drop between displays, a drag that didn't move, every end trigger mid-drag), `StickerGestureTests` (rows 12–17, 25: the square grown once, the transform only, write then settle, a render landing mid-gesture, the knob with Shift, the scale limits, every end trigger mid-gesture), `EditingWiringTests` (row 24), `StickerViewEditingTests` (the knob, the margin, drags in screen points), `ToolbarPillTests` (the pill above or below, the panel policy, first mouse, the style row), `ClickThroughFallbackTests` (row 27: no switching while a button is held), and `EditGeometryTests`/`LibraryEditingTests`. Not covered by unit tests: real activation and key status, real key, pinch and rotate events, the pill as a real child window over other apps, focus moving between real apps, real sleep, lock and display unplugging, alpha hit-testing of the hit pad, how smooth the edits feel, and the 50-sticker launch time and memory (rows 28–30).
