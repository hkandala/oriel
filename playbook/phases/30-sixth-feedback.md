# Phase 30: The user's sixth round of feedback

Goal: the items of two Scrawl captures taken on a remote machine with many workspaces and tabs in two
windows: the session swipe, the overview, memory and CPU, Connect progress, three-finger swipes, tab drops
on New Workspace, quick splits and the Agents button's panel.

## Items

- **Lane W (1).** On a session swipe in a big session, the strip and tab bar changed 0.4–0.8 s after the
  sidebar; change them together.
- **Lane V (2–5, 12).** 2: a loader in tiles that show nothing yet. 3: tiles blurred, then sharpened when
  they turned live. 4: the sidebar and tab bar popped in late after the zoom. 5: the overview still dropped
  frames. 12: a card in the strip never shows a picture smaller than its own pixels.
- **Lane P (6, 11).** 6: measure the user's running app (read only), reproduce with `scripts/stress.py`,
  fix what costs too much; explain the 15.4 GB peak seen earlier. 11: drop Move Pane to Tab's tab list from
  the menu bar.
- **Lane R (7).** Connect shows a loader from the click until the session opens.
- **Lane G (8).** Three-finger swipes between sessions and workspaces; ⌥ + swipe as the main way.
- **Lane D (9).** A tab dropped on New Workspace moves into a new workspace.
- **Lane Q (10).** Quick ⌘D presses rearranged the panes with an odd double motion.
- **Lane N (13).** The Agents button's panel also lists finished agents.

## Findings

### Lane D (item 9)

- **Fix.** `HostStore.move(tab:to:)` takes a nil workspace for a new one (`pane.move {new_workspace}` for the
  first pane, the rest as before). The workspace menu's New Workspace and Open Session rows stay pinned under
  the list, since by macOS 27's rule a row not built when the drag starts takes no drop.

### Lane G (item 8)

- **Cause.** macOS sends no scroll event for three fingers, `swipe(with:)` needs "swipe between pages" on three
  fingers, and gesture recognizers never see the trackpad. The raw touches (`NSTouch`) work once a view takes
  indirect touches, when the system's three-finger gestures are on four fingers or off.
- **Fix.** `ThreeFingers` (pure, tested by a check script) turns touches into one step per gesture; the
  window's frame view takes the touches (SwiftUI's hosting view handles its own). ⌥ + swipe was built, then
  dropped in phase 31.

### Lane R (item 7)

- **Cause.** Connect changed nothing the page reads until the first snapshot.
- **Fix.** `connect` sets `.connecting` and drops the client's errors while it runs; ssh's question replaces
  the loader while it is up.

### Lane P (items 6, 11)

- **Cause.** The 15.4 GB peak was the overview leak fixed in phase 28 (a full-size copy for every
  overview-only terminal). In the user's app now: about 0.75–1 GB, mostly the 16 kept terminals' pictures by
  design, and the overview's live tiles at full-window size each.
- **Fix, item 11.** The menu bar's list leaves Move Pane to Tab's tabs out, and the Window menu reads only the
  first nine titles, so a tab title change no longer rebuilds the menu bar: keys about 30 ms faster at 300
  tabs.

### Lane V (items 2–5, 12)

- **Cause, item 2.** Past the live cap the latest tiles in took every turn, so other tiles in view never drew.
  Now tiles with no picture go first, a drawn tile lets go if another waits, and a tile with no picture shows
  a spinner.
- **Cause, item 3.** Snapshots were at most 360 px wide; now they are taken at the tile's pixel size, capped at
  100 MB.
- **Cause, item 4.** The zoom's end built the sidebar, title row and strip in one turn. The sidebar and title
  row now stay laid out under the overview, hidden, and fade in with the zoom.
- **Cause, item 5.** Every snapshot re-chose the live tiles mid-scroll (surfaces freed and made on the main
  thread); hover hit tests over the tiles ran each frame. Now nothing turns live or lets go until the scroll
  ends, tiles take no hit tests while scrolling, and live tiles are capped at about 400 MB.
- **Cause, item 12.** An overview-only terminal's small snapshot became its still in the strip, stretched.
  Out of a miniature, a still narrower than the view's pixels is dropped.

### Lane N (item 13)

- **Decisions.** Two groups, Needs you then Done, with the Agents view's labels; the amber dot and the Dock
  badge still count only needs you.

### Lane Q (item 10)

- **Cause.** After quick ⌘D presses one snapshot replaced several stand-ins at once, and herdr's panes became
  new cards that slid in a second time while the stand-ins faded.
- **Fix.** herdr's new panes take the gone stand-ins' cards in tree order, so each pane comes once, where it
  ends up; a closing card's header keeps its pane.

### Lane W (item 1)

- **Cause.** Each card's VoiceOver actions listed one action per tab of the session, and SwiftUI builds them
  with the view whenever any accessibility client runs (the user runs several).
- **Fix.** The actions keep New Tab and New Workspace only; the card's menu lists every tab. A swipe into 300
  tabs went from about 1 s to 0.3–0.4 s on CI.
- **Decisions.** The remaining 0.1–0.2 s (SwiftUI building the new page) stays: changing all three in one
  frame needs every page kept built or a nested hosting view, neither worth the risk.
