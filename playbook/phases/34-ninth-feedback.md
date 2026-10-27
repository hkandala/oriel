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
  `talking-to-herdr.mdx`, `window.mdx` and phase 04; open limits as "Left" lists in phases 31 and 32; reasons for left-out features and the
  Developer ID plan in `future-work/index.mdx`; similar marks in `resources/branding/README.md`.
- **Fix:** phase 33's item 8 is back word for word, and lane D's Findings say the future-work designs
  returned. Stale links in phases 08, 11, 12 and 22 point at the files that hold the facts now.
- **Decisions:** facts already on a page stay there, not repeated (the cursor shape in `settings.mdx`, the
  direct-socket cost in `talking-to-herdr.mdx`, why `done` is unused in `layout.mdx`); copy on select is lane
  C's. The libghostty visibility mechanism went to the docs' "What streams", not a `TerminalDrawing.swift`
  comment: this lane is docs only while lane C changes Terminal code. Left out as history or noise: price
  tables, run ids, per-phase metrics.
