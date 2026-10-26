# Phase 31: The user's seventh round of feedback

The user tested on 2026-10-26 (about 01:00). Capture E:
`/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1793001818197-6f5d-10.scrawl` (read it
with the scrawl skill, `/Users/hkandala/.agents/skills/scrawl/SKILL.md`). Each lane writes `## Findings` at
the end. `/tmp/oriel-gui.lock` is held for "user"; UI tests run on CI until the orchestrator says otherwise.

## Lane S: selection stays in view (items 1, 2)

1. **The sidebar scrolls to the selected workspace.** In a session with many workspaces, when the
   selected workspace changes (from the overview, ⌃⌘[ ], ⌃⌘1–9, a three-finger swipe, the palette, a
   notification), the sidebar's list scrolls just enough to show its row. The Agents view does the same for
   its selected agent row.
2. **The tab bar's selection capsule gets stuck** (capture E #2 0:19–#6 0:32): after zooming from the
   overview into a middle tab of a workspace with many tabs, the capsule sits between two tabs ("long
   horizon" half covered) until the next click. It happens every time. Find why (the capsule reads the
   strip's offset, and phase 29 lane T's `.defaultScrollAnchor` may set the first offset without the change
   the capsule listens to) and fix it for every way a tab is shown.

## Lane G: gestures (items 3–6)

