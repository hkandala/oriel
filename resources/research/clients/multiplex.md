# Multiplex (multiplex-term/Multiplex): tmux first, herdr per host

- SSH: **Citadel 0.12.0** (pinned exact, because 0.12.1 moved to an unaudited NIO-SSH fork) + vendored swift-nio-ssh 0.3.5.
  They also wrote a clean-room mosh.
- herdr (`Services/HerdrProbe.swift`, `docs/agents/backends-and-probe.md`): **every interaction is an SSH exec of the CLI**.
  The probe script runs `command -v herdr; herdr status --json; herdr session list --json; herdr --session <s> api snapshot`.
  Each tick costs about 25 KB, against 3.5 KB for tmux. Attach is `herdr session attach <name>` in a PTY (it auto-creates or
  revives the session). Tabs and workspaces are created with `tab create` / `workspace create --focus`. Shortcut keys send
  herdr's `⌃B` defaults, read from `herdr --default-config`.
- Rendering: **SwiftTerm** (vendored fork; `docs/agents/swiftterm-fork.md`). Key rail with hold-CTRL chords and macros,
  dictation with RNNoise.
- Pairing: closed-source `mpx bind` (QR / Bonjour + PIN / clipboard). The app's **public** key goes into `authorized_keys`
  with a `multiplex:bind:<id>` comment. The offer pins all host key fingerprints. Hosts sync through iCloud Keychain.
- Notifications (`Services/AttentionCenter.swift`): **local only**, from probe events and in-band bells, so "the app must be
  running". Background: an opt-in per-host `beginBackgroundTask`, measured at **about 26 s on iPad**, plus `BGAppRefreshTask`.
  They explicitly decided against fake `audio`/`voip` background modes (App Review rejection risk). The code comment says
  "True background delivery would need a push service."
