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

## Findings

### Lane W

- **Cause:** phase 33 lane D cut the design pages of unbuilt parts while it made the docs describe the app
  as built; only a short list stayed in `future-work.mdx`.
- **Fix:** a Future work section in the sidebar. `future-work/index.mdx` lists the six design pages, then
  the smaller items with their details (Settings window, herdr's machines in Add Remote Host, Local Network
  privacy, VoiceOver screen text, tmux, a bigger server helper), waiting on herdr and left out. Sub pages:
  Pane kinds and plugins (index with the picker and run and dial, agent panes and image paste, plugin UI,
  packages, labels, state, API, security), Web page, Chat view, Floating pills (look and how they work in
  one page), iPhone and iPad (layout, watching, connections, notifications, plugins on iOS, platform), Rex
  as a second multiplexer. Restored from `ba4f85d^` and the sections `17cba5a` cut; each says "Not built".
- **Decisions:** the dropped decision rows (D17, D18, D20–D22, D24–D27, D29, D30, D32, D36,
  D37, D51–D53, D56, D58, D59) stay off the Decisions page;
  each page ends with a short Choices list that keeps their why and rejected options, and gets numbers when
  built. Mock-up components (`<Flow>`, `<PillsDemo>`, `<Phones>`, `<PanePicker>`) became text. The deleted
  plugin research stayed deleted: `resources/research/plugins/plugins.md` already holds its facts and
  measurements, and the pages link there.
- **Fix:** updated to the app as it is: the relay (dial and forwards are channels, not sessions; the
  server helper's `MaxSessions` reason is gone, and Citadel would need a relay too), floating panes as
  windows, no iOS target, cards keyed by session too, image paste through `Exec.upload` (16 MB), no
  `suppressesTerminalResponses` today, and no chat tooltip that sends the user to a herdr command. Build order, risks, inspirations and sources stayed out.
- **For the user:** read the Future work section on the docs site.
