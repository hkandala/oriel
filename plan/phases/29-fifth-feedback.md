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

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each lane's
  last code commit; one review round per lane (spec and ponytail, read only).

## Findings

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
- **Reviews.** Spec (should): read the tree in the write's turn, D69 updated; nits taken: first pane as the fallback
  (an ordered result), keyboard check after the menu drop, own-row check, every drag point inside the Oriel window.
  Ponytail: one helper branch for both scripts, one own-workspace rule. Not taken: `drop(tab:on:)` back in Page.swift
  (its 400-line limit; `follow` is internal for it), a labelled 4-tuple for `Move` (SwiftLint `large_tuple`), a
  number-only label kept (herdr's number rule is `Page.title`'s), a stand-in tab refused silently (a sub-second case).
- **Known limit (check by hand).** Once a drag springs the menu open, the panel's full-window backdrop sits over the
  strip, so the drag can end only on a menu row (or nowhere) until it ends; the menu closes then.

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
