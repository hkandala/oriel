# herdr-remote (dcolinmorgan): Python relay, PWA, Telegram, SwiftUI Mac and iOS apps

**Architecture.** `relay/herdr_relay.py` (asyncio websockets, `:8375`) serves the PWA and a WS JSON protocol.
- Clients: PWA, Telegram bot, TUI, **Herdi.app** (macOS menu bar plus a notch "Dynamic Island" panel, `herdi-mac/`), **Herdi iOS** (SwiftUI, Live Activity, widget, haptics, `herdi-ios/`), and herdi-win.
- Remote access is a `cloudflared` quick tunnel with a token, an Origin allowlist, mDNS, and a JSONL audit log.

**herdr access is CLI subprocesses only** (`_invoke_herdr`, :783): `pane list`, `pane read <id> --lines N --source visible|recent --format ansi`, `pane process-info`, `pane layout`, `pane focus --direction`, `pane send-text`, `pane send-keys`.
- It polls every 2 s.
- **Fast path**: a plugin `[[events]] on = "pane.agent_status_changed"` runs `on_event.py`, which reads `HERDR_PLUGIN_EVENT_JSON` / `HERDR_PLUGIN_CONTEXT_JSON` and sends a **UDP datagram to 127.0.0.1:8376**.
- The Mac app also has a "Direct (herdr CLI)" mode that shells out to `herdr pane list` itself (binary lookup: UserDefaults → `HERDR_BIN` → `which` → `/opt/homebrew/bin`, `~/.local/bin`).

**Multi-host.** `HERDR_REMOTES=host1,host2`. Every call becomes `ssh <ControlMaster opts> host HERDR_SESSION=… herdr …`. ControlMaster avoids 30 handshakes per minute.

**Terminal mirror.** `read_pane` with `format:'ansi', source:'recent'`, refreshed about every 3 s and reconciled per styled run (`web/js/mirror.js`).
The comments record a key fact: **agent TUIs run on the alternate screen, so herdr keeps no scrollback for them**. `recent` reads past the viewport cost about 31 ms per line and scroll the operator's terminal.

**Chat/history.** `relay/transcript.py` reads Claude, pi and kimi transcripts via `agent_session`. The uuid is regex-validated before it touches a path.
**Approvals** are screen-parsed (`detect_question`, `detect_approval_options`, `detect_checkbox_options`, `menu_cursor_row`…). Answers walk the menu with `send-keys Down…` + `Enter`, and a prompt hash rejects stale answers.

**Push.** Web Push (pywebpush) with `Topic: herdr-herd` and TTL 6 h (offline phones get only the latest), plus a "clear" push on unblock.
Telegram notifications can be replied to.
iOS uses local notifications and a Live Activity while connected. No APNs server was found (guess based on code size).

---
