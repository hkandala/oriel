# Phase 25: The user's second round of feedback

Goal: the items the user sent after phase 24, in three waves of lanes: looks, keys, the Agents view,
closing and sessions, snappiness, pane motion, floating panes, an empty-strip bug, memory and CPU.

## Items

### Wave 1

- **Lane H (1, 10, 11).** 1: in Glass the keyboard card and the others looked too different; bring them
  close. 10: remove Fade Inactive Panes entirely. 11: "Increase / Decrease / Reset Font Size" (Ghostty's
  words).
- **Lane I (2, 7).** 2: the ⌘-held keycaps sat on the tab's icon; show them at the capsule's end. 7: one
  key pattern per level (new, previous / next, jump 1–9) and a Keyboard Shortcuts panel on ⌘/.
- **Lane J (4).** Agents view: workspace order groups rows under workspace headers; a row's title is the
  pane's name, else the agent's; the header is the session name; the keyboard card's agent is lit.
- **Lane K (5, 6, 8, 9).** 5: closes ask only when a program besides the shell runs. 6: Reset Pane Name.
  8: "session", never "page" in the UI; a new session goes last. 9: Stop and Delete in Open Session.
- **Lane L (15).** ⌃⇧ keys of the user's pi extensions did not reach pi.

### Wave 2

- **Lane S (13, 14).** 13: a new tab shows "New Tab", never herdr's number. 14: ⌘T, ⌘W, ⌘K and the rest
  react at once (measure first); the session swipe twice as quick.
- **Lane A2 (3).** Split, close and zoom animate; the other cards must move, not jump.
- **Lane F2 (16).** Float a pane in its own window (Detach, Close, Stay on Top), a placeholder in the tab,
  saved and restored with the windows.

### Wave 3

- **Lane I2 (17, 21–24, 31).** 17: a roomier shortcuts panel with a keycap per key. 21: a split gives the
  new pane the keyboard; ⌘[ ⌘] step in tree order. 22: ⇧⌘↩ did not zoom. 23: one key pattern for every
  level (T new, W close, `[` `]` step, 1–9 jump; ⌘ pane or tab, ⇧⌘ tab, ⌃⌘ workspace, ⌥⌘ session). 24:
  working dots on the selected tab too. 31: Move Pane to Tab lists every tab of the session, by workspace.
- **Lane P (18–20, 26).** 18: a clear hierarchy in the Agents view header. 19: Detach in Open Session; red
  Stop and Delete. 20: no hover panel when nobody needs you. 26: the hover card was see-through in Glass.
- **Lane B2 (25).** The strip was empty in a one-tab workspace.
- **Lane T (27, 28).** 27: a preview of the tab in its hover card. 28: a Rex-like light rim on the cards.
- **Lane O (30).** Oriel used 1.2 GB and 17–32 % CPU on the user's Mac: bound the surfaces, pause hidden
  terminals, cut SwiftUI work; one herdr helper per session if it has no cons.

## Findings

### Lane L (item 15)

- **Cause.** `PaneSurfaceView.herdrKey` dropped Shift from Ctrl chords, so ⌃⇧S went to herdr as `ctrl+s`.
- **Fix.** The chord keeps `shift+`; herdr encodes it for each program, as its own TUI does.

### Lane J (item 4)

- **Cause.** The list grouped only by priority, a row's title read only the agent's name, and no row was
  ever lit (`AgentButton` had no selected state).
- **Decisions.** Workspace groups reuse the priority labels' view; the lit row follows the keyboard card,
  as the lit card does; the filter matches pane names too.

### Lane H (items 1, 10, 11)

- **Cause, item 1.** The other cards were faded (0.7) and their Glass fill was a step darker than the window,
  while the keyboard card was a step brighter.
- **Fix.** No fade (item 10, D64); Glass cards a step brighter than the window, the keyboard card only a
  little more. Classic unchanged. A palette tie now goes to a title that starts with the filter.

### Lane I (items 2, 7)

- **Fix.** The keycap sits in the capsule's status slot; the new workspace and session keys live in the one
  command list, and the shortcuts panel is built from it, so it never goes stale.

