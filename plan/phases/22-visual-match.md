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
