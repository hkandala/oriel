# pdx (leekt/pdx): Android handheld

- sshj 0.40 over exec. Commands (`HerdrCommandBuilder.kt`): `herdr --session S agent list`, `agent get <pane>`,
  `pane read <pane> --source recent-unwrapped --lines 160 --format ansi` (2 s poll), and live
  **`herdr terminal session control|observe <terminal_id> --cols --rows`**. It targets herdr 0.9.0 / protocol 22.
- Renders with an offline xterm.js bundle in a WebView. "Send + Enter" writes paste bytes and then a separate Enter on the
  control channel. Writes are never replayed.
- Chat: Codex only. It runs `exec <codex> app-server --listen stdio://` over SSH and calls `thread/read` and
  `thread/turns/list` (read-only).
- It has no push and no background notifications. Its device key is Ed25519, encrypted on the device, and the user copies
  the public key into `authorized_keys` by hand.

---
