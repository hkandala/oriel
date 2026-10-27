# Phase 27: The user's third round of feedback

Goal: the items the user sent after trying phases 24–26: instant tab returns, the Agents sidebar, quick
closes and pane motion, floating panes, and the overview that replaces the tab preview.

## Items

- **Lane A3 (1).** Going back to a visited tab shows at once: keep visited terminals' surfaces and streams,
  drawing paused, as Ghostty does; free only past a measured budget.
- **Lane G3 (2–5).** 2: the sort control reads "Workspace" and "Priority" and looks like a button. 3: the
  `default` session shows the machine's name in the sidebar header. 4: the header is the rows' size, bold.
  5: groups fold, kept per session and order.
- **Lane T3 (6–9).** 6: quick ⌘T then quick ⌘W steps back one tab each, also through stand-ins. 7: closing
  a pane gives the keyboard to the pane used before it. 8: pane motion a third shorter. 9: the session
  swipe calm and quick, tracking the fingers.
- **Lane F3 (10–14).** 10: a floating window opens at about 60 % of the main window. 11: the placeholder
  shows the pane's info and is one button. 12: a taller title row, as the main window's. 13: the same
  buttons as the title row. 14: open herdr's plugin popups in a floating window.
- **Lane V (15, 16).** 15: drop the tab preview from the hover card. 16: the overview: every tab as a live
  miniature, grouped by workspace, sideways through sessions, a click zooms into the tab.

## Findings

### Lane G3 (items 2–5)

- **Decisions.** `default` shows the device's name (the Mac's own name, or the remote machine's), in the
  sidebar header, the window title and the collapsed title row; Open Session and the palette keep herdr's
  names. Folds live in one `@AppStorage` string, per machine, session and order.

### Lane V (items 15, 16)

- **Fix.** The hover card is back to its pre-preview self.
- **Decisions.** Each tile hosts the card's own terminal view, scaled by AppKit, so grid, pixels and herdr's
  PTY keep the card's size; no surface or stream of its own (D70). ⌃⌘O, a title-row button, Esc to leave.
- **Cause on the way.** Esc never reached the overview: the terminal moved into a miniature kept the first
  responder. A terminal now refuses the keyboard inside a miniature. Tab ids repeat across sessions, so tiles
  are keyed by page.

### Lane F3 (items 10–14)

- **Cause, item 14.** herdr 0.9.5 gives Oriel nothing to open: a popup has no pane or terminal id in the API
  and sends no event (probed on a throwaway server). Not built; the upstream ask is in Future work.
- **Fix.** `FloatReader` sizes a new window over its main window; the traffic-light placement moved into a
  `TrafficLights` base class both windows use; one `PaneInfo` view serves the title row and the placeholder.

### Lane A3 (item 1)

- **Cause.** Only 4 hidden terminals kept their surface, and their "still" was empty: libghostty frees a
  hidden surface's swap chain and marks its IOSurfaces purgeable-empty, and the system took volatile stills
  back within seconds.
- **Fix.** 16 visited terminals keep stream and surface, drawing paused; a card leaving view copies its last
  frame into a still that shows until the surface draws again.
- **Decisions.** A count, not a byte budget: the picture is the one size-dependent part (16 full-window ones
  measured about 650 MB on Retina).

### Lane T3 (items 6–9)

- **Cause, item 6.** The tab history lost each stand-in when herdr's tab took its place; a starting pane's
  close waited for herdr and a second ⌘W was dropped; ⌘W on a stand-in closed a pane of the tab before.
- **Fix.** `Ahead.arrived` maps every stand-in to herdr's tab and every page follows it in the same turn; a
  starting pane in a fresh tab hides at once; `keyboardPane` takes only the shown tab's terminal.
- **Cause, item 9.** Showing the session at the lift held the main thread for its first draw, and a
  `scrollTo` during the system's paging snap waited for it: a stall, then a jump.
- **Fix.** The scroll monitor takes the lift and momentum, and the sidebar slides with a 0.2 s critically
  damped spring from the fingers' speed; the session shows when the pages arrive. Pane motion is 0.13 s.
