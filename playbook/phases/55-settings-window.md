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

- **Cause, the palette after Open Browser Here** (42099119524, shard 4). ⌘K right after Open Browser Here: the
  recording shows the new card's address field focused under the open palette, then the palette's caret, while
  XCUITest never saw the palette's field focused. The new browser card's keyboard claims (its address field's retries
  every 50 ms, a claim kept while its state file is read, a late `follow`) went on after the palette opened and
  fought the palette's own focus retries. **Fix (product):** while a panel is open no card that asks the window's
  registry, nor the address field's retries, takes the keys; claims from before it opened are dropped; its close
  gives them to the keyboard card, in one `onChange` so the keys go back only once the panel counts as closed. Chats,
  plugin cards and popups that take the keys on appear are not gated (not seen). No new test: the race needs a claim
  that lands after ⌘K. A keyboard check's failure now says what has the keyboard.
- **Open.** Chosen-tests run 42106508443 on the fix failed the same test one step later: the palette kept the keys
  and took "he" of "here", then after Esc the address field did not get the keyboard. The recording ends before the
  Esc (XCUITest drops the last seconds), so what took the keys is unknown; the next failure's message names it.
- **Runs, the palette fix.** On c8606fc8 (22 tests: the browser test, the palette and Open Session tests, two
  workspace-menu drags) 42106499085 green, 42106508443 red as above; on edd7b80b (same code plus the failure message)
  42109502283 and 42109512581 (the browser test alone) and 42111067562 and 42111076839 (the 22) green; rebased on
  main as 85e0df0a, 42113780707 and 42113791548 (the 22) green.
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
- **Cause, the placeholder typed into zsh failed** (the user's File Explorer card after the update). The app started
  herdr's server again at 12:07 and herdr brought the card's pane back as a login zsh, with the old placeholder's
  screen above its prompt (the placeholder did not exit). The app typed ⌃U, then the `exec` line, in one
  `pane.send_input` text. zsh had turned bracketed paste on at its prompt, so herdr pasted the text and the ⌃U arrived as
  a plain character: `command not found: ^U`. Twice, as two launches each tried once (pids 65384 at 12:07 and 23261 at
  12:19); the guard is once per shell process per launch. Bash 5.1 and later fails the same way (spiked on herdr 0.9.5);
  the old spike passed only on a shell that had not turned bracketed paste on yet. **Fix:** ⌃U goes as a key
  (`pane.send_keys`), then the line as text. A retry now lands on a line that works.
- **Why the other cards were fine.** Of the cards, only this one came back live from the restart; the browser cards in
  `w6`, `w7` and `wB` came back without a program and were made again by Replace Pane, which starts a card with its placeholder as the pane's command,
  with no shell to type into.
- **Cause, "Saved directory is unavailable"** (the user's second explorer card; eleven panes of `default` at that restart). Cards were
  made in the folder of the pane they were opened from, here `~/code/oriel`, which the migration moved. herdr saves that
  folder and, after a restart, keeps a pane whose folder is gone with no program at all. **Fix:** a card whose
  argument is a path starts in that path's folder (a file's folder, a root). A URL card and one with no argument keep
  the source folder: ⌘T from the card, its opens, Replace Pane and a plugin with no `opens` use it. A card pane that herdr brings back with a
  `restore_error` is made again in its place under the same label (so it keeps its state), once per pane.
- **Decisions.** Two Macs that see the restart at once can both make the card again: two cards, one to close by hand.
  A remake that fails is not tried again until the next launch. Several such cards in one tab hide one by one while
  they are made again (untested: the old pane no longer hides with the new one, which shares its label).
- **Left (not fixed here).** 766 `tail -F … /T/oriel-follow-*` and `oriel-unread-*` processes (with their `awk`)
  from older builds run with parent 1, and 40 `ovvi-` ones from today: the chat followers outlive a killed app, as
  `tail -F` never reads its stdin. They depend on removed temporary files and do nothing; `pkill -f 'T/oriel-'` ends
  the old ones. No process in the user's panes uses a removed path; two shell panes of
  `default`, `w2K:p1` and `w2M:p1`, still wait without a program for `~/code/oriel-design` and `~/code/oriel-agentapi`.
- **Runs.** Both UI tests green in chosen-tests run 42109609335 on d773d5f6; 42108320174 on 274c2fdd passed the
  remake and failed the zsh test's own prompt wait (a read trims the space after `%`). No red run on the old code: the
  2-run cap; the spike shows the old line failing in zsh and bash 5.3.
- **For the user.** In pane `w4:pHQ` (File Explorer, `mira-features-since-oct-9.md`), close the card and open the file
  again, or, once this build is installed, relaunch Ovvi: it sends ⌃U and the line again into that pane's zsh.
- **Cause, leaked chat followers** (808 `tail -F` under launchd on this Mac, most following HerdrKit's test files). A
  follower runs in a wrapper that ends it on stdin's close with one SIGTERM to the follow script's shell. macOS's `sh`
  (bash 3.2) loses that one TERM: one that came while its trap was pending was dropped by the `exec tail` that
  followed (10 of 10 drops just after the backlog, on dash too), and on a loaded Mac one also went missing in `wait`.
  `tail -F` never reads stdin and never writes once its file stops growing, so it never learned its reader was gone.
  A hard kill of the app took the same path: the kernel closes stdin, the one TERM is lost.
- **Fix:** the wrapper's watcher sends its kill each second until the run is gone, for every shell and window. A
  dropped follower only closes its stdin: the old SIGKILL of the wrapper, landing before it forked its watcher, would
  leave the script running. Shell harness at load 110–290: 0 of 600 drops left a process (close, SIGKILL then close,
  and a killed parent; bash and dash), against 9 of 10 before.
- **Runs.** The new unit test failed on the old code and passes now. The chat tests (Claude Code, Codex and Pi over
  the relay, two on This Mac) and two observe tests passed: 42113550449 on the first fix, 42120026045 on the final one.
- **Other helpers the app starts, all bounded:** placeholders live in their herdr pane and end with its terminal;
  the SOCKS front runs inside the app; an ssh master (`ControlPersist=10m`, keepalive 15 s) ends 10 minutes after its
  last client, and the relay's client ends with the app's pipe; the remote relay exits when its stdin ends and closes
  every run's stdin; the `watch` script has no trap, so the first TERM ends it; plugin builds and calls run with
  stdin closed and a timeout, so after a hard kill they run to their own end; herdr's server outlives the app by
  design (D47).
