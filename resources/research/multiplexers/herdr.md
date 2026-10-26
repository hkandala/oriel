# herdr as a backend

What herdr 0.9.x offers a client, and its quirks. The full API is `herdr api schema --json`; the calls Oriel
uses are in `docs/content/docs/reference/herdr-calls.mdx`, and how Oriel uses them in
`docs/content/docs/talking-to-herdr.mdx`. File references are to herdr's source.

## 1. Socket API

### 1.1 Transport
- Unix domain socket (named pipe on Windows), mode `0600` (`src/api/server.rs: SOCKET_PERMISSION_MODE = 0o600`). There is no auth beyond filesystem permissions.
- Path resolution order: `--session <name>` → `HERDR_SOCKET_PATH` → `HERDR_SESSION=<name>` (`~/.config/herdr/sessions/<name>/herdr.sock`) → default `~/.config/herdr/herdr.sock`.
- **Newline-delimited JSON. It is not JSON-RPC 2.0**, although it looks similar: request `{"id":"…","method":"…","params":{…}}`, success `{"id","result":{"type":"…",…}}`, error `{"id","error":{"code","message"}}`.
- **One request per connection.** `handle_connection_with_stop` reads one initial line (max 1 MiB, 5 s timeout), answers, and closes. Long-lived connections exist only for `events.subscribe` (stream), and for `events.wait`, `agent.wait`, `agent.prompt` (with wait), and `pane.wait_for_output` (one delayed response). A second `events.subscribe` on an open subscription is ignored (herdr-web-ui notes the same).
- Server-side app dispatch timeout is 5 s (`APP_RESPONSE_TIMEOUT`). Stream write timeout is 5 s.
- Subscriptions are **server-polled every 100 ms** (`CONNECTION_POLL_INTERVAL`) from a shared in-memory ring of **512 events** (`event_hub.rs MAX_EVENTS`). A slow reader gets `error.code:"events_lost"` and the server closes that connection. To recover: resubscribe, wait for `subscription_started`, call `session.snapshot` on another connection, and treat events as invalidation signals.
- `ping` → `{"type":"pong","version":"0.9.x","protocol":22,"capabilities":{"live_handoff":true,"detached_server_daemon":true,"endpoint_protocol_generation":1,"surface_interest":true,"health_check":true,"ssh_agent_registration":true}}`

### 1.2 Methods

Every method is in `herdr api schema --json`. Some are in the schema but not in the public docs; the TUI client uses them.
Key strings for `send_keys` look like `enter`, `esc`, `ctrl+c`, `alt+x`, `shift+tab`, `f1`, `minus`. `prefix+` strings are not accepted.

### 1.3 Shapes worth knowing

- `session.snapshot` gives `version, protocol, focused_*_id, workspaces[], tabs[], panes[], layouts[], agents[]`.
- `layout.set_split_ratio` path: `false` is the first child, `true` the second. Rects are in cells.
- `revision` is the metadata revision, not the output.

### 1.4 Events
Subscription types: `workspace.{created,updated,metadata_updated,renamed,moved,reordered,closed,focused}`, `worktree.{created,opened,removed}`, `tab.{created,closed,focused,renamed,moved}`, `pane.{created,closed,updated,focused,moved,exited,agent_detected}`, `layout.updated` (all global), plus **per-pane** ones: `pane.agent_status_changed {pane_id, agent_status?}`, `pane.scroll_changed {pane_id}`, `pane.output_matched {pane_id, source, match, lines?}`.

Frames (note the two naming styles):
```json
{"id":"r1","result":{"type":"subscription_started"}}
{"event":"layout_updated","data":{"type":"layout_updated","layout":{…PaneLayoutSnapshot}}}
{"event":"tab_renamed","data":{"type":"tab_renamed","tab_id":"wA:t2","workspace_id":"wA","label":"renamed"}}
{"event":"pane_focused","data":{"type":"pane_focused","pane_id":"wA:p1","workspace_id":"wA"}}
{"event":"pane.output_matched","data":{"pane_id":"wA:p1","matched_line":"… echo MARKER42","read":{…full pane_read…}}}
```
Lifecycle events use `snake_case` names. Subscription-only events (`pane.output_matched`, `pane.agent_status_changed`, `pane.scroll_changed`) use dot names.

