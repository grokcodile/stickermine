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
| 1 | Unplug the external display | Unplug its cable. | Its Maple vanishes and does not stay on the remaining display (a flash of under half a second while macOS rearranges windows is tolerable; write it down if seen). Log: `display <UUID> removed; its stickers are ordered out` (Core Graphics callback) or, if that callback didn't fire, `ordered out <id>: display <UUID> is gone`; then a `reconcile #n` line within about 0.5 s. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 2 | Replug it | Plug the same cable back into the same port. | The Maple returns. Log: `ordered in <id> at …` with its setup frame. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 3 | Replug on another port | Unplug, then plug into a different port. | Same as row 2 (the display UUID is expected to stay the same; if the Maple doesn't return, note the new UUID from `reconcile` and `library.json`). | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 4 | Lid closed (MacBook with external display, keyboard and mouse) | Close the lid; wait 10 s; open it. | While closed: the built-in display's Maple is ordered out; the external one doesn't move. After opening: the built-in Maple is back with its setup frame. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 5 | Sleep and wake | Apple menu › Sleep; wait 30 s; wake and unlock. | Both Maples drawn at their setup frames. A desktop icon under a Maple's opaque pixels can't be clicked (she still absorbs clicks). Log: a `reconcile` shortly after wake and another about 1.5 s later; with the rebuild switch on, new `ordered in` lines about 1.5 s after wake. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 6 | Lock and unlock | ⌃⌘Q; wait 10 s; unlock. | Same as row 5. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 7 | Resolution change | System Settings › Displays: pick another "Larger Text / More Space" option for the main display; then restore the original. | While changed: the main display's Maple stays on that display at the same relative position, scaled with the display and fully on screen (a `reconcile` line with at least `1 changed`; no `ordered in` line, except that with the rebuild switch on every Maple is recreated about 1.5 s later and logs one). After restoring: back at the setup frame. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 8 | Mirroring on | Displays: mirror one display onto the other. | Only the mirror primary's own Maple shows (on both panels); the other Maple is ordered out; nothing lands on the wrong display. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 9 | Mirroring off | Stop mirroring. | Both Maples at their setup frames. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 10 | Arrangement change | Displays › Arrange: drag the external display to the other side; then put it back. | Each Maple stays on its own display at the same spot on that display (its global frame origin changes with the arrangement, its place on the display doesn't). | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 11 | Main display change | Displays › Arrange: drag the menu bar onto the external display; then back. | Same as row 10. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 12 | Display powered off | Turn the external display off with its power button (or let it sleep); wait 1 min; turn it on. | While off: its Maple either stays put (a sleeping display still counts as connected) or is ordered out as in row 1, and nothing moves to the remaining display; no flood of log lines (one `reconcile` per burst of events) and Activity Monitor shows Stickermine near 0 % CPU. After: the Maple is at its setup frame. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |
| 13 | Library untouched | After all rows: `shasum "$LIB/library.json"`. | The baseline hash. | not run: hands-on checks deferred by Ethan (2026-10-23); run before release | |

## Outcome

Fill in after the run: which rows failed (if any), what was fixed, and the commits that fixed them.

Not run yet (2026-10-23): Ethan deferred the hands-on checks; every row is to be run before release. Until then, `StickerManagerTests` with `FakeScreens` covers part of what these rows exercise: displays disappearing and returning, no usable display, a resolution change borrowing the closest size, the Core Graphics remove callback, and that none of it writes the library. Not covered by unit tests: mirroring (only `DisplayRegistryTests` filters mirror secondaries), the stacking order after a reconnect, and switching a resolution back; those rest on the hardware rows.
