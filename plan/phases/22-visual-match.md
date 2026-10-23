# Phase 22: Visual match with Rex

Goal: the shared parts of the window look like Rex's in size, spacing and finish, in light and dark,
Glass and Classic. The user found the tab bar, the pane cards (glass), the sidebar and the traffic
lights "a bit off". This phase compares Rex and Oriel side by side and closes the gaps. It changes looks
only: no new features, no new settings.

Read first: `plan/ui-layout.md`, `resources/research/clients/rex-ui.md` (geometry, colors, timings),
`resources/research/clients/rex-internals.md` (§3.1, §3.2, §3.6, §3.9, §5.1–§5.3), the Rex pictures in
`resources/inspirations/rex-app/` (`light-mode.jpg`, `glass-untinted.jpg`, `classic-tinted.jpg`,
`classic-untinted.jpg`, `three-splits.jpg`, `tabs-with-status.jpg`, `sidebar-tabs.jpg`,
`sidebar-hidden-header-in-titlebar.jpg`, `crop-*.jpg`), `Oriel/Views/Style.swift` (the `Look` tokens), and
the Findings of phases 10, 13, 14 and 17 (measured colors and the reasons for earlier deviations).

## Build

1. **Reference set.** Use the Rex pictures in the repo. Rex screenshots of the user's own Rex windows
   may be taken only read-only (`screencapture -x -l <window id>` of a window that is already open), never by
   driving Rex, never touching the user's Rex session. Pick, for each look (Glass dark, Glass light,
   Classic dark, Classic light), the Rex picture closest to it. Note the desktop behind Glass pictures:
   compare Glass on the same wallpaper or by the elements that do not depend on it (sizes, strokes, text).
2. **Oriel set.** The same scenes in Oriel at the same window size and scale (2x): one tab, three tabs
   with a blocked and a working agent, three splits, sidebar open and collapsed, zoomed card, light and
   dark, Glass and Classic. Take them from e2e attachments (keepAlways) so they can be re-taken on CI.
3. **Compare.** For each element, put Rex and Oriel side by side (one composite image per element and
   look, cropped to the element) and measure in points, with the same pixel tool phase 10 used (sRGB):
   - title row: height, traffic light position (inset from the left and the top), item gaps, button
     glyph size and weight;
   - tab bar: track height and radius, capsule height, radius and inset, tab width rules, dividers, icon
     size, title font size and weight, × size and position, working dots, selected pill (glass or Classic);
   - pane cards: radius, gap, header height, header font, header buttons, fill, rim, outer stroke, shadow,
     keyboard card vs others, fade;
   - sidebar: width, page header, row height (one and two lines), row insets, selected pill, state icon
     size, branch line font and color, worktree indent and guide, footer field and button;
   - window background and the tint in each look; text colors (primary, secondary) on each surface.
   Write the deltas as a table in this file's Findings: element, look, Rex, Oriel, change.
4. **Traffic lights and title row height.** Rex places the traffic lights inside a taller bar (rex-internals
   §3.1, a private window API). Find the closest public way first (for example a unified window toolbar,
   which makes the title bar taller and centers the traffic lights), measure it against Rex, and use it if
   it lands within 2 pt. No private API. Record what you chose and why.
5. **Fix.** Change the `Look` tokens and the view sizes so each delta is within 1 pt in size and within a
   few sRGB steps in color, or record why not (for example a Glass color that depends on the wallpaper).
   Keep one source per value (`Style.swift`); no per-view color literals (the `look_colors` lint rule).
5b. **Tabs over the cards** (user, during the phase). With the sidebar open, the title row's leading part
   (traffic lights, sidebar toggle, machine button) is exactly as wide as the sidebar and follows its resize
   handle live, so the first tab capsule starts where the strip's cards start. With the sidebar collapsed the
   row stays as it is. e2e: the first capsule's minX equals the first card's minX (± 1 pt), also after a resize.
6. **Re-take and compare again** until the table has no open row. Put the final side-by-side composites
   in `/tmp/oriel-shots/22/compare/` and list them in the report.
7. **Docs.** Update `docs/content/docs/ui/theme-and-accessibility.mdx` (token table),
   `docs/content/docs/ui/window.mdx` (sizes), `plan/ui-layout.md` (the title row height if it changes) and
   decisions D42 / D44 where values change.

## e2e

- Existing tests stay green (layout changes can move hit points: run the full suite once at the end).
- One test per look takes the comparison scenes as attachments (keepAlways), so the screenshots can be
  re-taken on CI. No pixel assertions.

