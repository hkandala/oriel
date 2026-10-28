# Phase 34: The user's ninth round of feedback

The user tested on 2026-10-27 (about 01:00), after phase 33. Each lane writes its Findings under its own
heading at the end.

## Lane W: future work designs in the docs (item 1)

1. **"I don't see all the design details we had for future work: plugins, browser, floating pills etc. In
   docs/ add a future work section and have sub pages for the design details we had earlier."** Phase 33
   lane D deleted them (`ba4f85d`, `4677dff`, `360e326`). Bring the designs back as a Future work section
   in the docs: `future-work.mdx` becomes the section's index, with one sub page per design (plugins and
   their sub pages, web pages or browser, chat view, floating pills, iPhone and iPad, and any other design
   for an unbuilt part, such as other backends), restored from git (`git show ba4f85d^:<path>`) and the
   deleted plugin research. Keep the design details; update only what the app has since changed (the
   relay, floating panes as windows, no iOS target today, decision numbers) and mark each page "not built".
   Skip pages that were history, not design (build order, risks, inspirations, sources). Plain English.

## Lane C: copy to the clipboard from remote machines (item 2)

2. **"Copy to clipboard doesn't work on remote machines."** pi's extension copies the prompt editor's
   contents with a hotkey: it works with pi on this Mac, but with pi on a remote machine nothing reaches the
   Mac's clipboard. Copy on select in pi, Claude Code and other agents fails on remote machines too. Find the
   whole path: how the pi extension copies (`/Users/hkandala/code/pi-hkandala`; probably `pbcopy` locally
   and OSC 52 otherwise), whether herdr passes OSC 52 from a pane to its clients (the `terminal session
   control` stream, also over the relay), and whether Oriel's libghostty surface handles a clipboard write
   (the runtime's write-clipboard callback and its confirm setting). Fix it in Oriel; if herdr drops OSC 52,
   say what herdr needs and do the best Oriel can. Check that local copy still works and that reading the
   clipboard (OSC 52 read) stays off or asks, as Ghostty does by default. e2e: `printf` an OSC 52 write in
   a pane, locally and on CI's sshd (RemoteTests), and check `NSPasteboard`.

## Lane X: restore lost knowledge (item 3)

3. **Phase 33 cut too much; nothing essential may be lost, and the playbook stays lean.** From an audit of
   55e4665 against main, put back as short current facts: parallel GUI testing (why XCUITest cannot be
   isolated on the host, the Tart VM setup and run, the 2-VM limit, risks, cost); herdr API facts from the
   phase spikes (and fix the `tab.move` "Refused" row); libghostty root causes; test and measuring how-tos;
   CI ideas tried and dropped; the open known limits of phases 31 and 32; phase 33's item 8 word for word;
   the branding similarity screen, the Developer ID plan, the reasons for left-out features, and stale
   links in phases 08, 11, 12 and 22. Generic, repeated lessons only; no history or dated text.

## Lane C2: copy what OSC 52 sends, on remote machines (item 3)

3. **"I don't want regular terminal copy, we should be able to copy what OSC 52 sends to us."** Undo lane C's
   `copy-on-select = clipboard`. "When I use herdr in Ghostty, this copy works as expected even on remote
   machines": find how (herdr's TUI client, `herdr --remote`, the server's `ServerMessage::Clipboard`, how
   Ghostty takes the OSC 52) and every way Oriel can get the same writes on remote machines (local already
   works). Go deep: a herdr client Oriel runs or speaks to, the relay, the remote server's environment and
   clipboard tools, herdr's API and config, an upstream change. Pick the simplest one that works, build it,
   and e2e it on CI's sshd.

## Lane V: chat view research (item 4)

