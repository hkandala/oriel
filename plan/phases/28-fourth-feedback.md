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
   overview. More room on all four sides (the user asked again: top, bottom, left and right), like the
   user's reference (`overview.png`, phase 27): the grid sits centered with wide margins.

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

## Lane F, also: herdr popups through Oriel (item 7, #9 3:46)

7. herdr 0.9.5 tells API clients nothing about plugin popups (phase 27 lane F3), so the user chose
   option 1: an `oriel://` URL that any tool can open to float a pane, and pi-herd uses it when the click
   came through Oriel.
   - **Oriel:** register the `oriel` URL scheme; `oriel://float?session=<herdr session>&pane=<pane id>`
     (optional `machine=`) opens that pane in Oriel's floating window over the frontmost main window, even
     when that session is not open as a page in any window (load it for the float without adding a page).
     Opening it again for the same pane brings the window forward. Unknown session or pane: a notice, no
     window.
   - **How pi-herd knows:** the click reached pi through Oriel exactly when Oriel is the frontmost app
     (another client would be frontmost otherwise). pi-herd checks the frontmost app on macOS only
     (`lsappinfo front` then its bundle id, a few ms, at click time only); when it is Oriel
     (`dev.hkandala.oriel`) it runs `open -g "oriel://float?…"` for the agent's pane in the pi-herd
     session, else it opens herdr's popup as today. On Linux or over SSH it always uses herdr's popup.
   - **pi-herd** is in the user's repo `/Users/hkandala/code/pi-hkandala/extensions/pi-herd` (the popup
     code is in `herdr.ts` `popupCommand` and `index.ts` around "Views an agent"). The user allowed this
     change. Follow that repo's own AGENTS.md and commit rules; keep the change small.
   - An issue or PR to herdr upstream is not part of this.

## Checks

- `make lint build test`; a UI test for each item a test can see; the full CI suite green on each
  lane's last code commit; one review round per lane (spec and ponytail, read only).

## Findings

### Lane R (items 8–11)

- **Root causes.**
  - 8: the machine menu and Add called `WindowPages.show(machine:)`, which left every page of the window and
    opened the machine's `default` in it. Now both call `WindowPages.open(machine:connect:)`: a static hand-off
    (`opening`) that the new window's restore takes; Add also connects there, so ssh asks in the new window.
    The current machine does nothing; the ⌥-click path is gone. ⌘N now keeps the window's machine, as
    window.mdx already said (it always opened This Mac).
  - 9: the master's start output (stderr merged) was shown whole on Disconnected, and OpenSSH prints the
    server's login banner there at LogLevel INFO. The master now runs with `-o LogLevel=ERROR`: only ssh's
    error lines (fatal, error) remain. That also hides "Connection closed by …" (logged at INFO), so a start
    that fails with no text says "The connection to ‹target› closed (ssh exited N)".
  - 10: the question was a plain `.sheet`. It and Add Remote Host are now one `dialog()` overlay: the palette's
    `floatingGlass`, 14 pt corners, 13 pt type, the field in the palette's capsule (`fieldCapsule()`, now shared
    with `FilterField`), `.glass` / `.glassProminent` buttons, the machine's icon and name as the title. The
    window behind takes no clicks; only the buttons close it (Esc is Cancel).
  - 11: the hidden field depended on the prompt naming "password", "passphrase" or "PIN"; "Passcode:" did not.
    Now every answer is a `SecureField`; only the host-key yes/no has no field.
- **Company names:** the plans (phase 26 round 2) no longer name the user's servers or their OTP product; the
  Meta (Muse) program icon is gone (catalog, `build.mjs`, SOURCES, svg, image set, contact sheet regenerated
  with the pinned packages: only that entry changed). Left on purpose: generic tool logos (GitHub, AWS, …),
  "muse" in third-party research notes quoting upstream agent lists, and git history.
- **Tests.** CI's sshd has a generic `Banner`; `testAPasswordHostAsksAndNeverRetriesByItself` checks the
  Disconnected text has "Permission denied" and not the banner, and that the host key and password are asked in
  the new window while the first keeps its page. `testAddingAKeyHostOpensItInANewWindowWithoutAsking` checks
  the new window's machine (`window.machine` test value), the first stays This Mac, the window's own machine in
  its menu opens nothing, a pick in the first window opens another Key Host window, and ⌘N there stays on Key
  Host. `testWindowsOnDifferentSessionsEachControlTheirOwn` opens its second window with ⌘N (no ⌥-click).
  The hidden field is asserted on the password prompt only: no CI prompt lacks the word, and the code no longer
  branches on it.
- **Accepted (nits).** While a dialog shows, the window's menu commands (⌘W, ⌘T, ⌘K) still act on the page
  under it, and Tab can leave the dialog; a sheet blocked both. Two machine picks before the first new window
  restores give the second This Mac (`ponytail:` on `opening`). No test presses Esc on the dialog.
- **Reviews (one round).** Ponytail: 12 items, no blocker; fixed 1–4, 9–11 (stale "sheet" wording, the
  `keep` func inlined, shorter docs); 5–6 (move `dialog()`/`fieldCapsule()` to Style.swift) not done: Style.swift
  is at the 400-line limit. Spec: 8 items, no blocker; fixed 1 (closed-connection text), 2 (no hand-off without
  an opener), 5–6 (the machine of each window, ⌘N and the menu), 8 (docs); 3, 4, 7 above.
- **CI.** Dispatch 40246511257 (f15de32): the key host test red (the new window lay over the first, so the
  click hit its menu; fa83cc6 raises the first), the rest green. 40247028967 (fa83cc6): both remote tests
  green. 40247752826 (f3626b4, after the reviews): the four remote and window tests green. Full
  suite 40247826547 on 6a1946d (code as of 0914774, the lane's last code commit): every remote and window test
  green (all six of RemoteTests, testWindowsOnDifferentSessionsEachControlTheirOwn, testMachineMenuListsThisMac);
  red only in other lanes' areas: testEmptyPageOffersNewWorkspace and the swipe tests (lane E),
  testOrielURLFloat* (lane F).
