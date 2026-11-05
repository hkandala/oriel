# Phase 55: Settings window

Goal: a Settings window (⌘,) in the style of macOS System Settings, with the settings that work today: seven topic
pages in a sidebar, a page per machine and per plugin, and settings that plugins declare in their manifest. The plan is
idea 1 of the research `settings-plan.html`; the design is `docs/content/docs/ui/settings.mdx` (D106, D107).

The user's words: "can you also start one agent on settings window, go with your recommendation idea 1 and implement
everything end to end, and test and review everything".

## Track A: the window and the app's pages (p55-settings)
1. **The window.** A SwiftUI `Settings` scene: sidebar (General, Appearance, Terminal, Agents, Machines, Plugins,
   Privacy), search in the sidebar that rings the row it finds, 715 × 560 pt. Privacy shows only with approved websites.
2. **General and Appearance.** Focus follows mouse, Show Shortcuts; picture tiles for the look, the text size.
3. **Terminal.** Font, cursor, blink, Option as Meta, copy on select, through libghostty's configuration, live.
4. **Agents.** Terminal or Chat first, extra arguments and a New Pane switch per agent, the notification switches
   (the Ovvi ▸ Notifications submenu goes; the palette keeps three commands).
5. **Machines and Privacy.** The machine list and a page per machine (name, target, icon, Clear website data,
   Remove); the approved websites per machine.

## Track B: Plugins (p55-plugins)
1. **The Plugins page** replaces the Plugins panel; a plugin's page with its settings, permissions, Allow, Don't Allow
   and Forget Trust; a badge for plugins that wait.
2. **Plugin settings** in the manifest (toggle, choice, number, text, path), global scope, in `settings.json`, read
   by cards through plugin API 3 (`ovvi.settings.get`, the `settings` event).
3. **The default plugins** use them: File Explorer, Git, the browser.

## Findings

### Track A
- **Decisions.** A SwiftUI `Settings` scene with a `NavigationSplitView` and grouped forms; the sidebar toggle is
  removed. Privacy holds the approved websites and shows only when a machine has one. Agents switched off in New Pane
  join `hideInNewPane`, the list that hides plugins. Extra arguments go right after the command, before Ovvi's flags
  (OpenCode ignores what follows its `--`); the second try types the bare command. Blink on leaves libghostty's
  default (a program may still ask for a steady cursor); off sets `cursor-style-blink = false`. Copy on select is
  `clipboard`: libghostty-spm drops `true`'s selection-clipboard writes.
- **Left out.** The live terminal preview (every card shows a change at once), Disconnect, drag to reorder machines
  (a grouped form takes no `onMove`), and everything that needs an unbuilt plan (updates, telemetry, the tour, Open at
  Login, herdr import).
- **Cause.** With no main window's command list (Settings or About key), the disabled Close Pane took ⌘W: Close Window
  now has it there.
- **Tests.** UI tests pin the new keys at launch like the notification switches (the defaults are shared with the
  user's app); the Settings tests launch unpinned and put the shipped values back.
- **Runs.** Full run 42052483502 on eb71f62c: one failure, `testAFileDroppedOnARemoteCardPastesItsCopysPath` ("the
  press did not start one", the file-drag helper's press, phase 33's cause; nothing here touches it). Full run
  42059188736 on d402cc34: every test passed, but shard 4 ran past the 25-minute job limit after its tests ended: the
  new tests (61 s and 36 s there) counted 15 s each in `scripts/test-times.tsv`, which now has their times. On-demand
  runs 42052489930 and 42059194411 green.
- **For the user.** The cursor shape and blink (no test can see them); Notification Settings… opens Ovvi's page in
  System Settings; a search pick rings its row for a second.

### Track B
- **Decisions.** The browser's one setting is its network for new cards on a remote machine (The Machine or This
  Mac); each card's chip still switches it. A choice is segmented with at most 4 options of at most 24 characters in
  all, else a pop-up. A path setting is a plain field (one value for every machine). The default plugins keep the
  user's own choice in their card's state and start new cards from the setting.
- **Left.** The Plugins badge counts waiting cards from `Plugin` init and deinit, so a waiting card that the kept-cards
  limit drops leaves the count while its pane still waits. A page that polls under the trust prompt after Forget Trust
  writes a `denied:` line to its log on every call.
- **For the user.** Git ▸ Diff layout with a diff open, File Explorer ▸ Show hidden files with a tree open, Browser ▸
  This Mac then a new remote browser card (its chip says This Mac), and a hand-edited `settings.json` with a typo (a
  switch then shows the notice and leaves the file as it is).

### Final review fixes
- **Cause, the remote file drop** (42052483502: "the press did not start one"). The recording shows the press
  landing on the icon, the pointer reaching the card and then, about a second later, the drag image there: on a busy
  runner the helper's drag session began after `drag.swift` had already posted its release on its timer, and that
  session never ended. Not phase 33's cause (the press before the icon's window was up). **Fix:** `file-drag`
  posts the drag itself and moves only once its session began (`willBeginAt`); the helper no longer runs
  `drag.swift` for it.
- **Cause, the spring-load drop** (42065157131, shard 3). XCUITest plays a drag on a timetable from its start: on a
  busy runner its moves came 0.4 s late and the release kept its time, so the 1.2 s hold was about 0.7 s on screen and
  0.4 s in the app, under the 0.65 s spring-load; the highlight showed, then the drop. Neither lazy capsules (the
  capsule was made and highlighted) nor the pinned settings play a part. A first fix held 1.2 s after drag.swift's
  last move: its release, 0.5 s after the workspace row's spring-load, left a drag session that never ended (the image
  stayed under the pointer, no drop; 42092809564), likely as the release came while the app built beta's page.
  **Fix:** the helper's `press` holds over the target until the test saw the spring-load and the new page's card or
  capsule, then calls `release`: no hold on a clock.
- **Cause, pi's `/tree`** (42065157131, shard 4). The composer types `/tree` into the terminal in a task after it
  hides, and the test sent Enter once it hid: the Enter reached pi first (the blank line before `/tree` in the
  pane). Not the Settings window. **Fix:** the test waits for `/tree` in the pane before its Enter.

- **Runs.** The four drag and chat tests (both file drops, the spring-load, pi's chat) green in chosen-tests runs
  42096736451 and 42096746914 on c38ecebe and 42097821135 on 70a780e8 (docs only on top); 42092809564 on 0c542f9f
  found the second leg's stuck session.

### Follow-up fixes

- **Cause, `ovvi float <session>/<pane>` refused a running session.** A command naming another session checked the
  session list that Ovvi reads at connect and in Open Session. A session started later (pi-herd's, whose server
  restarted after Ovvi launched) was "not running", so pi-herd's float failed and it fell back to a herdr popup that
  Ovvi does not show; the next open hit herdr's "a popup pane is already open". **Fix:** a session missing from the
  list makes Ovvi read the list again once before it refuses. The other readers of the list read it fresh already
  (Open Session on appear, the "not running" page on each failure).
- **Fix, pi-herd** (pi-hkandala): a failed float shows Ovvi's error and opens no popup; a popup of pi-herd's that
  nobody sees no longer blocks the next open.
- **Runs.** The new test red on the old code at its float after the start (42106371894) and green with the fix
  (42106377248), beside the agent-control, open, balance and agent-start tests (the last skips on CI: it has claude).
- **For the user:** with Ovvi open, start a pi agent hidden (a new pi-herd server), then open it from pi's agents
  tab: it floats.
