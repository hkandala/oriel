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

### Lane P (items 6 and 11)

- **The user's Oriel, read only** (Release built 21:37, launched 21:42; two windows, one on the remote `devvm-aai`
  with many workspaces, one on This Mac's `default`; 22:08–23:00): footprint 750 MB–1.07 GB, peak 1.5 GB (with the
  overview used in capture B); IOSurface 470–630 MB: 14 full-window pictures or surfaces of 2920 × 1972 (22 MB each:
  the 16 kept terminals' copies, D46, and the two shown tabs), 8 half-window ones (11 MB), 193 overview snapshots of
  360 × 244 (0.37 MB, 71 MB); malloc 153–155 MB allocated, stable over 70 minutes (no leak); 18 libghostty surfaces
  (16 kept + 2 shown), 64 threads. CPU 0.6–3 % with no input, 10–50 % while the user worked (overview scrolls, tab
  switches). One SSH master (2 s of CPU in 42 min) and one relay carry the remote; 11 local herdr runs. `sample` of
  the main thread while the user worked: about half idle, the rest SwiftUI layout and Core Animation commits.
- **The 15.4 GB peak** (lane S, the user's build before 21:37) was the overview's leak lane V fixed in 4d3ae63 (phase
  28): every terminal the overview alone showed kept a full-size copy of its picture when its tile let go (4.4 GB
  after one 200-tab scroll then). This build peaks at 1.5 GB after the same use, and three overview open-and-close
  rounds here (below) end within 20 MB of each other.
- **Reproduced** (`scripts/stress.py` 300 tabs, 30 workspaces, 300 panes, 100 agents; local Release, Retina,
  2920 × 1972 window, no XCUITest; keys posted to the app's pid only; script `/tmp/p30-measure/run.sh`):

  | | Footprint | IOSurface | Malloc (dirty) | herdr runs | CPU, no input |
  |---|---|---|---|---|---|
  | Launch, quiet tab | 149 MB | 66 MB | 43 MB | 2 | 9.4 % |
  | 30 tabs visited | 662 MB | 430 MB | 118 MB | 18 | 11.7 % |
  | Overview open, scrolled | 2058 MB | 1535 MB | 185 MB | 35 | 16.2 % |
  | Overview closed | 787 MB | 483 MB | 188 MB | 18 | |
  | Two windows | 854 MB | 522 MB | 203 MB | 19 | 15.1 % |

  The two-window state matches the user's app. Peak 2.2 GB, in the overview.
- **Where it goes.**
  1. The overview: +1.3–1.4 GB while it is open. A live tile's terminal draws at its card's full size, scaled into
     the miniature (`MiniTerminal`), so each of its 16 live tiles has a full-window swap chain (3 × 22 MB here).
     Lane V's area: passed to the orchestrator for lane V's item 5. On main after lane V's 728c071 the overview
     opened at 1.1–1.5 GB instead of 1.7–1.8 GB in the same script.
  2. The kept set (D46): about 30 MB per full-window terminal on Retina (its 22 MB copy of the last picture and about
     5 MB of libghostty's heap), so about 500 MB for 16. By design; no change.
  3. Malloc keeps about 70 MB dirty after the first overview (85 → 153 MB; 7 MB more per later round) though the
     heap holds only 88 MB (`heap`): freed libghostty surfaces' pages. `malloc_zone_pressure_relief` 2 s after a
     surface is freed gave nothing back (tried, reverted).
  4. CPU with no input, 100 agents working: about 9 %. `sample` (6 s): the main thread 4.3 % (Core Animation
     commits of the shown tab's printing agents, then SwiftUI and `HostStore.apply`), snapshot decoding 2.6 %
     (`JSONDecoder` of the 280 KB snapshot, about 6 ms, 4 a second: D5's 250 ms spacing), the rest the 18 surfaces'
     threads. The user's real session, with fewer events, sits at 0.6–3 %. No change.
  5. Per key: AppKit's key-equivalent search over the menu bar, and the menu bar made again whenever a tab title in
     View ▸ Pane ▸ Move Pane to Tab changed (item 11).
  - CI's heap (40276792304, Debug, XCUITest attached) is not the app's own: SwiftUI's accessibility tracking
    (`AnyTrackedValue`, `PropertyList`, `AccessibilityProperties`, about 60 MB) that XCUITest's queries fill.
- **Item 11** (127bf21). `CommandList.menuBarList` is `all` with Move Pane to Tab's tab list left out (a private
  `tabs` flag, passed to `CommandList.pane`); the menu bar and its `shown` key read it, so a tab's new title no longer
  makes the menu bar again. The card's header and context menus (`PaneItems`) and the palette still list every tab;
  VoiceOver's actions have New Tab and New Workspace only (3682e6b, another lane). The Window menu's ⌘1–9 jumps read
  only the first 9 tabs', workspaces' and sessions' titles (they read every title before, so the menu bar's list was
  made again at any title change of the workspace). Keys, the app's own time from the event to the frame, median of 5–12 (same script, the
  commit before vs 127bf21):

  | | ⌘1 | ⌘2–⌘5 | ⌃⌘[ | ⌃⌘] | ⌘K |
  |---|---|---|---|---|---|
  | Before | 116 ms | 129–138 ms | 160 ms | 175 ms | 119 ms |
  | After | 81 ms | 99–109 ms | 122 ms | 140 ms | 109 ms |

  CPU with no input did not change (9.5 % → 9.4 %).
- **Tests.** `testMoveToTabLandsBesideTheLastCard` also opens View ▸ Pane ▸ Move Pane to Tab in the menu bar: New
  Workspace there, no tab. `testHundredsOfPanesStayQuick` keeps `heap`'s summary ("heap, busy tab", the helper's new
  `heap` action, 02eebea).
- **Docs.** window.mdx (View ▸ Pane's Move Pane to Tab has New Tab and New Workspace only).
- **CI.** 40274017771 (`testMoveToTabLandsBesideTheLastCard`, green), 40274683473 and 40276792304 (the stress test,
  green; busy tab 15.9–16.6 %, footprint 217–222 MB as phase 29).
- **For the user to check by hand:** View ▸ Pane ▸ Move Pane to Tab shows New Tab and New Workspace only; a card's
  header menu, its right-click menu and ⌘K's Move Pane to Tab still list every tab. Tab and workspace keys in a big
  session feel a little quicker. `footprint Oriel`: about 0.8–1 GB with two full-screen Retina windows after many
  tabs visited (16 kept terminals at about 30 MB each), more only while the overview is open.

### Lane V (items 2–5, 12)

- **Item 2, root cause.** Two things. The tile showed the card's bare fill while nothing was drawn, with no sign it
  was loading. And past the live cap (16 cards, 6 remote) a tile in view never got a turn: the cap took the latest
  tiles in, so with 4-pane tabs only 4 local (1 remote) tiles in view ever drew; the rest stayed blank as long as
  they were in view unless the strip had shown them. **Fix** (30f8074, 0c05525): a tile with a card that has no
  picture shows one spinner (`overview.tab.<id>.loading`); `overviewCards` puts tabs whose cards have no picture
  first, then the live ones, then the rest, so each tile in view gets a picture in turn (a tile that drew lets go if
  another waits and keeps its snapshot); the tile's `onChange(of: loading)` settles again when one drew. A tab over
  the cap alone still loads; a zoomed tab counts its zoomed card only.
- **Item 3, root cause.** Snapshots were at most 360 px wide; a tile on Retina shows its card at about 2× that, so a
  snapshot was upscaled (blurred) until the tile turned live. **Fix:** taken at the tile's pixel size
  (`WindowPages.tileScale`, the tiles' scale of the strip's page at their last layout, per window, a third before),
  capped at 100 MB by bytes (lane P), oldest out, and an evicted snapshot's waiting still goes with it. Review
  blocker fixed on the way: a tile that let go before it drew snapshotted its own snapshot, shrinking each turn.
- **Item 4, root cause.** The overview replaced the sidebar, the title row and the strip; the zoom's end made all
  three in one turn (the sidebar's rows, the tab bar, the strip and its cards), so they popped in late, more so in a
  big session. **Fix** (30f8074, a6dec94): the sidebar and the title row stay laid out under the overview, hidden,
  disabled and out of the accessibility tree (`underOverview`), and fade in with the 0.18 s zoom; only the strip is
  made at its end, showing the same picture as the zoom's last frame. The hidden sidebar's swipe anchor takes no
  drag; a hover card closes when its trigger is disabled. Regression on the way (CI 40274997505, 17 tests):
  `accessibilityHidden(false)` on the chrome overrode the hidden overlay image in the sidebar button, which then
  carried `titlebar.sidebar` too; now `accessibilityElement(children: .contain / .ignore)`.
- **Item 5, root cause** (Release, this Mac, Retina, 120 tabs / 140 panes / 40 agents, `scripts/stress.py`, posted
  swipes, no XCUITest; a `sample` of 8 s): the main thread was 35–45 % busy while scrolling, with turns up to 390 ms.
  (1) Every herdr snapshot (4 a second with agents) ran `showTerminals`, which chose the overview's live tiles again
  from the tiles in view mid-scroll: surfaces freed (`ghostty_surface_free`), snapshots rendered and new surfaces
  made on the main thread; and the 150 ms settle fired mid-momentum. (2) SwiftUI's hover hit tests over the tiles at
  every frame (about a tenth). (3) Each live tile is a full-window libghostty surface drawn on the main thread
  (`ghostty_surface_draw`, about 7 %) and kept a full-size swap chain (lane P: 16 live tiles, 1.5 GB). **Fixes**
  (728c071, 0a9f140): a snapshot keeps the live set (`overviewStreams`); nothing turns live or lets go until the
  scroll ends (`onScrollPhaseChange`); the tiles take no hit tests while scrolling; live tabs up to 400 MB of window
  pixels × 3 (about 5 tabs on a full Retina window; the rest load in turn).

  | Per 1.45 s swipe (16 swipes) | Before (c417cb9) | After (0a9f140) |
  |---|---|---|
  | Frames (120 Hz) | 112 (77 fps) | 139 (96 fps) |
  | Hitches (> 25 ms) | 8.7 (6–12) | 5.1 (2–8) |
  | Main thread's longest turn per 5 s while scrolling | 120–390 ms | 30–160 ms |
  | Footprint, overview open / scrolled | 1227 / 1190 MB (16 live cards) | 519 / 311 MB |

  Not done: the rest of the main thread is SwiftUI's lazy grid layout (about a fifth) and libghostty drawing the
  live tiles on the main thread (its display link); fewer live tiles is the lever left. `xctrace`'s Animation
  Hitches template crashed attaching to the app (segfault), so the numbers are the app's own scroll meter.
- **Item 12, root cause.** An overview-only terminal keeps its small snapshot as its still (`dropPicture`); shown in
  the strip later (its capsule, or the zoom before its tile drew), `coverNewSurface` put that still over the new
  surface, stretched to the card: blurred until it drew. **Fix** (8184c69, 0c05525): out of a miniature a stretched
  still narrower than the view's pixels is dropped (`dropSmallStill`, on a new superview and a new surface); the
  card shows its fill and fades in. A full-size still (a card that grew while away) still shows. Lane W told.
- **Tests.** `testOverviewLoadsEveryTileInTurn` (two never-shown 9-pane tabs side by side, past the 16 cards: a
  loader, then every card drew); `testACardNeverShowsTheOverviewsSmallSnapshot` (`FrameProbe`'s new `s` code: a small
  still shown in a card; by capsule and by zoom); `testOverviewShowsEveryTabLiveAndOpensOne` (the sidebar is not made
  again after the zoom, `sidebar made` in `app.latency`); `testOverviewCostsAndLetsGoAfter` (a tile's snapshot is at
  its pixel width: the card's value is `<state> <snapshot px>`). Overview card values now carry the static-text
  trait: a group's value never reached XCUITest, so the old "empty" check had passed vacuously.
- **Reviews.** Ponytail: one `pictured`, `small` returns Bool, comment reflows (taken). Spec: blocker (snapshot of a
  snapshot) and 11 shoulds, all taken (eviction of the waiting still, per-window scale, the last turn, zoomed tabs,
  key view loop and hover card under the overview, the ⌥ swipe, only a snapshot's still dropped, flaky loader check,
  a size check that failed on the old code, docs); verify round clean.
- **CI.** Ad-hoc 40274766574, 40276311322 (red: the duplicate id and the card values above). Full suite on 1691e6f:
  see the report.
- **For the user to check by hand:** a big remote session's overview: spinners in tiles that have nothing yet, and
  each tile filling in turn; text sharp when scrolling back (no blur, then sharpen); after a click on a tile the
  sidebar and tab bar fade in with the zoom; scroll the overview fast (smoother; tiles turn live once it stops);
  after the overview, a tab shown in the strip never shows a blurred picture first; `footprint Oriel` with the
  overview open (about 0.3–0.5 GB here, was 1.2–2 GB).

### Lane N (item 13)

- **Root cause.** The Agents button's panel (`NeedsYouPanel`) filtered `agentPanes` to `.needsYou`, and its hover was
  enabled only by `HostStore.waiting`.
- **Decisions.** `AgentsPanel` (now in `TitleBar.swift`, next to its one user) lists two groups, the priority order's
  first and third: Needs you, then Done (`.finishedUnseen`), each under the Agents view's label look and text
  ("Needs you 1", "Done 2"; a plain `Text`, no fold: a hover panel has no place to keep folds). The header is
  "Agents · ‹title›", since the group labels now name the states. `HostStore.done` counts done panes next to
  `waiting` (in `showStrongest`), so the button stays off the per-pane states; the hover opens when either count is
  above 0. The amber dot, `titlebar.agents`' value and the Dock badge still count only needs you. A click on a done
  row goes to its pane (`AgentButton`, as before); the tab in view counts its finish as seen (D14), which clears it.
  The panel's rows stay an eager `VStack`: done rows pile up until seen, so make it lazy only if `scripts/stress.py`
  shows a hitch when it opens.
- **Learned.** A plain `Text` gives XCUITest its string as the value, and its label is "" (lane J of phase 25 found
  the same). The test reads the group labels' `stringValue`.
- **Test.** `testTheAgentsPanelListsDoneAgentsAfterNeedsYou`: a done agent alone opens the panel (the badge still
  says 0); needs you and done in that order, with labels and header; a click on the done row selects its tab, closes
  the panel and clears the finish; the next hover has no Done group. `testBlockedAgentNeedsYouAndThePopoverGoesToIt`
  still covers the empty panel.
- **CI.** 40276253590 (9b6d5b6): the new test and the agents tests green;
  `testAFinishShowsDoneUntilItsRowIsClicked` red on two `titlebar.sidebar` elements (lane V's 30f8074, fixed in
  a6dec94). 40276544611 (65f14c9): the new test red on `.label` of a plain `Text` (fixed in 984e7ad).
  40279636152 (984e7ad, agents tests) green. Full suite 40279661212 on 984e7ad: every agents test green; 2 reds in
  lane V's overview area (`testACardNeverShowsTheOverviewsSmallSnapshot`, `testOverviewCostsAndLetsGoAfter`).
- **For the user to check by hand:** let an agent finish in a tab you are not looking at, then hover the Agents
  button: Done group under Needs you, the amber dot only for needs you; click the done row: its tab shows and the
  Done goes away; with nothing waiting or done, no panel.
