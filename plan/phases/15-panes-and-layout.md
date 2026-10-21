# Phase 15: pane cards and layout

Goal: pane cards look and act like Rex's (header, buttons, fade, context menu), and the split layout
can be changed by hand: drag, double-click and keys on dividers, balance, focus and move panes with
keys.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (panes, dividers, zoom, fade,
pane actions), `resources/inspirations/rex-app/three-splits.jpg`, `zoomed-pane.jpg`,
`docs/content/docs/layout.mdx`, `docs/content/docs/ui/window.mdx` (pane card, zoom),
`docs/content/docs/talking-to-herdr.mdx` (writes table), decisions D10, D11, D13, D41, D42,
`Oriel/Views/Strip.swift` (`SplitLayout`, `PaneCard`), `Packages/HerdrKit/Sources/HerdrKit/SplitNode.swift`.

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
   (light) for the keyboard card. Settings ▸ Panes: **Fade inactive panes** (on) and **Fade panes in
   inactive windows** (on).
4. **Show pane headers** (Settings ▸ Panes, on). Off: no header; the card is all terminal; actions stay
   in the context menu, the menu bar and the palette.
5. **Context menu** on the header and on the card's edge (not inside the terminal, which keeps its own
   right-click): Split Right, Split Down, Split Left, Split Up, Zoom / Restore, Move to New Tab, Move
   to Tab ▸ (the workspace's other tabs), Move to New Workspace, Rename Pane…, Close Pane.
   - Split Left / Up: `pane.split` right / down, then `pane.swap` of the old and the new pane (herdr
     splits only right and down).
   - Move to New Tab: `pane.move {destination: {type: "new_tab", workspace_id}}`; to a tab:
     `{type: "tab", tab_id, split: "right"}`; new workspace: `{type: "new_workspace"}`.
   - Rename: an inline field in the header, `pane.rename {pane_id, label}`; an empty name clears the
     label. Labels that start with `oriel:` are the app's own (plugins, later) and are not offered.
   - All with `focus:false` where herdr takes it; read the snapshot after.

### Dividers

6. **Hit area.** Each split's 8 pt gap is the divider, with a 16 pt hit area centered on it and the
   resize cursor (`NSCursor.resizeLeftRight` / `resizeUpDown`). On hover a grip shows: a 36 × 3 pt
   capsule (gorex) in the hover token color, fade 0.2 s.
7. **Drag.** The split moves live in the view (an app-side ratio for that split until the next
   snapshot shows herdr's). On release: `layout.set_split_ratio {tab_id, path, ratio}`, ratio clamped
   to 0.1–0.9. The path comes from the split's place in the tree (`false` = first child). Terminals
   keep the existing 100 ms resize settle, so a drag does not flood herdr with PTY resizes.
8. **Double-click** a divider: ratio 0.5.
9. **Balance** (⌃⌘=, View ▸ Pane ▸ Balance Splits): each split gets "leaves on its first side ÷ all
   leaves under it"; one `set_split_ratio` per split.
10. **Keys.** ⌃⌘← → ↑ ↓: `pane.resize {pane_id, direction, amount: 0.05}` on the keyboard card.
11. **Accessibility.** Each divider is an adjustable element ("Divider between ‹a› and ‹b›", value =
    ratio as a percent; increment and decrement move it 5 % and send the ratio).
12. **Autobalance** (Settings ▸ Panes, off): after a split, balance the tab.

### Focus and move with keys (the app's own keyboard card, never herdr focus, D13)

13. ⌥⌘← → ↑ ↓: give the keyboard to the nearest card in that direction (card frames from the layout,
    nearest by the center's distance along the axis, overlap first).
14. ⌘[ and ⌘]: previous and next card in the tree's order, round the ends.
15. ⌥⇧⌘← → ↑ ↓: move the keyboard card: `pane.swap {pane_id, direction}`. The keyboard follows the
    pane.
16. **Focus follows mouse** (Settings ▸ Panes, off): a card under a resting pointer (0.15 s) gets the
    keyboard. Never while a mouse button is down or the palette or a menu is open.
17. **Split keys.** ⌘D Split Right, ⇧⌘D Split Down (View ▸ Pane). Split Left and Split Up have no
    shortcut: ⇧⌘← and ⇧⌘↑ (Rex's keys) would steal "select to line start" from the app's text fields.
18. **Layout motion.** When the tree changes (split, close, move, ratio from herdr), card frames
    animate 0.2 s ease-out. If terminal resizes during the motion flicker, keep each terminal surface at
    its old size, clipped by its card, until the motion ends, then resize once. Reduce Motion: no
    animation.

### Docs

19. Update `layout.mdx` (dividers, balance, keys, motion, fade), `ui/window.mdx` (pane card, zoom,
    context menu), the keyboard table, `talking-to-herdr.mdx` writes table (split left/up, rename,
    move to new tab, keyboard move), `ui/settings.mdx` (Panes tab), D42 (divider and fade rules).

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