4. **Research how [orca](https://github.com/stablyai/orca), [paseo](https://github.com/getpaseo/paseo) and
   [paradev](https://github.com/paradevai/paradev) offer both a terminal and a chat view for agents** (one
   agent per repo), and propose the best and simplest way for Oriel: switching back and forth between
   terminal and chat without ending the running process if possible (orca may restart the agent in chat
   mode; that is acceptable if nothing better exists), streaming the agent's transcript file as a naive
   option, and it must work on remote machines. Write the findings in `resources/research/` and update
   `docs/content/docs/future-work/chat-view.mdx`.

## Lane C3: pi extensions copy through herdr metadata (item 5)

5. **"I don't like the approach for the copy: we are changing way too many things just for copy. I'm okay
   copying regular text with ⌘C. My only concern is the pi-hkandala extensions that copy to the clipboard.
   pi-herd already asks Oriel to open floating panes; do the same for copying: simpler in pi-hkandala, and the
   app listens and copies."** Revert lane C2's clipboard client (and its side-effect workarounds). Then, like
   the float request (phase 31 lane F): the pi extensions that copy, when their pane carries Oriel's presence
   token, send the text to Oriel through herdr metadata; Oriel reads the request from `pane.updated` and puts
   the text on the Mac clipboard. Works for local and remote machines. Both repos.

## Lane K: keyboard follows a session swipe (item 6)

6. **"When a session swipe happens, text input doesn't get active on the new active pane."** Two sessions,
   one pane each; typing in session A, a three-finger swipe to session B shows B's pane, but typing gives the
   error bell until a click on the pane: the keyboard stayed on session A's terminal. Swiping between tabs
   works. Fix every way a session changes (three-finger swipe, sidebar paging, ⌥⌘[ ], Open Session, the
   overview), so the shown page's keyboard card takes the keys.

## Lane T: the tab title fades under the close button (item 7)

7. **"In the tab pill, the text overlaps with the close button. Add better shadowing on the text where the
   close button is, so it doesn't look cut abruptly or overlapping"** (screenshot
   `/tmp/oriel-shots/34pill/user.png`: "swebench autopilot setup" runs into the ×). When the × shows, the
   title fades out before it (a gradient mask), in both looks and schemes; when the × is hidden, the title
   keeps its full width.

## Lane P: Replace Pane, ⌘R (item 8)

8. **"⌘R replaces the current active pane with an empty pane, with a confirmation when needed, like closing a
   pane. It's in the ⌘K menu too. Mostly for when I change my shell setup and need to restart the shell:
   instead of opening a new pane and closing the current one."** The new pane takes the old one's place and
   size in the layout, starts in the old pane's folder, and gets the keyboard. The confirmation follows Close
   Pane's rule (ask only when something other than the shell runs). Also in the card menu and the Shortcuts
   panel, local and remote.

## Lane P2: Replace Pane without motion (item 9)

9. **"It works, but the pane animates in from the left or right on replace. Remove that: no animation, the
   pane contents just clear and show the empty shell; use our usual fade-in for pane contents."** The card
   keeps its place with no slide or layout motion; only the terminal's reveal fade plays.

## Lane D2: destructive buttons in red (item 10)

10. **"For all confirmation dialogs, the action button should be red; I see them in blue, like Replace Pane
    and Close Pane."** Every confirmation whose action ends or replaces something (close pane, tab,
    workspace, window, session detach or delete, replace pane, remove machine, others) shows its action
    button in red (destructive), while Return still confirms.

## Findings

### Lane K

- **Cause:** a page gave its keyboard card the keyboard (`Page.shown`) only when its selected tab differed from
  the tab it last gave the keyboard to (`keyboardTabID`). Showing another page changes no tab, so a page shown
  again kept its old `keyboardTabID` and never claimed the keyboard; the other page's terminal kept it (or, once
  out of the window, nothing had it: the bell). A tab step changes the tab, so tabs worked. The first visit to a
  page worked too (no `keyboardTabID` yet).
- **Fix:** `WindowPages.show`, which every way a page comes into view ends in (three-finger swipe and sidebar
  paging through `WindowPages.step`, the same call as ⌥⌘[ ]; sidebar dots, Open Session, the palette, the
  overview, a notification), clears the page's `keyboardTabID` when the page changes, so `shown` gives its
  keyboard card the keyboard. Under the overview or a panel `shown` waits (⌥⌘[ ] work under the palette and
  Open Session, whose field keeps the keys); closing the overview or the panel gives them to the card.
- **Runs:** `testKeysGoToTheSessionShown` (Open Session, a sidebar swipe, ⌥⌘], typing an echo each time and
  reading it in that session's pane through herdr): red on the old code ("waited for back-42" after ⌥⌘[, the
  same `WindowPages.step` as the three-finger swipe), green with the fix, both local under the GUI lock.
