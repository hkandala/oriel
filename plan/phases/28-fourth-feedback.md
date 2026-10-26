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

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each
  lane's last code commit; one review round per lane (spec and ponytail, read only).

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
- **Reviews (one round).** Ponytail: 12 items, no blocker; fixed 1–4, 9–11 (stale "sheet" wording, the
  `keep` func inlined, shorter docs); 5–6 (move `dialog()`/`fieldCapsule()` to Style.swift) not done: Style.swift
  is at the 400-line limit. Spec: 8 items, no blocker; fixed 1 (closed-connection text), 2 (no hand-off without
  an opener), 5–6 (the machine of each window, ⌘N and the menu), 8 (docs); 3, 4, 7 above.
- **CI.** Dispatch 40246511257 (f15de32): the key host test red (the new window lay over the first, so the
  click hit its menu; fa83cc6 raises the first), the rest green. 40247028967 (fa83cc6): both remote tests
  green. 40247752826 (f3626b4, after the reviews): the four remote and window tests green. Full
  suite 40247826547 on 6a1946d (code as of 0914774, the lane's last code commit): every remote and window test
  green (all six of RemoteTests, testWindowsOnDifferentSessionsEachControlTheirOwn, testMachineMenuListsThisMac);
  red only in other lanes' areas: testEmptyPageOffersNewWorkspace and the swipe tests (lane E),
  testOrielURLFloat* (lane F).

### Lane V (items 3, 4)

- **Root cause, item 3.** The overview's pages, workspaces and tiles sat in lazy stacks (`LazyHStack`,
  `LazyVStack`, `LazyVGrid`), and phase 27 (6f33fad) streamed only the tiles the grid laid out. A tile scrolled
  into view was made then: its card's terminal view entered the window, libghostty builds a surface only in a
  window (`AppTerminalView.viewDidMoveToWindow`), the stream opened, the new surface (clear) waited 100–400 ms
  for herdr's frames to settle and its first reveal faded in over 0.12 s; a tile scrolled away freed its surface
  again. Frame 11 of `scrawl zoom … --at 1:08` shows three empty tiles at the top while the user scrolls.
- **Fix** (aa8a5e1). Nothing in the overview is lazy: an `HStack` of pages, a `VStack` of workspaces, rows of
  `columns` tiles (`HStack`s with clear fillers, so a short last row keeps the tiles' width). Every terminal
  view of every session in the window is in the window, and `showTerminals` streams every card of every page
  while the overview is open, each made with its own page's client (no visits, as before; on leaving the
  overview-only ones let go as in phase 27). The tile-tracking (`overviewTabs`, `laidOut`, `cardTerminals`) is
  gone. The zoom leaves at once when the selected tile is out of view (its frame outside the canvas). Remote
  machines are no longer left out: the rule came from the SSH session cap, which lane R2's relay (one SSH
  session per host) removed.
- **Item 4** (a2b2677, aa8a5e1). In the overview the title row is the traffic lights and one × at its end
  (`overview.close`, "Close Overview ⌃⌘O"), which leaves by the zoom; the machine button, Agents, the overview
  button, ⌘ and the hidden sidebar toggle and + are gone (`TitleBar.row` is the normal row). ⌘K and ⌘. still
  work. Margins all round: 8 % of the width left and right (at least 48 pt), 40 pt above and below; the
  columns (2–4 tiles of 340 pt) come from the width between them.
- **Numbers** (CI 40246320315, 1x, `testOverviewCostsAndLetsGoAfter`, 17 cards of which 8 print): strip 85 MB,
  1.5 % CPU, 4 herdr runs; overview open 205–208 MB, 14 %, 17 runs (every card at once; phase 27's lazy grid:
  134 MB with 8 runs); scrolled to the end the same 17 runs; closed 108 MB, 0.7 %, 4 runs. On Retina expect
  about 52 MB per full-window card while the overview is open (phase 27: 902 MB with all 17 laid out).
