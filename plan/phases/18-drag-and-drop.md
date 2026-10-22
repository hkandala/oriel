# Phase 16: drag and drop

Goal: drag a pane by its header to swap, split, move it to another tab or workspace; drag tabs and
workspaces to reorder them. The design already has the drop table (`ui/drag-and-drop.mdx`); Rex gives
the look and timings.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (pane drag, drop indicator,
spring-loading, tab reorder), `docs/content/docs/ui/drag-and-drop.mdx`,
`docs/content/docs/talking-to-herdr.mdx` (writes table: swap and move), `docs/content/docs/platform.mdx`
(other details), D13, D35.

## Build

1. **Start.** Drag a card's header (the title area, not its buttons) 4 pt or more. The header no longer
   moves the window (it never did: the window moves only from the title row). With headers hidden
   (phase 15), drag with ⌥ held anywhere on the card's edge.
2. **Preview.** The dragged card shows a small snapshot of itself (header + top of the terminal) at
   50 % size under the pointer; the card in place dims to 0.4.
3. **Drop targets and indicator.** An indicator is a rounded rect (radius 10) filled with the accent
   at 0.2 and a 2 pt accent stroke, animated 0.12 s between targets.

   | Drop on | Indicator | herdr call |
   |---|---|---|
   | the center third of a card in the same tab | the whole target card | `pane.swap {source_pane_id, target_pane_id}` |
   | an edge band (the outer quarter) of a card in another tab | that half of the target card | `pane.move {pane_id, destination: {type:"tab", tab_id, split, target_pane_id}}`; for left or top, then `pane.swap` |
   | a tab capsule or a sidebar tab row; hold 0.65 s to page to that tab, then drop on a card | the capsule or row lit | `pane.move {… type:"tab", tab_id, split:"right"}` |
   | the tab track's empty end or the `+` button | a ghost capsule at the end | `pane.move {… type:"new_tab", workspace_id}` |
   | a workspace header in the sidebar | the header lit | `pane.move {… type:"new_tab", workspace_id}` |
   | empty sidebar space | a ghost row "New Workspace" | `pane.move {… type:"new_workspace"}` |

   Inside one tab only swap is offered (design). A pane cannot leave its machine (one machine now).
4. **Spring-loading.** Holding over a capsule or row for 0.65 s selects that tab (the strip pages
   there) and the capsule pulses once (scale 1.04, 0.2 s).
5. **After the drop.** One write, then the snapshot. `pane.move` and `pane.swap` can return
   `changed:false` with a reason: show it in the notice. `pane.swap` makes herdr focus that tab (known,
   accepted in the design).
6. **Tabs.** Drag a title-bar capsule or a sidebar tab row to reorder inside its workspace:
   the others slide apart (0.22 s, curve 0.2 0.9 0.3 1); on drop `tab.move {tab_id, insert_index}`.
   A tab cannot be dropped in another workspace (herdr moves tabs only inside one).
7. **Workspaces.** Drag a sidebar section header to reorder: `workspace.move {workspace_id,
   insert_index}`.
8. **Escape** cancels a drag. A failed write leaves the layout as herdr has it.
9. **Docs.** Update `ui/drag-and-drop.mdx` (timings, indicator, tab and workspace reorder) and the
   writes table.

## e2e

XCUITest can drag (`press(forDuration:thenDragTo:)`).
- Drag a card's header onto the center of its neighbor: herdr swaps them.
- Drag a card onto a tab capsule, hold, then onto the right edge of a card there: the pane is in that
  tab, split right.
- Drag a card onto empty sidebar space: a new workspace holds it.
- Drag the third capsule to the first place: herdr's tab order changes.
- Drag a workspace header below the next one: herdr's workspace order changes.

## Done when

- Screenshots: a drag over a center target, over an edge target, spring-loaded tab, tab reorder in
  progress.