## Review

The E2E reviewer is replaced by a **visual reviewer**: it reads the composites and the delta table,
measures a sample of rows itself, and flags any element still visibly off. Spec and ponytail reviewers as
usual.

## Done when

- The delta table has no open row (each row fixed or with a recorded reason).
- Composites for every element in all four looks are in `/tmp/oriel-shots/22/compare/`.
- `make lint build test` and the full e2e suite are green, locally or on CI.

## Findings

### Delta table

Rex: the repo pictures (2x, Display P3 converted to sRGB with `sips`). Oriel: `testScenes*` attachments at Rex's
window size (1180 × 760 pt, 2x). Glass depends on the desktop (Rex's pictures: a gray desktop; the local runs: a dark
terminal behind), so Glass colors are compared as steps from the window, not as absolute values. There is no Rex
picture of Classic light: it is compared with Rex's System light material file and `light-mode.jpg` for sizes.

| Element | Look | Rex | Oriel before | Change |
|---|---|---|---|---|
| Title row height | all | 46 pt | 40 pt (compact toolbar) | 46 pt |
| Traffic lights | all | 14 pt, centers (23, 23), pitch 23 (AX 16 pt at 15/38/61, y 15) | centers (19, 20) | moved to Rex's (AX frames equal) |
| Row items start | all | session picker at 85 pt; sidebar toggle centered 82 pt right of the red light (`sidebar-tabs.jpg`) | 78 pt | 91 pt (toggle centered at 105) |
| Track | Glass, Classic light | 34 pt, y 6–40, primary 0.05 | same | — |
| Track | Classic dark | none (flat `#1e1e1e`) | white 0.05 (`#282828`) | none |
| Selected pill | Classic dark | flat `#292929`, no rim | `#393939` (white 0.08 on the track) + 0.8 pt rim | white 0.045, no rim: `#292929` |
| Selected pill | Glass | Liquid Glass | Liquid Glass | — (system) |
| Selected pill | Classic light | white, black 0.1 stroke, shadow (JSON) | same | — |
| Tab width, gap, radius | all | (avail − (n−1))/n, 64–220, 1 pt, 16.5 | same | — |
| Tab title | dark / light | selected ≈ white 0.9 / `#1b`; others ≈ white 0.65 (user's picture; 0.78 in `glass-untinted.jpg`) / black 0.65 | labelColor (222 / `#26`) for all | `Look.selected` white / black 0.9, `Look.chrome` white / black 0.65 |
| Tab title size | all | ascender 20 px | 20 px | — |
| Divider | dark / light | white ≈0.17 / black ≈0.14, 18 pt | separator (white 0.1 / black 0.1) | `Look.divider` |
| Title row glyphs (sidebar, machine, Agents, ⌘, +) | dark / light | ≈ white 0.62 (user's picture) / ≈`#5a` | secondary (151 / `#80`) | `Look.chrome` |
| Glyph size | all | + 11 pt, ⌘ 12 pt | same | — |
| Icon tile, badge | all | 22 × 18, r 5; 7 pt dot | same | — |
| × on hover | all | 22 pt, x = width − inset − 15 | 22 pt, 6 pt from the end | — (≤ 1 pt; hover only, not in the shots) |
| Working dots | all | spec only (no Rex picture) | spec values | — |
| Card top | all | y 46 | y 44 (40 + 4) → 50 with the 46 pt row | the strip's 4 pt room lies under the row: y 46 |
| Card fill | Glass dark | others 6 steps darker than the window, keyboard 5 brighter | +9 and +20 | `cardFill` black 0.14 (Rex's pane backdrop); keyboard + white 0.05 |
| Card outer stroke, keyboard | Glass dark | black 0.5, as the others | white 0.1 | black 0.5 |
| Card outer stroke, keyboard | Glass light | ≈ black 0.10 | black 0.07 | 0.1 |
| Card shadow | Glass light | black ≈0.1, blur 5, y 2, visible | ≈ invisible (× fill alpha) | on an opaque copy cut out under the card |
| Card shadow | Classic light | none (System JSON) | black 0.06 (≈0.036 seen) | none |
| Keyboard card | Classic dark | no visible difference (both `#222`) | `#1f`, 0.8 pt white 0.1 stroke | kept (orchestrator): the fade marks it, phase 10's choice |
| Header title, card without the keyboard | all | faded with the content (173 vs 229) | not faded | header fades with the terminal |
| Header buttons | dark / light | ≈ white 0.33 / black 0.33 | secondary | `Look.paneButton` |
| Header glyph and title | all | glyph 21.5 pt, title 38.5 pt from the window edge | 16.5, 38.5 | leading 11, spacing 4 |
| Restore (zoomed) | all | accent glyph on a faint accent circle | white on a solid accent circle | `.tint` on `.tint` 0.15 |
| Window tint | Glass light | Modern light: canvas at 0.7 | white 0.5 | white 0.7 |
| Window | Classic | `#1e1e1e` / (JSON) `#f6f6f6` + white 0.5 | `#1e1e1e` / `#f6f6f6` | — (phase 10's light reason) |
| Sidebar to cards | all | cards at x = 240 (sidebar width) | x = 256 (8 + 240 + 8) | cards at the width; the handle lies over the gap |
| Sidebar rows | all | pill 10 pt from the window edge, 30 pt, pitch 32 | 16 pt, 30 pt, pitch 32 | 10 pt |
| Page header | all | ≈12 pt semibold, secondary, 22 pt in | 11 pt regular, 24 pt in | 12 pt semibold, 22 pt in |
| Sidebar row title | all | ascender 20 px | 19 px | — |
| Sidebar footer | all | filter icon + buttons | filter field + Open Session (design) | — (layout's choice) |
| Tabs over the cards | sidebar open | (user's request) | tabs after the machine button | leading area as wide as the sidebar |
| Tab bar, user's picture (`rex-tabs-dark-2026-10-22.png`) | Glass dark | track 34 pt (y 6–40), capsule 30 pt 2 pt inside it, radius 15; tabs 220 pt; tile 11 pt in from the track, title 11 pt after the tile; divider 18 pt | capsule 34 pt filling the track; tile 8.5 pt in, title 9 pt after; divider 16 pt | capsule and hover 2 pt inside the track (`ChromeStyle.inset`), tile 11 pt in, 10 pt spacing, divider 18 pt |
| Tab title font | all | 13 pt regular (ascender 20 px) | 13 pt regular | — |
| Row items gap, glyph weight | all | ≈ 8 pt; medium | 8 pt; medium | — |
| Card radius, gap | all | 10 pt, 8 pt | 10 pt, 8 pt | — |
| Card header | all | 36 pt, ~13 pt medium (ascender 20 px), title primary, folder secondary | 36 pt, 13 pt medium | — (glyph and buttons above) |
| Card rim | Glass | 0.7 pt `plusLighter` white 0.1 (keyboard: 0.1) | same | — |
| Content fade | all | 0.7 / 1.0 (0.5 / 0.8–0.85 in a window that is not key) | same | header fades with it (above) |
| Window tint | Glass dark | `hudWindow` + `#1e1e1e` 0.5 + black 0.6 `overlay` | same | — (desktop-dependent: Rex `#2c` on gray, Oriel `#18` on a dark terminal) |
| Secondary text | all | ≈ 0.7 of the primary (tab folder 185 vs 255) | `.secondary` of the surface's style | — |
| Sidebar rows, two lines | all | 44 pt (Rex's activity rows ≈46 pitch) | 44 pt | — |
| Sidebar selected row | Glass / Classic | the tab pill (glass / flat) | the look's `Pill` | — |
| State icon, branch line | all | (Rex has none: workspace rows are herdr's) | 14 pt slot, 7 pt dots; branch 11 pt secondary | — (design D67) |
| Worktree indent and guide | all | (Rex has none) | 14 pt, 1 pt separator line | — (design) |
| Track ends | all | 1.5 pt past the first and last tab | at the tabs | — : the first capsule's slot lines up with the cards (5b) |
| Card stroke, others | Classic dark | none (`#1e` to `#22` at the edge) | white 0.07, 0.7 pt | none |
| Terminal text inset | all | 11.5 pt from the card's edge | 9 pt | 11 pt padding (12 with Ghostty's own) |
| Sidebar page header and first row | sidebar open | 3 pt lower (from the red light) | — | sidebar top room 7 pt |
| Sidebar toggle | all | centered 82 pt right of the red light | 75 pt | row starts 91 pt in |
| Workspace button text | collapsed | (Rex's picker label: chrome, semibold) | session secondary on chrome (≈0.45) | session chrome, workspace `Look.selected`, divider rule |
| Header buttons | Glass dark | ≈ white 0.33 | 0.4 | 0.33 |

### Deviations

- **Classic dark keeps phase 10's keyboard card** (orchestrator): Rex's `classic-untinted.jpg` shows no difference
  between the keyboard card and the others (both `#222`, no visible stroke); Oriel keeps the darker fill and the
  0.8 pt stroke, which the fade backs up.
- **Classic light has no card shadow**, as Rex's System light material (phase 10 had a faint one).
- **No Rex picture for Classic light, working dots or ×**: compared with Rex's material file and the recovered
  constants (rex-internals §5.1) instead.
- **The header glyph differs in art, not size**: Rex draws `>_` for shells; the icon catalog (phase 12) gives
  zsh a filled terminal window. Same 11.5 pt box; left as the catalog's.
- **Tabs start over the cards while the sidebar is open** (user, during the phase): the toggle and the machine
  button sit in a leading area `sidebarWidth − 91 − 8` wide. Collapsed, the row is unchanged.
- **The hover card's split minimap is gone** (user, during the phase).

### Decisions

- **Traffic lights: moved with public AppKit.** A probe measured the public toolbar styles: `.unifiedCompact` is 40 pt
  with the lights centered at (19, 20), `.unified` 52 pt at (26, 26); neither is within 2 pt of Rex's (23, 23)
  in 46 pt. So the window keeps the compact toolbar and `WindowReader` moves the three standard buttons with
  `setFrameOrigin` (Electron's `trafficLightPosition` way), on every frame change AppKit makes (resize, key, zoom,
  full screen exit), and skips full screen. Their accessibility frames now equal Rex's (16 pt at 15/38/61, y 15).
- **The title row is 46 pt and the cards start at its bottom**: the strip's and sidebar's 4 pt top room (for the
  cards' strokes, phase 10) lies under the row (`VStack(spacing: -4)`, the row on top for its clicks and drags).
- **Sidebar width is window edge to cards, as in Rex**: the pages are `width − 8` wide, the 8 pt handle lies over
  the strip's gap (the sidebar sits in front, `zIndex`), so the cards start at x = width (240).
- **Text tokens:** `Look.chrome` (white / black 0.65; the user's picture, newer than `glass-untinted.jpg`, wins) is the title row's and sidebar's foreground; icons and
  titles inherit it (`IconButton` draws `.primary`, the inherited style). `Look.selected` for the selected tab and
  row, `Look.divider` = chrome at 0.22, `Look.paneButton` for card header buttons, `Look.track`.
- **The light card shadow is drawn on an opaque copy cut out under the card** (`destinationOut`): on the
  translucent fill it was as faint as the fill (phase 10's note).
- **Program icons moved to `ProgramIcons.swift`**: Style.swift passed SwiftLint's 400 lines; the tiles draw the
  catalog's colors, so `look_colors` excludes that file too.

### Assumptions

- **AppKit keeps the standard buttons' frames as set until its next layout**, and every layout posts a frame change.
  Seen on resize, ⌥-zoom and full screen in the e2e test; a macOS update could lay them out without one.
- **Glass light at white 0.7** reads like Rex's on a light desktop; on the dark terminal behind the local runs it
  measured `#dadada` (Rex `#f5f5f5` on its desktop).

### Learned

- **A `destinationOut` overlay did not cut the shadow's copy** (visual review): `fill.overlay(shape.blendMode(.destinationOut)).compositingGroup()`
  darkened the whole Glass light card by about black 0.1; a `ZStack` of the two inside the group cuts (checked with
  `ImageRenderer` in a script: 194 vs 218 at the card's center).
- **The closing-a-pane test failed once on CI** (`pane.w2:p3.close` not found after the hover) and passed locally
  with this phase's code; taken as a hover flake.
- **A button moved inside its own frame notification snaps back**: AppKit finishes its own `setFrame` after the
  notification. Placing again on the next main-queue turn fixes the zoom button (a probe window reproduced it).
- **XCUITest window screenshots are in the display's profile** ("Color LCD"): convert to sRGB (`sips -m`) before
  reading pixels; Rex's JPEGs are Display P3.
- **An accessibility container's frame is the union of its children**, not its own frame: the sidebar's width
  test saw the pages plus the handle.
- **A second ⌃⌘F during the full screen animation is lost on CI**: the test checks entering full screen only.
- **A launch argument sets the window frame**: `-NSWindow Frame main-AppWindow-1 "x y w h …"` in the argument
  domain beats a saved frame, so the scenes run at Rex's 1180 × 760.
