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

## Lane P, also: Move Pane to Tab out of the menu bar (item 11)

11. The user agreed: drop Move Pane to Tab's tab list from the menu bar (View ▸ Pane), since AppKit's
    key-equivalent search over it costs about 30 ms per key at 300 tabs (phase 29 lane S). Keep the list in
    the card's own menus (header and right-click, built when opened) and in the palette's Move Pane to Tab
    page. Measure the key latency at 300 tabs before and after (scripts/stress.py).

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each lane's
  last code commit; one review round per lane (spec and ponytail, read only).

## Findings
