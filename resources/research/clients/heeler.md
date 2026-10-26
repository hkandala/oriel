# Heeler (ZingerLittleBee/Heeler): iOS, libghostty, SSH, push

The most complete design here. ADRs in `docs/adr/` explain each choice.

## Transport (ADR 0011 `libssh2-direct-streamlocal-transport.md`)
- They replaced Citadel + NIOSSH + `exec socat` with an in-repo `Packages/HeelerSSH` (libssh2 1.11.1 + OpenSSL
  XCFrameworks checked in). It uses non-blocking POSIX sockets and `DispatchSourceRead/Write`. It does not use SwiftNIO.
- Each herdr API request opens a new **`direct-streamlocal@openssh.com` channel to `herdr.sock`**. This follows herdr's
  "one request per socket connection" contract. One extra long-lived channel carries `events.subscribe`.
- Wire format (`Sources/Heeler/Transport/HerdrWire.swift`): NDJSON `{"id","method","params"}\n`.
  Subscribe: `{"method":"events.subscribe","params":{"subscriptions":[...]}}`. Event lines decode as `{event, data}`.
- Methods used (`HeelerSSHTransport.swift`): `ping`, `agent.list`, `session.snapshot`, `pane.read`, `agent.read`,
  `agent.prompt`, `agent.send_keys`, `agent.start`, `agent.focus`, `agent.rename`, `tab.create/rename/close`,
  `workspace.create/rename/close`, `worktree.create/list/remove`, `pane.close`, `plugin.list`.
- Events they subscribe to: `pane.agent_status_changed`, `pane.agent_detected`, `pane.created/closed/exited/moved/focused/updated`,
  `pane.output_matched`, `tab.*`, `workspace.*`, `worktree.*`.
- Interactive terminal: an SSH **PTY exec** that runs the herdr CLI and lets herdr do the attach:
  ```swift
  "/bin/sh -c '\(pathExport); export HERDR_SOCKET_PATH=\"$2\"; printf \"<marker>\"; exec \(attachCommand) \"$1\"\(takeover)' attach '<target>' <socket>"
  ```
  `attachCommand` is `herdr agent attach` (agents) or a terminal attach (shells), with `--takeover`. The marker lets them drop
  shell/rc chatter that prints before the exec.
- On Windows hosts (no unix socket) they speak `herdr terminal session control`-style records instead:
  `{"type":"terminal.input","bytes":b64}`, `{"type":"terminal.resize","cols","rows"}`, and they read `terminal.frame`
  (`WindowsTerminalChannel.swift`).
- Health check: herdr `ping`, not SSH keepalive. Budgets: 8 RPC channels + 1 events channel (forwarding budget), and
  8 exec/SFTP channels + 1 attach PTY (session budget). Both stay under OpenSSH `MaxSessions` 10.
- Precondition: sshd must allow stream-local forwarding (OpenSSH default). If a channel open fails, they run
  `test -S <socket>` to diagnose. If herdr is not running, they say so; it is a permanent, non-retryable error.

## Pairing (ADR 0007), using a herdr plugin (`plugin/herdr-plugin.toml`)
- `herdr plugin install ZingerLittleBee/Heeler/plugin` and then `herdr plugin action invoke heeler.pair`. A `[[panes]]`
  popup renders the QR.
- The QR payload holds: candidate addresses, port, username, **host key fingerprint**, and a **Bootstrap Key**. The Bootstrap
  Key is a one-time Ed25519 private seed with a 2-minute TTL. Its `authorized_keys` line is `restrict,command="<accept script>"`.
- The app connects with the Bootstrap Key. The forced command appends the **Device Key** public key (generated on the
  device, private key kept in a Keychain-backed CryptoKit object). The app then reconnects with the Device Key. The Host is
  saved only after the whole ceremony succeeds.
- The SSH package never sees the private key. It gets the public blob plus a signing closure.

## Push (ADR 0008 + 0014): who runs APNs?
- The **developer runs it**: a stateless Cloudflare Worker (`relay/src/worker.js`, `apns-jwt.js`) that holds the `.p8`.
  Default URL: `https://heeler-apns.bybee.dev`. The relay keeps no state, has no DB, and never retries.
- Trigger: a plugin `[[events]] on = "pane.agent_status_changed"` hook runs `node src/notify-hook.js` once per event
  (`HERDR_PLUGIN_EVENT_JSON`). It waits about 5 s, re-checks the status through `HERDR_BIN_PATH` (debounce), and dedupes
  through `HERDR_PLUGIN_STATE_DIR`.
- Registration: the app writes its APNs token and a fresh 32-byte Notification Key into `notifications.json` on the host
  over SSH. The key also stays in the shared Keychain. The plugin seals the payload with AES-256-GCM (`{v,kid,n,ct}`,
  AAD `HERDR-NOTIFY:1`) and POSTs it to the relay. A Notification Service Extension decrypts it.
- Live Activities: one per Host, updated by a second hook. Status counts are plaintext and details are sealed
  (`HERDR-ACTIVITY:1`). The widget decrypts at render time.
- Foreground: system banners are suppressed (`willPresent` returns `[]`). An in-app banner runs from the live event stream.

## Background and reconnect
- `AppActivityCoordinator.swift`: on background, `beginBackgroundTask` opens a grace period of about 30 s and the
  connections stay up. When the grace period expires, the app tears the connections down on purpose. On foreground it
  reconnects. `EventsSession` has bounded backoff, re-subscribes on the same SSH connection if only the channel dropped,
  and opens a new transport if the connection died.

## Input
- **Composer** (ADR 0013): the terminal displays output only. The user drafts in a native text view, then Send →
  `agent.prompt`. If the agent is `blocked`, Send types the draft into the PTY without Enter instead. A "tools keyboard"
  (Esc, Tab, Shift-Tab, arrows, Enter, snippets, skills) replaces the system keyboard through a zero-height `inputView` swap.
- **Direct Input** (ADR 0016, opt-in): the system keyboard goes straight to the PTY. A shortcut row (Esc/Tab/S-Tab/Enter)
  is **normal content, not `inputAccessoryView`**. `TerminalScreenView.inputAccessoryView` returns `nil`, because UIKit
  tears down an accessory view when the keyboard mode switches.
- libghostty (ADR 0004): `UITerminalView` + `InMemoryTerminalSession`. PTY bytes go in through `receive(_:)` and Ghostty's
  write/resize callbacks feed the SSH channel. Keys are sent with `UITerminalView.sendKey`, so Ghostty encodes them for the
  active mode (kitty/fixterms).
- Attachments: SFTP to a temp path, then the path is inserted into the draft.
