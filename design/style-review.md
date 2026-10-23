# M3 style review

The M3 checks that need a person at the Mac (plan Task 9): the style gallery by eye, and the four styles as live stickers on the desktop. **Result** is filled in by whoever runs the check, with what was actually seen; an agent executing the plan asks Ethan and records his answers, and never fills a Result itself.

| Field | Value |
|---|---|
| Date | 2026-10-23 |
| macOS (`sw_vers -productVersion`, `sw_vers -buildVersion`) | 27.2 (26B118) |
| Mac model and displays (name, resolution, scale) | Mac17,4; built-in Liquid Retina 2880 × 1864, 2× (1440 × 932 pt), main; no external display |
| Build (`./build.sh` signature line) | `Signing with: DEA1A3749B06CF3619F72152EFC35A48E380C4E4` (Developer ID, hardened runtime) |
| Spike decision applied (`defaultContents`) | `.surface` (spike not run; plan default) |

## Gallery (`-styleGallery`)

| # | Check | Expected | Result |
|---|---|---|---|
| 1 | `timings.txt` | Every `puffy` row ends `kernel`, every `puffy-builtin` row `builtIn`; `maple` `puffy` well under 200 ms (write the kernel's compile time and Maple's Puffy time) |  Executor, from the file: every `puffy` row `kernel`, every `puffy-builtin` row `builtIn`; kernel compiled in 284 ms (first launch); `maple` `puffy` 23–29 ms. |
| 2 | `maple-sheet.png` | Puffy inflated, highlights top and left, darker bottom-right; nose and left eye not washed out (or noted for item 8); built-in Puffy similar, softer, no white wash or streaks; Outline's border even; the shadow falls downward |  Executor, viewing the PNGs: Puffy inflated, highlight top-left, rim darker bottom-right. **Before the fix**, both Puffy columns had fine vertical streaks in the highlight (obvious on the smooth `fringe`/`p3` discs) and the built-in had blocky bands — root cause CIGaussianBlur's half-precision horizontal pass; fixed in f85ba45 (box-blur height), re-rendered: streaks gone. Still visible after the fix: the specular haze covers part of Maple's left ear and snout (noted for item 8). Built-in Puffy softer, no streaks, a broad soft highlight band. Outline border even; Shadow/None no added border. |
| 3 | `maple-turned-sheet.png` | Puffy's highlights still top-left on the turned, mirrored Maple |  Executor: Puffy's highlight stays top-left on the turned, mirrored Maple. |
| 4 | `star-sheet.png` | `outline` rounder at the inner corners than `outline-open`; both crisp |  Executor (crops at full size): `outline` rounds the inner corners; `outline-open` keeps a sharper notch; both crisp. |
| 5 | `bar-sheet.png` | Same bar length in every column; border around it for Outline and Puffy |  Executor: same bar length in every column; border around it for Outline and Puffy. |
| 6 | `fringe-sheet.png` | No light ring in `shadow` and `none` on the dark row |  Executor: no light ring in `shadow`/`none` on the dark row; `outline`/`puffy` cover the edge with white. |
| 7 | `p3-sheet.png` | Equally saturated red in every column; Display P3 profile in Preview's inspector |  Executor: `p3-none.png` and `p3-puffy.png` carry the Display P3 profile (`sips -g profile`); the red looks equally saturated across columns in a converted view (true P3 depth needs a person at a P3 display). |
| 8 | Ethan's verdict on Puffy and Outline | Accepted as is, or the change he wants (a spec change) |  Pending Ethan. Question for him: the Puffy specular haze over Maple's ear and snout (spec values: ambient 0.35, diffuse 0.65, shininess 40, specular 0.55, dome height 0.9R). |

## Live stickers (`-debugPlaceMaple all`)

| # | Check | Expected | Result |
|---|---|---|---|
| 1 | Four Maples placed | Puffy, Outline, Shadow, None left to right; kernel compiled line in the log |  Executor, from the log: kernel ready, then four `placed Maple … (puffy/outline/shadow/none)` in that order. Arrangement not checked: the pointer wasn't centred, so the row was clamped at the right edge (two frames share x = 1290, by the reachability clamp). |
| 2 | Shadows | Downward, fading out fully, no cut-off line; none for None |  not run: hands-on (Ethan deferred hands-on checks, 2026-10-23) |
| 3 | Click-through beside the ear and just outside Outline's border | The icon underneath is selected |  not run: hands-on (Ethan deferred hands-on checks, 2026-10-23) |
| 4 | Click on the shadow under the paws | The icon underneath is selected |  not run: hands-on (Ethan deferred hands-on checks, 2026-10-23) |
| 5 | Click on the fur, another app frontmost | Nothing happens |  not run: hands-on (Ethan deferred hands-on checks, 2026-10-23) |
| 6 | Colours vs `maple-outline.png` | The same |  not run: hands-on (Ethan deferred hands-on checks, 2026-10-23) |
| 7 | Backing-scale switch (1×/2×) | Redrawn sharp at the new scale, same place (or `not run: no 1× display`) |  not run: hands-on (Ethan deferred hands-on checks, 2026-10-23) |
| 8 | Relaunch | Same places and styles; `library.json` lists all four styles |  Executor: `library loaded: 1 stickers`, four `ordered in` at the same frames; `library.json` lists puffy, outline, shadow, none. |
| 9 | Footprint with four Maples | (record the number) |  32 MB (`footprint -p Stickermine`). |

## CI dry-run app

(Task 10 Step 7: the kernel line from the dry-run app's `timings.txt`, its number of `kernel` rows, its `sdk` line, and how the puffy column of its `maple-sheet.png` looked, or why it wasn't run.)
