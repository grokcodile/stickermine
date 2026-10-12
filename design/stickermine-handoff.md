# Stickermine: handoff brief for the Claude Code project

Source of truth for design: the "Stickermine Logo Options" design artifact (boards: `Main.dc.html` pickaxe icon, `Site.dc.html` website). Everything below is what was decided there plus the product decisions from earlier chats.

## 1. What it is

A Mac app. Screenshot something, the app cuts out the subject, you pick a sticker style, and the sticker is stuck live on the desktop (a real floating object, not baked into the wallpaper).

**Tagline (final):** "Turn quick screenshots into fun stickers that live on your desktop."

**Images and isolated subjects only. No text stickers.** Logos are treated like any other image.

## 2. Product decisions

**Capture flow**
- Screenshot, subject detected, background removed, style applied, sticker attaches to the cursor, click to place.
- Default capture shortcut: control-option-command-S, rebindable in settings. (Holding S was considered and dropped.)

**Styles**
- Each sticker has its own style. There is no global style.
- Style options: puffy, thick white outline with shadow, none, shadow only.
- Later ideas, not v1: B/W, retro, holidays, seasons. No automatic seasonal changes (feels gimmicky, changes without consent).

**Sticker behavior**
- Principle: stickers stay exactly as the user left them until they move, restyle or remove them. Keep it as simple as a physical sticker.
- Pinned at desktop level by default. Active stickers get a per-sticker "float on top" button.
- Double-click makes a sticker active, showing a move icon and a remove icon.
- Resizable, rotatable, flippable.
- Spaces: one shared set is fine for v1. Per-Space stickers are wanted as a later option.
- Stage Manager: unknown whether it works. Needs testing.
- Stickers hide during screen sharing (wanted).

**Displays**
- Stickers live on the display where they were placed.
- Layout is remembered per display. If a known display's size changes, use the closest match. User edits update the layout.
- A new unseen display starts empty.
- Stickers on a disconnected display are hidden until it returns, with no indicator.

**App presence**
- Double-clicking the app icon opens the sticker history window, which also holds settings and Quit.
- Menu bar icon: starts a new capture. Drawn as a solid one-color sticker-silhouette glyph (white or black to match the menu bar, template image).
- The menu bar icon can be hidden. The app still works through the shortcut.

**First run**
- Ships with tutorial stickers the user can read and delete.

**Later (not v1):** history browser, saving layouts or groups, more filters.

## 3. Business model

- Free, open source, no subscription. After the user has placed a few stickers, show a gentle, skippable ask to support the developer. Fully free if they decline, and never nag again after "Maybe later".
- Tips go to Ko-fi: https://ko-fi.com/grokcodile
- The website shows this as the last footer sticker: "☕️ Buy me a coffee".

## 4. Technical starting points (to verify, not decided)

- **Subject cutout:** prefer the system's on-device subject lifting (Vision foreground instance mask, macOS 14+) over shipping a model. This matches the "use what macOS already has" approach from Pullcord and Key54.
- **Capture:** ScreenCaptureKit or the system screenshot path. Decide in the spike.
- **The risky part is the live sticker window:** borderless, non-activating, click-through where transparent, desktop level, correct behavior across Spaces and display changes, and hidden during screen sharing.
- **Suggested first spike:** a sticker window that floats at desktop level, can be dragged, and survives Spaces and display changes. If that feels good, everything else is polish. Prototype this before any capture UI.
- **Minimum macOS:** the site mock says "macOS 14+" as a placeholder. Confirm the real minimum once the Vision API choice is made.

## 5. Project setup (mirror Pullcord and Key54)

Follow the same conventions as his other apps. Items marked "confirm" are assumptions from the Pullcord/Liteswitch setup and should be checked against that repo:
- Swift, no third-party dependencies if possible (confirm).
- MIT license, open source on GitHub under `grokcodile/` (repo name to match the final app name).
- `build.sh`, `install.sh`, `notarize.sh` pipeline: Developer ID Application signing, hardened runtime, trusted timestamp, notarization and stapling (confirm).
- Distributed via GitHub Releases and a Homebrew cask (`brew install --cask stickermine`). The cask doesn't exist until the first release, so keep that line on the site as a placeholder until then.
- Landing page in `docs/`, hosted on GitHub Pages (confirm; the Liteswitch repo used `docs/`).
- README states the design philosophy. For consistency with his other apps: the app should get smaller as macOS gets better.