### Lane K (items 5, 6, 8, 9)

- **Cause, item 5.** Tab and workspace closes set `closing` at once. Now every close reads
  `pane.process_info` and asks only when a program besides the shell runs.
- **Fix.** Reset Pane Name sends `pane.rename` with `label: null`; new sessions append; Stop and Delete use
  `herdr --session S session stop|delete S`, and both ask first.

### Lane I2 (items 17, 21–24, 31)

- **Cause, item 22.** SwiftUI `Commands` do not observe `@Observable` state, so the menu bar kept Zoom Pane
  disabled from when the tab had one card, and AppKit swallowed ⇧⌘↩.
- **Fix.** `menuBar(_:)` puts what the menu shows in the focused value, and `CommandList` is `Equatable` on it,
  so the menu bar rebuilds when it changes. A split gives herdr's new pane the keyboard once a snapshot
  shows it.
- **Decisions.** The key table of item 23 as written; holding ⌃⌘ shows keycaps on the first nine workspace
  rows.

### Lane F2 (item 16)

- **Cause.** herdr 0.9.5 has no floating pane its API shows, so floating is Oriel's own (D50).
- **Decisions.** A `WindowGroup` per floated terminal, restored by the main window after its pages (SwiftUI's
  own restore came first); the window shares its main window's page and streams; the pane stays in its tab.

### Lane S (items 13, 14, and lane K's leftovers)

- **Measured first.** `-recordLatency` records the time from a key to the commit that drew its change. ⌘T,
  ⌘D and the closes took 17–39 run-loop turns while 2–5 herdr runs went by; the palette built ~100 rows.
- **Fix.** `Ahead` shows a new tab, split or close in the key's turn and lets the snapshots confirm it; the
  palette's rows are lazy; the session swipe slides from the lift. A new tab shows "New Tab" while its shell
  starts.
- **Decisions.** A close hides at once only when every pane's last answer is its shell; writes queue instead
  of failing; `process_info` asks run 8 at a time.

### Lane A2 (item 3)

- **Cause.** `SplitLayout` nested one view per split, so a pane whose leaf changed became a new view: it
  jumped to its size and its terminal moved to a new host.
- **Fix.** The cards are one flat `ForEach` by pane id, placed by the tree; every change moves the same views.
  CI's Mac has Reduce Motion on, so motion tests launch with `-forceMotion YES`.
- **Decisions.** A closed card fades (a scale left its terminal at full size).

### Lane O (item 30)

- **Cause.** Each terminal kept three full-size Metal surfaces (17 MB each at full window on Retina) for good;
  the working dots were a `TimelineView` that laid out the whole window 15 times a second; hidden terminals
  kept drawing (libghostty marks a view visible when it leaves its window).
- **Fix.** Core Animation runs the dots; only shown terminals draw; a few recent ones keep their surface and
  the rest free it, keeping a purgeable still. 1.2 GB / 17–32 % became about 200 MB / 3–6 % on the same
  scenario.
- **Decisions.** One herdr helper per terminal stays: `terminal session` takes one target and herdr ties a
  connection to one terminal.

### Lane B2 (item 25)

- **Cause.** One `Strip` served every workspace; after it drew again on a middle tab, a switch to a workspace
  with fewer tabs laid out no page.
- **Fix.** A strip per workspace (`.id`). Any accessibility client hides the bug, so `make strip-check`
  drives the app with key events and reads window captures; the UI test cannot fail on the old code.

### Lane P (items 18–20, 26)

- **Cause, item 26.** Liquid Glass is thin on a small panel. Every floating panel now puts the glass over
  `.regularMaterial` (`floatingGlass`).
- **Fix.** A title and section-label hierarchy in the Agents view; the hover panel never opens empty.

### Lane T (items 27, 28)

- **Decisions.** The preview reuses what exists: a drawing card's IOSurface as a layer's contents, the
  others' screen text from `pane.read`, refreshed only while the card is open. The rim is measured from
  Rex's screenshot: a thin rim and a top highlight, the same on every card. (The preview was later replaced
  by the overview, phase 27.)
