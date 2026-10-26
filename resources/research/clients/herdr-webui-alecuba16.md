# herdr-webui (alecuba16): Rust Axum, vanilla JS

**Architecture.** One binary: Axum server, embedded assets, and an optional **built-in PTY multiplexer** (`src/builtin_backend.rs`, 9k lines) that reimplements a herdr-shaped API.
"external-herdr" mode talks to real herdr ≥0.9.0.
- The browser uses `/api/*` with an `x-herdr-backend` header, plus `/ws/events` and `/ws/terminal` (backend chosen by `?backend=`, because browsers can't set WS headers).
- It also ships `herdr-webui-tui` (Ratatui) on top of a reusable `src/backend_client.rs`.

**herdr API used.** `session.snapshot`, `workspace.*`, `tab.*`, `pane.list|read|layout|close`, `agent.list`, `agent.start`, **`agent.prompt {pane_id,text}`**, `worktree.*`, `events.subscribe` (1 s→30 s retry).
- herdr refuses `agent.prompt` with `agent_blocked` / `empty_agent_prompt`. The webui maps `agent_blocked` to HTTP 409: "the agent is waiting for an answer in the terminal".
- The herdr skill says `agent prompt` honours the pane's bracketed-paste mode and sends text + Enter as one ordered submission.

**Streaming.** Direct attach on `herdr-client.sock` (`src/protocol.rs` mirrors herdr's `wire.rs`, "client protocol 22", **exact version match required**):
```rust
TerminalHello { version: 22, cols, rows, cell_width_px, cell_height_px, pixel_mouse }
AttachTerminal { terminal_id, takeover: true }        // also ObserveTerminal{target}, ControlTerminal{target,takeover}
← Welcome{version, encoding: TerminalAnsi, error}  ← Terminal(TerminalFrame{seq,width,height,full,bytes})
→ Input{data} / Resize{..} / AttachScroll{..} / Detach
← Notify, Clipboard (OSC 52), TerminalBell, MouseCapture, SemanticNotification
```
- `src/terminal_hub.rs` keeps **one backend attach per terminal**, fanned out to N WebSockets.
- It has an 8 MiB replay ring for late joiners and a 1.5 s teardown grace, and it drops stalled clients (close 4404) instead of blocking.
- Renderer: wterm bundle with a Ghostty (default) or wterm core.
- OSC 10/11 colour-query replies from the browser renderer are filtered out so they never reach the PTY.

**Chat.** Only jcode (`SUPPORTED_AGENTS = &["jcode"]`). It reads `~/.jcode/sessions` (snapshot `.json` plus `.journal.jsonl` replay).
- **Prompt cards** appear for blocked panes: the tail is parsed for numbered options and answered with `N`+Enter.
- The tail is **re-parsed right before sending**, so a stale card never fires.

**Notifications:** local only (Web Audio tone and the Notification API on blocked/done). **Multi-host:** none.
**Persisted:** localStorage, plus `webui-settings.json` (recent workspaces).

---
