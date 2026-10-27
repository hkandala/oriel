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


### 2.3 Clipboard (OSC 52)

How a program's copy reaches a client (herdr 0.9.5, spiked in throwaway sessions and over a local sshd):
- The pane's ghostty-vt parses OSC 52 and keeps only writes (`take_clipboard_writes`; reads are answered with
  nothing and clears ignored, `crates/ghostty-vt`). `src/pane.rs` sends `AppEvent::ClipboardWrite {content}`
  (no pane id); `src/server/headless/notifications.rs:334` forwards it as `ServerMessage::Clipboard {data: base64}`
  (tag 5) to `send_to_foreground_client` only. The JSON API maps it to nothing (`src/app/api.rs:112`), and
  `terminal session control|observe` print only frames and the close.
- **The client in front** (`foreground_client_id`) is a shell client with `surface_active`: set at its hello and
  at every input, resize or surface activation (`promote_client_to_foreground`); when it leaves, the most recently
  active shell client (`latest_shell_client`). Direct terminal clients never are.
- **herdr's TUI** writes the text with `write_osc52_bytes` (`src/selection.rs`): with `SSH_CONNECTION`,
  `SSH_TTY`, VS Code or WSL it prints OSC 52 to its terminal, else it uses the platform tool (`pbcopy`). So in
  Ghostty a TUI run over `ssh` prints OSC 52 into ssh, and Ghostty writes the Mac's clipboard (its
  `clipboard-write` is `allow` by default, `clipboard-read` is `ask`); a local TUI attached to a remote
  machine (`remote-client-bridge`) gets the `Clipboard` message and runs `pbcopy`. Spiked: a TUI over a local
  sshd printed `ESC]52;c;dmlhLXNzaC10dWk=` for a pane's printf.
- pi's `copyToClipboard` sets the native clipboard (`pbcopy` on macOS, `wl-copy`, `xclip` or `xsel` on Linux) and
  also sends OSC 52 when `SSH_CONNECTION`, `SSH_CLIENT`, `MOSH_CONNECTION` or `PI_CLIPBOARD_OSC52` is set, or on a
  headless Linux. A remote server started over SSH has `SSH_CONNECTION`, so remote pi sends OSC 52.

Every way a GUI on `terminal session control` could get the writes:

