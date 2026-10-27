# Phase 24: Fixes from the user's first hands-on use

Goal: the issues the user found running the app for the first time, in two rounds of lanes.

## Items

- **Lane A (1, 2).** 1: panes sometimes stayed empty after the hide-then-fade used against the first-frame
  flicker. 2: text reflowed badly while a card was resized; keep the grid, then send the size once settled.
- **Lane B (4–7).** 4: a new tab showed a wrong icon (GitHub) before zsh's. 5: tabs keep their width and the
  row scrolls. 6: a soft fade where tabs are cut off. 7: a click selects a tab with no scroll or snap.
- **Lane C (8, 9).** 8: right click in a terminal did nothing; match herdr. 9: dropping files or an image on a
  terminal pastes their quoted paths.
- **Lane D (3, 10–12).** 3: the traffic lights flickered on workspace switches. 10: align the Agents list
  rows and header. 11: "All caught up". 12: with the sidebar collapsed, menu highlights follow the pointer.

### Round 2

- **Lane E (14, 16–18).** 14: still a slide on a click, + and ⌘T; only a scroll gesture animates. 16:
  closing a tab selects the tab used before it. 17: drag auto-scroll in the tab row. 18: Close Tabs to the
  Right.
- **Lane F (19).** After a resize the text faded out and back in; never blank.
- **Lane G (13, 15).** 13: one leading edge for the Agents view header, labels and rows. 15: the empty
  needs-you panel shows only "All caught up".

## Findings

### Lane A (items 1, 2)

- **Cause, item 1** (read, not reproduced). The hide went through SwiftUI and showed the content only when
  SwiftUI updated the very host that held the terminal; a host made or moved mid-way could keep alpha 0.
- **Fix.** The terminal hides and shows its own view, with a guaranteed reveal at most 0.4 s after a grid
  change. While a card's size changes, the host keeps the terminal's frame (clipped, top left) and fits it
  150 ms after the last change.

### Lane B (items 4–7)

- **Cause, item 4.** A new tab's card asked `pane.process_info` at once and got a shell startup program
  (`gh`), so the GitHub icon showed until the next ask.
- **Fix.** `Pane.starting` blocks every ask in a new pane's first second, then waits while a program other
  than the shell runs. Tabs are a fixed 220 pt; fades only on a side with tabs out of view; a click selects
  without scrolling.

### Lane C (items 8, 9)

- **Cause.** Right clicks went to herdr and libghostty, and neither showed a menu in a shell; the terminal
  view registered no drag types.
- **Decisions.** A context menu (Copy, Paste, Select All, the pane commands); ⌥-right click sends the click
  to a program that reads the mouse, as herdr's `right_click_passthrough_modifier = "alt"`. Drops paste
  shell-escaped paths as Ghostty does, as a bracketed paste; images go to a temp file first.

### Lane D (items 3, 10–12)

- **Cause, item 3.** Each title change makes AppKit re-tile the title bar and move the buttons back; the
  correction for the zoom button came a frame late.
- **Fix.** `WindowReader` places the buttons in its own `layout()`, after AppKit's tiling and before the frame
  draws. Agents rows: name, status and age on line 1, the place on line 2. `FilterList` lights the row under a
  moving pointer.
- **Decisions.** The default window is at most the screen, and a zoom fills it (CI's small screen pushed the
  zoom button off screen).

### Lane G (items 13, 15)

- **Cause.** The header kept the workspaces view's insets; the empty panel drew its header above both
  branches.

### Lane F (item 19)

- **Cause.** Lane A hid each grid change with alpha 0, so the text went blank for about 0.25 s.
- **Fix.** Pause libghostty's drawing while herdr's frames settle, so the layer keeps its last picture, then
  switch at once. The pause runs before libghostty hears of a change (font size, frame), or the old cells drew
  with the new font.

### Lane E (items 14, 16–18)

- **Cause, item 14.** The strip scrolled with an animation on every selection change in the same workspace.
- **Cause, item 16.** A closed tab gave way to herdr's active tab, usually the first.
- **Fix.** Every selection change scrolls without animation; `Page` keeps each workspace's tab history. The
  tab row's own drop auto-scroll already worked, so no custom scroll was added.
