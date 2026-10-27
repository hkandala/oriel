# Phase 28: The user's fourth round of feedback

Goal: the items of the user's first Scrawl capture: empty sessions, the session swipe, the overview, floating
windows, herdr popups through Oriel, and remote machines.

## Items

- **Lane E (1, 2).** 1: an empty session shows an icon and "This session is empty" in the strip, no button.
  2: the session swipe stuck, then jumped.
- **Lane V (3, 4).** 3: overview tiles faded in while scrolling. 4: in the overview the title row holds only
  the traffic lights and one ×; wider margins.
- **Lane F (5–7).** 5: a taller floating window; a clear hierarchy between the pane's info and its place. 6:
  the placeholder says the pane floats and has a Show Pane button. 7: `oriel://float?session=…&pane=…`
  floats any pane; pi-herd uses it when the click came through Oriel.
- **Lane R (8–11).** 8: a remote machine opens in a new window. 9: never show the server's login banner in
  errors; no company names anywhere. 10: ssh's questions in a glass dialog. 11: every answer is a hidden
  field except the host-key yes/no.

## Findings

### Lane R (items 8–11)

- **Cause.** The machine menu replaced the window's pages; the master's stderr (with the banner at
  LogLevel INFO) was shown whole; only prompts naming "password", "passphrase" or "PIN" got a hidden field.
- **Fix.** `WindowPages.open(machine:)` hands the machine to a new window; the master runs with
  `LogLevel=ERROR`; ssh's questions and Add Remote Host share one glass `dialog()` overlay; every answer is a
  `SecureField`. The plans and the program icon catalog no longer name the user's company.

### Lane V (items 3, 4)

- **Cause, item 3.** Tiles sat in lazy stacks and only laid-out tiles streamed, so a tile scrolled into view
  made a surface, waited for herdr and faded in.
- **Decisions.** "Every card live" made the user's stress test (hundreds of agents) laggy, so the rule is
  bounded live tiles (16, 6 on a remote machine) plus IOSurface snapshots of every terminal that stops
  drawing; a tile turning live keeps its snapshot over the new surface until it drew. Footprint is bounded by
  the cap, not the tab count.
- **Causes on the way.** Repeated row ids across workspaces hid later rows; a `CGImage` snapshot was copied
  again by Core Animation; a full picture copy for every overview-only terminal on the main thread.

### Lane F (items 5–7)

- **Decisions.** A floating window opens at 75 % of the main window's height; a thin divider and quieter text
  separate the place. A session with no page gets a float-only page (no sidebar row, no strip page, not
  saved) that goes with its last float. pi-herd floats through Oriel when Oriel is the frontmost app
  (macOS only, never over SSH).

### Lane E (items 1, 2)

- **Cause, item 2** (from the recording, 60 fps). A quick flick moved the pages 45 pt, then they stood still
  for 0.65 s: the slide asked of SwiftUI's scroll view did not run, and a 0.6 s fallback snapped back and
  showed the wrong session. CI's slow VM never reproduced it.
- **Fix.** The session pages are no longer a scroll view: an `HStack` offset by the app's own `Swipe`, which
  the scroll monitor drives with every move and the lift; the session shows at `.logicallyComplete`.
- **Decisions.** At rest only the page in view is laid out (a laid-out page past the clip widened the
  accessibility frame); a swipe mid-slide starts from the drawn offset.
