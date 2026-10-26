# Phase 17: pane cards and layout

Goal: pane cards look and act like Rex's (header, buttons, fade, context menu), and the split layout
can be changed by hand: drag, double-click and keys on dividers, balance, focus and move panes with
keys.

## Build

### Card

1. **Header.** 36 pt tall. Leading 6 pt: the program glyph (phase 12), the title (program, then the
   folder in secondary text). Trailing 8 pt: four 22 × 22 pt buttons 2 pt apart: Split Right
   (`rectangle.split.2x1`), Split Down (`rectangle.split.1x2`), Zoom
   (`arrow.up.left.and.arrow.down.right`), Close (`xmark`). The buttons show on the keyboard card and on
   a hovered card. Zoom is disabled when the tab has one pane.
2. **Zoomed card.** Only two buttons: Restore (`arrow.down.right.and.arrow.up.left`, white on an accent
   circle) and Close.
3. **Fade.** Replace the black overlay. A card without the keyboard draws its content (the terminal)
   at opacity 0.7 and uses the phase 10 "no keyboard" card fill; the keyboard card is 1.0 with the
   keyboard-card fill and stroke. In a window that is not key: 0.5 for the others, 0.8 (dark) or 0.85
   (light) for the keyboard card. One setting, **Fade inactive panes** (on), turns both fades off: a toggle in the View menu
   (View ▸ Fade Inactive Panes, `@AppStorage`), as there is no Settings window (D62). The watching window's
   0.85 dim (phase 16) multiplies with these.
