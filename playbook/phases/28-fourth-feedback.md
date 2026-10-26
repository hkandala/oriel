# Phase 28: The user's fourth round of feedback

The user recorded a 5-minute Scrawl capture on 2026-10-25 (16:26): voice, clicks and red marks over Oriel.
Bundle: `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1792970538277-6f5d.scrawl`.
Read it with the scrawl skill (`/Users/hkandala/.agents/skills/scrawl/SKILL.md`): `summary.md`,
`contact-sheet.png`, `frames/frame-NN.png`, and `scrawl zoom "<bundle>" --at M:SS --span S --frames N`
for motion. Speech recognition mishears words ("Oreo"/"ovary" = overview, "pain" = pane, "herder" = herdr).
Moments are named like "#3 (1:08)". Each lane writes `## Findings` at the end.

The user may be testing on this Mac: `/tmp/oriel-gui.lock` is held for "user"; UI tests run on CI until
the orchestrator says otherwise.

## Lane E: empty session and session swipe (items 1, 2)

1. **Empty session** (#1 0:07): a session with no workspace shows a "+ New Workspace" button in the
   middle of the window (and one in the sidebar). The user wants no button in the middle: an icon and a
   short line that says the session is empty (the user asked for this text; it overrides the no-hint
   rule here). The sidebar's + stays.
2. **Session swipe lags** (#2 0:30, then the swipes at about 0:33–0:46): "this used to be smooth before;
   now it gets stuck". Phase 27 lane T3 rewrote the swipe (its Findings). Look at the recording frame by
   frame (`scrawl zoom … --at 0:33 --span 14 --frames 40`), find what stalls (the sidebar page and the
   strip move out of step in some frames), and make it smooth again: the page follows the fingers, then
   finishes without a stop or a jump. Check with local Retina recordings when the GUI is free.

## Lane V: overview (items 3, 4)

3. **No fade while scrolling the overview** (#3 1:08, #4 1:32): tiles of tabs not opened before fade in
   as they scroll into view. While the overview is open, keep every tile's terminal of every session in
   the overview alive and drawn (not only the laid-out ones), so scrolling never shows a fade. The user
   accepts the memory while the overview is open; on leaving, the overview-only terminals go as now
   (phase 27 lanes A3 and V).
4. **Overview chrome** (#5 2:08): remove every title-row item in the overview (machine button, Agents,
   the overview button, ⌘ palette); keep only the traffic lights and one × button that leaves the
   overview. More room on all four sides (the user asked again: top, bottom, left and right), like the
   user's reference (`overview.png`, phase 27): the grid sits centered with wide margins.

## Lane F: floating window and placeholder (items 5, 6)

5. **Floating window** (#7 2:54): open a bit taller by default. In the title row, the pane's name and its
   place ("hkandala-mbp › oriel › oriel") run together; give them a clear hierarchy, for example a thin
   vertical separator between the pane's info and the place, with the place in quieter text.
6. **Placeholder in the tab** (#8 3:20): today it shows only the pane's info line in an empty card, which
   reads as nothing. Show that the pane is open in a floating window: a short line saying so, and a
   button ("Show Pane") that brings the floating window forward (the user asked for this text).

## Lane R: remote hosts (items 8, 9, 10, 11)

8. **A remote machine opens in a new window** (#10 4:18): Add Remote Host and picking a machine in the
   machine menu open a new window for that machine; the current window and its sessions stay.
9. **No server banner in errors** (#11 4:29): the Disconnected page showed the server's login banner
   ("… authorized users only …") above ssh's error. Show only ssh's own error line(s), never the banner
   (ssh's `-q` or `LogLevel=ERROR` on the master, or drop banner lines). Nothing in the repo may name a
   company or its servers: make docs and plans generic ("a server with one-time passcodes").
10. **ssh's question sheet** (#12 4:54): make it fit the app (glass, the palette's look, the app's
    typography) instead of a plain macOS sheet.
11. **Secret answers are hidden:** in #12 the one-time passcode showed as plain text, because only
    "password", "passphrase" and "PIN" prompts got a hidden field. Every answer is hidden except the yes/no
    host-key question.

## Lane F, also: herdr popups through Oriel (item 7, #9 3:46)

7. herdr 0.9.5 tells API clients nothing about plugin popups (phase 27 lane F3), so the user chose
   option 1: an `oriel://` URL that any tool can open to float a pane, and pi-herd uses it when the click
   came through Oriel.
   - **Oriel:** register the `oriel` URL scheme; `oriel://float?session=<herdr session>&pane=<pane id>`
     (optional `machine=`) opens that pane in Oriel's floating window over the frontmost main window, even
     when that session is not open as a page in any window (load it for the float without adding a page).
     Opening it again for the same pane brings the window forward. Unknown session or pane: a notice, no
     window.
   - **How pi-herd knows:** the click reached pi through Oriel exactly when Oriel is the frontmost app
     (another client would be frontmost otherwise). pi-herd checks the frontmost app on macOS only
     (`lsappinfo front` then its bundle id, a few ms, at click time only); when it is Oriel
     (`dev.hkandala.oriel`) it runs `open -g "oriel://float?…"` for the agent's pane in the pi-herd
     session, else it opens herdr's popup as today. On Linux or over SSH it always uses herdr's popup.
   - **pi-herd** is in the user's repo `/Users/hkandala/code/pi-hkandala/extensions/pi-herd` (the popup
     code is in `herdr.ts` `popupCommand` and `index.ts` around "Views an agent"). The user allowed this
     change. Follow that repo's own AGENTS.md and commit rules; keep the change small.
   - An issue or PR to herdr upstream is not part of this.

## Findings

### Lane R (items 8–11)

- **Root causes.**
  - 8: the machine menu and Add called `WindowPages.show(machine:)`, which left every page of the window and
    opened the machine's `default` in it. Now both call `WindowPages.open(machine:connect:)`: a static hand-off
    (`opening`) that the new window's restore takes; Add also connects there, so ssh asks in the new window.
    The current machine does nothing; the ⌥-click path is gone. ⌘N now keeps the window's machine, as
    window.mdx already said (it always opened This Mac).
  - 9: the master's start output (stderr merged) was shown whole on Disconnected, and OpenSSH prints the
    server's login banner there at LogLevel INFO. The master now runs with `-o LogLevel=ERROR`: only ssh's
    error lines (fatal, error) remain. That also hides "Connection closed by …" (logged at INFO), so a start
    that fails with no text says "The connection to ‹target› closed (ssh exited N)".
  - 10: the question was a plain `.sheet`. It and Add Remote Host are now one `dialog()` overlay: the palette's
    `floatingGlass`, 14 pt corners, 13 pt type, the field in the palette's capsule (`fieldCapsule()`, now shared
    with `FilterField`), `.glass` / `.glassProminent` buttons, the machine's icon and name as the title. The
    window behind takes no clicks; only the buttons close it (Esc is Cancel).
  - 11: the hidden field depended on the prompt naming "password", "passphrase" or "PIN"; "Passcode:" did not.
    Now every answer is a `SecureField`; only the host-key yes/no has no field.
- **Company names:** the plans (phase 26 round 2) no longer name the user's servers or their OTP product; the
  Meta (Muse) program icon is gone (catalog, `build.mjs`, SOURCES, svg, image set, contact sheet regenerated
  with the pinned packages: only that entry changed). Left on purpose: generic tool logos (GitHub, AWS, …),
  "muse" in third-party research notes quoting upstream agent lists, and git history.
- **Tests.** CI's sshd has a generic `Banner`; `testAPasswordHostAsksAndNeverRetriesByItself` checks the
  Disconnected text has "Permission denied" and not the banner, and that the host key and password are asked in
  the new window while the first keeps its page. `testAddingAKeyHostOpensItInANewWindowWithoutAsking` checks
  the new window's machine (`window.machine` test value), the first stays This Mac, the window's own machine in
  its menu opens nothing, a pick in the first window opens another Key Host window, and ⌘N there stays on Key
  Host. `testWindowsOnDifferentSessionsEachControlTheirOwn` opens its second window with ⌘N (no ⌥-click).
  The hidden field is asserted on the password prompt only: no CI prompt lacks the word, and the code no longer
  branches on it.
- **Accepted (nits).** While a dialog shows, the window's menu commands (⌘W, ⌘T, ⌘K) still act on the page
  under it, and Tab can leave the dialog; a sheet blocked both. Two machine picks before the first new window
  restores give the second This Mac (`ponytail:` on `opening`). No test presses Esc on the dialog.

### Lane V (items 3, 4; phase 29 items 4–6)

- **Root cause, item 3.** The overview's pages, workspaces and tiles sat in lazy stacks, and phase 27 (6f33fad)
  streamed only the tiles the grid laid out. A tile scrolled into view was made then: its card's terminal view
  entered the window, libghostty builds a surface only in a window (`AppTerminalView.viewDidMoveToWindow`), the
  stream opened, the new surface (clear) waited 100–400 ms for herdr's frames and its first reveal faded in over
  0.12 s; a tile scrolled away freed its surface. Frame 11 of `scrawl zoom … --at 1:08` shows three empty tiles.
- **First fix, replaced** (aa8a5e1): nothing lazy, every card of every session live while the overview is open.
  The user's stress test (hundreds of agents on a remote server) made it very laggy and its memory followed the
  session, so the orchestrator changed the rule: bounded live tiles plus cached snapshots.
- **Design now** (53f8af6, bebc6b1, f775c07, c7a6b88, 60d831e, 4d3ae63, 2b1d93c, 63f685c). One `LazyVGrid` per
  session page (fixed columns, a section per workspace, the title above it). A tile reports
  `onScrollVisibilityChange`; 150 ms after the last tile came into view (a debounce, so a scroll makes no surface or
  stream on the main thread), `showTerminals` streams the cards of the page in view's visible tiles, whole tabs,
  the latest in first, up to 16 cards (6 on a remote machine, whose streams share the relay's one SSH session),
  plus the selected tab's; tiles scrolled away let go then. Every terminal that stops drawing (strip or tile)
  leaves a snapshot: an IOSurface at most 360 px wide (about 0.4 MB), the 256 latest kept, shown by every tile that
  is not live. A tile turning live keeps its snapshot as the terminal's still over the new surface until that drew
  (`dropPicture`, then `coverNewSurface` and `dropStill`), so it turns live in place; a reveal inside a miniature
  never fades; a terminal never shown shows the card's fill. An overview-only terminal keeps no full picture when
  it lets go (a full-size IOSurface each, 4.4 GB after a 200-tab scroll before 4d3ae63) and gets no terminal object
  until it is live. Kept (visited) terminals are as lane A3 left them: they come back to the strip at once.
- **Root causes on the way.** (1) Row ids repeated across workspaces in the lazy stack (`id: \.self` on each
  workspace's row starts), so later workspaces' rows never showed (CI 40252351835, 40254270873). (2) A
  `CGImage` snapshot was copied again by Core Animation (CoreImage 236 MB plus CoreAnimation 242 MB after one
  scroll): IOSurfaces now, shown as layer contents. (3) `keepPicture`'s full copy for every overview-only terminal
  leaving a tile (a 17–50 MB memcpy each, on the main thread): only kept terminals copy now. (4) A scroll-phase
  gate stuck on; a debounce instead.
- **Item 4** (a2b2677, aa8a5e1). In the overview the title row is the traffic lights and one × (`overview.close`,
  "Close Overview ⌃⌘O"), which leaves by the zoom; ⌘K and ⌘. still work. Margins: 8 % of the width left and
  right (at least 48 pt), 40 pt above and below; 2–4 columns of 340 pt tiles between them.
- **Phase 29 item 6** (3f48029): the zoom takes 0.18 s (was 0.25), and the overview fades in over 0.18 s when it
  opens (at once under Reduce Motion). **Item 5** (the flicker after zooming into a tab not shown) went to phase
  29 lane T: a new strip's empty scroll position draws page 0 for one commit.
- **Numbers, phase 29 item 4** (`testOverviewOfManyTabsStaysBounded`: `scripts/stress.py` 200 tabs, 8 workspaces,
  272 panes, 50 agents; 20 trackpad swipes down, 4 back; this Mac, Retina):

  | | Strip | Overview open | Scrolled through |
  |---|---|---|---|
  | Every card live (aa8a5e1, CI 1x, 17 cards) | 85 MB | 205 MB, 14 % | the same |
  | 24 live, `CGImage` snapshots (Debug) | 229 MB | 1829 MB | 2412 MB |
  | 16 live, IOSurface snapshots, no overview-only copies (Release) | 226 MB | 1190 MB, 14 % | 1.2–1.7 GB, 17 % |

  At most 18 herdr runs at any time (the strip's 2 plus 16). Frames while scrolling (XCUITest attached, Release):
  212 hitches in 3500 frames (6 %); lane S's baseline on this Mac with XCUITest attached reads 25–30 % (Debug),
  without it 0.5 % (sidebar) to 2–4 % (tab bar); `sample` during the scroll found the main thread about 95 % idle.
  CI's VM (no GPU) reads 40–50 % for any scroll, so the hitch rate is recorded (`app.latency`), not asserted. The
  footprint is bounded by the cap (16 full-window cards are about 1.1 GB on Retina), not by the tab count.
- **Tests** (`OverviewTests.swift`). `testOverviewOfManyTabsStaysBounded` (new): streams ≤ strip + 16 + 2 during
  the swipes, snapshots kept, footprint < strip + 1.6 GB, plus `sample` and the frames. `testOverviewCostsAndLetsGoAfter`:
  tiles in view stream, ≤ strip + 18 after the scroll, and scrolled back, a tile that was live shows its snapshot
  or terminal at once (`overview.card.‹pane›` never "empty"). `testOverviewShowsEveryTabLiveAndOpensOne`: no
  title-row button but ×, the margins (left = right = 8 % / 48 pt, 40 pt above), w2's row made live as it scrolls
  in, × leaves. The stress test is on demand (`ON_DEMAND` in the Makefile, with lane S's): run it with
  `make e2e ONLY=…` or `only_testing`. `testOverviewZoomIntoAnUnshownTabShowsItSteadily` (lane T took the flicker). The remote cap of 6 has
  no test (CI's remote host has no overview scenario).

### Lane F (items 5, 6, 7)

- **Item 5, root cause.** `FloatReader.frame(over:)` made a new window 60 % of the main window's height. In the
  title row, `PaneInfo`'s folder and the place line were both `.secondary` with only the 8 pt stack gap between,
  so "pi ~/code/oriel" and "hkandala-mbp › oriel › oriel" read as one run. Now 75 % of the height (floor 460 pt;
  a 560 floor made CI's 674 pt window almost all float), a 1 pt `look.divider` line 12 pt tall (as the
  collapsed sidebar's workspace button) and the place in `.tertiary` (4bdb56a, c8a256e). A frame AppKit saved
  for a terminal floated before still wins (autosave per terminal).
- **Item 6, root cause.** Phase 27 lane F3 made the placeholder the pane's quick info on a card-wide button: the
  card's header already says the same, so the body read as empty. Now "This pane is open in a floating window."
  (secondary) and a glass **Show Pane** button, centered (4bdb56a). The button is in the card's middle, which a
  new float (centered over the main window) covers until the main window comes forward; the tests click the
  main window first (c8a256e).
- **Item 7.** `oriel://float?session=…&pane=…[&machine=…]` (9f0caf9, 1316f18): the front main window of the
  machine floats the pane. A session with no page there gets a float-only page (`WindowPages.floatOnly`): its
  store connects, no sidebar row, no strip page, never settled (so no selection, and a float never hands its
  cards the keyboard), not saved; `Page.floating`'s `didSet` drops it with its last float (detach, red light,
  herdr closed the pane, window closed). Open Session on that session makes it a page with its floats. The
  lookups the floating window, the registry and `showTerminals` use go over `withFloats`; the overview's
  every-card streaming (lane V) stays on `list`. Unknown pane, session or machine: a warning notice in the front
  window. No window at all: one opens and floats it (`early`).
- **pi-herd** (pi-hkandala d7db340, 32de79e). `attach`: outside a popup, when the frontmost app is Oriel
  (`lsappinfo info -only bundleid "$(lsappinfo front)"` has `"dev.hkandala.oriel"`; macOS only, never with
  `SSH_CONNECTION`, asked at click time, about 40 ms), it runs `open -g "oriel://float?session=<socket's
  session>&pane=<pane>"`, for every agent: also one on the same server (Oriel shows neither herdr's popups nor
  its focus, D13) and from the `pi-herd` session itself. Else as before. `npm run check` green; `sessionOf` and
  `orielInFront` checked with node on this Mac.
- **Tests.** `testFloatingWindowOpensLargeWithTheMainWindowsTitleRow` (75 %, the 17 pt gap of the line, the
  placeholder's text and its centered Show Pane), `testOrielURLFloatsAPaneOfASessionWithNoPage` (no page, keys
  reach two's pane, again = the same window, the no-pane and no-session notices, Detach ends two's runs, a page's
  pane in a workspace not in view), `testOrielURLFloatGoesWithItsWindowAndOpensOne` (closing the main window ends
  two's runs; a URL with no window opens one; Open Session keeps the float and the connection).

### Lane E (items 1, 2)

- **Root cause, item 1.** `Detail` drew the same `NewWorkspaceButton` as the sidebar page for a session with no
  workspace. Now the strip shows `ContentUnavailableView` "This session is empty" with an icon (`square.dashed`),
  only while the session is live (not while it reconnects before its first snapshot); the sidebar page keeps its
  New Workspace button and the header's `+`.
- **Root cause, item 2 (from the recording).** Frame by frame at 60 fps (`scrawl frames … --fps 60`, 0:36.4–0:40.4):
  a quick flick (the fingers on the pad about 40 ms, then momentum) moved the pages about 45 pt in one frame, then
  they stood still for 0.65–0.7 s. Then the window showed the next session while the pages snapped back to the old
  one, and about 0.45 s later the old session came back (0:37.7–0:38.9 and 0:39.5–0:40.3). That is phase 27's
  0.6 s fallback: the slide asked of SwiftUI's scroll view (`ScrollPosition.scrollTo(id:)` while the router held
  back the gesture's end) did not run. Then the fallback handed the end to the scroll view (its snap goes to the
  nearest page) and showed the target session; at idle the scroll position showed the first again. The slides that
  ran still showed their session 150–200 ms after the pages looked arrived: it waited for the spring's tail to
  come within 0.5 pt. CI did not reproduce the stall: its slow VM posts a flick's moves about 50 ms apart, so the
  old code took the flick for stopped fingers (`ev` notes in run 40251702377).
- **Fix.** The sidebar's session pages are no longer a scroll view: an `HStack` offset by `Swipe.slide` (in pages,
  `@Observable`, read only by `Pager`), through `Slid` (Animatable, so the e2e record reads every frame). The router
  finds them by their frame in the window (`ScrollAnchor.area`, from SwiftUI's `.global`) and gives them every move
  (`drag`), the lift with the fingers' speed (`lift`), drops the momentum, and turns one page per sideways wheel
  burst. The lift slides with the session spring and shows the session at `.logicallyComplete`, not after the tail.
  At rest only the page in view is laid out (a laid-out page past the clip widened the sidebar's accessibility frame
  to every page, so XCUITest's center fell on a page edge). The others come in, one update before an animated
  slide (in the same one the offset from rest would slide too). A swipe mid-slide starts from the drawn offset
  (`Swipe.drawn`). Removed: `SwipeRouter.finish`, the held end, the 0.6 s fallback, `ScrollPosition` and the scroll
  phase handling in the sidebar.
- **Deviations.** Fingers count as stopped after 0.1 s without a move, not 50 ms (CI). XCUITest's `scroll` over the
  sidebar is a phase-less wheel: it now turns a page and leaves no swipe record, so `testPanelsAndSwitchesReactAtOnce`
  no longer counts swipe records. `Swipe`, `Pager` and `Slid` live in SwipeRouter.swift (Sidebar.swift's 400 lines).
- **Regressions on the way (fixed).** 945a762–94cf490: no swipe reached the pages (the sidebar's accessibility frame
  covered both pages, the test's center fell on the edge). 8c524dd–643e336: a page not laid out was an empty `Group`,
  which takes no room, so every page but the first showed blank at rest (the user saw it, and
  `testClosingAPageAndQuittingLeaveNoStreams`). 8c524dd also deleted `Latency.note`, which lane M had started to use:
  main did not build until ad8952c.
- **Tests.** `testQuickSessionFlickLandsOnTheNextPageInStep` (3 moves of 20 pt then momentum: lands, rests on the
  shown session, no gap over 100 ms, shown within 80 ms of the pages within 2 pt), `testSessionSwipeFollowsTheFingers…`
  (the same show timing), `testSwipedSessionPagesShowTheirRows` (three sessions: the swiped-to page's rows on screen
  and hittable at rest), `testSwipesPageTheSidebarAndTheStripApart` (a strip swipe 30 pt into the card, where page
  two lay), `testEmptyPageOffersNewWorkspace` (one New Workspace button, "This session is empty" in the strip).
- **Local, Retina, debug, motion on** (6d0acf9): a frame every 8 ms from the lift (140 pt) to the page, within 2 pt
  at about 150 ms, the session shown at 208 ms.

