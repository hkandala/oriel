# Phase 22: Visual match with Rex

Goal: the shared parts of the window look like Rex's in size, spacing and finish, in light and dark,
Glass and Classic. The user found the tab bar, the pane cards (glass), the sidebar and the traffic
lights "a bit off". This phase compares Rex and Oriel side by side and closes the gaps. It changes looks
only: no new features, no new settings.

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
   `docs/content/docs/ui/window.mdx` (sizes and the title row height) and
   decisions D42 / D44 where values change.

## Findings

### Deviations

- **Classic dark keeps phase 10's keyboard card** (orchestrator): Rex's `classic-untinted.jpg` shows no difference
  between the keyboard card and the others (both `#222`, no visible stroke); Oriel keeps the darker fill and the
  0.8 pt stroke, which the fade backs up.
- **Classic light has no card shadow**, as Rex's System light material (phase 10 had a faint one).
- **No Rex picture for Classic light, working dots or ×**: compared with Rex's material file and the recovered
  constants (rex-internals §5.1) instead.
- **The header glyph differs in art, not size**: Rex draws `>_` for shells; the icon catalog (phase 12) gives
  zsh a filled terminal window. Same 11.5 pt box; left as the catalog's.
- **The tab slot lines up with the cards, the capsule sits 2 pt inside it**, as Rex's capsule sits in its track;
  with one tab or in Classic dark (no track) the visible pill starts 2 pt right of the cards.
- **The find bar's buttons got the header's 11 pt regular glyphs too**: both are 22 pt `IconButton`s, and the find
  bar is a pane control like the header's.
- **The lifted card snapshots what shows**: a card partly scrolled out of the strip or under the sidebar lifts with
  that part blank or with the sidebar's pixels (the header snapshot had the same limit).
- **Agents button icon** (user, during the phase): `list.bullet.rectangle`, filled while the Agents view is on.
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
  row, `Look.divider` white 0.17 / black 0.14 (Rex), `Look.paneButton` for card header buttons, `Look.track`.
- **The light card shadow is drawn on an opaque copy cut out under the card** (`destinationOut`): on the
  translucent fill it was as faint as the fill (phase 10's note).
- **Program icons moved to `ProgramIcons.swift`**: Style.swift passed SwiftLint's 400 lines; the tiles draw the
  catalog's colors, so `look_colors` excludes that file too.