- **For the user:** swipe between two sessions with three fingers and type at once: the keys reach the shown
  pane with no click.

### Lane W

- **Cause:** phase 33 lane D cut the design pages of unbuilt parts, and research files with design facts,
  while it made the docs describe the app as built; only a short list stayed in `future-work.mdx`.
- **Fix:** a Future work section in the sidebar. Its index lists the design pages, then the smaller items
  with their details, waiting on herdr and left out. Sub pages: Pane kinds and plugins (picker, run and dial,
  where it lives, agent panes and image paste, plugin UI, packages, labels, state, API, security), Web page,
  Chat view, Changes panel (new, from Kero's research), Floating pills, iPhone and iPad, Rex as a second
  multiplexer. Each says "Not built"; pills, plugin UI and iPhone have "Checks before building", web page and
  plugin UI a risks table.
- **Fix:** brought up to date: the relay (dial and forwards are channels, not sessions; Citadel runs the same
  relay), floating panes as windows, no iOS target, cards keyed by session too, image paste through
  `Exec.upload` (16 MB), light and dark pages, and the 13 Rex corrections (revision 5, no cross-session move,
  one data stream per block per client, stale owners, binary bytes over the relay, an isolated test server).
- **Fix:** the deletion audit's research losses went back into `resources/research`: Rex's actions, Lua,
  config and hosted web client (`multiplexers/rex.md`), Rex.app's Settings window and themes
  (`clients/rex.md`), a client comparison table and patterns (`clients/README.md`), and the plugin evidence,
  JavaScriptCore limits, remote survey and placeholder facts (`plugins/plugins.md`).
- **Decisions:** the dropped decision rows (D17, D18, D20–D22, D24–D27, D29, D30, D32, D36, D37, D51–D53,
  D56, D58, D59) stay off the Decisions page; each page ends with Choices that keep their why and rejected
  options. Plugin pages allow WebAssembly (`'wasm-unsafe-eval'`). Chat shows no text that sends the user to a
  herdr command (no tooltip, no installer). Mock-up components became text. Build order, inspirations and
  sources stayed out.
- **For the user:** read the Future work section on the docs site. Two choices are yours: (1) for an agent
  without herdr's integration, chat falls back to screen text silently; the other way is an **Install
  integration** button (principle 3), which would drop "an installer for agent integrations" from Left out on
  purpose. (2) The Changes panel and its git chip on cards are a proposal from Kero's research, marked
  "proposed" until you agree.

### Lane C

- **Cause:** herdr 0.9.5 parses a pane's OSC 52 write but hands it (`ServerMessage::Clipboard`) only to its
  foreground TUI client, and `terminal session control` prints only frames and the close, so no clipboard
  write ever reaches Oriel. On this Mac pi and the agents copy with `pbcopy`, which hid it; on a remote
  machine pi falls back to OSC 52 (it does when `SSH_CONNECTION` is set, and the servers Oriel starts there
  have it). Spiked: a `printf '\e]52;c;…\a'` in a throwaway pane gives three frames and no OSC 52 or event.
- **Fix:** libghostty's `copy-on-select = clipboard`: the card's own selection goes to the Mac's clipboard
  when the mouse button comes up (and on Select All), locally and on remote machines, also in mouse apps,
  where the drag also reaches the program. OSC 52 reads stay denied (libghostty asks the host, which has no
  handler; herdr sends none anyway).
- **Decisions:** copy on select is on with no setting (a fixed default). In a mouse app it copies the text
  as drawn, borders too, unlike herdr's TUI, which gives that drag only to the program. The brief's OSC 52
  e2e cannot pass on herdr 0.9.5; the tests drag over a row in a mouse app (local, and Key Host on CI's
  sshd) and check `NSPasteboard`. What herdr needs is on the Future work page (Waiting on herdr): a
  `terminal.clipboard` event on the control stream; Oriel then writes it to the clipboard in a few lines.
- **Runs:** red on the old code (both tests: clipboard nil) 40474163618; green on the fix: push run
  40474416375.
- **Replaced by lane C2:** copy on select is reverted; OSC 52 writes reach the clipboard through a clipboard client.
- **For the user:** pi's copy key (the editor's contents) and vim's `"+y` still do not reach the Mac from a
  remote machine until herdr forwards OSC 52: select the text in the card instead (only what is on screen).
  A drag in Claude Code or pi now replaces the clipboard with what is drawn; locally the agent's own copy
  lands after it and wins.