| Option | Result | Cost and risk |
|---|---|---|
| (a) herdr's TUI in a hidden pty per session, with `SSH_CONNECTION` set so it prints OSC 52, read from its output | works (spiked) | needs a pty (`script` differs per OS), draws a whole TUI, plays the user's herdr sounds and desktop notifications on that machine, starts a stopped server; same front and size effects as (b) |
| (b) a shell client of our own on the client socket: endpoint hello, read only tag 5 | works locally and over SSH (built in phase 34, then reverted: too many side effects for a copy) | about 30 lines of Perl sent per run; endpoint generation 1 is kept for every later version (`src/protocol/endpoint.rs`). It is in front until a TUI is used, and as the only shell client it lays out every tab at its size (120 × 40, herdr's default no-client size), so unheld panes follow that layout (a split in an unshown tab halves them; a released pane goes back to its share). herdr also refills a session whose last workspace closes (`ensure_default_workspace`), which turns an empty session's page into a new workspace. While in front it takes a TUI's sounds, toasts, bells and title, and herdr answers color queries with defaults; herdr's own git refresh runs every 1.5 s while any shell client is attached. Gets the focused tab's cells, dropped on the machine. Sends no input and causes no focus events (checked with `?1004h`) |
| (b') the same through `remote-client-bridge` | works | the bridge starts a stopped server and registers the SSH agent socket with it: avoided by connecting to the socket directly |
| (c) shim `pbcopy`, `xclip`, `wl-copy`, `xsel` on the server's `PATH`, sending the text back over the relay | partial | only programs that call those tools (vim's `"+y`), only servers the app starts, and pi needs `SSH_CONNECTION` removed; misses every program that sends OSC 52 itself (agents, `printf`, Neovim, nested ssh). A second return path |
| (d) herdr API, events, config, `pane.read` with escapes | none | no event carries the write; `pane.read` gives the parsed screen; config has only the copy toast's position |
| (e) local programs | pi and most tools use `pbcopy` on This Mac, so local copy works; an OSC-52-only program (a `printf`, ssh from a local card) fails locally too | (b) covers both |
| (f) upstream: a `terminal.clipboard` line on control streams | the clean fix | below |
| (g) the program asks the GUI through pane metadata, as pi-herd's float request: a token names a file with the text | **chosen** for pi-hkandala's extensions (phase 34 lane C3) | only programs that know it; a token value holds 80 characters after trimming, without control characters (`MAX_METADATA_TOKEN_VALUE_LEN`, `src/app/api_helpers.rs`), 16 tokens per report and 32 per pane, so the text goes in `/tmp/oriel-copy-<uuid>` on the program's machine and the GUI reads and deletes it with one run. The GUI's mark says `remote` on panes of another machine, where the program's own `pbcopy` would miss the GUI's Mac |
| direct terminal attach (uherdr, herdr-world) or `observe` | none | herdr sends `Clipboard` only to shell clients |

The upstream ask (f): carry the terminal id in `AppEvent::ClipboardWrite`, send `ServerMessage::Clipboard` also
to the direct clients of that terminal (`terminal_stream_client_ids`), and have `terminal session control` print
`{"type":"terminal.clipboard","data":"<base64>"}`. A GUI on control streams then gets each write from the pane it
streams, with no shell client that moves the front or sizes panes.

## 3. Data model

- **IDs** (per server and session; two machines can both have `w1:p1`): workspace `w7`, `wA` (base-36-ish counter); tab `w7:t1`; pane `w7:p1`; terminal `term_65d4963eec1341` (stable for the terminal process, survives `pane.move`). Tab and pane numbers are public counters per workspace (`session.json: public_pane_numbers`, `next_public_pane_number`). **A cross-workspace `pane.move` assigns the next free `pane_id` there** (`w1:p4` → `w2:p2`) but keeps the terminal; inside a workspace a moved pane keeps its id. Ids are never given again while the server runs and are kept across a cold restart; a restarted server gives new terminal ids. Key caches by `terminal_id` when you need continuity.
- **Layout:** a BSP tree per tab, `direction: right|down`, `ratio: f32`, persisted (`persist/snapshot.rs LayoutSnapshot::Split{direction,ratio,first,second}`). It is exposed and settable: `layout.export`/`layout.set_split_ratio`/`pane.resize`/`layout.apply` (creates a new tab from a tree; does not keep live PTYs). `pane.split` takes `ratio`.
- **Zoom:** per tab (`zoomed` in the layout). `pane.zoom on|off|toggle` also focuses the pane inside the tab and moves herdr's focus; a tab with one pane refuses (`single_pane`). Moves into or out of a zoomed tab fail with `reason:"zoomed_tab"`.
- **Move:** `pane.swap` (same tab, keeps ratios), `pane.move` to an existing tab (`split` + `target_pane_id?` + `ratio?`), `new_tab`, or `new_workspace`. It emits `pane.moved` (no fake close/create). Refusals are `changed:false` with a `reason`: `same_pane`, `same_tab`, `cross_tab`, `no_neighbor`, `zoomed_tab`. `new_workspace` without a label is named after the pane's cwd. Tabs: `tab.move {insert_index}`; another workspace's `workspace_id` is ignored (the tab moves inside its own). Workspaces: `workspace.move`/`move_block`.
- **Labels and metadata:**
  - `workspace.label`, `tab.label` (rename methods; events `workspace.renamed`/`tab.renamed`).
  - `pane.label` (`pane.rename`): trimmed, **no length cap** (`terminal/state.rs set_manual_label`), **persisted** in `session.json` (`PaneSnapshot.label`), restored after a cold restart, **no change event**. A 127-char URL label round-tripped intact.
  - `pane.report_metadata`: `title`, `display_agent`, `state_labels{idle|working|blocked|done|unknown}`, and `tokens{name: value}`. Values are capped at **80 chars**, there are at most 32 keys, and they are **not persisted** across restart. They need a `source` like `user:foo`. Workspace tokens work the same way via `workspace.report_metadata`.
  - `pane.split/tab.create/workspace.create` accept `env` for the new process only. Env is **not** exposed by the API and **not** persisted.
  - `launch_argv` (from `layout.apply` commands or plugin panes) is persisted, but on cold restore it is re-run **only for live handoff** (`persist/restore.rs:692 if was_imported`). After a normal restart the pane comes back as a shell.
  - ⇒ **The only durable free-form field on a pane is `label`.** Re-read after a rename: no event fires.
- **cwd and process:** `cwd` (pane/workspace cwd), `foreground_cwd` (live foreground process), `pane.process_info` (pids, argv, cwd per foreground process).
- **Agents:** `agent` (label like `pi`, `claude`, `codex`), `agent_status` (`idle|working|blocked|done|unknown`; `done` = idle in a pane no herdr client looks at), `terminal_title(_stripped)` from OSC 0/2, `display_agent`/`title`/`state_labels` from metadata, and `agent_session`. Rollups: workspace and tab `agent_status`. AgentInfo also has `state_change_seq`, `completion_seq`, `screen_detection_skipped`. `pane.report_agent {pane_id, source, agent, state, seq}` takes idle, working, blocked, unknown and drops a report whose `seq` is not above the last; `state_change_seq` is one counter per server; `completion_seq` is set on working → idle and blocked → idle and is null again at the next change (idle → idle changes nothing); `pane.release_agent` drops only that source's report. Detection uses foreground process + screen manifests (`~/.config/herdr/agent-detection/*.toml` overrides) + integration hooks (`pane.report_agent`). `agent.explain` shows why.
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
- **Popups:** herdr's one floating object. A terminal drawn as a centred box over the tab, at most one per
  server. It is not a pane: no `pane_id`, not in `session.snapshot`, no events, not saved, no agent
  detection. Its `terminal_id` shows only on the private client socket. The public API can only open it
  (`plugin.pane.open placement:"popup"`, plugin entrypoints only) and close it (`popup.close`, no
  parameters). "Overlay" and "zoomed" placements are normal split panes in a tab with its `zoomed` flag set.
- **Probing popups again:** run a throwaway server with its own config folder
  (`XDG_CONFIG_HOME=/tmp/hx herdr --session oriel-dev-x server`, so the user's `plugins.json` stays
  untouched), link a throwaway plugin with `placement = "popup"`, and subscribe to every event type. The
  server log shows `pane.spawn` for the popup.
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
- `session stop` is synchronous; the next start restores workspaces and layout. `session delete` refuses a
  running session (`session_delete_failed`) and succeeds for a missing one. CLI errors are JSON on stderr.
- `worktree.create` writes to `~/.herdr/worktrees/<repo>/`. `worktree.open` needs a `workspace_id` in the
  repository when the focused workspace is not in one (`not_git_worktree`).
- `agent.start` does no install check and returns at once; `integration.list` lists what is installed.
- `pane.focus` moves every attached TUI to that tab and marks the tab seen. Never call it from a GUI.