Gaps and quirks:
- **There is no output stream.** `pane.output_changed` exists in the schema, but no code emits it (`plugins/mod.rs` tests say "warning-only until hook semantics exist"). `events.wait` accepts only `pane_agent_status_changed`; everything else returns `unsupported_event_wait_match` (`src/api/wait.rs:760`). `pane.output_matched` is the server polling `pane.read` every 100 ms.
- **`pane.rename` emits no event**. Neither `pane.updated` nor anything else fires, so a label change must be followed by a re-read. Metadata `title`/`display_agent`/`state_labels` changes arrive through the per-pane `pane.agent_status_changed`. Token changes and terminal-title changes emit `pane.updated`.
- `pane.agent_status_changed` needs a `pane_id`, so the client needs one subscription entry per pane and must reopen the stream when the pane set changes (herdr-web-ui `server/collector.ts` does this).
- `pane.focus` / `agent.focus` move the **server's** focused workspace/tab/pane. They also move **every attached TUI client** to that tab, and they mark the whole tab as seen. The docs line "does not move other clients' views" is about `pane.focused` events caused by *manual* selection in one client. Our app should not call focus casually.

### 1.5 Reading output, sending input, resize
- **Read:** `pane.read`/`agent.read` with `source=visible` (current screen), `recent` (scrollback, wrapped), `recent_unwrapped` (logs), `detection` (the bottom buffer the agent detector sees). `format=ansi` keeps SGR. `lines` limits rows. The result has `truncated`. The JSON API has no raw PTY byte stream.
- **Input:** `pane.send_text` (literal), `pane.send_keys` (key names), `pane.send_input` (both, ordered), `agent.prompt` (honors bracketed paste and sends a delayed Enter; can also wait).
- **Resize:** the JSON API cannot set PTY cols/rows. Pane PTY size = layout rect × the viewing client's area (with no client viewing, the default area is 120×40). Ratios are server state. The only external way to set a pane's PTY size is `terminal session control` + `terminal.resize` (see 2.2). That also **locks** the pane from layout-driven resizes while the controller is attached (`direct_attach_resize_locks`, `src/ui/panes.rs:331`).

---

## 2. Client↔server protocol and live terminal bytes

### 2.1 `herdr-client.sock`: private binary protocol
- Path = the API socket path with `-client` inserted (`herdr.sock` → `herdr-client.sock`, `src/server/socket_paths.rs`).
- Framing: **u32 little-endian length prefix + bincode-encoded Rust enums** (`src/protocol/wire.rs`; `MAX_FRAME_SIZE` 2 MiB, 32 MiB with graphics). `PROTOCOL_VERSION = 22`.
- `ClientMessage` variants (order frozen for endpoint gen 1): `TerminalHello`, `Input{data}`, `ClipboardImage`, `Resize`, `Detach`, `AttachTerminal{terminal_id,takeover}`, `AttachScroll`, `ObserveTerminal{target}`, `ControlTerminal{target,takeover}`, …, `ClientShellHello{surface_size,…}`, `ClientShellResize`, `ClientShellPaneInput{pane_id,events}`, `ClientShellEndpointRequest{boot_id,request}` (JSON API tunnelled over this socket), …, `EndpointControl{kind,data}`.
- `ServerMessage`: `Welcome{encoding: SemanticFrame|TerminalAnsi}`, `Terminal(TerminalFrame{seq,width,height,full,bytes})`, `Graphics`, `ServerShutdown{reason}`, `Notify`, `Clipboard` (OSC 52), `ClientShellSnapshot`, **`PaneSurface`** ("active-tab pane content rendered at a client-requested size"), `PaneSurfacePatch`, `SemanticNotification{kind: NeedsAttention|Finished|UpdateInstalled|Custom,…}`, `ClientShellEndpointResponseChunk`, `EndpointControl{kind,data}`.
- Since 0.9, the TUI is a "client-owned shell" (`src/protocol/endpoint.rs`): the client draws the sidebar and tabs. The server sends a JSON snapshot (`shell.snapshot.v1`) and cell surfaces (`shell.surface.v1`) for **the client's one active tab**. The hello/welcome negotiate codecs, advertised `methods` and `capabilities` (`surface_interest`, `health_check`, `agent_view_projection`, `agent_completions`). A third party *could* implement this in Swift (bincode of Rust enums, cell grids), but it is a private, Rust-shaped protocol tied to one active tab per connection. **Not recommended.**

