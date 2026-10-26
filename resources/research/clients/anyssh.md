# anyssh (patricio0312rev/anyssh): SSH client for iOS

- General-purpose iOS SSH client: libssh2+OpenSSL xcframework (`make vendor`), SwiftTerm, a tree-sitter git diff view, and
  a file browser.
- herdr adapter (`Packages/AnySSHKit/Sources/Multiplexers/Adapters/HerdrCommands.swift`): CLI over exec, batched with
  labelled sections. `herdr session list --json`, `herdr [--session s] api snapshot`, `agent focus <pane>`,
  `tab focus <id>`, `pane read <pane> --source recent-unwrapped --format text --lines N`, and the config file is read with
  `cat ~/.config/herdr/config.toml`. Attach is `'herdr' session attach '<session>'` (`MuxAttachCommand.swift`).
- Polling (`MuxPollCadence`): 1 s while visible, 5 s in background, stopped when suspended.
- `HerdrStallWatcher` diffs `agentStatus` between snapshots and schedules a local "job finished" notification on a change to
  `blocked`/`done`, plus a Live Activity. Both only work while the connection is alive. It has no push and no chat.
