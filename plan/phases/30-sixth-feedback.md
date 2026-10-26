# Phase 30: The user's sixth round of feedback

The user sent two Scrawl captures and notes on 2026-10-25 (about 22:00), testing a remote machine with many
workspaces and tabs, in two windows. Read the captures with the scrawl skill
(`/Users/hkandala/.agents/skills/scrawl/SKILL.md`; `scrawl zoom "<bundle>" --at M:SS --span S --frames N`):

- A: `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1792990648853-6f5d-2.scrawl`
- B: `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1792990838464-6f5d-5.scrawl`

Each lane writes `## Findings` at the end. `/tmp/oriel-gui.lock` is held for "user"; UI tests run on CI
until the orchestrator says otherwise. Read-only probes of the user's running Oriel (`footprint`,
`vmmap --summary`, `top`, a few seconds of `sample`) are allowed.

## Lane W: the strip lags the sidebar on a session swipe (item 1)

1. A #1 (0:01)–#2 (0:34): on a session swipe in a big remote session, "this tab flickers, it still moves
   around". In A at 0:12.1–0:12.5 the sidebar already shows the new session while the strip and tab bar
   still show the old session's cards; they change about 0.4–0.8 s later. Find what delays the strip and
   tab bar (the new page's first layout, its terminals' streams over the SSH relay, the snapshot, the strip
   made new per page) and make the strip, tab bar and sidebar change together; show the old picture or a
   still until the new cards draw, never the old session's cards beside the new sidebar.

## Lane V: overview (items 2–5)

2. A #3 (0:50), #4 (1:00): while previews load (tiles that show nothing yet), show a loader in the tile.
3. A #5 (1:10): on scroll, tile text blurs and then sharpens (the 360 px snapshot, then the live surface).
   Make snapshots sharp enough at the tile's size on Retina (snapshot at the tile's pixel size) so going
   live is not visible.
4. B #1 (0:13)–#4 (0:45): after zooming into a tab, the sidebar and tab bar pop in abruptly, a moment after
   the zoom (more with many tabs). Fade them in, and find why they come late with many tabs.
5. B #5 (0:47)–#6 (1:23): overview scrolling still drops frames, the animation is jagged. Profile a local
   Release build (when the GUI is free; Instruments Animation Hitches / Time Profiler) and remove the
   main-thread and commit costs per frame.

12. (Lane V, 22:35) **No blurred pane in the normal view.** The user sees a pane show blurred for a moment and
    then sharpen in the normal view too, not only in the overview: likely the overview's small snapshot
    (or another downscaled picture) shown as a card's still. Rule: a card in the strip or a floating window
    never shows a picture smaller than its own pixel size. A sharp full-size still (phase 27 lane A3) may
    show; when only a small one exists, the card shows nothing and fades in (phase 29 lane T's 0.06 s) when
    its terminal draws. In the overview, item 3's sharp snapshots apply.

## Lane P: memory and CPU in the user's real setup (item 6)

6. B #5: the user has two windows open on a remote machine with many workspaces and tabs. Measure the
   running app read-only (footprint, IOSurface, herdr runs, idle CPU, `sample` of the main thread) and
   find the bottlenecks; then reproduce them with `scripts/stress.py` and fix what costs too much. Also
   check the 15.4 GB peak footprint lane S saw in the user's earlier build (was it the overview leak lane V
   fixed, or something else?). Before/after numbers in the Findings.

## Lane R: Connect shows progress (item 7)

