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