### Lane X

- **Cause:** phase 33 cut whole research files and phase sections to make the playbook lean, and with them
  facts no other file held.
- **Fix:** each fact went to the one page that owns its topic, shortened and current: GUI slots in VMs and
  CI ideas tried and dropped in `ci.md`; screenshot pixels, accessibility frames, XCUITest gaps, saved
  state and measuring in `lessons.md` (one-off finds in their phases: SwiftUI traps in 13, Release coverage
  in 31); herdr's spike facts in `multiplexers/herdr.md`, `drag-and-drop.mdx` (the `tab.move` row: another
  workspace is ignored, not refused) and `talking-to-herdr.mdx`; libghostty causes in
  `talking-to-herdr.mdx`, `window.mdx` and phase 04; open limits as "Left" lists in phases 31 and 32;
  reasons for left-out features and the Developer ID plan in `future-work/index.mdx`; similar marks in
  `resources/branding/README.md`.
- **Fix:** phase 33's item 8 is back word for word, and lane D's Findings say the future-work designs
  returned. Stale links in phases 08, 11, 12 and 22 point at the files that hold the facts now.
- **Decisions:** facts already on a page stay there, not repeated (the cursor shape in `settings.mdx`, the
  direct-socket cost in `talking-to-herdr.mdx`, why `done` is unused in `layout.mdx`); copy on select is lane
  C's. The libghostty visibility mechanism went to the docs' "What streams", not a `TerminalDrawing.swift`
  comment: this lane is docs only while lane C changes Terminal code. Left out as history or noise: price
  tables, run ids, per-phase metrics.

### Lane V

- **Cause:** a chat view that switches without ending the agent needs the agent's own record of the conversation.
  Orca, Paseo and Paradev run a structured chat as a second, headless process (Claude Agent SDK over stream-json,
  `codex app-server`, `pi --mode rpc`, ACP) on a copy or a resume of the conversation; none shows one process as
  both. Only Orca's transcript chat switches in place, which is Oriel's design. Chat code: Orca 150–170k lines,
  Paseo about 88k, Paradev about 30k.
- **Fix:** the design keeps the transcript chat and now prefers a path from `agent_session`, shows a "Working"
  row, and sends a Codex on its shared daemon to screen text; the rejected structured mode and the later Codex
  attach are under Choices; Claude Code's transcript path is under Waiting on herdr. Research:
  [chat-view.md](../../resources/research/ui/chat-view.md).
- **Decisions:** no structured mode or ACP: they end the agent, need a fork back, cost a large adapter per agent,
  and die with the SSH link. Spiked: codex 0.163's app-server streams a thread's turns to every client that resumed
  it, so a later chat could join a Codex on the daemon (the upstream default since 0.157), once a pane maps to its
  thread. Without the daemon the TUI holds its rollout open (`lsof` works). herdr drops the `transcript_path` its
  Claude hook sends.
- **For the user:** the first slice is proposed in the research file (pi and Claude Code transcripts, the switch,
  the reply box, screen text for the rest, local and remote).

### Lane C2

- **Cause:** herdr 0.9.5 sends a pane's OSC 52 write (`ServerMessage::Clipboard`) only to its shell client in
  front, the kind its TUI is; a `terminal session control` stream never gets it. In Ghostty the TUI gets the
  write and prints OSC 52 into its terminal (through `ssh` when it runs remotely; a local TUI uses `pbcopy`), and
  Ghostty sets the clipboard. Locally Oriel only seemed to work because pi and most tools use `pbcopy` on the Mac;
  an OSC-52-only program failed locally too.
- **Fix:** each open session runs a clipboard client: a Perl script sent in the command (as the relay is), local
  and over the relay, that says herdr's endpoint generation 1 hello on the client socket as a shell client in
  front and prints each write as base64; the app sets `NSPasteboard`. Lane C's copy on select and its tests are
  reverted. The option table (TUI in a hidden pty, own client, PATH shims, API, upstream) is in
  `resources/research/multiplexers/herdr.md` 2.3.
