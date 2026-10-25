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
  fold; fixed in 1b881f4); full suite 40197782383 on 1b881f4.
- **For the user to check by hand:** ⌃⌘O in a busy session: tiles live and readable at Retina, the selected tab's
  card in Glass and Classic, × on hover; a click's zoom with Reduce Motion off (smooth, ends where the strip's
  page is, with the sidebar open and closed); a two-finger swipe between sessions inside the overview; memory
  after scrolling through many tabs (`footprint`), and back after Esc.
