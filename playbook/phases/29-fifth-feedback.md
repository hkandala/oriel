# Phase 29: The user's fifth round of feedback

Goal: tab drags to another workspace, remote host editing and contrast, the overview at scale, menus that
follow the pointer, quick splits and keys, the whole UI at hundreds of tabs, selection colors, and a
flicker when a tab is shown.

## Items

- **Lane D (1).** Drag a tab onto a workspace row (or the collapsed sidebar's workspace menu) to move it
  there with its panes and layout.
- **Lane R (2, 3, more).** 2: Add Remote Host in the glass look, readable. 3: edit a remote host's name,
  target and icon, or remove it; a searchable SF Symbols grid. Also: Open Session in a remote window lists
  that machine's sessions; picking a machine with an open window brings it forward; ⌘N opens at 90 % of the
  screen; no glyphs in the dialog titles.
- **Lane V (4–6).** 4: the overview lagged while scrolling at scale: bounded live tiles and cached snapshots.
  5: a flicker after zooming into a tab (moved to lane T). 6: a 0.18 s zoom and a fade-in on open.
- **Lane M (7, 8).** 7: list highlights lag behind the pointer. 8: Open Session flickers as it loads.
- **Lane K (9–12).** 9: quick ⌘D gives the keyboard to the newest pane. 10: ⌥⌘ arrows pick from the layout
  at once, as Ghostty. 11: Move Tab on ⇧⌘← ⇧⌘→. 12: holding ⌘ shows the workspace keycaps too.
- **Lane T (13).** A tab flickers whenever it becomes shown (swipes, keys, the overview's zoom); all pane
  fade-ins twice as fast.
- **Lane S (14).** The UI stays snappy with 30 workspaces, 300 tabs and hundreds of panes printing: a
  stress harness, measurements before and after, fixes for what scales badly.
- **Lane C (15, 16).** 15: selected terminal text was unreadable. 16: letter icons take the same box as
  logos, so names line up.
- **Lane F (more).** The placeholder gets Show Window and Bring Back Here; in a floating window ⌘W detaches.

## Findings

### Lane M (items 7, 8)

- **Cause, item 7.** `ChromeStyle` animated the whole button on hover, so the lit row's pill faded out and in
  over 0.14 s; the palette also redrew all its rows on each new light.
- **Cause, item 8.** Open Session started from an empty list. It now shows the page store's last list at once
  and refreshes rows in place.

### Lane D (item 1)

- **Fix.** `HostStore.move(tab:to:)` moves the first pane to a new tab in the target workspace, then each
  other pane beside its split's other side with its ratio, rebuilding herdr's tree (`SplitNode.rebuild`,
  unit-tested).
- **Cause on the way.** macOS 27 finds no SwiftUI drop target added after a drag entered the window, so the
  collapsed sidebar's workspace menu is present (hidden) through every drag and opens on a 0.65 s hold.

### Lane R (items 2, 3, more)

- **Cause.** Secondary text and the palette's soft field capsule vanished on grey glass; nothing could change
  a machine after Add.
- **Fix.** Primary text and an outlined `dialogField()`; one `HostDialog` for Add and Edit; a remote window's
  Open Session groups say "Running on ‹machine›" (both machines ran the same session names).

### Lane F (more)

- **Fix.** Show Window and Bring Back Here on the placeholder; ⌘W detaches and ⇧⌘W closes in a floating
  window.

### Lane C (items 15, 16)

- **Cause, item 15.** libghostty-spm's default theme sets only a grey selection background, so Ghostty drew
  selected text in the window's background color (1.2:1).
- **Fix.** `selection-foreground = cell-foreground` and a blue background like macOS's (7.6:1 dark, 14.1:1
  light). Letter icons take the logos' square.

### Lane K (items 9–12)

- **Cause, item 9.** A split's stand-in has no terminal, so the first responder stayed on the old card and
  each quick ⌘D split it again; the history pruned the new terminal before a snapshot had it.
- **Fix.** `Page.newest` is the ⌘D target and is lit at once; only the newest split takes the keyboard.
- **Cause, item 10.** ⌥⌘ arrows asked herdr's `pane.neighbor` (a bridge run per key), which picks the pane
  at the middle of the edge. `SplitNode.neighbor` now picks from the tree: the pane used last, else the one
  sharing most of the edge.

### Lane S (item 14)

- **Causes** (profiles of a 400-pane session): the first snapshot asked `process_info` of every pane at once;
  snapshot reads ran back to back, and each 280 KB reply was split by an O(n²) scan; `apply` rebuilt a set
  per pane; every capsule and row scanned every pane; each card built Move Pane to Tab with 300 titles;
  `usedTerminals` edited in place made Observation redraw the window on every snapshot.
- **Fix.** Program asks through a `Gate` of 8; reads spaced 250 ms while events keep coming (never after the
  app's own write); the splitter scans only new bytes; per-tab state kept by the store; menus built when they
  open. Quiet CPU went from 117 % to about 10 %, ⌘1 from 17 s to about 130 ms.
- **Decisions.** A tab switch still costs about 90 ms of main thread (SwiftUI layout, picture copies and
  AppKit's key equivalent search); the one-frame target is not met. macOS allows 511 ptys in all, so CI's
  stress test asks 400 panes.

### Lane T (item 13, and lane V's item 5)

- **Cause.** A new strip's empty scroll position lays out page 0 for one commit before the retry scrolls to
  the selected tab.
- **Fix.** `.defaultScrollAnchor(start, for: .initialOffset)` puts the first layout on the selected page;
  `ScrollPosition(id:)` as the initial value was not honored. A `-recordFrames` probe checks every commit
  after a tab change. Pane fade-ins are 0.06 s.

### Lane V (items 4–6)

- Written with phase 28's lane V.
