# Phase 27: The user's third round of feedback

The user built main at about 04:20 on 2026-10-25 and tried phases 24–26. The orchestrator settled the open
points; each lane writes `## Findings` at the end. Read the Findings of phases 24 and 25 first: most items
change code those lanes wrote.

The user is testing on this Mac: `/tmp/oriel-gui.lock` is held for "user" until the orchestrator says
otherwise. UI tests run on CI (Reduce Motion is on there; `-forceMotion YES` turns motion on).

## Lane A3: live surfaces stay (item 1)

1. **Going back to a tab must show at once.** Lane O freed the libghostty surface of every hidden terminal
   past the 4 most recent, so a tab visited a while ago fades in when shown again. The user accepts more
   memory for snappiness. Keep the surface (and stream) of terminals the user has visited, drawing paused
   while hidden, so showing them again is instant: no rebuild, no fade, no wait for herdr's frames. Look
   at how Ghostty does it (its surfaces for hidden tabs and occluded windows: what it keeps, what it
   pauses, whether it shrinks or drops the swap chain), and copy that. Free surfaces only past a memory
   budget chosen from measurements (for example the last 16 visited terminals, or about 600 MB), oldest
   first. Lane O's other wins stay: dots on Core Animation, hidden terminals not drawing, no surface before
   the first stream. Measure before and after (lane O's scenario and numbers in phase 25's Findings).

## Lane G3: agents sidebar (items 2–5)

2. The sort control reads "Workspace" (not "Workspace order") and "Priority", and looks like a small
   button (a capsule with a fill on hover, like the header buttons), not plain text.
3. **The session named `default`** is not shown by that name anywhere in the sidebar header: it shows the
   machine's name instead ("This Mac", or a remote host's name). Other sessions show their own name. The
   Open Session panel and the palette keep the real session names.
4. The session name in the header is the rows' size, bold (not larger).
5. **Collapsible groups:** each group header (a status in Priority, a workspace in Workspace) folds and
   unfolds its rows with a chevron; the folded state is kept per session and mode across relaunches. A
   folded group keeps its header and count.

## Lane T3: tabs, panes and motion (items 6–9)

6. **⌘T fast, then ⌘W fast:** after several quick ⌘T, each ⌘W closes the shown tab and goes to the one
   used before it, one step back each time, even while the new tabs are still stand-ins or their shells
   are starting. Now it jumps to a tab whose shell has loaded. The tab history must follow a stand-in to
   herdr's real tab id.
7. **Closing a pane** gives the keyboard to the pane used before it in that tab (most recent first), as
   closing a tab does; else the neighbor as now.
8. **Pane motion faster:** split, close and zoom about a third shorter than lane A2's.
9. **Session swipe:** lane S's spring (response 0.14 s) feels too fast and odd. Make it calm and quick:
   somewhere between the tab spring and lane S's, no bounce, and the page must track the fingers during the
   swipe and finish from the release speed. Check it on the CI recording with motion forced; the user
   judges by hand.

## Lane F3: floating panes (items 10–14)

10. A new floating window opens bigger: about 60% of the main window's size (at least 720 × 460 pt),
    centered over it.
11. **The placeholder** in the tab shows the pane's quick info like the floating window's title row (icon,
    program, folder, agent status) and the whole card is a button that brings the floating window forward;
    drop the separate Show button.
12. **The floating title row** is taller: room above and below the traffic lights like the main window's
    title row (match its height and the lights' position).
13. **Its buttons** (pin, Close, Detach) use the same icons, size, weight and color as the card header
    buttons and the main title row; they look like one app.
14. **herdr's own floating panes.** herdr shows popups from plugin panes (`placement = "popup"` in a
    plugin's `herdr-plugin.toml`; methods `plugin.pane.open`, `plugin.pane.close`, `popup.close`; events
    `plugin_pane_opened`, `plugin_pane_closed`; see `herdr api schema --json`). Example: the user's pi-herd
    extension (`/Users/hkandala/code/pi-hkandala/extensions/pi-herd`, plugin in
    `/Users/hkandala/code/pi-hkandala/herdr/plugin`) opens an agent in a popup from pi-footer. When herdr
    opens a popup in a session Oriel shows, Oriel opens its floating window for it, streams it, and closes
    it when herdr closes the popup; closing or detaching the window closes the popup in herdr
    (`popup.close`). It must work for any plugin popup, not only pi-herd's. Find what the snapshot and the
    events give (is a popup a pane with a terminal id? its size?) before building. Phase 25 lane F2 said
    "herdr's popup is not a pane": check that again with the plugin API.