- **Decisions:** the own client over herdr's TUI in a pty (no pty, no drawing, no sounds or toasts, no server
  start); the socket directly, not `remote-client-bridge` (which starts a stopped server and registers an SSH agent
  socket). Accepted costs, those of an attached herdr TUI: it holds the front until a TUI is used (taking its sounds,
  toasts and title meanwhile); herdr lays out every tab at its 120 × 40 and sizes unheld panes from it (the hover
  card test now ends its line with `cat`, as a narrow pane's prompt wraps); herdr refreshes git every 1.5 s; and
  herdr refills a session whose last workspace closes, so the client starts only once a session has a workspace
  (the empty page stays for a session opened empty).
  The upstream ask (a `terminal.clipboard` line on control streams) is on the Future work page.
- **Runs:** red on the old code (tests without the feature): 40484619881 (both: clipboard nil); green: push run 40487141179 (full run, on 5ccd878).
- **For the user:** try pi's copy key and an agent's copy on select on a remote machine. While a herdr TUI attached
  to the same session is the one last used, it gets the writes instead (in Ghostty on this Mac they still land);
  when it detaches, Oriel gets them again.

### Lane C3

- **Cause:** the user wants only pi-hkandala's copies to reach the Mac; lane C2's clipboard client (a herdr shell
  client in front) moved herdr's front from a TUI, laid out unshown tabs at 120 × 40, refilled an emptied session and
  needed workarounds. All of it is reverted (`1b465c0`); the OSC 52 facts stay in herdr research 2.3.
- **Fix:** copy requests, like float requests. Oriel's `oriel-shown` mark now says `remote` on an SSH machine's panes
  (`1` on This Mac). When a pane's mark is `remote`, pi-hkandala's `herdr/oriel-copy.ts` writes the text to
  `/tmp/oriel-copy-<uuid>` and reports the uuid as the pane token `oriel-copy`. Oriel reads it off `pane.updated` in
  any open session, reads and deletes the file with one run (over the relay when remote) and sets `NSPasteboard` once
  per id. pi-prompt-clipboard's key, pi-content-layout's ●
  and its selection copy call it first and fall back to pi's `copyToClipboard`.
- **Decisions:** a file, not chunks: herdr cuts a token value at 80 characters (16 tokens per report, 32 per pane), so
  a long prompt does not fit. The token holds only the id and Oriel builds the path, so no token names another file;
  `/tmp`, as macOS's `$TMPDIR` path would pass 80. The mark's value, not SSH variables, says remote: a remote Mac's
  server started without ssh has none, and its `pbcopy` would copy onto that Mac. The helper is one shared file in
  `herdr/`, so those two extensions now load from the repo, not alone from npm.
- **Runs:** red on the old code 40492087778; green: push run 40494465206 (full run, on ab62903), chosen tests 40494518693.
- **For the user:** pull pi-hkandala on the remote machine too, `/reload` pi there, then press `ctrl+shift+s` in pi
  in an Oriel card of that machine: the prompt lands on the Mac's clipboard. Other programs' OSC 52 copies (vim,
  Claude Code) still need ⌘C on a selection.

### Lane T

- **Cause:** the title's 16 pt fade ended 12 pt from the capsule's end, under the × (whose 22 pt circle ends
  28 pt from it), so the title showed at full strength up to the × glyph and ran into it.
- **Fix:** while the × shows, the title's room ends 28 pt from the capsule's end, so it fades out before the
  ×; otherwise it keeps its 12 pt and its normal fade. The same in Glass and Classic, light and dark.
- **Runs:** no UI test: the title is part of the tab button's accessibility element, so no frame of it
  reaches XCUITest; checked on Release screenshots, before (left) and after (right) in each look:
  `/tmp/oriel-shots/34pill/compare.png` (full windows `before-*.png`, `after-*.png` there).
- **For the user:** hover a tab with a long title: it fades out before the ×.

### Lane P

- **Fix:** Replace Pane (⌘R; card menu and File menu next to Close Pane, palette, Shortcuts panel, floating window).
  herdr 0.9.5 has no respawn, so it is `pane.split` (right, `focus:false`) then `pane.close` of the old pane: in
  herdr's tree the new pane takes exactly the old one's slot and size, and herdr starts it in the old pane's live
  folder (spiked: a `cd` before the split is kept). Works the same over SSH.
- **Decisions:** no stand-in card. Every new pane of the tab hides (`Ahead.replacing`) while the old one is in the
  snapshot, and the old card stays until herdr has closed it, so one snapshot swaps them in place: no split showing
  first, no empty card. The new terminal is handed the keyboard at herdr's answer (as a move does); in that same
  snapshot the zoom moves to it and a floated pane's new pane floats in a window with the old window's frame and Stay
  on Top, before the old window closes. ⌘W on the old pane during a replace does nothing, a held ⌘R's repeats are
  dropped. The question is Close Pane's (only when more than the shell runs), titled "Replace “‹name›”?" with a
  Replace Pane button; Return confirms. The split is to the right (a fresh prompt redraws on the resize); herdr's
  pane label does not carry over (the item asks for an empty pane).
- **Ceilings:** no test proves "never beside it first": the split-to-close gap is one round trip, too short for
  XCUITest to sample. ⌘D on the same tab right after ⌘R can show an empty slot for up to two snapshots (the split's
  ahead tree still has the old leaf).
- **Runs:** three new tests (shell pane: no dialog, same slot and size to the point, same folder, old id gone, keys
  reach it; program pane: Esc keeps it, the palette's Replace Pane asks again, Return replaces; zoom and floating
  window). Red on the old code locally (⌘R did nothing: "waited for a new pane", no dialog), green locally.
- **For the user:** in a pane, change your `.zshrc`, press ⌘R: a fresh shell in the same place and folder. Try it
  with `vim` open (it asks), zoomed (⇧⌘↩), and in a floating window.

### Lane P2

- **Cause:** the strip keeps each card's view by pane id. At the swap the old pane id left the tree and the new one
  came, so SwiftUI made a new card: it started beside its slot and slid in from its side of the split (the strip's
  "new card" motion), while the old card faded out.
- **Fix:** the strip's view ids map a replaced pane's new pane onto the old pane's card view, as a split's stand-in
  hands its card to herdr's pane, before the stand-in mapping. The map (`Ahead.cards`, new → old) lasts while the
  new pane is there, not one show: the strip renders after the snapshot, and a second snapshot or redraw may come
  first (review). The card stays where it is; only its terminal is new, and
  `TerminalCard`'s new host plays the usual reveal fade. Splits and closes keep their motion.
- **Runs:** `testReplacingAShellPaneTakesItsPlaceAndFolder` now launches with `-forceMotion YES -recordMotion YES`
  and checks the strip's card counter ("came went") does not change: red on the old code ("3 0, then 4 1"), green
  with the fix, both local under the GUI lock (with the other replace tests and the quick-split test).
- **For the user:** ⌘R a pane: the card stays put, the old text clears and the new prompt fades in.

### Lane D2

- **Cause:** every confirmation (close pane, tab, tabs, workspace, Replace Pane, Stop and Delete Session) already
  had a destructive button, but it was also the default button (`.keyboardShortcut(.defaultAction)`, for Return).
  AppKit draws the default button blue whatever its role, and gives a destructive button no Return (spiked with a
  bare `NSAlert`: `hasDestructiveAction` drops its `\r`; setting `\r` back turns it blue). `.tint` and
  `.foregroundStyle` on an alert button change nothing.
- **Fix:** the buttons lose `.defaultAction`, so AppKit draws them red; the app's key monitor clicks a sheet's
  enabled destructive button on Return or Enter when the sheet has no default button (`NSWindow.confirm`). Machine
  dialogs keep their own default buttons; there is no other alert in the app (Detach Session never asks).
- **Runs:** XCUITest can read the color from pixels: the close-pane, Replace Pane and Stop Session tests now check
  the button is red (`isRed`, its margin lowered from 50 to 30: the dark red bubble reads about 45), and every
  dialog test that confirms with Return passed locally (close pane, tab, tabs to the right, other tabs, workspace,
  floated pane, Replace Pane, Stop and Delete Session). On the old code the button is blue.
- **For the user:** close a pane running `sleep 100`: the Close Pane button is red, and Return still closes it.
  Before and after, dark and light: `/tmp/oriel-shots/d2/compare.png` (Debug build through XCUITest; AppKit draws
  the alert the same in Release).