7. Clicking Connect on a remote machine gives no feedback until the session opens. Show a loader (the
   page's connecting state) from the click until ssh asks its question, and again after the answer until
   the session opens; the question sheet replaces the loader while it is up.

## Lane G: three-finger swipes (item 8)

8. The user asks for three-finger horizontal swipes to move between sessions and three-finger vertical
   swipes to move between workspaces (two-finger horizontal scroll moves between tabs). macOS reserves
   three-finger swipes for system gestures by default (Mission Control, App Exposé, swipe between full-screen
   apps, or "swipe between pages" when set to three fingers). Find what an app can receive (`swipe(with:)`,
   `NSTouch` with `allowedTouchTypes = .indirect`, gesture recognizers) with the default settings and with
   those system gestures turned off, spike it, and build what works without breaking two-finger scrolling.
   If it only works with a system setting changed, say which, and show nothing in the UI about it (no hint
   text); the orchestrator tells the user.

   **Decision (user, 22:30): ⌥ + swipe is the main way.** Holding ⌥ (Option) and swiping with two fingers
   (or a mouse wheel) moves between sessions horizontally and between workspaces vertically, anywhere in
   the window (over cards too), one step per gesture with the session spring / a workspace switch, and
   never scrolls the terminal while ⌥ is held. It mirrors the layout (sessions side by side, workspaces in a
   vertical list) and the keys (⌥ is the session level). ⌃ + scroll is out (macOS screen zoom), ⇧ + scroll
   is out (macOS turns it into horizontal scroll), ⌘ + scroll stays free. Three-finger swipes stay an extra
   only if an app can receive them with the user's settings; report what you find.

## Lane D: a tab dropped on New Workspace (item 9)

9. Dragging a pane over the sidebar offers a New Workspace drop row; dragging a tab does not (phase 29
   lane D refused it: "not asked"). Offer the same New Workspace row for a tab, and dropping there moves the
   whole tab (terminals, split tree, ratios, label) into a new workspace: the first pane with
   `pane.move {new_workspace}`, then the others as phase 29 lane D's `move(tab:to:)` does. Same in the
   collapsed sidebar's workspace menu.

## Lane Q: quick ⌘D rearranges the panes (item 10)

10. Capture C: `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1792991374332-6f5d-8.scrawl`.
    In a new tab the user presses ⌘D three times fast (events at 8.7, 9.0 and 9.2 s, again at 22.7 s, and
    ⌘W three times at 19.1–19.5 s): the panes rearrange with an odd animation, "that kind of flicker". Find
    why (likely phase 29 lane K's stand-ins placed in one order and herdr's real panes arriving in another,
    or phase 27's slide-in animating a pane from the wrong place) and make quick splits and closes settle
    straight into their final layout: each new pane appears once, where it ends up, with no pane moving
    twice.

## Lane N: the Agents button's panel shows finished agents (item 13)

13. Hovering the Agents button shows only agents that need the user (blocked). It also lists agents that
    finished (the "done" state that stays until its row is clicked, phase 15), so the user can look at what
    happened: two groups, needs-you first, then done, each with the group labels the Agents view uses; a
    click goes to the pane and clears its done state as today. The panel still shows nothing when both
    groups are empty. The button's badge and the Dock badge keep counting only needs-you, unless they
    already count done.

## Lane P, also: Move Pane to Tab out of the menu bar (item 11)

11. The user agreed: drop Move Pane to Tab's tab list from the menu bar (View ▸ Pane), since AppKit's
    key-equivalent search over it costs about 30 ms per key at 300 tabs (phase 29 lane S). Keep the list in
    the card's own menus (header and right-click, built when opened) and in the palette's Move Pane to Tab
    page. Measure the key latency at 300 tabs before and after (scripts/stress.py).

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each lane's
  last code commit; one review round per lane (spec and ponytail, read only).

## Findings

### Lane D

- **Root cause.** Phase 29 refused a tab on New Workspace on purpose ("not asked"): `RowsDrop` showed the ghost row
  only for a pane, `PaneDrop` took a tab only for `.newTab`, and the workspace menu's New Workspace row had no drop.
- **Build.** `HostStore.move(tab:to:)` takes a nil workspace for a new one: the first pane goes with `pane.move
  {new_workspace, tab_label}` (`Destination.newWorkspace(tabLabel:)`, null when none), the rest as before
  (`SplitNode.rebuild`). `RowsDrop`'s ghost row, the header `+` (`PaneDrop`) and the menu's New Workspace row
  (`MenuRowDrop.Target` now holds a `Destination`) take a tab; the page follows it as for a row.
- **Decisions.** The new workspace keeps herdr's name (the first pane's folder), as a pane's move does; the tab keeps
  its label. A tab alone in its workspace is taken too, as a lone pane is (its workspace comes back last, named after
  the folder). The menu's New Workspace and Open Session rows now sit under the scrolled list (`FilterList.pinned`):
  with many workspaces New Workspace was below the fold, and by phase 29's macOS 27 rule a row not built as the drag
  starts never takes a drop. Workspace rows out of view still do not (a known limit).
- **Learned (spike).** `pane.move {new_workspace}` with no `label` names the workspace after the pane's folder;
  `tab_label` names its tab.
- **Test.** `testDraggingATabOntoNewWorkspaceMovesItWithItsLayout`: phase 29's 3-pane tab (0.3 / 0.7, labelled), held
  over the collapsed sidebar's workspace button and dropped on the menu's New Workspace: the same tree by terminal,
  ratios and label in a new workspace, selected, keyboard kept; then onto the sidebar's empty space: another new
  workspace, the first one closed. The header `+` with a tab is not driven (the same `PaneDrop` case as the menu row).
  Its setup is `movingTab()`, shared with phase 29's test.
- **Review.** Spec: the doc table row had 4 cells (fixed); New Workspace below the menu's fold (pinned, above); nits
  taken: the `+` comment, these Findings. Not taken: a `+` leg in the test, an `underRows()` helper (two uses).
- **Commits.** 48bc723 (the drop, test, docs), 00f1c04 (New Workspace kept in view, review fixes).
- **CI.** 40273349296 (the drag tests on 48bc723, green). Full suite 40274069052 on 127bf21 (has 00f1c04): green.
- **Check by hand.** With many workspaces, collapse the sidebar, hold a tab over the workspace button and drop it on
  New Workspace; the menu's New Workspace and Open Session rows now stay under the list when it scrolls.