## Lane V: overview instead of tab previews (items 15, 16)

15. **Drop the tab preview** in the hover card (phase 25 lane T's TabPreview, its read loop and timer):
    the hover card goes back to its state before lane T (title, rows, the needs-you lines). Keep lane T's
    card rim (item 28).
16. **Overview** (`.build/fb/overview.png`, phase 25 item 29): a mode that hides the tab bar and sidebar and
    shows a canvas of live tab previews. Each tab is a miniature of its real layout at its real proportions,
    drawn live (not text), with its title row. Tabs are grouped under their workspace's name; scrolling
    vertically goes through the workspaces of the session; scrolling horizontally (or swiping) goes to the
    next session of the window. Clicking a tab leaves the overview and shows that tab, zooming from its
    miniature to the full window. A title-row button, a command (palette, View menu) and a key toggle it
    (pick the key with lane I2's pattern in phase 25; ⌃⌘O or similar, not taken). Esc leaves it.
    - Live miniatures must be cheap: decide from measurements how to draw them (for example a small
      observe-only surface per terminal with a scaled font, or the live surfaces of lane A3 scaled down).
      Write the choice in the design pages; coordinate with lane A3 through the orchestrator if it
      touches the surface registry.
    - New view: send the orchestrator one rough CI screenshot before polishing.

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each lane's
  last code commit; one review round per lane (spec and ponytail, read only).

## Findings

### Lane G3 (items 2–5)

- **Item 3, as the user decided later:** a `default` session shows the device's name: for This Mac, the Mac's own
  name from System Settings (`SCDynamicStoreCopyComputerName`, "Hari's MacBook Pro", read once per launch), not the
  words "This Mac"; for a remote machine, its name from the machine list. Other sessions show their own name.
- **Root causes.** 2: the labels were the words of phase 25, and the sort `Menu` had `ChromeStyle(radius: 6)`
  on a label with 6 pt padding: a hover tint the user did not read as a button, with a square shape. 3: the
  header drew `page.id`, the herdr session name, as-is. 4: phase 25 lane P made the title 13 pt semibold "a step
  above the rows"; the rows are 13 pt too, so only the weight changes: 13 pt bold. 5: groups had no fold.
- **Decisions.** `HostStore.title` (the name above) in the sidebar header, the needs-you panel's header, the page
  dots' VoiceOver label and the title row's "‹title› | ‹workspace›" button while the sidebar is collapsed (it
  stands for the header), and the window title "‹tab› - ‹title›" (orchestrator, after the lane); Open Session, the
  palette and the workspace menu keep herdr's names.
  The sort control is a capsule (`ChromeStyle(radius: 11)`, 22 pt high, 8 pt padding) that ends on the rows' edge
  and never shortens (`fixedSize`: a long session name shortens instead; on CI "Workspace" read "Works…" before).
  Groups fold by a click anywhere on the label; a chevron at its end points right while folded and shows pointing
  down only under the pointer while open, as in a macOS sidebar. Workspace groups got a count ("alpha 2"), so a
  folded one keeps it as priority groups do. Folds live in one `@AppStorage` string, a line per fold
  ("‹machine› ‹session› ‹order› ‹group›"; group = the state's case name or herdr's workspace id), so per session and
  order, across relaunches. The fold animates 0.2 s (none under Reduce Motion). A filter does not unfold a group.
- **Known limits.** A closed workspace's fold line stays, and herdr can give its id to a new workspace, which then
  comes up folded (ponytail comment). Renaming the Mac shows after a relaunch.
- **Tests.** `testAgentGroupsFoldAndStayFoldedAfterARelaunch` (new): the sort capsule's fill under the pointer
  (median brightness of its screenshot, the one pixel check: no accessibility value says "hovered"), fold and
  unfold a priority group (label and count stay, value `collapsed` / `expanded`), fold a workspace group, the other
  order unaffected, still folded after a relaunch; a teardown unfolds both, as the folds outlive the app and
  session one is shared by the run. `testAgentsViewListsEveryAgentByPriorityOrWorkspaceOrder`: "Workspace", the
  capsule's end on the rows' end, the header the rows' height, labels with counts, and it now waits for the rows'
  states (CI 40192968701 read the Done row while it still said Working). No test for item 3: it needs a session
  named `default`, which is read only (rules.md), and the app has no unit target.
- **CI.** 40192442654 (red: the new test hovered a workspace row the Agents view hides), 40192968701 (red: the
  states race above), local runs of both tests green (Retina, glass), full suite 40194683589 on c662ac6, the lane's
  last code commit: every agents and sidebar test green; 2 reds in other lanes' areas
  (`testFloatingWindowOpensLargeWithTheMainWindowsTitleRow`, lane F3: 368 vs 370 pt;
  `testPaletteEnterTakesTheMovedRowAndKeysFollow`). The fold test takes about 40 s on CI (a relaunch and the
  teardown's two order switches).
- **Window title** (57dd4a6): the four window-title tests green on CI 40196247210.
- **For the user to check by hand:** the header on This Mac's `default` (your Mac's name, bold, the rows' size) and
  on a remote machine's `default`; the sort capsule under the pointer in all four looks; folding a group, then
  relaunching.

### Lane V (items 15, 16)

- **Root cause, item 15.** Phase 25 lane T added `TabPreview` to the hover card (a picture timer, a text read
  each second). Removed: the card is again its pre-lane-T self (title, rows, the needs-you lines read once on
  open), `TabPreview.swift` and its two tests are gone; lane T's rim (`CardSurface`, item 28) and
  `testGlassCardsHaveABrighterTopRim` stay (426b9a6).
- **Item 16, how the miniatures draw** (D70, window.mdx "Overview"). Each tile hosts the card's own libghostty view
  in `MiniTerminal.Mini`, whose bounds are the card's terminal size and frame the tile's: AppKit scales the layer
  (a probe: a bounds-scaled layer-backed view gets a 0.3 layer transform and renders scaled), libghostty sizes from
  the view's own bounds × the window's scale, so grid, pixels and herdr's PTY keep the card's size. No surface,
  stream or copy of its own; the strip is not shown meanwhile, so a view lives in one place, and the strip's hosts
  adopt the views back. Streams: lane A3's `PaneViewRegistry.show(_:unvisited:...)` (agreed with A3): the cards
  of the tiles the lazy grid lays out stream and draw, are no visits, and those shown only by the overview let go
  when it closes. Weighed: a small observe-only surface per pane (a herdr run each, its grid cannot fit), the
  live surfaces' pictures on a timer, `pane.read` text, SwiftUI `scaleEffect` (does not scale an AppKit view).
- **Numbers** (lane O's scenario: 17 cards, 8 printing; `testOverviewCostsAndLetsGoAfter`). This Mac, debug,
  Retina: strip 166 MB / 1.4 % CPU / 4 herdr runs; overview, 12 cards in view, about 700 MB / 9–10 %; all 17 laid
  out 902 MB (586 MB IOSurface) / 16.7 %; closed again 224 MB / 1.7 % / 4 runs. CI (1x): 84 → 134 MB with 8 runs.
  The content-scale cut the orchestrator offered is not possible without changing libghostty-spm (its scale comes
  only from `window.backingScaleFactor`, `core` is private; A3 also noted the grid would move); the lazy grid
  bounds it instead (6f33fad): a tile scrolled away lets its cards go.
- **Decisions.** ⌃⌘O (lane I2's ⌃⌘ is the workspace level; the overview shows the session's workspaces), View ▸
  Show Overview with a check, the palette, the title-row button between Agents and ⌘, Esc. Tiles: one card per
  tab (orchestrator, from the reference): a 36 pt title row (icon stack, title, status; × on hover, the tab bar's
  close) over the miniature; the selected tab has the keyboard card's look; 2–4 a row, 16 pt gaps, 24 pt margins;
  the session's sidebar title (`store.title`) heads each page. A click selects the tab and grows its miniature to
  the strip's page in 0.25 s (none under Reduce Motion), then the strip shows. Sideways the overview pages through
  the window's sessions. The Agents button and ⌘. leave it first and act after the zoom; a notification or Dock
  click leaves it at once; other keys and the palette work under it (⌘T adds a tile).
- **Root causes on the way.** (1) Esc never reached a SwiftUI `focusable`: the terminal moving into a miniature
  kept the first responder. Now `PaneSurfaceView` refuses the keyboard inside a miniature, the overview clears the
  first responder, and a key monitor takes Esc unless a panel or text field has it; a claim made while in a
  miniature lands when the view is back in its card (`viewDidMoveToSuperview`). (2) The zoom jumped: an animated
  frame reached the miniature's terminal views only at its end (their sizes come from a `GeometryReader`), and the
  overlay was inserted in the same update as the change. Now an `Animatable` modifier sets the frame each step,
  one turn after the insert; `-recordMotion` counts the miniature's sizes (≥ 4). (3) Spec and ponytail review:
  tab ids repeat across sessions, so the laid-out tiles, the tile frames and the zoom were keyed by page; a window
  drag refit each tile's terminal every frame (now 150 ms after, as the card's host); 2–4 columns explicitly.
- **Deviations.** `Miniature.swift` holds the miniature and `MiniTerminal` (PaneSurfaceView reads `Mini`);
  `showPending` moved to an extension (WindowPages' body length). Remote machines: only the shown tab's cards
  are live in the overview (the SSH session cap; the remote lane reworks it), the others keep their last picture.
- **Tests** (`OverviewTests.swift`): `testOverviewShowsEveryTabLiveAndOpensOne` (sidebar and tab bar hidden,
  title and workspaces, two a row 16 pt apart, × closes a tab in herdr, a never-shown tab's white block in its
  tile, the zoom's sizes, the tab shown with its PTY at the card's size, keyboard back, Esc),
  `testOverviewSwipesBetweenSessions` (a swipe lands on session two and makes it the window's page, a same-id
  never-shown tab of session two draws live, Esc without motion gives the keyboard back),
  `testOverviewCostsAndLetsGoAfter` (streams up while open, back to the strip's count after).
- **CI.** 40192962147 (rough: Esc red), 40193514086, 40194287889 (green), 40196409137 (a layout check below CI's
  fold; fixed in 1b881f4); full suite 40197782383 on 1b881f4 (one red: `testPaletteEnterTakesTheMovedRowAndKeysFollow`,
  ↓ after "show" now lands on Show Overview, the View menu's order; fixed in fd0f177). Full suite 40199215983 on
  fd0f177, the lane's last code commit, and its rerun of the failed shards: every overview, hover card and palette
  test green; three reds in lane T3's area, red in both attempts: `testClosingATabAsksOnlyWhileAProgramRuns` (the
  tab bar's × of w2:t4 not found), `testSessionSwipeFollowsTheFingersAndSlidesOnFromTheirSpeed` (4 steps, needs
  more) and `testLayoutMotionAnimatesWithoutBlanking` (restore 153 ms over 150, then a pane read timeout); all
  three green on 1b881f4, before T3's c83d6ea, 20d3b7f and 46f4514.
- **For the user to check by hand:** ⌃⌘O in a busy session: tiles live and readable at Retina, the selected tab's
  card in Glass and Classic, × on hover; a click's zoom with Reduce Motion off (smooth, ends where the strip's
  page is, with the sidebar open and closed); a two-finger swipe between sessions inside the overview; memory
  after scrolling through many tabs (`footprint`), and back after Esc.

### Lane F3 (items 10–14)

- **Item 14, not built: herdr 0.9.5 gives Oriel nothing to open.** Probe on a throwaway server with its own config
  folder (`XDG_CONFIG_HOME=/tmp/hx27f3 herdr --session oriel-dev-27f3-a server`, so the user's `plugins.json` and
  sessions were never touched), a throwaway plugin linked there (`placement = "popup"`, `sh -c 'echo; sleep'`) and
  an events subscription on every type. `plugin.pane.open {placement: "popup"}` answers only `{type: "ok"}`: the
  server spawns the popup's terminal (its log shows `pane.spawn` with 18 × 69 cells, the process runs), but the
  reply, `session.snapshot`, `pane.list` and `pane.get` have no pane or terminal id for it, `terminal session
  observe` finds no target, and opening it or `popup.close` sends no event. `plugin_pane_opened` / `_focused` /
  `_closed` are only replies (`success_response`), never events, and come only for the other placements
  (`overlay` = a zoomed split, `split`, `tab`: normal panes with `pane.created`). Only herdr's private client socket
  (bincode `ClientShellPopupSurface`) sees the popup, which D6 and D20 rule out. So phase 25 lane F2 and the
  research of 2026-10-08 (`resources/research/ui/floating-panes.md`) hold. The upstream ask is in
  `future-work.mdx`: the popup's terminal id and size in the snapshot, open/close events, a close by id. With
  those, Oriel streams it by terminal id in this floating window as it does a floated pane. Plugin unlinked,
  session stopped and deleted, `/tmp/hx27f3` removed.
- **Root causes.** 10: the scene's `.defaultSize(560, 360)` was the only size, and SwiftUI placed it on its own.
  11: lane F2 built a quiet placeholder (icon, name, a Show button). 12: the window used `.hiddenTitleBar`, whose
  title bar is 28 pt with the lights where AppKit puts them; the main window's 46 pt row and Rex's light positions
  came from `WindowReader`, which only the main window had. 13: the header used 22 pt card-header buttons in
  primary (dimmed while a write ran), not the title row's 28 pt buttons in `look.chrome`.
- **Decisions.** 10: `FloatReader` sets a new window's frame when AppKit has none saved for the terminal
  (`setFrameUsingName` false): `max(720, 0.6 × main)` × `max(460, 0.6 × main)`, centered over the main window that
  floated it, `constrainFrameRect` for the screen; then the autosave as before, so a pane floated again keeps the
  user's frame. 12: the light placement moved out of `WindowReader.Reader` into a `TrafficLights` base class both
  readers subclass (one copy of the observers and the layout hook), and the float scene got the main window's
  `.unifiedCompact` toolbar with an empty spacer (and the full-screen toolbar on hover, spec review), its row
  `TitleBar.height` and `TitleBar.inset`, plus a `WindowDragGesture` on empty space. 13: the card header's buttons
  (22 pt, 11 pt regular, `paneButton`) and the title row's (28 pt, body medium, `chrome`) differ, so "the same as
  both" cannot be literal: the floating row is a title row now (item 12), so it uses the title row's buttons with
  the card's icons (`pip.exit` mirrors the card's `pip.enter`, `xmark`). 11: one `PaneInfo` view (program tile,
  program and folder as the card header writes them, or the label; the state capsule when an agent runs) in both
  the floating title row (before "session › workspace › tab") and the placeholder, where the whole card body is one
  `ChromeStyle` button (fill on hover) with the old `pane.‹id›.show` identifier. The place line's session is
  `HostStore.title` (lane G3: `default` shows the machine's name), per the orchestrator.
- **Tests.** `testFloatingWindowOpensLargeWithTheMainWindowsTitleRow` (new): frame 60 % / 720 × 460 and centered
  over the main window, the three lights at Rex's places, the 28 pt buttons centered on the 46 pt row, the pane's
  info in the title row (`float.‹id›.info`) and in the placeholder, the placeholder button filling the card, a
  click in its corner bringing the window forward with the keyboard. Checked locally on Retina too (after the GUI
  was free). The card element is 18 pt wider than the button, not 16 (its border): 3 pt accuracy. Learned: a
  window element held across a click that brings that window forward was "no longer valid after interruption
  handling" once on CI: the last check finds the terminal without the window.
- **Reviews.** Ponytail: no blockers; dropped the screen clamp (AppKit's constrain does it), fixed a wrong comment,
  `PaneInfo` truncates as the card header does. Spec: full-screen toolbar on hover; the test did not see the pane
  info (it read the button's own label): the label now comes from `PaneInfo`, with its own identifier in the title
  row; all three lights checked; future-work wording.
- **CI.** 40192618928 (8 floating and light tests, green on ed8e451). Full runs: 40196255503 on f81f40c: red in
  this lane (the stale window, fixed in 9d6c8fe) and in others' areas: `testPaletteEnterTakesTheMovedRowAndKeysFollow`,
  `testOverviewShowsEveryTabLiveAndOpensOne`, HerdrKit `relay carries runs over one process`
  (`SSHExecTests.swift:49`).
  Final full run 40198270835 on 9d6c8fe (this lane's last code commit): every floating, light and HerdrKit test
  green; the one red is `testPaletteEnterTakesTheMovedRowAndKeysFollow`, red also on lane G3's run 40194683589 on
  c662ac6, before this lane's code (not this lane's area).
- **For the user to check by hand:** a new floating window's size and place over a large main window and over a
  main window near a screen edge; the title row's lights and buttons against the main window's; a floating window
  in full screen (toolbar on hover); the placeholder's hover fill and click.

### Lane A3 (item 1)

- **Root cause.** Two things made a tab visited a while ago fade in. (1) Lane O kept the surface and stream of only
  4 hidden terminals; the rest were freed and rebuilt on show. (2) Their "still" never held a picture: ghostty frees
  a surface's swap chain while it does not draw (ghostty c4e16970a, in our libghostty, the same as Ghostty's hidden
  tabs) and marks each IOSurface `kIOSurfacePurgeableEmpty` as it frees it (`pkg/macos/iosurface`), so the layer kept
  an emptied picture; and a volatile still is taken back by the system within seconds (logged: `old == 2` on every
  return), so `revealed = false` and the card faded in. Kept terminals had the same hole: CI's recording showed a
  kept card blank for one frame (83 ms) when its tab came back (40192669231), the view re-entering the window before
  the surface drew again (about 0.1 s later).
- **Ghostty's way, copied.** Ghostty keeps every tab's surface and PTY reader, occludes hidden tabs and covered
  windows (`ghostty_surface_set_occlusion`), drops the swap chain while occluded and builds it again on the next draw
  (0.43 ms in its commit), and does not shrink anything. Oriel already occludes hidden cards (lane O), so libghostty
  frees their swap chains; what was missing is keeping the terminals and a picture.
- **Changes.** `PaneViewRegistry.spare` 4 → 16 (78d941f, 7282cb1, 4e4451c): visited terminals keep stream and
  surface, drawing paused. A card that leaves view copies its last frame (`keepPicture`: one IOSurface, a row copy
  under the surfaces' locks, about 2 ms for a full-window Retina card) into a `still` sublayer before drawing pauses;
  it shows until the surface's first new frame drops it (lane O's KVO). Evicted stills stay volatile (lane O); kept
  ones do not. A control move between windows (D66) ends the hidden kept terminals' streams (`pause`) instead of
  reopening up to 16 per window; they open the right stream when shown. Lane V's hook:
  `show(_:unvisited:alive:client:)`, overview showings are no visit and are freed when it stops showing them unless
  kept. `-spareTerminals N` for tests.
- **Numbers** (lane O's scenario, `testMemoryAndCPUOverManyTabs`; Retina = this Mac, Debug):

  | | Before (lane O, 4 kept) | After (16 kept, copies) |
  |---|---|---|
  | Footprint, Retina, quiet / busy tab | 190 MB | 405 / 419 MB (IOSurface 218 MB) |
  | Footprint, Retina, 33 full-window tabs | 198 MB (4 kept) | 653 MB (IOSurface 419 MB) |
  | herdr runs | 5 (33 MB) | 16–17 (110 MB) |
  | CPU quiet / busy, Retina | 3.4 / 6.5 % | 4.6 / 6.8 % |
  | Footprint, CI (1x), quiet / busy | 103 / 116 MB (40190929489) | 131 / 141 MB (40196456202) |
  | CPU quiet / busy, CI | 1.2 / 3.4 % | 1.7 / 3.9 % |

  A kept terminal costs about 6 MB in the app (no scrollback: `scrollback-limit 0`), its picture (17 MB at full window
  on Retina) and a 7 MB herdr run. 32 kept, measured without copies: 359 MB for 33 full tabs, but with copies it would
  pass 1 GB at full window, so 16 (the user's 17 terminals fit).
- **Decisions.** A count, not bytes: the picture is the one size-dependent part and 16 full-window ones measured
  653 MB. Copies over purgeable copies: the system took purgeable ones within seconds. Copies over a shrunken copy:
  the picture shows for about 0.1 s and must match the frame after it. The remote rule went with lane R2's relay
  (one SSH session per host, b8e0455): remote terminals are kept like local ones.
- **Tests.** `testAVisitedCardComesBackAtOnce` (new): six more tabs, the card's herdr run stays, text printed while
  away; from the key on, never loading, every screenshot has ink and shows the new screen (red on the old code:
  w1:p1's stream ended, 40192763939 on a throwaway tag). `testAnEvictedCardComesBackWithItsPicture` runs with
  `-spareTerminals 4`. `testMemoryAndCPUOverManyTabs` expects all 16 shown terminals' runs (13–17). The one-frame
  blank is too short for XCUITest's screenshots (about 0.15 s each); checked on recordings frame by frame instead
  (local, Retina, motion on: old picture, then the new screen, no blank frame).
- **Reviews.** Spec: the copy fixes its items 1, 2, 7 (no volatile live picture any more); 3 measured (above); 4
  wired by lane V (eab529b); 5 the loop starts at the key; 6 `pause` on a control move; 8–10 comments, docs, the
  helper count range. 11 (a remote test) dropped: the remote rule is gone. Ponytail: `unvisited` is called by lane V
  now; the `purgeable` branches merged; `make`'s parameter renamed.
- **Known limits.** A minimized or covered window drops its swap chains too (libghostty), so it may show one blank
  frame when it comes back; not copied (Ghostty behaves the same). An evicted card still fades in once (past 16).
- **CI.** 40192669231 (red: the new test read a hidden card), 40193748306 (green, without copies), 40196456202
  (green on 4e4451c: the new, eviction, usage, every-path and resize tests); full suite 40197953846 on 3587863 (after
  4e4451c, the lane's last code commit): every terminal, reveal, usage and latency test green; 4 reds outside lane A3:
  `testFloatingWindowOpensLargeWithTheMainWindowsTitleRow` and `testPaletteEnterTakesTheMovedRowAndKeysFollow` (red
  in lane G3's run too), `testDroppingAFileFromFinderPastesItsPath` and `testGoToDirectoryAndInsertPath` (both green
  alone in 40199753823).
- **For the user to check by hand:** after `make install`, visit 10–15 tabs with agents working, go back to the
  first ones: the old picture, then the new one within a frame or two, no fade and no empty card. `footprint` after
  half an hour (expect 300–650 MB with 16 hidden terminals) and `top` (a few percent).
