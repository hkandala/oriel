# Phase 17: pane cards and layout

Goal: pane cards look and act like Rex's (header, buttons, fade, context menu), and the split layout
can be changed by hand: drag, double-click and keys on dividers, balance, focus and move panes with
keys.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md` (drag and drop table: what herdr allows),
`resources/research/clients/rex-ui.md` (panes, dividers, zoom, fade, pane actions),
`resources/inspirations/rex-app/three-splits.jpg`, `zoomed-pane.jpg`, `docs/content/docs/layout.mdx`,
`docs/content/docs/ui/window.mdx` (pane card, zoom), `docs/content/docs/talking-to-herdr.mdx` (writes
table), decisions D10, D11, D13, D41, D42, D64, `Oriel/Views/Strip.swift` (`SplitLayout`, `PaneCard`),
`Packages/HerdrKit/Sources/HerdrKit/SplitNode.swift`.

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
   (light) for the keyboard card. One setting, **Fade inactive panes** (on), turns both fades off. This
   phase adds the Settings ▸ Panes tab with it and Focus follows mouse (step 14). The watching window's
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
8. **Balance** (⌃⌘=, View ▸ Pane ▸ Balance Splits): each split gets "leaves on its first side ÷ all
   leaves under it"; one `set_split_ratio` per split.
9. **Keys.** ⌃⌘← → ↑ ↓: `pane.resize {pane_id, direction, amount: 0.05}` on the keyboard card.
10. **Accessibility.** Each divider is an adjustable element ("Divider between ‹a› and ‹b›", value =
    ratio as a percent; increment and decrement move it 5 % and send the ratio).

### Focus and move with keys (the app's own keyboard card, never herdr focus, D13)

11. ⌥⌘← → ↑ ↓: give the keyboard to the nearest card in that direction (card frames from the layout,
    nearest by the center's distance along the axis, overlap first). herdr's read-only
    `pane.neighbor {pane_id, direction}` could answer this instead. Use one of the two, not both, and
    record which.
12. ⌘[ and ⌘]: previous and next card in the tree's order, round the ends.
13. ⌥⇧⌘← → ↑ ↓: move the keyboard card: `pane.swap {pane_id, direction}`. The keyboard follows the
    pane.
14. **Focus follows mouse** (Settings ▸ Panes, off): a card under a resting pointer (0.15 s) gets the
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
    move to new tab, keyboard move), `ui/settings.mdx` (Panes tab), D42 (dividers), D64 (fade).

## e2e

- Drag a divider: herdr's split ratio changes (snapshot) to the dropped value ± 0.02.
- Double-click a divider: ratio 0.5. ⌃⌘=: three panes in a row get 1/3 each.
- ⌥⌘→ moves the keyboard to the right card (`hasKeyboard`); ⌥⇧⌘→ swaps the panes in herdr.
- Context menu: Move to New Tab makes a tab with that pane; Rename Pane sets herdr's label; Split Left
  puts the new pane on the left.
- Zoom is disabled in a one-pane tab; a zoomed card shows only Restore and Close.
- The fade: a card without the keyboard reports a lower content opacity (expose it as part of the
  card's accessibility value, for example "faded").

## Done when

- Screenshots: a three-pane tab with the grip showing, a context menu, a zoomed card, faded and
  unfaded cards in a key and a non-key window.

## Findings