3. **Remove ⌥ + swipe** (phase 30 lane G's SwipeRouter path, its test and docs); keep three-finger swipes.
4. **Three-finger vertical direction is reversed:** fingers up should go to the workspace above (the
   previous one), fingers down to the one below, like scrolling the sidebar's list. Horizontal stays.
5. **Faster two-finger paging between tabs**, and the overview's horizontal swipe between sessions at the
   same speed: the page should follow the fingers one to one and a flick should land on the next page
   sooner. Measure finger distance vs page movement and the time to land (CI recordings, local runs when the
   GUI is free) before and after.
6. **In the Agents view,** a three-finger vertical swipe moves the selection to the previous / next agent
   row (and shows that agent's pane, as a click does), instead of switching workspaces. In the workspaces
   view it switches workspaces. A vertical three-finger swipe always moves what the sidebar shows.

## Lane F: pi-herd floats through herdr, local and remote (item 7)

7. pi-herd's `open oriel://float?…` (phase 28 lane F) works only for agents on this Mac: an agent on a
   remote machine cannot open a URL on the Mac. Replace it with a request that travels through herdr, so
   it works wherever the agent runs and needs no frontmost-app check:
   - **Request:** pi-herd sets metadata tokens on its own pane (`pane.report_metadata`, a short `ttl_ms`):
     the target (session and pane id, for example `oriel.float = pi-herd/<pane id>`) and a nonce.
   - **Oriel:** it already follows every shown session's events, over the relay for remote machines. On a
     float request token it opens that pane in its floating window (phase 28's `oriel://` path inside, on
     the machine the event came from, loading a float-only page when the session has no page), then
     answers on the same pane with an ack token carrying the nonce.
   - **pi-herd:** after the request it waits briefly (about 300–500 ms) for the ack (event or `pane.get`);
     with an ack it stops; without one (no Oriel attached, or herdr's own TUI only) it opens herdr's popup
     as before. The `lsappinfo` check goes.
   - Spike first: which event a metadata change sends (`metadata_updated`, `pane.updated`?), whether tokens
     reach every client, how `ttl_ms` clears them, and the token limits (16 tokens, name pattern).
   - Both repos: Oriel here, and pi-herd in `/Users/hkandala/code/pi-hkandala` (its own AGENTS.md and
     commit rules). Keep `oriel://float` for other tools.

## Integration (items 8–10)

8. **Return confirms the close dialog:** when closing a pane or tab asks first, Return does nothing and the
   user has to click. The confirm button is the default button (Return), Esc cancels, in every close
   dialog (pane, tab, other tabs, tabs to the right, workspace, Stop and Delete in Open Session, floating
   pane).
9. **CI back to about 7–8 minutes:** the full suite went from about 6 to 13–16 minutes (171 tests, about
   40 minutes of test time; the 12 slowest take 30–80 s each), more with reruns. Move the heavy measurement
   tests to ON_DEMAND (a perf job run on request or before a release), balance the shards by measured
   time instead of by name, and keep `make e2e` covering the behaviour those tests guard with cheaper
   checks where needed.
10. **No flaky tests:** fix the known flakes at their cause (Go to Directory / Insert Path, double-click
    rename, HerdrKit's relay "carries runs over one process" exit 9, the quick-split keyboard check,
    the session swipe bound at 80 ms, lane G's posted-swipe distance), and the open bug from phase 30 lane
    Q (after a burst of ⌘D one split went to the first card: A | C | B | D). A full run must pass without a
    rerun, twice in a row.

## Checks

- `make lint build test`; a UI test for each item a test can see (three-finger swipes: the recognizer's
  check script); the full CI suite green on each lane's last code commit; one review round per lane (spec
  and ponytail, read only).

## Findings

### Lane G

- **Item 3, ⌥ + swipe.** Removed: `SwipeRouter`'s ⌥ lock (gesture and wheel), `scripts/swipe.swift`'s 7th argument
  and the helper's, `testOptionSwipesMoveBetweenSessionsAndWorkspaces`, the docs (swiping, keys table, D35,
  platform). A swipe with ⌥ held now scrolls as one without it. `WindowPages.step` stays (⌥⌘[ ], three fingers).
- **Item 4, root cause.** `ThreeFingers` mapped fingers up (touch y grows upward) to the next workspace, as the
  system's own swipes. Now `.row(deltaY > 0 ? -1 : 1)`: up is the row above. Sideways is unchanged.
- **Item 6.** A vertical three-finger step is a sidebar row (`ThreeFingers.Step.row`). The sidebar's anchor carries
  an `agent` closure while the Agents view shows (not in the overview); `SwipeRouter.take` calls it, else
  `stepWorkspace`, so with the sidebar hidden or in the overview it steps the workspace. `AgentsList.groups` is now
  the one source of the list's order (by priority or workspace, filtered) for the view and for `AgentsList.step`,
  which goes to the row above or below the lit one, round the ends, by `Page.go(to:)` as a click. Skipped: a folded
  group's rows, and floated panes (a click on one only brings its window forward, so the lit row would never move
  past it). None lit: down goes to the first row, up to the last.
- **Item 5, root cause.** The strip and the overview were SwiftUI scroll views with `.scrollTargetBehavior(.paging)`;
  the router handed them the gesture and its momentum, and the system's paging decided the landing: it ignores the
  fingers' speed (a 140 pt flick slid back to its page) and its snap took about 0.55 s. **Fix:** they take the
  gesture as the sidebar's pages do (`Paging`, SwipeRouter.swift): the router gives an anchor with `drag` its moves
  (`ScrollPosition.scrollTo(x:)`, one to one, the axis pick's first 4 pt too) and its lift with the fingers' speed,
  and drops the momentum; the lift slides to the page it lands on (`Swipe.landing`, shared with the sidebar: the next
  one that way, the nearest under 100 pt/s) with the session spring from that speed (`Animation.session`), and
  selects the tab or shows the session at `.logicallyComplete` unless a key, a click or another swipe moved the
  pages. `.paging` is gone from both: with it the swipe's first `scrollTo(x:)` snapped to the next page (CI
  40292985497: the lift found the strip already there). So a wheel's burst over either turns one page (`step`), XCUITest's
  scroll too. A lift already on its page (clamped at the last) lands at once.
- **Numbers** (CI, Debug, 1x VM, XCUITest attached, `-forceMotion`; `scripts/swipe.swift` swipes over a card, page
  792 pt; the `page` record of `Latency`: the strip's offset at each frame from the lift):

  | Strip | Before (system paging) | After |
  |---|---|---|
  | 420 pt at 1875 pt/s: page's move by the lift | 390–420 pt | 420 pt |
  | its time from the lift to within 2 pt of the page | 546–550 ms (last change 606–617) | 251 ms (last change 301) |
  | 140 pt flick at 625 pt/s | 130 pt by the lift, then back to its own page over 551 ms | 140 pt, on the next page at 244 ms |

  Before: runs 40290851145, 40291752480, 40292891260; after: 40294392725 and 40295293239 (420 pt, at rest by 253 ms).
  The overview had the same scroll view and paging; before, its posted swipe never turned a page in the test
  (40292891260); after (40299936835, page 1024 pt): 420 of 420 pt by the lift, within 2 pt at 250 ms; a 140 pt
  flick back 140 pt by the lift, on its page at 263 ms. The strip in the same run: 232 ms and 249 ms; fingers that
  stop after 40 pt back on their page by 149 ms. A scroll view's geometry reports only some frames of an
  animated `scrollTo` (records jump 0 → 118 or 211 ms), but the screen recording of 40295293239 has a frame every
  33 ms through the slide: no stall.
- **Tests.** `testTabAndOverviewSwipesFollowTheFingersAndLandSoon` (LatencyTests): the strip and the overview, a long
  swipe and a flick back, each one to one by the lift (within a step) and at rest on the page under 400 ms; fingers
  that stop before they lift go back. Red on the old code (above). `testSwitchingTabsShowsTheirPageAtOnce` now posts a
  trackpad swipe (XCUITest's scroll is a wheel, which turns a page without motion under Reduce Motion).
  `testSwipesPageTheSidebarAndTheStripApart` checks a ⌥ scroll steps no workspace. `three-fingers-check` checks the
  new direction. Item 6 has no UI test: XCUITest cannot post touches; the order is the view's own (`groups`).
  `Latency.lifted`/`slid` take a name (`swipe` for the sidebar, `page`), so a strip slide never lands in a sidebar
  record (it did in 40290851145).
- **Reviews (one round).** Spec: a lift on its page never ended (fixed), a tab closed mid-slide selected (fixed),
  floated agent rows stuck the step (fixed), the 300 ms bound too tight (400), window.mdx's strip text, stale
  comments, the overview under a panel (fixed), docs. Not done: a mid-slide swipe test (spec nit 10). Ponytail: the
  folded-keys parse once, `Group: Identifiable`, `ScrollGeometry` straight to `Paging.laid`, `drag(count:)`, the
  test's swipe arguments, comments; kept the ⌥ scroll check (a removed feature's guard, 1 s).
- **Docs.** swiping.mdx (three fingers, the pages' spring for all three, wheels), window.mdx (Agents view, the
  marker), theme-and-accessibility.mdx (keys table), decisions.mdx (D35), platform.mdx.
- **For the user to check by hand:** two-finger swipes between tabs, slow and as a flick (the page under the fingers,
  then on the next tab about 0.25 s after the lift); the same in the overview between sessions; stop the fingers
  before lifting (back to the same page); a mouse wheel sideways over the strip and the overview (one page a burst);
  three fingers up: the workspace above, down: below; in the Agents view, three fingers up and down move the lit row
  and show its pane; ⌥ + two-finger swipe now just scrolls.
- **Commits.** e5c5d4f, 273d8cc, c759eae (the measuring test), f467583 (items 3, 4, 6), b80e59f (item 5), 13481fa
  (no `.paging`, review fixes), 10370e7, 13b62ec (tests), and these Findings.
- **CI.** Full suite 40295293239 on 10370e7 (has every code change): lint-build and shards 1–3 green; shard 0 red
  only in `testTabAndOverviewSwipesFollowTheFingersAndLandSoon` (its record filter, a test bug, fixed in 13b62ec).
  40299936835 (that test and `testSwitchingTabsShowsTheirPageAtOnce` on 13b62ec): green. Open: a full suite on the
  last commit.

  40299936835 (that test and `testSwitchingTabsShowsTheirPageAtOnce` on 13b62ec) was running at hand-over. Open: a
  green run of the new test (the overview half has not run yet on the new code), then the full suite.

### Lane S (items 1, 2)

- **Item 1, cause.** Nothing scrolled the lists: the workspace list and the Agents view had no scroll position, so a
  selection made anywhere but a click on a row (the overview, ⌃⌘[ ], ⌃⌘1–9, a swipe, the palette, a notification)
  could land below the fold. **Fix** (3727df4, 17124d3): a `ScrollPosition` on each list and
  `scrollTo(id:)` with no anchor (just enough) when the selected workspace or the lit agent row changes, without
  motion, and again one turn later for a row new in that update. The workspace row's scroll target is a clear
  background 18 pt taller each way, so the row stops clear of the fade. The Agents view also scrolls when it opens and
  on a sort change (its lazy stack is made anew).
- **Item 2, cause** (capture E #2–#6; reproduced on CI, also on a plain workspace switch without the overview). On
  a new strip's first layout, `containerRelativeFrame` sized the pages at the window's width, not the strip's (CI:
  content 5 × 1024 pt in a 792 pt container). Phase 29's `defaultScrollAnchor` placed the first offset from that
  (2164 pt for the middle of 5 tabs, page 2.732). Later passes corrected it to page 2, but `onScrollGeometryChange`
  delivered its actions merged and out of order: the last one delivered was 2.732 (probe log on a throwaway tag:
  `… g 1584 792 3960; g 2164 792 3960; g 1700 792 3960; a 2.0; a 2.732; g 1584 …`, stripPage 2.732). The capsule
  reads `stripPage`, so it rested 0.73 of a tab past the shown one (floor…ceil lit both) until the next scroll. The
  user's 2.39 is the same formula on their window (window / strip ≈ 1.16). **Fix** (eb98366): the pages take a
  `GeometryReader`'s size, so the first layout already has the right width and offset, and no bogus geometry is
  reported at all (an offscreen probe app: one pass at the page, where `containerRelativeFrame` gave three). The
  same fix gives lane G's `Paging` the right start offset on a new strip's first swipe.
- **Tests.** `testTheSelectedRowScrollsIntoView` (24 working workspaces: ⌃⌘[ round to the last row, which ends
  near the list's end; ⌃⌘3 up to a middle row with the fade's room; ⌃⌘1; the Agents view's lit row after ⌃⌘[,
  after the view reopens, after ⌃⌘3; the workspace list again). `testTheCapsuleRestsOnTheTabShownHoweverItShows`
  (zoom into the middle of 5 tabs, the workspace again, ⌘4), and `expectShown` now asks that only the shown tab is
  lit, which made `testStripShowsEachWorkspaceClickedBackAndForth` red on the old code (`tab.w3:t4`, `tab.w3:t5`
  both "in view").
- **Reviews.** Spec: the Agents view's first scroll and sort change (fixed, and tested), the fade room untested
  (⌃⌘3 step), motion (no animation now), the duplicate session step (dropped), docs (fades are the workspace list's).
  Left: `testWorkspaceKeepsItsSelectedTab` keeps its loose lit check; `stripPage` still takes whichever geometry
  arrives last (no case left that shows it). Ponytail: no blocker or should; the string-keyed `onChange` stays
  (Sidebar.swift is at 400 lines), the 18 stays three literals.
- **Learned.** On a new `ScrollView`'s first layout, `containerRelativeFrame` can resolve to the window's size, and
  `onScrollGeometryChange` may deliver a stale value last; size pages from a `GeometryReader` when the first offset
  matters. A main push that is lint-red happens when `make lint build | grep` hides the exit code (3727df4, fixed in
  27f4af2): check exit codes, not grep output.
- **CI.** Probe runs on the deleted tag `probe-31s-capsule`: 40291207055, 40292335688 (old code: red, the logs
  above). 40292369686 (`testTheSelectedRowScrollsIntoView`, green on 3727df4). 40293816257 (the capsule, strip,
  flicker and tab-switch tests, green on 40dbb26). Full suite 40294678064 on 511c1bd (after 17124d3, the lane's last
  code commit), with a rerun of the failed jobs: every lane S test green (both new ones, the strip, flicker, Agents
  and sidebar tests); `testDoubleClickRenamesAndEscapeCancels` red once, green on the rerun (the recording: beta
  selected, the list did not move; a double-click taken as one click). Red in other lanes' areas:
  `testTabAndOverviewSwipesFollowTheFingersAndLandSoon` (lane G, 126 vs 140 ± 10 pt, both attempts),
  `testSwitchingTabsShowsTheirPageAtOnce` (both attempts: its last step, "a swipe does slide", counts no geometry
  between pages; green on 40dbb26 with this lane's strip fix in 40293816257, so likely lane G's 13481fa, swipes without
  SwiftUI's paging), `testOrielURLFloatsAPaneOfASessionWithNoPage` (rerun only, an XCUITest INFINITY point).
- **For the user to check by hand:** zoom from the overview into a middle tab of `mira` (and a workspace switch to a
  workspace on a middle tab): the capsule on that tab at once. In a session with many workspaces, ⌃⌘[ ] and the
  overview to a row below the fold: the list scrolls just enough; the same in the Agents view.
