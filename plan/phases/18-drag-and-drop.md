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

### Spike (herdr 0.9.5, step 0)

- **`pane.swap {source_pane_id, target_pane_id}`** trades the two panes' places (sizes stay with the places) and
  moves herdr's focus to the source pane and its tab, `focus:false` or not, also in another workspace; a swap
  across tabs is `changed:false, reason:"cross_tab"` and a pane with itself `same_pane`. A directional swap at an
  edge is `no_neighbor`, which the keys still ignore.
- **`pane.move` with `focus:false` never moves herdr's focus**, whatever the destination. Into another tab it
  splits beside `target_pane_id` at 0.5 of that pane; into its own tab it is `changed:false, reason:"same_tab"`
  with the reply still naming the pane. In the same workspace the pane keeps its id (to a new tab, back again);
  to another workspace it gets the next id there (`w1:p4` → `w2:p2`), its terminal stays. A tab left empty
  closes; the other tabs' default labels renumber. `new_workspace` names the workspace after the cwd ("tmp").
- **Without `target_pane_id`, `pane.move` into a tab splits the tab's focused pane**, not its whole layout (as
  `plan/ui-layout.md` had it): a drop on a capsule names the tab's last card instead, so where it lands does not
  hang on herdr's focus. The card menu's Move to Tab ▸ (phase 17) still omits it. ponytail: left as is; it lands
  beside herdr's focused pane there.
- **`pane.zoom` zooms only a tab with two panes or more** (`reason:"single_pane"` otherwise), and moves herdr's
  focus to the pane; a move into or out of a zoomed tab is `zoomed_tab`.
- **`tab.move`** reorders only inside the tab's workspace: a `workspace_id` of another workspace is ignored (the
  tab moved inside its own). **`workspace.move`** inserts before the workspace now at the index.
- **The drag: an AppKit dragging session**, started from the header's (capsule's, row's) SwiftUI `DragGesture`
  through the window's content view (`beginDraggingSession`), with one `NSDraggingSource` object for the app,
  and SwiftUI `DropDelegate`s as targets. The session belongs to the window, so a spring-load that drops the
  source card from the `LazyHStack` cannot cancel it, and the source's `endedAt` clears the page's drag state
  whatever view is left (SwiftUI's `onDrag` has no end callback, and macOS 26's `onDragSessionUpdated` lives
  on the view that goes away). The system gives the preview, Esc and the pointer badges. A window-level
  `NSEvent` monitor would have needed its own preview window, Esc and hit testing.

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

### Assumptions

- **macOS has no forbidden pointer for drags**: a `.forbidden` proposal shows the plain arrow, as a `.move` does
  (no badge for either). Checked by hand once the GUI is back.
- **A drag from a capsule or a header does not move the window**: `WindowDragGesture` sits behind the title row's
  controls, and headers have none. Checked by hand once the GUI is back.

### Learned

- **CI's recording, for the rough screenshot:** with the GUI paused, the rough screenshot came from a failed CI
  run's screen recording (`gh run download`, `xcresulttool export attachments`, ffmpeg frames). Recordings are
  kept only for failed tests.
- **The design had a herdr fact wrong**, found by the spring-load test failing on CI: `pane.move` into a tab
  without `target_pane_id` splits the tab's focused pane, not its whole layout. Proving the spring-load took
  three CI runs (no mid-drag checks; a lone pane does not zoom; then this).
- **Screenshots come from CI.** The scheme keeps every test's screen recording (`systemAttachmentLifetime =
  keepAlways`) and CI uploads the xcresult of green runs too, so a phase's drag-in-progress shots are frames of
  its tests' recordings (`xcresulttool export attachments`, then ffmpeg). Before, only failed tests kept one,
  and only failed runs uploaded the bundle.

- **A `.forbidden` proposal falls through to the drop target behind** (seen in CI's recording): the track's
  end, laid behind the whole track, lit its ghost capsule while a pane hovered its own capsule. The end target now
  covers only the space after the tabs, and carries the row's `WindowDragGesture`, since it takes that space's
  clicks.

### To check by hand when the GUI is free

1. Spring-load to another tab, then drop on a card's edge there: right and bottom split beside it; left and top
   end left of or above it (move, then swap). A card's center there: no indicator, not taken. The capsule pulses
   once (1.04).
2. Spring-load a workspace row (hold 0.65 s): its tabs show; then drop on a capsule there and on a card's edge
   there. A drop on the row itself: a new tab.
3. Esc mid-drag, before and after a spring-load: no herdr write, the card back at full opacity, no indicator or
   ghost left, and a second drag starts.
4. The pointer on places that are not targets (own card, own tab's capsule, page dots, the Agents view, a
   capsule over a workspace row, a row while the filter is on): whether macOS shows a forbidden pointer for a
   `.forbidden` proposal at all. If it shows the plain arrow, the `.tab` case in `RowsDrop` can go.
5. The window does not move when a drag starts on a header, a capsule or a row; the title row's empty space
   still moves it, also right after the tabs (the track's end target). A click on a capsule selects it, a double-click renames; a header's double-click zooms.
6. A drop outside the window or on a second Oriel window: nothing happens, the drag state clears.
7. A re-place in the same tab: no flash of the passing new tab in the title row; the moved card has the keyboard.
8. A full track (about 12 tabs): the `+` is highlighted. A sidebar with no empty space under its rows: is the
   ghost "New Workspace" row reachable?
9. The preview (the header's snapshot) in full screen and with the sidebar collapsed.
