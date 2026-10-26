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
     the machine the event came from, loading a float-only page when the session has no page). No ack
     (below).
   - **No ack wait (user, 02:45):** waiting for an ack would slow herdr's own popup when Oriel is not
     attached and be flaky over slow links. Instead Oriel marks the panes it shows with a presence token
     (source `oriel`, for example `oriel.shown`, `ttl_ms` about 30 s, refreshed about every 10 s while
     shown, cleared when the pane leaves view or the window closes). At click time pi-herd reads its own
     pane's metadata from the herdr socket on its own host (`pane.get`, a few ms): with a fresh presence
     token it sends the float request and opens no popup; without one it opens herdr's popup at once.
   - Spike first: which event a metadata change sends (`metadata_updated`, `pane.updated`?), whether tokens
     reach every client, how `ttl_ms` clears them, and the token limits (16 tokens, name pattern).
   - Both repos: Oriel here, and pi-herd in `/Users/hkandala/code/pi-hkandala` (its own AGENTS.md and
     commit rules). Keep `oriel://float` for other tools.

## Lane M: smooth paging and the pill after the overview (items 11, 12)

Capture F: `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1793008806798-6f5d-12.scrawl`.

11. **Paging animation cuts** (F #1 0:15–#3 0:39): since lane G's faster paging, a two-finger swipe between
    tabs, and much more a quick swipe between sessions in the overview, looks cut or jagged ("previously it
    was much better, just slow"). Look frame by frame (`scrawl zoom … --at 0:40 --span 6 --frames 60
    --full`), find the cut (a jump at the lift between the fingers' offset and the spring's start, the
    selection at logicallyComplete moving the page, a second scrollTo, frames dropped while the next page
    builds) and make it smooth while staying quick.
12. **Pill jump after the overview** (F #4 1:13–#6 1:42): choosing a tab in the overview shows the tab bar's
    pill on the previous selection for a moment, then it jumps to the new tab. The user's idea: when the tab
    bar comes back from the overview, it has no pill, and the pill fades in on the selected tab.

## Lane K: keys reach the right place (item 13)

13. **⌃⇥ sometimes steps panes instead of tabs**, quite regularly, and **with several windows a key (⌘D and
    others) sometimes acts on another window** than the one the user is in. Go through how every key is
    triggered (menu bar commands and their focused values, the app's key monitor and second keys, the
    terminal view's performKeyEquivalent and keyDown, floating windows, panels, the palette) and make each
    key act once, on the key window's current page and keyboard card, in every case: several main
    windows, floating windows, panels open, a window just made key, focus in a field. Tests for ⌃⇥ / ⌃⇧⇥
    in a tab with several panes, and for ⌘D with two windows after switching between them.

## Lane O: overview session paging and one fade (items 14, 15)

Capture G: `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1793017285451-6f5d-15.scrawl`.
Tab paging is good now (G #1).

14. **Swiping between sessions in the overview still drops frames** (G #2 0:10). Profile it locally on a
    Release build with real sessions of many tabs (scripts/stress.py), find what each frame waits on (the
    next session page's lazy grid built during the slide, live tiles turning on, snapshots decoding, SwiftUI
    layout of the whole page), and fix it: for example lay out the neighbor session pages before the swipe,
    keep every tile on its snapshot during a slide and turn tiles live only after it lands, or draw the
    sliding pages as cached pictures. A longer slide is the last resort, not the fix.
15. **One fade after the overview** (G #4 0:39, #5 0:54): the sidebar and the tab bar fade in with the zoom,
    but the tab bar's pill fades in on its own afterwards. All of them fade in together, in one shorter fade
    (about 0.12 s, the zoom's length or less).

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
- **Docs.** swiping.mdx (three fingers, the pages' spring for all three, wheels), window.mdx (Agents view, the
  marker), theme-and-accessibility.mdx (keys table), decisions.mdx (D35), platform.mdx.

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

### Lane F (item 7)

- **Spike** (herdr 0.9.5, `oriel-dev-31f-spike`). `pane.report_metadata` sends `pane.updated` with the whole pane,
  `tokens` included, about 100 ms after the report, and again when a token expires (no `metadata_updated` for panes);
  `pane.get` and `session.snapshot` list `tokens` too. The tokens are one map per pane by name, whatever the source: a
  report changes only the names it gives (`null` clears one), so Oriel's never touch pi's display agent, title, state
  labels or tokens; another source writing the same name overwrites it, and its expiry removes it. `ttl_ms` is per
  token. Names `^[A-Za-z0-9_-]{1,32}$` (so `oriel-shown`, not `oriel.shown`), 16 per report (`invalid_metadata_token`),
  32 per pane (`metadata_token_limit`), values cut to 80 characters.
- **Protocol** (talking-to-herdr#float-requests, D50). Presence: Oriel reports `oriel-shown` = `1` (source `oriel`,
  `ttl_ms` 30000) on every pane in view of a visible window (the shown tab of the page in view, and floats), on change,
  again every 10 s, cleared when it leaves view, its page or window closes or hides, and at quit (up to 1 s, in
  `applicationShouldTerminate`). Ask: pi-herd at a click reads its own pane (`pane.get` on its own socket); with
  `oriel-shown` it reports `oriel-float` = `‹session›/‹pane›` and `oriel-float-id` = a UUID (`ttl_ms` 1000) and opens
  nothing else; without it herdr's popup at once. Float: Oriel reads the request off the event (the one payload it
  reads), once per nonce, and floats over the asking session's controller window (`oriel://float`'s path, a
  float-only page when needed, on the event's machine).
- **Deviations.** The first build had an ack (`oriel-float-ack`) and pi-herd waited 500 ms for it; replaced by
  presence before the reviews (user, 02:45). The 10 s refresh is its own app-wide loop, not the git loop (a slow git
  pass over ssh could outlast the 30 s mark).
- **Left (reviews).** A float detached from a page that is not in view keeps its mark until the next snapshot or
  refresh (Page.swift is at 399 lines; its stream did so before too). A pane herdr moves keeps its old mark until it
  expires (the clear goes to the old id). Two Macs share `oriel-shown` (one's clear drops the other's until its
  refresh) and both float a request. A request while the events stream reopens (agent panes changed) is lost: the
  click does nothing. A click in herdr's own TUI on a pane Oriel also shows floats in Oriel. The hide path
  (`visible` false) has no test; leave, detach, out of view and quit do.
- **pi-herd** (pi-hkandala 9aa02d5, 522e6ca). `orielShows(socket, pane)` and `orielFloat(...)` in herdr.ts replace
  `orielInFront` (lsappinfo) and `open -g oriel://float`; `attach` asks before the hidden-session refusal, so an
  agent in the `pi-herd` session that Oriel shows floats too. `npm run check` green; both checked with node against
  the spike session.
- **Tests.** `testShownPanesAreMarkedAndAFloatRequestFloats` and `testARemoteMachinesPanesAreMarkedAndFloatThere`
  (through CI's sshd, over the relay) share `markAndFloat`: a new tab's pane is marked, its request floats two's
  w1:p1 (marked), Detach clears it, w1 clears the tab; the local one quits and finds w1:p1 cleared within 5 s. HerdrKit:
  one request per nonce, never again, malformed targets dropped.

### Lane M (items 11, 12)

- **Item 11, root causes** (capture F frame by frame, the screen recording's own frame times; an offscreen probe app
  of a paged `ScrollView`; lane G's `page` records). Two, each a cut:
  1. **The landing ran at the lift.** `withAnimation(_, completionCriteria: .logicallyComplete)` around
     `ScrollPosition.scrollTo` completes at once for a scroll (probe: 8 ms after the lift, in the slide's first
     frame; `.idle` came at full rest). So `Paging`'s landing (select the tab: its terminals stream, the keyboard; in
     the overview `pages.show`: the session's title row and sidebar, its live tiles) ran in the first frame and held it:
     CI (40299936835) drew the first frame after the lift 54–149 ms late; this Mac (Release-like Debug, 120 Hz) 57 ms,
     then 504 pt in one frame. The docs already said "shown at the lift, its first draw held the slide still (phase
     27)": `.logicallyComplete` looked like the sidebar's fix but is not one for a scroll.
  2. **The 0.2 s spring from a slow lift lurched.** In F (0:21.4, the strip) the fingers moved the page 54, 38, 27 pt a
     frame (about 1.6k pt/s at the lift); the next frames moved 360, 363, 189, 201 pt (up to 21k pt/s): most of a page
     in four frames, the spring's own path (a critically damped 0.2 s spring peaks at ω·d/e ≈ 15k pt/s over a page).
     The overview at 0:54.5 is the same, 84 % of a page in the first frame after the lift.
  **Fix** (475bc36, 5a38d2b): `Paging.slide`, a cubic whose x is linear: its first slope is the fingers' speed, it
  speeds up only as much as 0.28 s needs and eases out (slope 2, a plain ease-out, when their speed covers the rest
  sooner: duration `min(0.28, 2d/v)`). The landing runs from `laid` once the pages are within 1 pt of the page
  (`landing`, cleared by a drag; the page's offset as laid out then, so a resize mid-slide still lands). Not changed:
  the sidebar's session pages keep the session spring (not reported; they animate an offset, where
  `.logicallyComplete` works).
- **Numbers** (`page` records, ms:pt from the lift; 420 pt swipe at 1875 pt/s unless noted):

  | | Before | After |
  |---|---|---|
  | CI strip: first frame after the lift | 103 ms, 303 pt of 372 at once | 35 ms, 27 pt; largest step 78 pt in 51 ms; landed 284 ms |
  | CI flick back 140 pt at 625 pt/s | 54 ms, then 307 pt in one frame | 17 ms; largest 105 pt in 34 ms; landed 336 ms |
  | CI overview: first frame | 149 ms, 567 pt of 604 at once | 17 ms, 6 pt; largest 100 pt in 31 ms; landed 304 ms |
  | CI overview flick back | 76 ms, 574 pt at once | 17 ms; largest 163 pt in 33 ms; landed 308 ms |
  | This Mac, strip (page 1324 pt) | 11:443, **68:947**, 111:1196, 147:1274, 211:1313 | a frame every 8–9 ms: 9:427, 28:467, 50:541 … 262:1479, 286:1496 (page 1496) |
  | This Mac, overview (page 1728 pt) | (same stall) | 9:428, 17:447, 28:470 … largest step 137 pt in 19 ms; at rest 301 ms |
  | Landing (tab selected / session shown) | at the lift (16–20 ms) | 269–301 ms, within 1 pt of the page |

- **Item 12, root cause.** The pill sits at `page.stripPage`, the strip's offset. Under the overview there is no
  strip; a tab chosen there changed the selection but not `stripPage`, so the title row faded in with the pill (and
  the lit title) on the tab selected before, and the new strip's geometry moved it a turn after the zoom (F 1:31:
  "video" for 0.2 s, then "long horizon"). **Fix** (bab0811, 5a38d2b): no pill while the overview is open (the lit
  title is the selected tab's); `closeOverview` sets `stripPage` to the selected tab before the strip comes back, and
  the pill fades in there over 0.18 s (the user's idea).
- **Tests.** `testTabAndOverviewSwipesFollowTheFingersAndLandSoon` (lane G's, `swipeLands`): the landing comes once
  the pages are within 2 pt (the record's 4th field, `Latency.shown` now also for `page`), and no frame's step
  exceeds 1.5 × max(the fingers' speed, 1.5 × distance / 0.3 s) over its own Δt (17 ms floor) + 2 pt. Both by the
  slide's own frames and times, so a frame CI's VM skips does not count (no bare "first frame < 60 ms": integration's
  ask). `testTheCapsuleRestsOnTheTabShownHoweverItShows` launches with `-recordLatency` and asserts no "pill <tab> 2"
  note after the zoom (`TabBar.marker` notes the pill shown at rest on a tab other than the selected one). Both red
  on the old code (CI 40308630278 on a throwaway tag: "shown at 16 ms, before the pages arrived … 0:420,185:783", and
  `["pill 0.0 2"]`; this Mac the same for the swipe), green on the new code on this Mac.

### Lane K (item 13)

- **Root cause, ⌃⇥ steps panes.** The key monitor ran a second key (⌃⇥ ⌃⇧⇥ ⇧⌘P ⌘=) through the NSMenu item of its
  first and let the key go on when that item was disabled (Show Next Tab in a workspace of one tab, or a menu bar not
  yet updated after a change) or a text field had the keyboard. AppKit then moved the first responder to the next
  terminal (its key view loop): the keyboard stepped the panes. Reproduced locally (one tab, two panes: ⌃⇥ moved the
  keyboard). Now a matched second key in an Oriel window is always taken: its first's command runs when enabled, on
  the key window's own list; in a text field ⌃⇥ does nothing. The NSMenu walk went.
- **Root cause, a key acts on another window.** The menu bar's actions are closures of the focused value's
  `CommandList`, which can be another window's (SwiftUI updates it after a switch; an equal value keeps the old one and
  its closures). Every keyed menu item now runs the key window's command for that key, made when the key is pressed
  (`CommandList.keyWindow`: a holder view per window, put in by `menuBar`, so main and floating windows alike). A key
  the menu bar missed (a floating window's list has no ⌘D; ⌘4 when the other window had three tabs) runs the key
  window's command from `PaneSurfaceView.keyDown`'s ⌘ branch before it beeps. No window: the menu's own action (⌘N);
  behind a sheet: nothing.
- **Every path, checked.** Menu key equivalents (now to the key window's list), the second-key monitor (key window's
  list, always taken), the terminal's ⌘ fallback (key window's list), `herdrKey` (⌃⇥ no longer reaches it in an Oriel
  window), floating windows (their own list; ⌃⇥ there does nothing instead of going to the program), panels and the
  palette (overlays in the window: its list), the overview's and hover card's Esc monitors (unchanged). Nothing acts
  twice: the monitor swallows what it runs, and the terminal's fallback runs only for keys no menu item took.
- **Left.** A stale menu item that is disabled while the key window's command is enabled still swallows the key for
  that moment (AppKit matches the disabled item; nothing runs, never on the wrong window). Fixing it would take every
  Oriel key into the monitor and AppKit's layout-aware matching with it.
- **Tests.** `testControlTabStepsTabsNeverPanes` (three rounds of ⌃⇥ / ⌃⇧⇥ in t1's three panes, the keyboard stays on
  its card; a workspace of one tab and two panes, each way on its own: the keyboard does not move; red on the old
  code). `testCommandDSplitsInTheKeyWindowOnly` (two windows on two tabs, ⌘D after ⌘` four times each, the last two
  with no wait: only the key window's tab splits). The latter is a guard, not a repro: it is green on the old code too
  (XCUITest waits for idle between keys, so SwiftUI has updated the focused value by then).

### Lane O (items 14, 15)

- **Capture G, frame by frame** (the recording's own frame times, a column-profile shift per frame). At 0:13.3 the
  fingers moved the page 28 and 96 px, then nothing for 58 and 67 ms, then 860 px in one frame, two more frames still,
  then 696 and 392 px: the frames waited, then caught up. The same at 0:14.5, 0:15.3 and 0:16.6.
- **Profile** (Release, this Mac at 120 Hz, a throwaway bundle id so nothing of the user's app was touched; stress
  sessions of 4, 12 and 60 tabs with agents; `scripts/swipe.swift` swipes; a temporary probe logging each run loop
  turn over 6 ms, each `laid` frame with the view bodies made since, and `sample`/`xctrace` Time Profiler). What each
  frame waited on:
  1. **Every tile in view remade at every move of the fingers.** `Paging.drag`'s `scrollTo(x:)` changes the overview's
     `ScrollPosition` state, so the overview's body ran at each move and made each `OverviewPage`, and through them
     every `Tile` (closures in their fields never compare equal): 7.6 tile bodies a frame on average, more in a big
     session. Each tile's icons called `URL(filePath:)` on a bare program name, which reads the working folder
     (`getcwd`, a syscall) — 5 % of the main thread while dragging.
  2. **A swipe's start remade them all again**: the router lets the gesture's first event through to the grid under
     the pointer before it picks the axis, so the page's grid began a scroll; its `scrolling` state changed
     `allowsHitTesting`, and an `allowsHitTesting` change re-ran every tile's body below it (30–60 tiles, 20–40 ms),
     Equatable or not. The zoom's start did the same (`allowsHitTesting(zoom == nil)`).
  3. **SwiftUI's hover hit tests at each slide frame** (the content moves under a still pointer: about a tenth of the
     main thread), and **the next session's page made in the swipe's first frame** by the lazy stack (36–56 ms), the
     last one dropped after the landing.
  4. **After the landing:** the sidebar under the overview (hidden, laid out) slid its session pages with the session
     spring for 0.3 s, both pages laid out each frame: the landing's turn took 155–290 ms and the following ones
     45–130 ms; a settle scheduled at the landing could fire in the next swipe (surfaces made and freed mid-drag).
- **Fix** (e4982ce, 867a057; 5cd1ae9 for `getcwd`): `OverviewPage` and `Tile` are Equatable (all fields but the `open`
  closure); no tile takes the pointer while the pages move, the grid scrolls or the zoom runs, by a clear overlay
  (`shielded`) instead of `allowsHitTesting`; the page in view and its neighbors are made (an `HStack` with the others
  as clear pages), so a swipe never makes a page; no settle or live change while a swipe holds or slides the pages
  (`overviewSliding`, checked again when the 150 ms settle fires); the sidebar moves at once under the overview; only
  the page in view's tiles read the live set. A panel opened mid-swipe sends the pages back and ends the slide.
  Not changed: the slide's length and curve (lane M's `Paging.slide`).
- **Numbers** (Release, this Mac; 6 swipes of 420 pt at 1875 pt/s; the `page` records until the landing; `main` = the
  app's busy time and longest turn per 5 s. Rows 1 and 5: six sessions of 4–60 tabs, two runs each; rows 2–4: three
  sessions, the probe build):

  | | Before (a81c26d) | After |
  |---|---|---|
  | Slide frames over 12 ms (120 Hz) | 31–35 of 230 (p90 16–17 ms, max 23–33) | 4–5 of 267 (p90 9 ms, max 17–25) |
  | Tile bodies per frame while dragging | 7.6 | 0.4 (a tile whose terminal drew) |
  | First frame of a swipe | 36–56 ms | 11–22 ms |
  | Turn of the landing, and after | 155–290 ms, then 45–130 ms turns | about 100 ms, then none over 50 |
  | Main thread per 5 s of swipes, longest turn | 1.3–1.8 s, 172–193 ms | 0.7–1.0 s, 99–139 ms |

  The landing's 100 ms (the new session's chrome and its live tiles, `showTerminals` 25–30 ms of it) comes after the
  pages arrived. The Release build carries code coverage counters (`ENABLE_CODE_COVERAGE` defaults on); off, the same
  bench showed no difference, so `make app` is unchanged.
- **Item 15, cause.** The sidebar and the title row fade with `open = overview && !leaving` (the zoom's start), the pill
  had its own fade on `overview`, which ends at `closeOverview` (the zoom's end): it faded in 0.18 s after the rest.
  **Fix** (39915d5, 867a057): the pill has no opacity of its own (under the overview it already sits on the selected
  tab), so it fades with its row; the chrome's fade is 0.12 s, from the zoom's start (the zoom stays 0.18 s).
- **Tests.** `testTabAndOverviewSwipesFollowTheFingersAndLandSoon` (lane G's) now asks that the overview's swipes make
  fewer than 6 tiles while the fingers move ("tiles <count>" at each lift, `Latency.tiles`) and that a tile click
  leaves the overview after the swipes (the overlay went). Red on the old code with the counter: `[56, 52]`. A first
  version had its own test on a 24-tab session (red on the old code at lane M's jump check, "a jump at 176 ms"); folded
  into lane G's (reviews: CI time, item 9). Item 15 has no frame test: an environment-carried fade recorder only sees
  its own modifier, so it was blind to the pill's `.opacity` (it was red on the old code only after rewriting that
  opacity into the recorder); the pill now has none to get wrong. `testTheCapsuleRestsOnTheTabShownHoweverItShows` keeps
  its astray-pill check.
- **Left.** A key, wheel or three-finger session change in the overview still slides with the `.session` spring with
  no hold on settles and the tiles taking the pointer; the router still lets a swipe's first event reach the grid
  under the pointer (harmless now, its scroll phase toggles the overlay only).

### Integration (items 8–10)

- **Item 8, cause.** The close dialog and Open Session's Stop / Delete were `confirmationDialog`s with a destructive
  button. macOS gives such a button no Return: `.keyboardShortcut(.defaultAction)` on it did nothing there (CI
  40304584542: the dialog stayed after Return). **Fix** (e4e638d, e6cc32f): both are `.alert`s, the destructive button
  carries `.defaultAction`, plus a `.cancel` button for Esc. Without `.defaultAction` an alert takes no Return either
  (tried locally). Every close goes through `CloseDialog` (pane, tab, other tabs, tabs to the right, workspace, the
  floating pane in its own window), Stop and Delete through Open Session's alert. **Tests:** Esc cancels the pane and
  tab dialogs; Return closes a pane, the floated pane and confirms Stop and Delete
  (`testClosingAPaneAsksUnlessOnlyItsShellRuns`, `testClosingATabAsksOnlyWhileAProgramRuns`,
  `testClosingAFloatedPaneAsksInItsWindow`, `testOpenSessionStopsAndDeletesASession`). Docs: D41, window.mdx.
  Found on the way: after Esc the pointer still on a capsule shows no ×, since its hover saw no end under the dialog;
  it shows once the pointer leaves and comes back (AppKit's tracking; not changed).
- **Item 10, the reds and flakes, each at its cause** (bullets from the fixers: swipe-flake-fixer, split-flake-fixer,
  misc-flake-fixer, and mine):
  - `testSwitchingTabsShowsTheirPageAtOnce`: red only on 511c1bd's old body; XCUITest's scroll is a wheel, which since
    13481fa turns a page with no motion under Reduce Motion. Lane G's 10370e7 posts a trackpad swipe, which follows
    the fingers; green since (40295293239, 40299936835, 40300354731, 40303429405, 40304560553 and every full run after).
  - `testTabAndOverviewSwipesFollowTheFingersAndLandSoon`: its reds were a clipped frame width (fixed in 10370e7) and a
    record filter that wanted more than 4 frames of an animated scroll (13b62ec). Green in the full runs after but one (lane M's jump bound, below); lane M
    owns it now (smooth paging).
  - `testSessionSwipeFollowsTheFingersAndSlidesOnFromTheirSpeed`, `testQuickSessionFlickLandsOnTheNextPageInStep`: the
    80 ms bound measured the show's own frame, and CI's VM drew no frame from 200 to 260 ms (40283556151:
    `…200:231,260:232`, shown at 262). **Fix** (c71cd9b): the bound reads the slide's last frame before the show's
    (18 ms in that run); a show in the spring's tail (phase 28's bug) still fails by 150–200 ms. The reds of
    40291250564 were the strip writing into the sidebar's record, fixed by lane G's 273d8cc.
  - `testQuickSplitsSplitTheNewestAndItKeepsTheKeyboard` and lane Q's A | C | B | D: one app bug. `Page.split` read
    the keyboard pane twice; a snapshot between the ⌘D and its task made the split before's pane the keyboard pane,
    so the ⌘D no longer matched `newest` and split the old card; that pane's pending keyboard request also landed
    after the next ⌘D and cleared `newest` (recordings of 40280765449 and 40277225989). **Fix** (845d9d9, 7781098): a
    ⌘D on the card that had the keyboard before the burst also goes to the newest; a ⌘D in a burst drops the older
    pane's keyboard request. The test asserts herdr's tree P | (Q | (R | S)).
  - `testDoubleClickRenamesAndEscapeCancels`: XCUITest sent a real double-click (clickCount 2, 0.1 s apart), but
    SwiftUI's `TapGesture(count: 2)` missed it while the first click's selection kept the app busy (0.35 s to draw).
    **Fix** (25afd2c, ad84bf5): the workspace row and the tab capsule start a rename on AppKit's own clickCount 2.
  - `testTabContextMenuRenamesAndMoves`: the right-click read the moved capsule's frame before the app drew it back
    and hit the middle tab (40262288574). The test waits for the drawn order (50e29b0).
  - `testGoToDirectoryAndInsertPath`: clicked the card of a tab not in view (made with focus:false); the strip slid
    back and the click hit the first tab. The test shows the tab first (3dd5754).
  - `testDroppingAFileFromFinderPastesItsPath`: Finder now and then started no drag on CI (no drag image in the
    recordings of 40274997505, 40277225989, 40304584542), always several tries in a row. Now
    `testDroppingAFilePastesItsPath`: a small window of `scripts/file-drag.swift` holds the file and
    `scripts/drag.swift` drags it (b9d6847, then the review's merge); 8 s instead of 11–29 s.
  - `testAgentGroupsFoldAndStayFoldedAfterARelaunch`: its body passed; its unfold teardown ran after the tabs closed,
    and XCUITest's menu click hit a menu that ended under it. The unfold now runs first (17c338f). A probe found no
    menu that closes by itself when tabs close.
  - `testOrielURLFloatsAPaneOfASessionWithNoPage`: its body passed; tearDown hovered `windows.firstMatch`, a floating
    window closing with its tab (INFINITY point). tearDown hovers the main window (cf86e78).
  - HerdrKit `relay carries runs over one process` (exit 9): the relay closed a run's stdin before its SIGKILL; the
    observe wrapper ends on EOF by itself (143) when the VM is slow. Reproduced with a 0.2 s sleep between the two.
    **Fix** (b5f09f3): kill first; 27 green runs under load.
  - `testMenuLightFollowsThePointer` (new red in 40309820769): the palette lit the row the pointer only crossed. A
    busy app ran the crossed row's hover late, with `NSEvent.mouseLocation` already on the next row, so the next row's
    hover saw no move. **Fix** (ab33702): only a pointer moved since the panel opened, or since keys or the filter last
    moved the light, lights a row; a row's own hover no longer resets that place.
  - Three reds in the first runs on 66f5097 (40319705774, 40319783362), none seen before:
    `testBlockedAgentNeedsYouAndThePopoverGoesToIt`: the recording shows the Agents panel gone before XCUITest's
    click reached its row (the pointer crosses the gap under the button); the busy app ran the panel's hover after the
    trigger's 0.15 s grace, and the click went to the card under it. **Fix** (c10dfaa): at the grace's end and on a
    click, a pointer inside the open panel's frame keeps it open, whatever its hover says (as ab33702 for the palette).
    `testHoverCardBlursTheTextBehindIt`: the click on the new capsule landed right of it (recording at the click), so
    the tab never showed and its hover card never came. Not proven why its frame was off then; likely the bar laid out
    again after `newTab`'s workspace change. `newTab` now also waits for the capsule's frame to rest (c5a9184).
    `testLayoutMotionAnimatesWithoutBlanking`: herdr's screen had lines 24–59 and then the prompt: the card attached
    after the lines, its resize made bash redraw the prompt over line 60. The test now waits for its card to draw
    before its fill (ac47679; the same wait in every `fill` failed, since a card of a tab not in view stays loading).
  - `testMoveToTabLandsBesideTheLastCard` (40330239513): the click on the moved card went to the last card
    (recording: keyboard in the middle card); herdr's order came before the app drew the card there. The test waits for
    the drawn order (95663e5), as 50e29b0 does for capsules.
  - `testEditingARemoteHostRenamesItAndRemoveTakesItOff` (40335691646): the machine menu, opened while the remote
    page's cards still loaded, closed under XCUITest's click into its submenu (recording). The test opens it once the
    page drew (8aaea72). Likely the same for a user who opens it in the first second after a remote launch; not changed.
  - `testTabAndOverviewSwipesFollowTheFingersAndLandSoon`, lane M's new jump bound (40335707458): one frame's offset
    came late and the next caught up (50 pt in 28 ms, then 111 pt in 21 ms). The bound now holds over two frames
    (3.3k pt/s there, bound 4.9k); the old spring's jump lasted several frames (bb3899b).
  - `testFloatingWindowOpensLargeWithTheMainWindowsTitleRow` (40335691646, 40342555702): XCUITest failed it inside
    `hasKeyboard` ("Failed to get matching snapshot"): its `exists` bound the terminal, and the focus read a moment later
    found that element gone as the floating window came forward. `hasKeyboard("id", in:)` is now one query with the
    focus in its predicate (7c2f95c, 57 call sites).
- **Item 9, CI** (plan/ci.md, "Phase 31"): 5 jobs, lint/build/HerdrKit on job 0; tests split by measured time
  (`scripts/shard.py`, `scripts/test-times.tsv`); the stress, cost, frame-record and look-scene tests on demand
  (`make e2e ON_DEMAND_ONLY=1`, the `on_demand` dispatch input), with one recorded tab change kept in every run
  (`testATabClickComesIntoViewWithoutAFlicker`); the swipe and drag helpers compiled once. Before: 40300354731, push to
  done 14 min 13 s, jobs to 12 min 50 s, 2382 s of tests. After: 40347859891 (7c2f95c): start to done 13 min 34 s with 1 min 45 s waiting for runners, jobs 9 min 29 s – 11 min 48 s, 2302 s of tests; 40317477966: 12 min 10 s. **7–8 minutes is not reached:** about 2 minutes of
  setup and build per job plus a fifth of about 2300 s of tests is 9–12 minutes, depending on the VMs (40309820769:
  jobs 8.4–9.1 min; 40312470304: 10–14 min, every test 28 % slower). It needs about 1500 s of tests on 5 runners or
  about 8 runners; each runner more saves about a minute. The slow tests have no idle waits to cut.
- **Item 10, proof.** Two full runs in a row on 7c2f95c (my last code commit), each green on its first try: 40347859891
  and 40347875413. Before them every full run had found one or two rare flakes (the list above); each got a fix at its
  cause. Earlier single greens: 40300354731, 40312470304, 40317477966, 40328866622, 40342540801.