- **Tests** (`OverviewTests.swift`). `testOverviewCostsAndLetsGoAfter`: on open every pane of the session
  streams (`helpers ≥` herdr's pane count), the last tile below the window's edge already has a surface (its
  terminal's grid value) before any scroll, and scrolling lets none go. `testOverviewShowsEveryTabLiveAndOpensOne`:
  no title-row button but × (`titlebar.sidebar`, `.machine`, `.agents`, `.overview`, `.palette`, `.new-tab` gone),
  the margins (left = 8 % / 48 pt, right = left, 40 pt above), × leaves. Each fails on the old code.
- **Reviews.** Spec: no blockers; shoulds were stale doc lines (leaving by ⌘. and the Agents button, the remote
  limit, the lazy cost) and the Findings. Ponytail: no blockers; stale comments, the cost bullet, a redundant
  assert; `Grid` instead of the rows was offered as a nit and not taken (flexible `Grid` columns follow their
  widest cell, so a one-tab workspace would get one wide column without fillers anyway). Fixed in 802e3c7.
- **CI.** 40246320315 (the three overview tests, green on aa8a5e1). Full suite on 802e3c7, the lane's last
  code commit: see below.
- **For the user to check by hand:** ⌃⌘O in a busy session with many tabs, never opened ones too: scroll fast
  down and up and swipe between sessions: no tile empty or fading; the title row (lights and × only) and the
  margins against your reference; × and Esc leave with the zoom; `footprint` while open (about 52 MB per
  full-window card on Retina) and back after it closes.

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
- **Learned.** SwiftUI swallows a custom-scheme URL when every scene has `handlesExternalEvents(matching: [])`:
  `application(_:open:)` never ran (CI 40246598046). The app installs its own `kAEGetURL` handler in
  `applicationWillFinishLaunching` and hands the URL to `application(_:open:)`. `XCUIApplication.open(_:)` on a
  running app left it "not foreground" for XCUITest after a second URL (CI 40247366831); the tests open the URL
  with `open -g -a <app>` through the e2e helper (`open-url`), as pi-herd does. SwiftFormat's `andOperator`
  turned `guard a ? b : c && d` into `guard a ? b : c, d`, which changes its meaning: the overview guard now
  uses a `tiles` local.
- **pi-herd** (pi-hkandala d7db340, 32de79e). `attach`: outside a popup, when the frontmost app is Oriel
  (`lsappinfo info -only bundleid "$(lsappinfo front)"` has `"dev.hkandala.oriel"`; macOS only, never with
  `SSH_CONNECTION`, asked at click time, about 40 ms), it runs `open -g "oriel://float?session=<socket's
  session>&pane=<pane>"`, for every agent: also one on the same server (Oriel shows neither herdr's popups nor
  its focus, D13) and from the `pi-herd` session itself. Else as before. `npm run check` green; `sessionOf` and
  `orielInFront` checked with node on this Mac.
- **Reviews.** Ponytail: no blockers; `takeFloatOnly` inlined into `open`, one lookup (`floatPending` holds the
  page), comments. Spec: shoulds fixed: a second pending URL dropped the first one's page, notifications for a
  session whose first window has it only float-only, no window (opens one), unknown machine (notice), D50 and the
  window page, tests for Open Session on a float-only session and for closing the main window, pi-herd's
  `pi-herd`-session refusal before the Oriel check. Left: one `early` slot (a URL and a notification click at
  launch: the later wins); a notice shows in every window on the current session.
- **Tests.** `testFloatingWindowOpensLargeWithTheMainWindowsTitleRow` (75 %, the 17 pt gap of the line, the
  placeholder's text and its centered Show Pane), `testOrielURLFloatsAPaneOfASessionWithNoPage` (no page, keys
  reach two's pane, again = the same window, the no-pane and no-session notices, Detach ends two's runs, a page's
  pane in a workspace not in view), `testOrielURLFloatGoesWithItsWindowAndOpensOne` (closing the main window ends
  two's runs; a URL with no window opens one; Open Session keeps the float and the connection).
- **CI.** 40245708850 (Show Pane under the taller float: fixed in c8a256e), 40246598046 (the URL never reached
  the app), 40247366831 (`XCUIApplication.open`), 40248364247 (a Detach click under the main window),
  40249713224 (both URL tests green on 3d1f6db). Full suite 40250012874 on 5980a94 (after 3d1f6db, the lane's
  last code commit): every floating, URL, key and Dock-drop test green; the reds are other lanes' areas: the
  session swipe tests (`testPanelsAndSwitchesReactAtOnce`, `testQuickSessionFlickLandsOnTheNextPageInStep`,
  `testSwipesPageTheSidebarAndTheStripApart`, `testSessionSwipeFollowsTheFingersAndSlidesOnFromTheirSpeed`) and
  `testGoToDirectoryAndInsertPath`.
- **For the user to check by hand:** float a pane never floated before (a saved frame wins): taller, the line
  between the pane and its place, the place quieter; the placeholder's line and Show Pane in a small split; in
  pi, from Oriel, open a `pi-herd` agent from the dashboard or pi-footer (after `/reload`): it opens in Oriel's
  floating window, not herdr's popup; again brings it forward; from the herdr TUI (another app in front) it
  stays herdr's popup. `open -g "oriel://float?session=<s>&pane=<id>"` from a shell does the same.
