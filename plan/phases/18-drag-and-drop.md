# Phase 18: drag and drop

Goal: drag a pane by its header to swap it, re-place it beside another card, or move it to another
tab or workspace; drag tab capsules and workspace rows to reorder them. Every target and herdr call is
in the tables of the window design (`docs/content/docs/ui/window.mdx`) ("Moving panes, tabs and workspaces by drag and drop"); this
phase builds exactly those, with Rex's look and timings.

## Build

### Pane drag

1. **Start.** Drag a card's header (the title area, not its buttons) 4 pt or more. The window moves
   only from the title row, never from a header.
2. **Preview.** The drag image: a snapshot of the card's header under the pointer; the card in place
   dims to 0.4.
3. **Indicator.** A rounded rect (radius 10) filled with the accent at 0.2 and a 2 pt accent stroke,
   animated 0.12 s between targets. A place that is not a target shows the forbidden cursor and no
   indicator.
4. **Targets** (card zones: the outer quarter on each side is that edge; the rest is the center):

   | Drop on | Indicator | herdr calls |
   |---|---|---|
   | the center of another card in the same tab | the whole target card | `pane.swap {source_pane_id, target_pane_id}` |
   | an edge of another card in the same tab | that half of the target card | re-place (step 5) |
   | the pane's own tab capsule | none: not a target (herdr refuses `reason:"same_tab"`) | — |
   | another tab's capsule in the title row | the capsule highlighted; after 0.65 s it spring-loads (step 6) | `pane.move {pane_id, destination: {type:"tab", tab_id, split:"right"}}` |
   | an edge of a card in another tab (after spring-loading) | that half of the target card | `pane.move {pane_id, destination: {type:"tab", tab_id, split, target_pane_id}}` (right or down); for left or top, then `pane.swap {source_pane_id, target_pane_id}` |
   | the center of a card in another tab | none: not a target (herdr cannot swap across tabs, `reason:"cross_tab"`) | — |
   | the empty end of the tab track, or the `+` | a ghost capsule at the end | `pane.move {pane_id, destination: {type:"new_tab", workspace_id}}` (the selected workspace) |
   | a workspace row in the sidebar | the row highlighted; after 0.65 s it spring-loads (step 6) | `pane.move {pane_id, destination: {type:"new_tab", workspace_id}}` |
   | empty space at the bottom of the sidebar page, or the page header's `+` (follow-up) | a ghost row "New Workspace", or the `+` highlighted | `pane.move {pane_id, destination: {type:"new_workspace"}}` |
   | page dots, the Agents view, another window | not a target | — |

   Nothing moves between sessions or machines (separate herdr servers), so a pane never leaves its
   page. A drop of a card on itself does nothing.
