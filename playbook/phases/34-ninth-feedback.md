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

## Findings

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
- **Runs:** red on the old code (tests without the feature): 40484619881 (both: clipboard nil); green: push run GREEN_RUN.
- **For the user:** try pi's copy key and an agent's copy on select on a remote machine. While a herdr TUI attached
  to the same session is the one last used, it gets the writes instead (in Ghostty on this Mac they still land);
  when it detaches, Oriel gets them again.
