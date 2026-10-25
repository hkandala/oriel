# Phase 28: The user's fourth round of feedback

The user recorded a 5-minute Scrawl capture on 2026-10-25 (16:26): voice, clicks and red marks over Oriel.
Bundle: `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1792970538277-6f5d.scrawl`.
Read it with the scrawl skill (`/Users/hkandala/.agents/skills/scrawl/SKILL.md`): `summary.md`,
`contact-sheet.png`, `frames/frame-NN.png`, and `scrawl zoom "<bundle>" --at M:SS --span S --frames N`
for motion. Speech recognition mishears words ("Oreo"/"ovary" = overview, "pain" = pane, "herder" = herdr).
Moments are named like "#3 (1:08)". Each lane writes `## Findings` at the end.

The user may be testing on this Mac: `/tmp/oriel-gui.lock` is held for "user"; UI tests run on CI until
the orchestrator says otherwise.

## Lane E: empty session and session swipe (items 1, 2)

1. **Empty session** (#1 0:07): a session with no workspace shows a "+ New Workspace" button in the
   middle of the window (and one in the sidebar). The user wants no button in the middle: an icon and a
   short line that says the session is empty (the user asked for this text; it overrides the no-hint
   rule here). The sidebar's + stays.
2. **Session swipe lags** (#2 0:30, then the swipes at about 0:33–0:46): "this used to be smooth before;
   now it gets stuck". Phase 27 lane T3 rewrote the swipe (its Findings). Look at the recording frame by
   frame (`scrawl zoom … --at 0:33 --span 14 --frames 40`), find what stalls (the sidebar page and the
   strip move out of step in some frames), and make it smooth again: the page follows the fingers, then
   finishes without a stop or a jump. Check with local Retina recordings when the GUI is free.

## Lane V: overview (items 3, 4)

3. **No fade while scrolling the overview** (#3 1:08, #4 1:32): tiles of tabs not opened before fade in
   as they scroll into view. While the overview is open, keep every tile's terminal of every session in
   the overview alive and drawn (not only the laid-out ones), so scrolling never shows a fade. The user
   accepts the memory while the overview is open; on leaving, the overview-only terminals go as now
   (phase 27 lanes A3 and V).
4. **Overview chrome** (#5 2:08): remove every title-row item in the overview (machine button, Agents,
   the overview button, ⌘ palette); keep only the traffic lights and one × button that leaves the
   overview. More room on the left and right, like the user's reference (`overview.png`, phase 27): the
   grid sits centered with wide side margins.

## Lane F: floating window and placeholder (items 5, 6)

5. **Floating window** (#7 2:54): open a bit taller by default. In the title row, the pane's name and its
   place ("hkandala-mbp › oriel › oriel") run together; give them a clear hierarchy, for example a thin
   vertical separator between the pane's info and the place, with the place in quieter text.
6. **Placeholder in the tab** (#8 3:20): today it shows only the pane's info line in an empty card, which
   reads as nothing. Show that the pane is open in a floating window: a short line saying so, and a
   button ("Show Pane") that brings the floating window forward (the user asked for this text).

## Lane R: remote hosts (items 8, 9, 10, 11)

8. **A remote machine opens in a new window** (#10 4:18): Add Remote Host and picking a machine in the
   machine menu open a new window for that machine; the current window and its sessions stay.
9. **No server banner in errors** (#11 4:29): the Disconnected page showed the server's login banner
   ("… authorized users only …") above ssh's error. Show only ssh's own error line(s), never the banner
   (ssh's `-q` or `LogLevel=ERROR` on the master, or drop banner lines). Nothing in the repo may name a
   company or its servers: make docs and plans generic ("a server with one-time passcodes").
10. **ssh's question sheet** (#12 4:54): make it fit the app (glass, the palette's look, the app's
    typography) instead of a plain macOS sheet.
11. **Secret answers are hidden:** in #12 the one-time passcode showed as plain text, because only
    "password", "passphrase" and "PIN" prompts got a hidden field. Every answer is hidden except the yes/no
    host-key question.

## Waiting on the user

7. **herdr's own popups** (#9 3:46): the user wants them to open Oriel's floating window. Phase 27 lane F3
   found herdr 0.9.5 gives no popup terminal id, no event and no close by id. Options were put to the user.

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each
  lane's last code commit; one review round per lane (spec and ponytail, read only).

## Findings