### 2.2 Documented bridge: `herdr terminal session observe|control`
This is the supported way for third-party GUIs to get live pane content (`src/client/terminal_sessions.rs`). It is a CLI that speaks the binary protocol (handshake with `RenderEncoding::TerminalAnsi`, then `ObserveTerminal`/`ControlTerminal`) and converts it to NDJSON on stdout/stdin. Unix only (no Windows direct attach).
```
herdr terminal session observe <pane|terminal|agent target> [--cols N] [--rows N]     # read-only, many observers
herdr terminal session control <target> [--takeover] [--cols N] [--rows N]             # one writer per terminal
```
stdout:
```json
{"type":"terminal.frame","seq":1,"encoding":"ansi","width":50,"height":10,"full":true,"bytes":"<base64>"}
{"type":"terminal.frame","seq":2,"encoding":"ansi","width":50,"height":10,"full":false,"bytes":"<base64>"}
{"type":"terminal.closed","reason":"detached"}
```
stdin (control only):
```json
{"type":"terminal.input","text":"echo hi\r"}            // or "bytes":"<base64>"
{"type":"terminal.resize","cols":40,"rows":8,"cell_width_px":0,"cell_height_px":0}
{"type":"terminal.scroll","direction":"up","lines":3,"source":"wheel"|"page_key","column":0,"row":0,"modifiers":0}
{"type":"terminal.mouse","action":"down|up|drag|move","button":"left|right|middle","column":12,"row":5,"modifiers":0}
{"type":"terminal.release"}
```
What the bytes are (important):
- They are **not raw PTY bytes**. The server keeps its own VT state (ghostty-vt) and renders that pane's **visible viewport** at the client's cols×rows, then sends **diffed ANSI**: the first frame is `full:true` with `ESC[2J`, later frames are cursor-addressed patches wrapped in `?2026h/l` (synchronized output)8;;\x1b\\\x1b[8;29H…CTRL-OK…\x1b[?2026l`]. A `terminal.resize` produces a new `full:true` frame at the new size.
- Scrollback is **not streamed**. `terminal.scroll` moves the server-side viewport, and the frames show the scrolled view. Feeding these bytes into SwiftTerm gives a correct screen, but SwiftTerm's own scrollback will be meaningless. For history, use `pane.read recent` or the server viewport (`terminal.scroll`, or the undocumented `pane.scroll`).
- `control` **resizes the actual PTY** to the controller size and locks layout-driven resize while attached (`attach_terminal_client` in `src/server/headless.rs:1722`). After release the PTY **stays** at the controller size until a TUI shell client re-lays out that tab. `observe` never resizes. It renders the PTY screen clipped or padded to the observer size.
- Only one controller per terminal. A second controller gets `ServerShutdown "already has an attached client; retry with --takeover"`, and with `--takeover` the old one gets `"terminal attach taken over"`. The full-screen sibling is `herdr terminal attach <terminal_id>` / `herdr agent attach <target>` (for humans; detach with `ctrl+b q`).
- Observers that make no write progress for 30 s are dropped.


## 3. Data model

- **IDs** (per server and session; two machines can both have `w1:p1`): workspace `w7`, `wA` (base-36-ish counter); tab `w7:t1`; pane `w7:p1`; terminal `term_65d4963eec1341` (stable for the terminal process, survives `pane.move`). Tab and pane numbers are public counters per workspace (`session.json: public_pane_numbers`, `next_public_pane_number`). **A cross-workspace `pane.move` assigns a new public `pane_id`** but keeps the terminal. Key caches by `terminal_id` when you need continuity.
- **Layout:** a BSP tree per tab, `direction: right|down`, `ratio: f32`, persisted (`persist/snapshot.rs LayoutSnapshot::Split{direction,ratio,first,second}`). It is exposed and settable: `layout.export`/`layout.set_split_ratio`/`pane.resize`/`layout.apply` (creates a new tab from a tree; does not keep live PTYs). `pane.split` takes `ratio`.
- **Zoom:** per tab (`zoomed` in the layout). `pane.zoom on|off|toggle` also focuses the pane inside the tab. Moves into or out of a zoomed tab fail with `reason:"zoomed_tab"`.
- **Move:** `pane.swap` (same tab, keeps ratios), `pane.move` to an existing tab (`split` + `target_pane_id?` + `ratio?`), `new_tab`, or `new_workspace`. It emits `pane.moved` (no fake close/create). Tabs: `tab.move {insert_index}`. Workspaces: `workspace.move`/`move_block`.
- **Labels and metadata:**
  - `workspace.label`, `tab.label` (rename methods; events `workspace.renamed`/`tab.renamed`).
  - `pane.label` (`pane.rename`): trimmed, **no length cap** (`terminal/state.rs set_manual_label`), **persisted** in `session.json` (`PaneSnapshot.label`), restored after a cold restart, **no change event**. A 127-char URL label round-tripped intact.
  - `pane.report_metadata`: `title`, `display_agent`, `state_labels{idle|working|blocked|done|unknown}`, and `tokens{name: value}`. Values are capped at **80 chars**, there are at most 32 keys, and they are **not persisted** across restart. They need a `source` like `user:foo`. Workspace tokens work the same way via `workspace.report_metadata`.
  - `pane.split/tab.create/workspace.create` accept `env` for the new process only. Env is **not** exposed by the API and **not** persisted.
  - `launch_argv` (from `layout.apply` commands or plugin panes) is persisted, but on cold restore it is re-run **only for live handoff** (`persist/restore.rs:692 if was_imported`). After a normal restart the pane comes back as a shell.
  - ⇒ **The only durable free-form field on a pane is `label`.** Re-read after a rename: no event fires.
- **cwd and process:** `cwd` (pane/workspace cwd), `foreground_cwd` (live foreground process), `pane.process_info` (pids, argv, cwd per foreground process).
- **Agents:** `agent` (label like `pi`, `claude`, `codex`), `agent_status` (`idle|working|blocked|done|unknown`; `done` = idle and not yet seen by the server), `terminal_title(_stripped)` from OSC 0/2, `display_agent`/`title`/`state_labels` from metadata, and `agent_session`. Rollups: workspace and tab `agent_status`. AgentInfo also has `state_change_seq`, `completion_seq`, `screen_detection_skipped`. Detection uses foreground process + screen manifests (`~/.config/herdr/agent-detection/*.toml` overrides) + integration hooks (`pane.report_agent`). `agent.explain` shows why.
- **Notifications:** the JSON API has `notification.show` (outbound, shows a toast in the TUI). Agent finished/needs-attention notifications go to client shells only, as private `SemanticNotification` messages. **Our app must derive notifications itself** from `pane.agent_status_changed` (working→done or blocked). The per-client "seen" state is client-local, as in the TUI.

---

## 4. Remote machines (0.9 "connecting machines")

- **Architecture:** each machine runs its own `herdr server`. Since 0.9 the client renders the outer UI, and servers "supply the terminal views". Only the **selected** machine streams pane surfaces (`surface_interest`). Others send only workspace, agent and notification state (`docs: connecting-machines.mdx`; blog `herdr.dev/blog/connecting-the-machines/`).
- **Transport = OpenSSH subprocesses**, no custom daemon or port:
  - UI connection: `ssh <target> herdr --session <s> remote-client-bridge [--idle-timeout-v1]`. This pipes stdio ↔ the remote `herdr-client.sock` (binary protocol) (`src/remote/attach.rs:403`).
  - API forwarding (`herdr --machine <label> <cmd>`): `ssh <target> <herdr> --session <s> remote-api-bridge`, after a probe `remote-api-bridge --check` → prints `herdr-api-bridge-v1` (`src/remote.rs`, `attach.rs:2662`). The bridge is a **byte pipe** stdin/stdout ↔ the API socket (`forward_remote_bridge_stdio`), so each request is one SSH exec, since the API is one request per connection. Verified locally: `echo '{"id":"x","method":"workspace.list","params":{}}' | herdr remote-api-bridge` returns the normal JSON.
  - Setup (`herdr machine add`, `herdr --remote`) finds or installs the remote binary (`~/.local/bin/herdr`), and starts the remote server as a detached daemon.
- **Auth model:** only OpenSSH (keys, agent, host keys). Profiles (`~/.config/herdr` state dir `client/endpoints.json`) store id, label, ssh target, remote session and enabled flag. No secrets. The remote socket relies on filesystem permissions (`0600`).

---

## 5. Plugins, browser panes, hooks

- **Plugins** (`docs/plugins.mdx`, `herdr-plugin.toml`): `[[actions]]`, `[[events]]` (hooks on event names; env `HERDR_PLUGIN_EVENT_JSON`), `[[startup]]`, `[[panes]]` (terminal-only entrypoints; placement `overlay|popup|split|tab|zoomed`), `[[link_handlers]]` (Ctrl-click URL regex → action, gets `HERDR_PLUGIN_CLICKED_URL`), `[[build]]`. The registry is `plugins.json` beside `session.json`. Linking a local folder (e.g. this user's `~/code/pi-hkandala/herdr/plugin`) works the same as `local-plugins/`. "The entire Herdr CLI is the plugin API." **"Native non-terminal plugin UI is not part of plugin v1."** Popups have no pane id.
- **Browser panes:** herdr has **no** browser pane. `ogulcancelik/herdr-browser` is **deprecated**. It streamed Chromium frames through `pane.graphics.stream`, which was **removed** in 0.9 (`pane.graphics.{info,set,clear,stream}` now return unknown-method; "no replacement socket image API"; apps should emit Kitty graphics in their own output). The successor is zenbu-labs/terminal-browser (Kitty graphics in a terminal pane). ⇒ Our WKWebView-over-placeholder approach does not compete with any herdr feature.
- **Agent state hooks:** `herdr integration install <agent>` writes agent-side hooks or plugins that call `pane.report_agent` / `pane.report_agent_session` (Claude: SessionStart → session id only, state from screen manifest; Codex `--no-daemon`: session + turn state; Pi/OpenCode/Kimi/Kilo/OMP: full state). Third-party agents can call these methods themselves (`docs/add-herdr-support.mdx`), including `resume_argv` so herdr re-runs them after a restart. `agent.view.set` lets a caller customize the TUI's agent list ordering and filtering.

---

## 6. Agent sessions and transcripts (for the chat view)

- `agent_session` on `pane.get/list`, `agent.get/list` and `session.snapshot` is a pointer to the agent's native session:
  - Pi: `kind:"path"`, `value` = `~/.pi/agent/<…>/sessions/<ts>_<uuid>.jsonl`.
  - Claude: `kind:"id"`, `value` = uuid → `~/.claude/projects/<cwd with / → ->/<uuid>.jsonl`.
  - Codex: `kind:"id"` → `~/.codex/sessions/YYYY/MM/DD/rollout-<ts>-<uuid>.jsonl`.
  - Others (opencode, kimi, …) are ids into their own stores (see the resume table in `docs/session-state.mdx`, `src/agent_resume.rs`).
- herdr does **not** parse or serve transcripts. A chat view would read those files on the pane's host. For remote hosts that means `ssh host cat/tail` or a helper. herdr-web-ui does exactly this (`server/claude-store.ts`, `codex.ts`, `pi.ts`, `conversation.ts`).
- Sending a chat message = `agent.prompt {target, text, wait?}` (paste-aware, returns `agent_blocked` if the agent is blocked). Answering a blocked prompt = `agent.send_keys`. A screen fallback is `agent.read source=recent_unwrapped`.

---

## 7. Facts from tests

- A pane label survives moves and a restart. The TUI's border title shows the metadata title, else the label, else the agent.
- Several controllers can hold different panes of one tab. A control stream survives `pane.move`: it is bound to the terminal.
- A layout rect is not the PTY size: use the viewport's rows.
- A subscribe through `remote-api-bridge` needs its stdin kept open.
- `agent.start` does no install check and returns at once; `integration.list` lists what is installed.
- `pane.focus` moves every attached TUI to that tab and marks the tab seen. Never call it from a GUI.
