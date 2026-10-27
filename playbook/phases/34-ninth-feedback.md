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