**Name and domain**
- Name: Stickermine. stickermine.app was available (about $15 first year, $27 renewal). Verify before relying on it.
- Footer links (Privacy, Contact, etc.) point to `.md` files on GitHub, not separate pages. Suggested files: `PRIVACY.md`, `CONTACT.md` in the repo root. Replace the `#` placeholders.

## 6. Website spec

One static page. Canvas background, and every element is a sticker. Mock file: `Site.dc.html`.

**Elements, top to bottom, left column**
1. Icon tile (128px, blue, white 8px border, rotated -4°) next to the "Stickermine" h1.
2. Description sticker (mint).
3. Download pill (blue) with a small line "v1.0 · 12 MB · macOS 14+ · Free" (all placeholders).
4. Homebrew sticker (dark, monospace `brew install --cask stickermine`, with a copy button that swaps to a checkmark).

**Right column**
- Demo video sticker: a white card with a 16:10 video area, with its bottom-right corner peeled up at 45°. Placeholder text: "[DEMO VIDEO · about 10 sec loop: capture, style, stick]". The loop is capture, style, stick.

**Bottom right, fixed to the viewport**
- Maple the dog sticker (`dog.png`, 620×910 cutout with white die-cut border), partly below the fold, rotated 3°.
- On hover, a pink speech-bubble sticker comes up from her mouth: "Make your desktop make you smile!" (white Fredoka 500, 18px).
- Respect `prefers-reduced-motion`.

**Footer (left aligned):** pill stickers "© Stickermine", "GitHub", "Privacy", "Contact", then a yellow "☕️ Buy me a coffee" pill linking to Ko-fi.

**Open placeholders to fill in**
- Real version, size, macOS requirement
- Download link, Homebrew cask (after release)
- Demo video
- GitHub, Privacy, Contact links
- Open Graph image and favicon (use the pickaxe icon)

## 7. Design tokens

**Colors**
| Role | Hex |
|---|---|
| Page background | `#F3F0E8` |
| Ink / dark sticker | `#1F2340` |
| Blue (icon tile, Download, h1) | `#3D4BE0` |
| Mint (description) | `#8FE3BE` |
| Pink (Maple's bubble) | `#FF4F81` |
| Yellow (coffee) | `#FFD84D` |
| Sticker border | `#FFFFFF` |

**Type:** Fredoka (Google Fonts, weights 300 to 600). H1 is 80px, weight 600, blue, with a 16px white text stroke painted under the fill (`paint-order: stroke fill`) and a soft drop shadow. Mono for the brew line (`ui-monospace, Menlo`).

**Sticker rules**
- White border: 8px on pills and tiles, 10px on the description card.
- Large radius (pills up to 44px, cards 36px).
- Soft shadow: `0 10px 24px rgba(31,35,64,0.22)`.
- Each sticker is rotated slightly, between -4° and +3°. Don't line things up perfectly.
- Interactive stickers brighten slightly on hover.
- The page never uses tooltips (removed on purpose).

**Icon (pickaxe)**
- macOS icon tile `#3D4BE0`, corner radius about 22.6% of the tile.
- Pickaxe with a fat white sticker outline (20px stroke at 200 units), centered, filling about 82% of the tile.
- Wooden handle `#E8963A` (highlight `#F6B76B`), steel head `#D3DCE5` with `#7B8794` outline, dark block `#5B6572` and `#434B57`.
- Rejected directions, don't revisit: mine cart (too childish), mining hat, peeling-sticker icon.

## 8. Assets to carry over

- `dog.png` (Maple cutout). Download it from the design artifact's files.
- Pickaxe SVG symbol: see `Main.dc.html` in the design artifact (`#pick`, plus the monochrome `#pickmono` for the menu bar glyph).
- `Site.dc.html` as the reference for the layout and CSS. It uses a design-tool wrapper (`x-dc`), so port the HTML and CSS to a plain page rather than copying it verbatim.