5. **Re-place in the same tab.** herdr refuses a move into the pane's own tab (`reason:"same_tab"`), so
   an edge drop in the same tab is three calls, each followed by a snapshot read:
   1. `pane.move {pane_id, destination: {type:"new_tab", workspace_id}}` (the pane gets a new tab;
      the pane id stays in the same workspace).
   2. `pane.move {pane_id, destination: {type:"tab", tab_id: <the old tab>, split: right|down,
      target_pane_id}}` (right for a left or right edge, down for a top or bottom edge).
   3. For a left or top edge: `pane.swap {source_pane_id, target_pane_id}`.
   The app keeps the old tab selected throughout, so the strip does not page. If step 2 or 3 fails,
   the pane stays where it got to, and the notice says so ("Moved the pane to a new tab: herdr
   refused the next step"). After the drop, the moved pane's card has the keyboard.
6. **Spring-loading.** Holding over a capsule for 0.65 s selects that tab (the strip pages there) and
   the capsule pulses once (scale 1.04, 0.2 s); the drop can then go on a card there. Holding over a
   workspace row for 0.65 s selects that workspace instead (its tabs show in the title row), so the
   drop can go on a capsule or a card. A drop on the capsule or row itself still uses its row in the
   table.
7. **After the drop.** The writes, then the snapshot. Every `pane.move` passes `focus:false` (the house
   rule; herdr's default is false). `pane.move` and `pane.swap` can return `changed:false` with a
   reason (`same_tab`, `cross_tab`, or `zoomed_tab` when a herdr TUI user zoomed the tab): show it in
   the notice. A pane moved to another workspace gets a new
   pane id; its terminal id stays, so its card and stream stay. Moving a tab's last pane closes that
   tab. `pane.swap` makes herdr focus that tab (known, accepted in the design).

### Tabs and workspaces

8. **Tabs.** Drag a capsule along the tab track to reorder inside its workspace: the others slide
   apart (0.22 s, curve 0.2 0.9 0.3 1); on drop `tab.move {tab_id, insert_index}`. A capsule over a
   workspace row is not a target (herdr moves tabs only inside a workspace): the forbidden cursor (none on macOS:
   see Follow-up).
9. **Workspaces.** Drag a workspace row up or down its page: the rows slide apart as tabs do; on drop
   `workspace.move {workspace_id, insert_index}`. A row with linked worktree children moves with them:
   `workspace.move_block {workspace_ids: [parent, children…], before_workspace_id}`. A child dragged
   alone stays in its parent's group (it reorders only among its siblings).
10. **Escape** cancels a drag (the system drag does this; with the `NSEvent` monitor, handle Esc). A
    failed write leaves the layout as herdr has it.
11. **Docs.** Rewrite `ui/drag-and-drop.mdx` with the tables above (targets, refusals, the same-tab
    re-place, timings, indicator, tab and workspace reorder) and the writes table in
    `talking-to-herdr.mdx` (`pane.move` chains, `workspace.move_block`). Change D69 if the build
    differs.

## Findings

### Deviations

- **A re-place reads the snapshot once, after the drop**, not after each step: each step uses the pane id
  herdr's reply names (`move_result.pane`), which is what a snapshot read in between would give. One more
  snapshot read sits before the equal splits, which need herdr's tree.
- **Every move into a tab gets equal splits** (an edge, or a capsule's split right): the run of same-direction
  splits holding the pane is evened out, as after a split (phase 17's `evened(around:)`), so a drop beside a
  card of a 50 / 50 tab gives thirds, not 50 / 25 / 25.
- **Workspace drags use `workspace.move_block`**, as Move Up and Move Down do, for a lone workspace too (no index
  arithmetic). A worktree dragged alone goes before another worktree of its repository, or, last, before the
  workspace after the last one in herdr's order (herdr shows a worktree under its repository whatever the order).
- **The `+` is highlighted** while a pane is over it, besides the ghost capsule: on a full track the ghost
  capsule has no room.
- **Workspace rows do not reorder while the sidebar filter hides rows** (a reorder needs them all); the drop is
  not taken.
- **The own tab's capsule does not spring-load** either (strictly "not a target").
- **The refusal notices**: `zoomed_tab` reads "The tab is zoomed in herdr"; any other reason reads "herdr changed
  nothing (reason)". The drag targets never send a move that `same_tab` or `cross_tab` would refuse.
- **No checks or screenshots mid-drag in XCUITest.** XCUITest runs nothing while `click(forDuration:thenDragTo:
  withVelocity:thenHoldForDuration:)` drags, not even the main queue (a `Task` meant to fire during the hold ran
  after the drop, on CI). So the spring-load test makes the drop fail (`zoomed_tab`, after `pane.zoom` in herdr):
  the tab can only be selected by the spring-load then. Drag screenshots come from the run's screen recording.

### Decisions

- **Types:** `Dragged` (pane, tab, workspace) on `Page.dragging`, set by `DragSource.begin` and cleared by the
  session's end; `DropTarget` (a card's center or edge, a tab, or a `Destination` for a new tab or workspace);
  `CardDrop`, `PaneDrop` (one-target places: the track's end, `+`), `TrackDrop` (capsules: pane spring-load and
  drop, tab reorder) and `RowsDrop` (rows: pane spring-load and drop, the ghost row, workspace reorder) as
  `DropDelegate`s, in `Drag.swift` and `ListDrops.swift`. `Page.drop` runs the writes; `HostStore.place` is the
  re-place and the move into a tab.
- **The pasteboard type `dev.hkandala.oriel.drag`** is declared in `Oriel/Info.plist` (merged into the generated
  one, excluded from the synchronized group's resources): undeclared, XCTest reported a runtime issue. The page,
  not the pasteboard, says what is dragged.
- **Zones:** the nearest edge within the outer quarter wins (corners go to the nearer side). A target's
  highlight and a card's indicator animate 0.12 s; capsules and rows slide apart with Rex's 0.22 s production
  curve (`Animation.slide`). The dragged capsule, row or card dims to 0.4 in place.
- **Tab and row reorder** compute the place from the pointer in the track's content space (equal slots) or from
  row frames measured while nothing is dragged, so the slide offsets never feed back into the target.
- **Row frames are measured while nothing is dragged**, so the slide offsets never move them; a snapshot from
  another client that moves rows mid-drag leaves them stale until the drag ends (ponytail: not worth code).
- **Drags start only on a live session** (a stopped session's last rows stay, but a drop could not write).
- **`HerdrError.refused(reason)`** for `changed:false` on `pane.move` and the id-based `pane.swap`; the
  directional swap keeps ignoring `no_neighbor` (the keys do nothing at an edge).

### Follow-up (after the hand checks)

- **Drop highlights end with the drag.** Each target clears its drop state when `page.dragging` goes nil
  (`clearsDrop`: card zones, capsule and track-end state, the `+`s, the rows' state) and draws its overlay only
  while a drag runs. The hand check's guess held: a `dropUpdated` can come after `performDrop`, with no
  `dropExited` after it. `DropIndicator` is an accessibility element (`drop.indicator`), so e2e checks that none is
  left after a drop.
- **The keyboard after a move waits for the snapshot.** A write reads the snapshot without waiting for it, so when
  the drop ended the store still had the pane in its old tab, and `focusKeyboardCard` gave the keyboard to the
  destination tab's old card (a left or top drop in a spring-loaded tab; right and bottom won the race). `follow`
  now leaves it to the next snapshot (`keyboardTabID = nil`, then `shown`) until the store has the pane there.
  XCUITest cannot drag to a spring-loaded tab's card (a drag ends where it holds), so this is a hand check.
- **The page header's `+` takes a pane** for a new workspace, highlighted while a pane is over it: a full page has
  no empty space under its rows, and the list does not scroll during a drag.
- **No forbidden case for a tab over the rows**: macOS shows the plain arrow for `.forbidden` (hand check 4).
- **Late drop callbacks** (spec review): a `dropUpdated` or `dropEntered` may also come after the session ended, so
  targets clear their state when a drag starts as well as when it ends, ignore updates with no drag, and a
  spring-load fires only while a pane is dragged. `focusKeyboardCard` records the tab as given the keyboard only
  when the card it should go to is in the tab, so any snapshot that comes before the moved pane shows retries.
- **`drop.indicator` is in the accessibility tree** (checked by hand: an AX query during a CGEvent drag found it
  over the target card, and none after the drop), so the e2e `vanishes` checks would catch a highlight left behind.
