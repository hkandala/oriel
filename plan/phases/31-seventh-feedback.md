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
  (40292891260); after: not yet measured on CI (the runs above stopped at the strip's record filter, fixed in
  13b62ec; 40299936835 was in flight at hand-over). A scroll view's geometry reports only some frames of an
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
  40299936835 (that test and `testSwitchingTabsShowsTheirPageAtOnce` on 13b62ec) was running at hand-over. Open: a
  green run of the new test (the overview half has not run yet on the new code), then the full suite.
