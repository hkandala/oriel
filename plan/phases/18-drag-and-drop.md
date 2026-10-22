# Phase 18: drag and drop

Goal: drag a pane by its header to swap it, re-place it beside another card, or move it to another
tab or workspace; drag tab capsules and workspace rows to reorder them. Every target and herdr call is
in the tables of `plan/ui-layout.md` ("Moving panes, tabs and workspaces by drag and drop"); this
phase builds exactly those, with Rex's look and timings.

Read first: `resources/research/clients/rex-internals.md` (§3.6, §5.4: AppKit pane drag and drop indicator view, spring-load delay; read before the step 0 spike; facts only, write your own code), `plan/ui-polish.md`, `plan/ui-layout.md` (drag and drop: what herdr 0.9.5 allows, every
target, tabs and workspaces), `resources/mockups/layout.html` (scene K), `resources/research/clients/rex-ui.md` (pane drag, drop indicator,
spring-loading, tab reorder), `resources/research/herdr/herdr-core.md` (move calls),
`docs/content/docs/ui/drag-and-drop.mdx`, `docs/content/docs/talking-to-herdr.mdx` (writes table:
swap and move), `docs/content/docs/platform.mdx`, D13, D35, D69.

## Build

### Spike first (half a day)

0. The strip is a `LazyHStack` and shows one workspace; a workspace switch swaps all its pages. So
   spring-loading to a far tab, or to another workspace's row, removes the drag's source card from the
   view tree, and a plain SwiftUI `DragGesture` on the header is cancelled mid-drag. The drag must
   survive that. Try an AppKit drag session (`NSView.beginDraggingSession` from the header, or SwiftUI
   `.onDrag` / `.draggable`) with drop handling (`DropDelegate`) on the title row, strip and sidebar,
   versus a window-level `NSEvent` local monitor for mouseDragged / mouseUp that draws the preview in a
   window overlay. Prefer the system drag: it gives the preview, Esc and the forbidden cursor
   (`DropProposal(operation: .forbidden)`) for free. Also check that a drag that starts on a title-row
   capsule does not move the window, and that XCUITest drags still work. Record the choice.

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
   | empty space at the bottom of the sidebar page | a ghost row "New Workspace" | `pane.move {pane_id, destination: {type:"new_workspace"}}` |
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
   workspace row is not a target (herdr moves tabs only inside a workspace): the forbidden cursor.
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

## e2e

XCUITest drags on macOS: `click(forDuration:thenDragTo:)` (phase 14); `press(forDuration:thenDragTo:)` sends no mouse down.

XCUITest can drag (`press(forDuration:thenDragTo:withVelocity:thenHoldForDuration:)`), but it holds only
at the end of a drag. All in `ORIEL_SESSION`, in a new workspace that the test closes after.

- Drag a card's header onto the center of its neighbor: herdr swaps them.
- Drag a card onto the left edge of its neighbor in the same tab: the snapshot has the pane left of
  that neighbor, in the same tab, and the tab count is unchanged.
- Drag a card onto another tab's capsule and hold 1 s at the end (`thenHoldForDuration`): that tab is
  selected and, after the drop, holds the pane split right. A drop on an edge of a card in another
  tab after spring-loading is checked by hand.
- Drag a card onto the empty end of the tab track: a new tab holds it.
- Drag a card onto another workspace's row: a new tab in that workspace holds it.
- Drag a card onto empty sidebar space: a new workspace holds it.
- Drag the third capsule to the first place: herdr's tab order changes.
- Drag a workspace row below the next one: herdr's workspace order changes; a parent with a worktree
  child moves with the child right after it.

## Done when

- Screenshots: a drag over a center target, over an edge target, a spring-loaded tab, a tab reorder
  in progress, a not-allowed target.

## Findings
