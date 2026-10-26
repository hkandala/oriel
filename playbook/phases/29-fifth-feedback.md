# Phase 29: The user's fifth round of feedback

The user sent these on 2026-10-25 (about 17:00) while phase 28 was still running. Screenshots in the main
checkout's `.build/fb/`: `addhost.png`, `arrows.png`, `movetab.png`. Each lane writes `## Findings` at the
end. `/tmp/oriel-gui.lock` is held for "user"; UI tests run on CI until the orchestrator says otherwise.

## Lane D: drag a tab to a workspace (item 1)

1. A pane can be dragged onto a workspace row in the sidebar, a tab cannot. Make a tab drag onto a
   workspace row (or a collapsed sidebar's workspace menu row) move the whole tab, with its panes and
   layout, to that workspace. herdr 0.9.5 has no cross-workspace `tab.move` (it takes only `insert_index`):
   move the first pane with `pane.move {destination: new_tab, workspace_id}`, then the others into that
   tab, then restore the split tree and ratios (herdr's layout methods). The drop zones and the drag card
   follow the pane drag's rules (phase 18 and drag-and-drop.mdx).

## Lane R: remote hosts (items 2, 3)

2. **Add Remote Host in the glass look** (`addhost.png` is from before phase 28 lane R's glass dialog:
   check the current one matches the palette's glass in all four looks).
3. **Edit a remote host:** rename it, change its SSH target and icon, and remove it, from the machine
   menu (a context menu on its row, or an Edit… item). Icon choice: many more icons than 8, in a compact
   picker (a grid popover or a menu with a search), SF Symbols only.

## Lane V: overview (items 4–6), added to phase 28 lane V

4. **Scrolling lags:** profile the overview while scrolling (Instruments or `sample` on a local Release
   build when the GUI is free; CI recordings until then) and make it smooth at 60 fps with many tiles.
5. **Flicker after zoom into a tab that was not the shown one:** after the zoom ends, the tab flickers;
   it does not happen for the tab that was already shown. Find the cause (likely the strip page or the
   terminal views moving back to their cards after the zoom) and remove it.
6. **Faster zoom** (about 0.18 s), and **a fade-in when the overview opens**.

## Lane M: menus and Open Session (items 7, 8)

7. **Hover in lists feels laggy** (⌘K palette, the collapsed sidebar's workspace menu, Open Session, other
   menus that use FilterList): the highlight should follow the pointer at once, with no fade out and in.
   Find the animation or delay (a hover tint animation, onContinuousHover work, a state round trip) and
   make the highlight move in the same frame.
8. **Open Session flickers every time it opens:** it loads the sessions, then redraws. Show the last
   known list at once (kept in memory per machine), refresh in the background, and update rows in place
   without a flash.

## Lane K: panes and keys (items 9–12)

9. **⌘D pressed fast several times:** the keyboard goes to the pane that settled last, not the one
   created last. As phase 27 lane T3 did for tabs: the newest stand-in keeps the keyboard and its history
   maps to herdr's real pane.
10. **⌥⌘ arrows are slow** (⌘[ is quick) and pick the wrong pane (`arrows.png`: three columns, the third
    split into four rows; from the first column, → twice lands on the third column's second row, not its
    first). Compute the neighbor locally from the layout (no herdr round trip), and choose like Ghostty:
    the pane used last in that direction, else the one that overlaps the current pane most, ties going to
    the top (or left) one.
11. **Move Tab Left / Right** shows ⌃⇧⇞ / ⌃⇧⇟ (Page Up / Down, `movetab.png`); most Mac keyboards have no
    such keys and the user could not use them. New keys: ⇧⌘← and ⇧⌘→ (as iTerm2), in the menu, the
    palette and the Shortcuts panel.
12. **Holding ⌘ shows the workspace keys too:** today holding ⌘ shows ⌘1–9 on the tabs, and only holding
    ⌃⌘ shows ⌃⌘1–9 on the workspace rows. Holding ⌘ shows both at once.

## Findings

### Lane M

- **Root cause, item 7.** `ChromeStyle` put `.animation(.easeOut(duration: 0.14), value: hovering)` on the whole
  button. FilterList lights the hovered row, so the update that changed `hovering` also changed `selected`: the old
  row's accent pill faded out and the new one faded in, with the row's white text, over 0.14 s. The animation now
  sits on the hover tint alone; the pill moves in the hover's own update. Second cost: the palette passed `lit` on
  every page, so each new light drew the whole palette (its command list and ~100 rows) again; only a preview page
  reads it now. Checked and kept: FilterList's `onContinuousHover` writes (a write of an equal value draws nothing).
- **Root cause, item 8.** Open Session kept its own `@State` list, empty as the panel opened: the first draw had only
  the open pages (and no New row: the suggested name came after the read), then the sessions and New pushed in above
  them. It now reads the page store's `sessions` (read as the page connects, `HostStore.loadSessions`), shows them at
  once and reads them again as it opens; rows change in place (by id). The suggested name is picked in `init` from
  that list and picked again only when the new read has it. "Per machine" is per page: a window is on one machine.
- **Tests.** `testPanelsAndSwitchesReactAtOnce`: Open Session's first draw lists the sessions (`-recordLatency`'s
  `open-session ‹names›` note at `onAppear`; empty before the fix). `testMenuLightFollowsThePointer`: the palette's
  light follows the pointer too. The fade itself is not visible to a test (the trait flips in the same update either
  way): it needs the user's eye.

### Lane D

- **Root cause.** No drop target took a tab outside its tab track: `RowsDrop` refused `.tab` on purpose (phase 18,
  "herdr moves tabs only inside a workspace"), and the collapsed sidebar's workspace menu took no drops at all (a
  panel that a drag could not even open). herdr 0.9.5's `tab.move` has only `insert_index`.
- **Build.** `HostStore.move(tab:to:)` (PaneWrites.swift) reads herdr's tree in its write's turn, moves the first pane
  with `pane.move {new_tab, workspace_id, label}` (the label unless herdr's number), then each other pane top down
  with `pane.move {tab, split, target_pane_id, ratio}` beside the first pane of its split's other side
  (`SplitNode.rebuild`, unit-tested: replaying it gives the tree back), each with the new pane id herdr's reply names.
  `Destination` gained `label` and `ratio` (null when absent; herdr takes null). `RowsDrop` takes a tab over another
  workspace's row; `PaneDrop` takes a tab over a new tab in another workspace (the menu rows); `SpringDrop` opens the
  workspace menu after 0.65 s over the collapsed sidebar's workspace button; `MenuRowDrop` (via
  `FilterList.Item.drop`) makes the page in view's menu rows targets. The page follows the tab with its keyboard card.
- **Decisions.** No spring-load for a tab over a row (the other workspace's tab row would not take it); no tab to a new
  workspace (not asked); the tab's drag image stays its capsule (the row and the button highlight as the pane drag's
  targets do); the menu closes when the drag ends; a partial failure says "Moved part of the tab: herdr refused the
  next step".
- **Learned (spike).** `layout.apply {tab_id, root}` with the tab's own pane ids does not rearrange them: it makes a
  new tab with new terminals (the programs are gone), so it is no way to move a tab. A ratio passed to `pane.move` is
  the first side's share. herdr closes the source workspace with its last tab. A move out of a herdr-zoomed tab is
  `zoomed_tab`, so nothing moves.
- **Test.** `testDraggingATabOntoAWorkspaceRowOrMenuRowMovesItWithItsLayout`: a 3-pane tab at 0.3 / 0.7 with a label;
  its own row moves nothing; onto beta's row the same tree by terminal id, ratios and label are in beta, the old tab is
  gone, the page and keyboard follow; then, sidebar collapsed, held over the workspace button and dropped on the
  menu's row it comes back the same. The two-leg drag is `scripts/drag.swift` (CGEvents, as `swipe.swift`;
  XCUITest drags to one point only), through the e2e helper's `drag` action.
- **Root cause, menu rows on this Mac (macOS 27.0.1).** Local runs (once the GUI was free) failed at the menu step
  while CI passed: no drop delegate in the menu was ever asked (`validateDrop` logged nothing), nor one on its list or
  the whole menu, nor the sidebar's rows when the spring opened the sidebar instead. macOS 27 finds no SwiftUI drop
  target added after a drag entered the window; one there from the start but hidden takes drops once shown. So with
  the sidebar collapsed the workspace menu is there through every drag, hidden and not hit-testable (its field does
  not take the keys, its rows refuse drops) until the hold opens it (3c0a8ca). The same likely holds for a spring-
  loaded tab's cards that were not laid out before the drag (not checked). Menu rows take drops only during a drag:
  `testMenuLightFollowsThePointer` failed on CI in 2 of 4 runs with drop targets on every row (915ec06; 3 green
  after).
- **Known limit (check by hand).** Once a drag springs the menu open, the panel's full-window backdrop sits over the
  strip, so the drag can end only on a menu row (or nowhere) until it ends; the menu closes then.

### Lane R (items 2, 3; contrast, remote sessions, machine picks, the new window's size, titles)

- **Root causes.**
  - 2: `addhost.png` predates phase 28's dialog; the current one already used the palette's `floatingGlass` in every
    look. What did not fit was the system segmented control for the icon (small blue-accent segments) and, from the
    user's second report (`remote-glass.png`), contrast: the question text and the labels were `.secondary`, and the
    fields used the palette's soft `fieldCapsule` (7 % primary), which vanished on the grey glass. Now the text is
    primary and a dialog field is `dialogField()`: the capsule over 60 % of the background color with a 20 % primary
    outline. CI screenshots in all four looks: "add remote host glass|classic dark|light".
  - 3: nothing could change a machine after Add (`addingHost: Bool`, a list only appended to). Now
    `WindowPages.hostDialog: Machine?` (a new machine, or one of the list) drives one `HostDialog` for Add and Edit;
    the machine menu has "Edit Remote Host ▸ ‹machine›" with Save and Remove. `MachineList.save` updates the list,
    every window of the machine (all of it: their next windows and pages use the new target) and every open store
    (name and icon only: they stay on the connection to the old target; `HostStore.machine` is now a `var`). The icon
    is a button whose popover is a 10-column grid of 136 SF Symbols (each checked with `NSImage(systemSymbolName:)`)
    with a search by symbol name, dots read as spaces on both sides.
  - Remote sessions: the panel was right (it reads the page's own store, so the window's machine; CI shows the
    remote's sessions); the user had no way to find it besides the small sidebar footer button and ⌥⌘T. The machine
    menu now has "Open Session…" too.
  - "Another device's sessions" (18:30): no path in the code shows another machine's list. Lane M's cache is
    `HostStore.sessions`, one per store, and a store is per machine id and session (`HostStore.open`'s key); a
    window's current page is always of its machine. The likely confusion: both machines run the same names
    (`default`, `pi-herd`), and the groups did not say which machine. A remote window's groups now read "Running on
    ‹machine›" / "Stopped on ‹machine›". `testOpenSessionListsOnlyItsWindowsMachine` guards it: This Mac's panel
    reads session two, then a Password Host window (no herdr there) lists none of it.
  - Titles (18:30): the Add / Edit title was a `Label` whose `+` / pencil glyph sat off the text line and pushed the
    text past the form's edge. Now text only, flush with the form's leading edge.
  - Machine picks: `WindowPages.open(machine:)` always opened a window. A pick now brings the machine's window used
    last forward (`WindowPages.windows` is in key order) and opens one only when there is none; Add still opens one.
  - New window size: `defaultWindowPlacement` gave 1200 × 760 at most. Now 90 % of the visible screen, at least
    1200 × 760 and at most the screen, centered; restored windows keep their frames. CI's 1024 pt screen still gets a
    full-width window, so no other test's layout changed.
- **Also.** A window restored on a removed machine opened its saved remote session names on This Mac; it now opens
  This Mac's `default` only. Open Session's start compares the machine by id (an edit during a start kept the open).
- **Tests.** `testTheRemoteHostDialogInEveryLook` (four looks, no Edit item without hosts, Esc on the dialog and on
  the popover, a dotted search, the pick). `testEditingARemoteHostRenamesItAndRemoveTakesItOff` (name, target and icon
  saved; the open window's machine name and its button's icon follow; Remove drops it and the Edit item).
  `testARemoteWindowOpensAnotherSessionOfItsMachine` (the machine menu's Open Session lists and opens session two in
  a Key Host window; the sidebar's panel lists both pages). `testAddingAKeyHostOpensItInANewWindowWithoutAsking` now
  checks a pick brings the Key Host window forward (two windows, then ⌘N makes three).
  `testNewWindowFillsMostOfTheScreen` checks ⌘N's frame against the formula. Not caught by a test: oriel-key is this
  Mac, so a panel that read This Mac would list the same sessions (the code uses the window's machine).
- **Accepted.** An edit while another window edits or removes the same machine: the later Save of a removed one does
  nothing. A window still restoring misses an edit. The popover is the system's (glass on macOS 26 in both styles).
  Reorder is not built.

### Lane F

- **Placeholder buttons (18:30).** The floated card's placeholder keeps its line and shows **Show Window** (was Show
  Pane: `Page.float`, the window comes forward) and **Bring Back Here** (`pane.<id>.back`: clears the float, as
  Detach, then `Page.go(to:)`, so the card has the keyboard) side by side, 8 pt apart, centered. Tests:
  `testFloatingAPaneOpensItsWindowAndDetachPutsItBack` brings it back from the placeholder,
  `testFloatingWindowOpensLargeWithTheMainWindowsTitleRow` checks both labels and the layout.
- **⌘W detaches (user).** In a floating window ⌘W is Detach Pane, as the red light, and ⇧⌘W Close Pane (still asks
  when a program runs): the menu bar, ⌘K and the title row's tooltips (`floatingCommands`, `FloatingWindow.header`). The Shortcuts panel
  shows only in a main window, so it lists none of these.
  Tests: the ⌘W detaches in `testFloatingWindowsHaveTheirOwnCommandsAndComeBackAfterRelaunch` and
  `testEachFloatingWindowsKeysActOnItsOwnPane`, ⇧⌘W's ask in `testClosingAFloatedPaneAsksInItsWindow`.

### Lane C

- **Root cause.** libghostty draws the selection: herdr drops mouse events for a program without mouse mode, so a
  drag selects locally (`PaneSurfaceView.mouseDown` feeds both). libghostty-spm's default theme sets only
  `selection-background` (Afterglow `#303030`, Alabaster `#C9D0D9`); with no `selection-foreground`, Ghostty draws
  selected text in the window background (`#212121`, `#F7F7F7`). The screenshot's pixels: text `#212121` on
  `#303030` (1.2 to 1); light was 1.45. herdr's own `selection_bg` (the user's config `#2e2e2e`) is a coincidence.
- **Fix** (c4f9e5d, 7085a91): `TerminalFont.controller` takes the default theme plus `selection-foreground =
  cell-foreground` (pinned Ghostty 1.3.2-HEAD has it) and a blue background: `#B3D7FF` light (macOS's), `#1B3A58`
  dark (system blue 0.25 over `#212121`; macOS's `#3F638B` gives 4.0). Default text: 7.6 dark, 14.1 light. Palette
  untouched. The selection is opaque, so Glass and Classic draw it alike.
- **Test** (cc03c0d, b5b52ab): `testSelectedTextIsReadable` fills the screen with full blocks, drags over the top
  half in each of the four looks, and polls the pixels: text over the selection > 4.5, the selection over the card
  > 1.1 (1.0 when nothing is selected).
- **Decisions.** Always blue, not the accent color (`ponytail:` names the upgrade). Reverse-video cells still draw
  in the background color when selected (Ghostty's `cell-foreground` rule; not worse than before).
- **Check by hand.** Select text in a plain shell and in an agent TUI in dark and light: blue block, text in its own
  color. In a mouse app (where herdr forwards the drag), libghostty still draws the same highlight.
- **Item 16, letter icons.** `ProgramMark` framed only the logo image (16 pt); the placeholder's letter took its
  natural width (about 7 pt for "C"), so `ProgramGlyph` (card headers, hover card rows) pushed the name less far.
  Both now take the same square (660a46c). Tiles (tab capsules, overview, Agents rows, palette and menus, floating
  pane) already sat in a fixed 22 × 18 frame. Test `testLetterIconsTakeTheLogosBox` (vim and cat side by side): the
  header names start at the same x in their cards (`pane.<id>.title`). Review: the glyph stays hidden from
  VoiceOver (the first try exposed it for the test); by eye, the letter is still 10.4 pt in the 16 pt square
  (`size * 0.75` if it looks small next to a logo).

### Lane K

- **Root cause, item 9.** Two things. (1) A split's new card is a stand-in with no terminal, so the first responder
  stays on the old card until herdr answers: every quick ⌘D split that old card again (A | D | C | B, not Ghostty's
  A | B | C | D). (2) Each split's `follow` recorded its pane in the keyboard history before any snapshot had it, and
  the next ⌘D's redraw (its stand-in) ran `shown(alive:)` on the old snapshot: the new terminal was pruned as closed,
  so the keyboard went back to an older card, and the panes took it in the order their snapshots and views arrived.
  Now `Page.newest` (the latest split's stand-in, then herdr's pane, until its terminal has the keyboard) is the ⌘D
  target and is lit at once; its write splits herdr's pane for it (`Ahead.splitPanes`, read in the write's own turn,
  as writes are FIFO), and a herdr pane still drawn as its stand-in is split where it shows. Only the newest split's
  pane takes the keyboard: a new split cancels the earlier one's handoff, the older panes join the history before it
  (so ⌘W steps back through them), and `shown` prunes only terminals it saw alive before. ⌘W while the stand-in is
  lit does nothing (it would close the old card); a tab or workspace switch ends the chain.
- **Root cause, item 10.** ⌥⌘ arrows asked herdr's `pane.neighbor` (a new `remote-api-bridge` run per key, 15–170 ms,
  and a repeat dropped while a write ran), and herdr picks the pane at the middle of the edge (the second of four
  rows). `SplitNode.neighbor` picks from the tree at once: of the panes along that edge, the one used last (the
  page's keyboard history), else the one sharing most of the edge, the first in tree order (top or left) on a tie.
  `pane.neighbor` left HerdrKit (Multiplexer, model, integration test).
- **Item 11.** Move Tab Left / Right on ⇧⌘← ⇧⌘→ (iTerm2's), in the menu, palette and panel; the ⇞⇟ glyphs went. The
  menu takes the key before a text field, so the arrow there still selects to the line's start or end; the palette
  and a menu click move the tab (the spec review's blocker: the palette's field still has the keyboard while its
  action runs, so only the arrow's own key event forwards).
- **Item 12.** `keycapHints` takes several modifier sets: the workspace rows show theirs for ⌘ or ⌃⌘.
- **Tests.** `testQuickSplitsSplitTheNewestAndItKeepsTheKeyboard` (⌘ held, "ddd" in one burst: four panes left to
  right in creation order, the last has the keyboard and takes typing, ⌘W twice steps back),
  `testSelectPaneKeysPickTheLastUsedElseTheTopNeighbor` (the user's layout: → → lands on the top row; back from the
  left to the row used last; nothing past the edge), a unit test for `SplitNode.neighbor`,
  `testTabContextMenuRenamesAndMoves` (⇧⌘←, a rename field keeps it, the palette), `testHoldingCommandShowsKeycaps`
  (the workspace keycaps), the panel rows.

### Lane S (item 14)

- **Harness.** `scripts/stress.py <session> [tabs=300] [workspaces=30] [--panes 400] [--agents 100]` fills a running
  throwaway session over its socket (400 panes in about 8 s here): shells without rc files, herdr's own tab labels,
  every other pane printing a line a second, 100 agent panes printing every 0.2 s, a new terminal title every second
  and a new state (`herdr --session … pane report-agent`) every 5 s. It replaced lane V's `overview-stress.py` (lane V
  uses it). macOS gives all programs 511 terminals together (`kern.tty.ptmx_max`), so 600 panes fail with an
  `openpty` error; the helper's `stress` action (session eight, made afresh, removed by the test's teardown) asks
  400 on CI and at most 200 here. `testHundredsOfPanesStayQuick` records the time to the first card, the main keys,
  three scrolls (`scroll <frames> <hitches> <ms>`, a display link from a scroll event to 0.3 s after the last), the app's
  CPU and memory (`usage`) on a quiet and a busy tab, `sample` profiles, and every 5 s the main thread's busy time,
  its longest turn, the snapshots applied and their own time (`main …`). `-recordLatency` now also writes these lines
  to stderr and gives each key the app's own time from taking the event to the frame ("⌘T 12ms 0 9ms"): an
  accessibility client (XCUITest) holds events back for seconds at this size, so the honest numbers are a Release
  build launched by hand (`open -n`) with keys and swipes posted to its window (Quartz events, only while it is the
  front window), no XCUITest attached.
- **What scaled badly** (profiles of the before build, `s29-before` = 8f68945 plus the harness):
  1. The first snapshot asked `pane.process_info` of every pane at once: 400 `remote-api-bridge` runs together; on CI
     the window stayed blank past 30 s and the run's teardown timed out.
  2. Snapshot reads came back to back while events kept coming (a hundred agents' titles and states, an event each),
     and each 280 KB reply line was split by scanning the buffer from its start at each pipe chunk: O(n²), the top
     function of the profile; together about 100 % of a core.
  3. `apply` made the set of every tab's focused pane again for each pane (O(panes × tabs)): 75 ms per snapshot on CI.
  4. Views scanned every pane: each tab capsule, sidebar row, the Agents button and the Dock badge read every pane's
     state (`strongest`), so any agent's change redrew all of them; the Agents view filtered every pane for each tab
     (180,000 steps) and built every row.
  5. Each card's body built Move Pane to Tab with every tab's title (300) for its context menu, header menu and
     VoiceOver actions, and `Page.title` built a 5-pane stack and abbreviated a path per tab.
  6. `Page.shown` edited `usedTerminals` in place on every snapshot: Observation notified though nothing changed, so
     every snapshot redrew the window's content and made the menu bar's whole command list again.
- **Changes.** (1) Program asks go through a `Gate` of 8 (FIFO; a card's ask and Return's go first; an ask a newer one
  replaced while it waited makes no run) (f929c04, c8f2621). (2) A snapshot read again starts 250 ms after the one
  before started while events keep coming, never after the app's own write (ce2e873, ac09391; D5 and
  talking-to-herdr.mdx); the line splitter scans only new bytes (9726394). (3) The focus set once per snapshot
  (f929c04). (4) `tab.agent`, `tab.working`, `workspace.state` and `store.waiting`, kept by the store (4e2ba24);
  `store.tabPanes` / `panes(in:)`, each tab's panes, set only when it changes (8a0e686); the Agents view groups once,
  is lazy, and rebuilds its rows for the other order (4b92cc4, d21b611). (5) `PaneItems` / `PaneActions` views, so the
  list is made when a menu opens (da15eb8); a cheaper `title` (same commit). (6) `usedTerminals` assigned, not edited
  (97e613b). Also `HostStore.write` uses the same `Gate` (one at a time, 2e69e74).
- **Numbers.** Release, this Mac (Retina, 120 Hz), 300 tabs / 400 panes / 100 agents working, no XCUITest; before =
  `s29-before`, after = d5224a0:

  | | Before | After |
  |---|---|---|
  | CPU, quiet tab | 117 % | 9–11 % |
  | Footprint | 246–253 MB | 155–184 MB |
  | Main thread busy per 5 s (no input) | 3.3–5.9 s, turns up to 5.8 s | 0.14–0.3 s, longest turn 6–20 ms |
  | Snapshots applied | 2 a second (the pipeline's own limit), 6.5 ms each | 4.4 a second (the spacing), 1.8 ms each |
  | Sidebar scroll (1.6 s swipe) | 5 frames in 13 s, frozen | 136–159 frames, 0–2 hitches |
  | Tab bar scroll | frozen | 125–135 frames, 2–8 hitches |
  | ⌘1 / ⌘2 | 17.5 s and 23.6 s | 120–140 ms (first 500 ms) |
  | ⌃⌘] / ⌃⌘[ | not reached | 190–210 ms |
  | ⌘K, ⌃⌘S, ⌘. | not reached | 150 ms, 70 ms, 60–100 ms |
  | Same keys, 20 tabs / 26 panes (after) | | 85–95, 110–170, 100–120, 50, 40–60 ms |

  CI (Debug, 1x VM, XCUITest attached): first card > 30 s (failed, 40252712951) → 7–8 s; CPU on a busy tab not
  measurable before (the window never drew), 103–114 % after the first two fixes (40254175696), 67–70 % (40258293654)
  → 15 % (40261876163); a snapshot's apply 75 ms → 6 ms; footprint 244–254 MB. Keys there take 0.1–1.2 s of the app's
  own time, much of it XCUITest's accessibility queries served in the same turns.
- **Not done, and why.** A tab switch costs about 90 ms of main thread in Release even at 26 panes, so the target of
  one frame per interaction is not met at any size; at 400 panes it is 120–140 ms. Its profile: SwiftUI's layout of
  the window, the leaving cards' picture copies (lane A3's `keepPicture`), and AppKit's key equivalent search, which
  makes SwiftUI rebuild the menu bar's items on each key (View ▸ Pane ▸ Move Pane to Tab lists every tab: without
  that list, 100 ms instead of 130 ms at 300 tabs). Snapshot reads still cost most of the 10 % idle CPU (a herdr run
  and a 280 KB decode, 4 a second while agents work).
- **Decisions.** 250 ms spacing (an agent's state shows up to a quarter second later in a busy session; a write is
  read at once). 400 panes on CI (600 took CI two minutes to make and timed the helper out in a full run), 200 here.
  The menu bar keeps every tab in Move Pane to Tab (the user's phase 25 ask). Declined review nits: a per-call helper
  timeout (lane V's stress call needs the 300 s too); the Agents view's workspace grouping stays rows × tabs (30,000
  steps at 100 agents).
- **Tests.** `testHundredsOfPanesStayQuick` (on demand: `make e2e ONLY=…` or CI's only_testing; the Makefile's
  `ON_DEMAND` keeps it out of the shards, where it pushed one past CI's 20 minutes; bounds: first card within 20 s, busy-tab CPU under 50 %, a snapshot's apply
  under 25 ms on average, every key in its turn or the next; each fails on the before build), the HerdrKit tests
  `events that keep coming read at most every spacing, writes at once` and `a long line and the lines around it read
  whole, and quickly` (both red on the old code).

### Lane V (items 4–6)

- Written with phase 28's lane V (`28-fourth-feedback.md`, "Lane V"): item 4's numbers (200 tabs, 272 panes,
  16 live cards, footprint bounded by the cap, hitches against lane S's baseline), item 6 (0.18 s zoom, fade-in
  on open, 3f48029); item 5 went to lane T.

### Lane T (item 13, and lane V's item 5)

- **Root cause.** A new strip lays out its first page for one frame, then jumps to the selected tab. `Detail` makes
  a new `Strip` on every workspace or session change (`.id("\(page.id) \(workspace.id)")`) and when the overview
  closes (the overview replaces the sidebar and strip). The new strip's `ScrollPosition` starts empty, so its
  `LazyHStack` lays out page 0. `onChange(initial:)` asks to scroll to the selected tab, but a lazy page that is not
  laid out yet cannot be found. So the `Task { scrollTo }` retry moves the strip one run loop turn later, after the
  first commit drew the first tab (or the window's fill around a page that was not laid out). Seen on this Mac in an
  XCUITest recording (Retina, motion on): right after the overview's zoom into "second", the window shows the first
  tab's three cards for one frame, then "second". The probe below shows the zoomed-into card 1496 pt to the right
  (one page) for one commit, and 792 pt on CI.
- **Fix** (a401401). `.defaultScrollAnchor(start, for: .initialOffset)` on the strip: the selected tab's page as a
  unit point of the pages (index / (count − 1)), so the first layout is already on it. `.initialOffset` applies once,
  so resizes, new tabs, closes and the sidebar behave as before. The `onChange` scroll and its `Task` retry stay for
  a new tab's page and for herdr's tab taking its stand-in's place. They are no-ops on a new strip now.
  `ScrollPosition(id:)` as the initial value was tried first and is not honored on the first layout: the strip stayed
  on page 0 with the position saying the second tab, and nothing corrected it (a local run).
- **What it was not.** The terminal reveal path (stills, `keepPicture`, the settle, the fade) showed no bad commit on
  any path, on CI or locally, before or after. ghostty frees its swap chain when drawing pauses (`setVisible(false)`
  → `releaseGpuResources`, ghostty c4e16970a), so a settle while shown could in theory show an emptied picture. The
  probe checks for emptied surfaces and saw none on the paths that hold a grid on show (a tab shown after the
  sidebar hid or showed). So no change there (ponytail: no fix without a failing case).
- **Probe** (`FrameProbe`, `-recordFrames YES`). For 1.5 s after the window shows another tab, it records at every
  run loop turn's Core Animation commit what each of the tab's cards draws: whether its terminal view is in a card's
  host in the window, its picture's ink on a 48 × 32 grid read from the IOSurface (the still or the live one),
  emptied or not, the reveal fade, and its top left in the window. A commit is bad when a card is gone, blank,
  fading, shows a third picture or moved (codes `-`, `0`, `f`, `p`, `j`). A display link's frames missed the bad
  commit: SwiftUI commits several times between two ticks. XCUITest's accessibility queries hold the app's main
  thread for up to 240 ms, so the test makes none while a record runs.
- **Test** (`testATabComesIntoViewWithoutAFlicker`). w1 gets a third tab, so the second tab is a middle page. Each
  tab is shown once first, then the test records tab click and key, workspace and back, session dot and back, ⌥⌘]
  and ⌥⌘[, a session swipe either way (natural scrolling decides which turns), the overview's zoom into another tab
  and into the shown tab, and a tab shown after the sidebar hid and after it showed. Each step must give exactly one
  record (none for a swipe that turned no page), and every record must have 0 bad commits.
  - Old code, CI 40258371228 (1x): red, `overview zoom into another tab: w1:t2 1/4 j(792,0)` and the same for the
    shown tab; every other step 0. Locally (Retina) on the old code: the zooms red in 3 of 3 runs (the shown tab in 2
    of 3), the other steps 0. So the user's "only for a tab that was not shown" was the first-tab case: a zoom into
    the first tab cannot show a jump.
  - The workspace and session steps (a new strip on a middle or last tab) never jumped in these runs: there the
    first scroll found the page. They go through the same strip, so the fix covers them. A heavier session (more
    tabs, a slower first layout) is the likely case where the user saw it. **For the user to check.**
  - Fixed code: all steps 0, locally three times (Retina) and on CI (below).
- **Faster fade-ins** (orchestrator, 598b912, 74f10d7). A terminal's first reveal (also a rebuilt, evicted card's,
  and the overview's tiles, which show the same views) goes from 0.12 s to 0.06 s. A new card's fade during a split
  goes from 0.13 s (with its slide) to 0.06 s (the slide stays 0.13 s). The zoom's fade of the other cards stays
  0.13 s, with the dividers. Under Reduce Motion, none of these fades run, as before. The hover card (0.13 s) and the
  overview's fade-in (0.18 s, lane V) are not pane fades and stay as they are. Docs: layout, states, window,
  talking-to-herdr.

## More from the user (2026-10-25 17:35)

- (Lane R) The glass dialogs have poor contrast (`.build/fb/remote-glass.png`): grey text on grey glass, the
  answer field nearly invisible. Same for Add Remote Host. The user also could not find how to list and
  open a remote machine's other sessions: Open Session in a remote window must list that machine's
  sessions.
- (Lane V, replaces phase 28 item 3) A stress test with hundreds of agents on a remote server made the
  overview very laggy, so keeping every tile live does not scale. Only tiles in or near view are live
  (hard cap, lower for remote machines); every other tile shows a cached, downscaled snapshot (memory-
  bounded cache) so it appears at once and turns live in place; never-seen tiles show herdr's text drawn
  small or a quiet placeholder, never a fade. A stress harness with 100–200 panes measures scroll frame
  rate, CPU and memory. Target: 60 fps scrolling at 200 tabs, memory bounded regardless of tab count.

## Lane T: a tab flickers when it is shown (2026-10-25 17:40)

13. The flicker after zooming into a tab from the overview (item 5) also happens when moving between
    sessions: it is a common flicker when a tab becomes shown, in whatever way. Find the one cause (for
    example a still picture removed before the live surface drew, a terminal view moving between hosts, a
    reveal or fade on a kept terminal, a strip page rebuilt) and fix it there, for every path: session
    swipe and dots, ⌥⌘[ ], the overview's zoom, tab clicks and keys, workspace switches. Lane T owns this;
    lanes V (overview) and E (session swipe, phase 28) leave the flicker to it.

## Lane S: the whole UI at scale (2026-10-25 17:45)

14. The UI must stay snappy with hundreds of workspaces, tabs and panes while panes print output (agents
    working). Build one stress harness (a script that creates a throwaway session with, say, 30 workspaces,
    300 tabs and 600 panes, a share of them printing like agents, some with agent states) and measure,
    before and after: key-to-frame latency of every main interaction (lane S of phase 25 has latency tests:
    ⌘T, ⌘W, ⌘D, ⌘K, tab and workspace switches, session swipe, the sidebar, the Agents view, the hover card,
    Open Session, drag and drop), frame rate while scrolling the tab bar and the sidebar, CPU and memory
    idle and busy, snapshot and event handling cost on the main thread. Profile (Instruments / `sample` on a
    local Release build when the GUI is free; CI meanwhile) and fix what scales badly (work per snapshot
    that grows with the number of panes, views that rebuild for every output line, lists that build every
    row). Lane V (overview) uses the same harness for the overview; lane S owns everything else.
    Targets: every interaction under one frame of main-thread work on top of herdr's own time, smooth
    scrolling, idle CPU a few percent, memory bounded by what is shown (phases 25 O and 27 A3).
- (Lane R, 17:50) Picking a machine whose window is already open brings that window forward instead of
  opening another. ⌘N opens a new window at a big default size (about 90% of the screen's visible frame,
  centered); restored windows keep their frames.
- (Lane T, 17:58) Every pane fade-in about twice as fast (first reveal, rebuilt card, split's new pane),
  or a straight swap where it looks fine; the no-blank rule stays.

## Lane C: selection colors (2026-10-25 18:00)

15. Selected text in a terminal is unreadable (`.build/fb/selection.png`): a grey block with the text
    drawn in a dark grey close to the block. Find who draws the selection (libghostty's own selection, or
    herdr's selection sent in its frames) and its colors (Oriel's libghostty config, the Alabaster /
    Afterglow defaults, herdr's theme). Make selections readable in light and dark, Glass and Classic: keep
    each cell's own text color over a selection background with enough contrast (for example Ghostty's
    `selection-foreground = cell-foreground` with a translucent accent or system selection color
    background), matching macOS's selection feel. Keep libghostty's palette otherwise (the user rejected
    other palettes).
16. (Lane C, 18:15) **Letter icons** (`.build/fb/letter-icons.png`): a program without a logo shows a
    letter ("G" for glow) that is smaller than the logos, so names after it do not line up. Every program
    icon, letters included, takes the same box everywhere it shows (hover card rows, tab capsules, card
    headers, Agents rows, palette, overview tiles), so the names align.

## More from the user (2026-10-25 18:30)

- (Lane R) The + and pencil glyphs in the Add / Edit Remote Host titles look off and out of line
  (`.build/fb/s-6.21.46.png`, `s-6.21.55.png`): drop them (title text only) or size and align them on the
  title's text line; the title's leading edge lines up with the form.
- (Lane R) Open Session shows another device's sessions: a window lists only the sessions of its own
  machine. The phase 29 lane M cache must be per machine and must never show another machine's list.
- (Lane E) With several sessions, the sidebar shows workspaces only for the first one once a swipe settles
  (`.build/fb/s-6.20.01.png`, `s-6.20.06.png`: the pages overlap mid-way). Likely the bug 643e336 fixed;
  confirm on the user's case.
- (Lane F) The floating placeholder gets two buttons: "Show Window" (brings the floating window forward)
  and "Bring Back Here" (detaches: closes the floating window and shows the pane in its card again).
