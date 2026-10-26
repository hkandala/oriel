# Kelpie (Getterbetter/Kelpie): Heeler fork for iPad and iPhone

Source: reddit `r/SideProject/comments/1we8kte`; TestFlight `AkJxAbnJ`. It is a hard fork of Heeler v0.1.8 and keeps
the transport, pairing, plugin and relay. The relay runs on the author's own Worker (`kelpie-apns.…workers.dev`).
Differences:
- **ADR 0017 `herdr-client-is-the-screen`**: the root view is a full-screen attach that runs the **herdr TUI client
  itself** (`exec herdr` / `exec herdr --session "<name>"`) over the SSH PTY. The native Console is one tap away in a
  `fullScreenCover`. Each attach exports `COLORTERM=truecolor` and `LANG`. One Transport carries one attach channel, so the
  client detaches while the Console is open. herdr keeps scrollback on the host, so nothing is lost.
  Below 64 columns herdr's own mobile layout takes over.
- **URL taps are caught on the client**: herdr would `open` the URL **on the Mac**. Kelpie finds URLs in the viewport
  text, because libghostty iOS has no "link at point" API.
- **ADR 0016 `ipad-pointer-input`**: a trackpad right-click and a long-press send an SGR right click (button 2) so herdr's
  menu opens. Hold-then-drag sends a left-button drag, which resizes herdr panes. Trackpad scroll uses a scroll-type
  `UIPanGestureRecognizer`. Touch selection uses its own overlay. Keyboard mode switches automatically between Composer and
  Direct Input from `GCKeyboard.coalesced` (hardware keyboard detection).
- Key row: `TerminalKeyBar` **is** returned as `inputAccessoryView` and shared with the composer field
  (`TerminalScreenView.swift:1241`). Heeler made the opposite choice.
- **ADR 0018 iCloud pairing sync**: `kSecAttrSynchronizable` Keychain items hold one **shared Device Key** plus one record
  per Host (host, fingerprints, Notification Key, `pendingPublicKeys`). They use no CloudKit. A sibling device that can
  reach the Host appends any pending keys to `authorized_keys`.
- **ADR 0019 native chat over Claude transcripts** (iPhone, currently paused): `pane.process_info` gives the pid and cwd.
  From those the app finds `~/.claude/sessions/<pid>.json` and then `~/.claude/projects/<enc cwd>/<sessionId>.jsonl`. It reads
  incrementally by byte offset (`tail -c +N` over an SSH exec channel) and refreshes on `pane.agent_status_changed` plus a
  timer. It sends with `agent.prompt`. Permission prompts (herdr `blocked` + a tool call with no result) are answered with
  `agent.send_keys`. Parser code: `Sources/Heeler/Chat/ClaudeTranscriptParser.swift`.
