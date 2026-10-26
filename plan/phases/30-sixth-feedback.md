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

### Lane G

- **What an app gets (item 8).** macOS sends no scroll event for three fingers. AppKit's `swipe(with:)` needs
  Trackpad ▸ Swipe between pages on three fingers (TrackpadKit's lab saw none on macOS 26), and
  `NSGestureRecognizer` never sees the trackpad. What works is the trackpad's raw touches (`NSTouch`), which a
  window gets once a view in it takes indirect touches. The system's three-finger gestures win when they are on, so
  the swipes need: Swipe between full-screen apps, Mission Control and App Exposé on four fingers or off, and no
  three-finger drag. The user's Mac already has that (read only with `defaults read`:
  `TrackpadThreeFingerHorizSwipeGesture` 0, `…VertSwipeGesture` 0, `…ThreeFingerDrag` 0, the four-finger ones 2).
  Nothing in the UI mentions it. Spike: `/tmp/touchspike/main.swift` (compiled, not run: a hand on a trackpad and
  the GUI are needed) prints every gesture, swipe and scroll event a window gets.
- **⌥ + swipe (the user's decision).** `SwipeRouter` locks ⌥ when a gesture begins (`.mayBegin`/`.began`) and then
  takes every event of it and its momentum, so no terminal scrolls. Sideways it drives the window's sidebar pages
  from anywhere (the same follow-the-fingers paging and session spring); with the sidebar hidden or in the overview
  it steps one session (`WindowPages.step`, now also used by ⌥⌘[ ] and the sidebar's wheel step). Up or down it
  steps one workspace (`Page.stepWorkspace`, as ⌃⌘[ ]). A ⌥ wheel steps once per burst (0.3 s apart). Under a
  panel, in a floating pane's window or a sheet, a ⌥ swipe steps nothing.
- **Three fingers.** `ThreeFingers` (pure, 40 lines): three fingers down 60 ms that moved 20 pt (trackpad points)
  mostly one way (2:1) give one step; four fingers or a cancelled touch give none until every finger lifts.
  Fingers left = next session, up = next workspace, as the system's swipes. `WindowReader` puts indirect touches on
  the window's frame view: SwiftUI's hosting view overrides `touchesBegan` (checked at run time) and replaces
  `.direct`, so it stays out. A `.gesture` monitor reads `allTouches()`. Not tried on hardware.
- **Tests.** `testOptionSwipesMoveBetweenSessionsAndWorkspaces`: a ⌥ trackpad swipe over a card moves sessions
  either way and never pages the strip; ⌥ up and down change the workspace and back; a ⌥ wheel (XCUITest's
  `perform(withKeyModifiers:)`) changes it; with the sidebar hidden a ⌥ swipe steps the session.
  `scripts/swipe.swift` takes a 7th argument for ⌥. `scripts/three-fingers-check.swift` (in `make test`) checks
  the recognizer: no trackpad on CI, and XCUITest cannot post touches.
- **Reviews.** Ponytail: one session step in `WindowPages` (was three copies), `take(Step)` instead of a Bool,
  a shorter doc: fixed. Spec: a hidden-sidebar test and docs wording (swipe begun with ⌥; the unverified claim
  about system gestures softened; D35 and platform.mdx): fixed. Not done: a 20 pt wait before a ⌥ step (a ⌥ gesture
  steps at 4 pt, as any gesture picks its axis); a floating window's ⌥ swipe stepping its main window.
- **CI.** 40273976883 (the ⌥ test and the two swipe tests on 86687aa, green). Full suite 40274997505 on d9f037d:
  lane G's and every swipe test green (`testOptionSwipesMoveBetweenSessionsAndWorkspaces`,
  `testSwipesPageTheSidebarAndTheStripApart`, `testSessionSwipeFollowsTheFingersAndSlidesOnFromTheirSpeed`); 19 red
  in other lanes' areas: 17 on "titlebar.sidebar: multiple matching elements" (the title row kept laid out under
  the overview since 30f8074, lane V), `testACardNeverShowsTheOverviewsSmallSnapshot` and
  `testDroppingAFileFromFinderPastesItsPath`.
- **For the user to check by hand:** ⌥ + two-finger swipe over a card, sideways (sessions, with the sidebar shown
  and hidden) and up/down (workspaces), one step a gesture, the terminal not scrolling; ⌥ + mouse wheel; plain
  two-finger scrolling in a terminal and on the strip still the same; a three-finger swipe sideways and up/down
  (once each per gesture); a four-finger swipe still switches Spaces and steps nothing in Oriel.

### Lane R (item 7: Connect shows progress)

- **Root cause.** A click on Connect ran `HostStore.connect(in:)` (the asking ssh start, then a refresh) but changed
  nothing the page reads: the state stayed `.failed(.disconnected)`, so the Disconnected page and its button stayed
  until the first snapshot. On Add Remote Host the run loop's BatchMode start failed first ("Host key verification
  failed"), so the new window showed Disconnected behind the question too. A failed connect also awaited the
  notice's 4 s before its refresh.
- **Fix.** `connect` sets the state to `.connecting` (only from a failed state, never from live) and a
  `connecting` flag. Errors from the client are dropped while it runs, and also when they came before the click and
  their session list waited for the start (`connects`, a count). The refresh comes right after the start, so its
  read ends Connecting: live, not installed, not running, or Disconnected again after a Cancel or failed passwords.
  Detail hides the loader while `pages.question` is up, and shows it again 0.3 s after the answer (the usual delay).
  A second click joins the first. A failed start that blocks (`.disconnected`) shows no notice: the page says it.
- **Accepted.** A start that asks has no time limit (a 2FA push can wait a minute after its answer), so a login
  that hangs without asking shows Connecting until ssh gives up (machines.mdx). On CI the question comes within
  0.3 s, so the loader before the question never shows there; the test checks that Disconnected goes at the click.
- **Test.** `testAPasswordHostAsksAndNeverRetriesByItself`: no loader while the host key and password questions are
  up; Connecting after the password, on Add and on Connect; Disconnected gone from the click. `scripts/ci-sshd.sh`
  gives oriel-pw a `.zshrc` that sleeps 2 s (only `-lic`, the herdr lookup, reads it), like a slow dev machine's
  login shell, so the loader after the answer lasts long enough to see.
- **Also.** HostStore was at its 400-line limit: the session server start moved to HostModels.swift (8e66b4c).
- **Review (one round, spec).** No blocker. Fixed: two quick Connects (1), comments (3, 4), the doubled "Canceled"
  (5), one Detail case (6), a test check (7), `mkdir -p` in ci-sshd.sh (8), docs (9). Kept: 2, see Accepted.
- **Commits.** 8e66b4c, 27bfda4, 64b158f. **CI.** 40273281796 (27bfda4, the four remote tests): green.
  Full suite 40273771915 (64b158f): green after `--failed` rerun on the same
  commit. The first attempt had two red tests outside lane R, both green on the rerun:
  testGoToDirectoryAndInsertPath, and HerdrKit's "relay carries runs over one process" (`exit().status == 9`), so
  both look flaky. All 9 remote tests ran on CI's sshd and were green; testAPasswordHost… took 31.8 s (the 2 s
  login shell, twice).