4. **Context menu** on the header (not inside the terminal, which keeps its own right-click): Split
   Right, Split Down, Split Left, Split Up, Zoom / Restore, Move to New Tab, Move
   to Tab ▸ (the workspace's other tabs), Move to New Workspace, Rename Pane…, Close Pane.
   - Split Left / Up: `pane.split` right / down, then `pane.swap` of the old and the new pane (herdr
     splits only right and down).
   - Move to New Tab: `pane.move {destination: {type: "new_tab", workspace_id}}`; to a tab:
     `{type: "tab", tab_id, split: "right"}`; new workspace: `{type: "new_workspace"}`. Move to Tab ▸
     lists only other tabs: herdr refuses a move into the pane's own tab (`reason:"same_tab"`). A
     pane moved to another workspace gets a new pane id; its terminal id stays, so its card stays.
   - Rename: an inline field in the header, `pane.rename {pane_id, label}`; an empty name sends
     `label: null`, which clears it.
   - All with `focus:false` where herdr takes it; read the snapshot after. Each action is an entry in
     the command list (phase 13).

### Dividers

5. **Hit area.** Each split's 8 pt gap is the divider, with a 16 pt hit area centered on it and the
   resize cursor (`.pointerStyle(.columnResize)` / `.rowResize`). On hover a grip shows: a 36 × 3 pt
   capsule (gorex) in the hover fill, fade 0.2 s.
6. **Drag.** The split moves live in the view (an app-side ratio for that split until the next
   snapshot shows herdr's). On release: `layout.set_split_ratio {tab_id, path, ratio}`, ratio clamped
   to 0.1–0.9. The path comes from the split's place in the tree (`false` = first child). Terminals
   keep the existing 100 ms resize settle, so a drag does not flood herdr with PTY resizes.
7. **Double-click** a divider: ratio 0.5.
8. **Equal splits (user, like Rex).** herdr halves the pane it splits (50 / 25 / 25). After every split
   the app makes (Split Right / Down / Left / Up, ⌘D, ⇧⌘D, a drop on an edge in phase 18), it evens out the
   run of same-direction splits that holds the new pane: n panes side by side get 1/n each (33 / 33 / 33).
   A run is the chain of splits in that direction; a child split in the other direction counts as one
   unit. Each split in the run gets "units on its first side ÷ units under it", one
   `layout.set_split_ratio` per split, sent after the split's snapshot arrives; then read the snapshot.
   Closing a pane does not re-balance (herdr gives its space to the neighbor; Balance fixes it).
   **Balance** (⌃⌘=, View ▸ Pane ▸ Balance Splits) applies the same rule to every run in the tab.
9. **Keys.** ⌃⌘← → ↑ ↓: `pane.resize {pane_id, direction, amount: 0.05}` on the keyboard card.
10. **Accessibility.** Each divider is an adjustable element ("Divider between ‹a› and ‹b›", value =
    ratio as a percent; increment and decrement move it 5 % and send the ratio).

### Focus and move with keys (the app's own keyboard card, never herdr focus, D13)

11. ⌥⌘← → ↑ ↓: give the keyboard to the nearest card in that direction (card frames from the layout,
    nearest by the center's distance along the axis, overlap first). herdr's read-only
    `pane.neighbor {pane_id, direction}` can answer this instead. Use one of the two, not both, and
    record which.
12. ⌘[ and ⌘]: previous and next card in the tree's order, round the ends.
13. ⌥⇧⌘← → ↑ ↓: move the keyboard card: `pane.swap {pane_id, direction}`. The keyboard follows the
    pane.
14. **Focus follows mouse** (a toggle in View ▸ Pane, `@AppStorage`, off): a card under a resting pointer (0.15 s) gets the
    keyboard. Never while a mouse button is down or the palette or a menu is open.
15. **Split keys.** ⌘D Split Right, ⇧⌘D Split Down (View ▸ Pane). Split Left and Split Up have no
    shortcut: ⇧⌘← and ⇧⌘↑ (Rex's keys) would steal "select to line start" from the app's text fields.
16. **Layout motion.** When the tree changes (split, close, move, ratio from herdr), card frames
    animate 0.2 s ease-out. If terminal resizes during the motion flicker, keep each terminal surface at
    its old size, clipped by its card, until the motion ends, then resize once. Reduce Motion: no
    animation.

### Docs

17. Update `layout.mdx` (dividers, balance, keys, motion, fade), `ui/window.mdx` (pane card, zoom,
    context menu), the keyboard table, `talking-to-herdr.mdx` writes table (split left/up, rename,
    move to new tab, keyboard move), `ui/settings.mdx` (the two View menu toggles), D42 (dividers), D64 (fade).

## Findings

### Deviations

- **⌃⌘= and ⌥⇧⌘ arrows are tested through their menu items.** On this Mac a global hotkey (BetterTouchTool or
  Raycast) takes ⌃⌘= before the app: a one-line log in the menu action and in the terminal's `keyDown` showed
  neither ran. The menu item (View ▸ Pane ▸ Balance Splits) works; the key binding is the same `Command`. ⌥⇧ chords
  are avoided for the same reason (speed rule 7).
- **Menu actions find their pane when they run.** SwiftUI rebuilds the menu bar's commands only now and then, and
  the keyboard card is the window's first responder, which it does not observe: a captured pane or tab would be the
  one from the last rebuild (phase 13's ⌘1…⌘9 items read the workspace when pressed for the same reason). `AppCommands.pane(page, target)`
  takes a closure that the actions call; Balance reads the selected tab when it runs and is enabled whenever a tab
  is selected (an even tab sends nothing). Titles and enabled states may still lag a little.
- **The zoom rule is in `Page.zoom`**: a tab's only card does not zoom from any path (button, double-click,
  ⇧⌘↩), as the disabled button says.
- **The page follows a moved pane.** The phase does not say; Move to New Tab, Move to Tab and Move to New Workspace
  select the destination tab and the pane keeps the keyboard there, as the keyboard follows a swapped pane.
  Without it the keyboard stayed on a terminal no longer in the selected tab.
- **Terminals hold their size during layout motion** (item 16's fallback, E2E review): resized at every animation
  frame, a neighbor's terminal went blank (cursor only) from about +95 to +280 ms after a split. `Motion` (in
  `Strip.swift`) sets `layoutMoving` for 0.2 s after each tree change; `TerminalHost.Host` then keeps the terminal
  view's frame, clipped, and fits it once when the motion ends (a terminal that never had a size fits at once). Not
  as a page appears: held then, a terminal attached at a passing launch size and resized right after (the first full
  run failed `testCardsAttachAtTheirSize` on it).
- **The grip's color** is gorex's muted icon color at 0.6 (`Look.grip`): the hover fill (`.primary` at 0.05) is
  invisible on a 3 pt capsule.
- **The keyboard card while a text field types** (spec review): the lit card and the menu bar's pane items follow the
  tab's last keyboard card (`Page.keyboardTerminals`), not herdr's focused pane, while the rename field, a filter or
  the palette has the keyboard. Before, ⌘W there could close herdr's focused pane without a prompt, and every card
  faded.

### Decisions

- **⌥⌘ arrows use herdr's read-only `pane.neighbor`**, not card frames: one call per key and no geometry code.
  herdr answers on its own 120 × 40 grid, whose ratios match the cards, so the neighbor matches what shows.
- **Equal splits** are `SplitNode.evened(around:)` in HerdrKit (unit tests in `SplitNodeTests`): a split's ratio is
  the units of its first side over its own units, where a child split the other way is one unit; with a pane, only
  the run of same-direction splits holding it (up from its parent while the parent splits the same way, then down
  through same-direction children); without, every split (Balance). Only changes above 0.001 are sent. A split is
  one `write`: `pane.split`, the swap for Left/Up, a fresh `session.snapshot`, then one `layout.set_split_ratio`
  per change; the snapshot read follows.
- **`Multiplexer` grew** `neighbor`, `swap(pane, heading)`, `resize`, `setRatio`, `move(pane:to:)`,
  `rename(pane:label:)`, and `split` returns the new pane. `Heading` (left/right/up/down) and `Destination` (new tab,
  tab, new workspace) are HerdrKit enums. An integration test runs them against a throwaway session.
- **Pane commands** (`AppCommands.pane`) are one list for View ▸ Pane and the header's context menu (sections
  `.pane`, `.paneMove`, `.close`); keys only (select, move, resize, Balance, Focus Follows Mouse) are `.paneKeys`.
  `Command.menu` draws Move to Tab ▸; `CommandItems` draws commands in both places. Close Pane stays in File (⌘W).
- **The drag holds an app ratio** (`@State held` per split) until herdr's ratio changes, herdr refuses the write
  (`write` now returns whether it went through and shows its notice without waiting 4 s), or herdr already has the
  value. The drag uses the global coordinate space: the divider moves under the pointer.
- **Ids and values:** `divider.<tab>.<path>` (`root`, else 0/1 digits), value "33%"; a card's value is
  "content 70%" (its terminal opacity with the watching dim). Both carry the static-text trait: as phase 10 found,
  a plain SwiftUI element shows XCUITest no value. `pane.<id>.rename` is the rename field.
- **Fade** is `alphaValue` on the terminal's host view (phase 16 learned SwiftUI's `opacity` moves the terminal's
  accessibility frame), computed in `PaneCard` from `@AppStorage("fadeInactivePanes")`, `appearsActive` and the
  color scheme.
- **Focus follows mouse** is a `.task(id:)` on the card's hover in a key window: every 0.15 s while the pointer
  rests on a card that is not the keyboard card, it moves the keyboard once no mouse button is down and no `NSText`
  is first responder (palette, rename, filters). Checking only once missed a rename or a drag that ended under the
  pointer (E2E review). Never for a card under a zoom (hidden sides also take no hits now).
- **A zoom ends when its card is alone** in its tab (moved, or its neighbor closed), in `settle`.
- **A divider change waits for a write in flight** instead of being refused as busy (a double-click soon after a
  drag, quick VoiceOver steps); only the latest waiting change is sent, and the held ratio stays until its snapshot.
- **A zoomed card that leaves its tab is no longer zoomed**: the page keeps the zoomed card's tab (`zoomedTabID`) and
  `settle` drops the zoom when the card is in another tab or alone, whoever moved it. Focus Follows Mouse acts only
  on cards of the selected tab (a palette pick to another tab left the old card hovered).
- **A drag's release computes its ratio from the gesture**, not the held value: a snapshot during the drag can drop
  it.
- **Rename** ends on Enter or Esc with the keyboard back on the card; a click elsewhere only closes the field.
- **Files:** `PaneCard` moved to `Oriel/Views/PaneCard.swift` and the pane writes to `Oriel/Store/PaneWrites.swift`
  (SwiftLint's file length).
