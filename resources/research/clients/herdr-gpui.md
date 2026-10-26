# herdr-gpui (penso): Rust and GPUI desktop client

Repo: https://github.com/penso/herdr-gpui. About 234k lines of Rust, most of it tests and UI.
Facts below come from the code and the READMEs. Guesses are marked **(guess)**.

## 1. Architecture

Cargo workspace (`Cargo.toml`), Rust edition 2024, `unsafe_code = "deny"`:

| crate | lines | role |
|---|---|---|
| `crates/herdr-protocol` | ~2.8k | Wire types copied from herdr 0.9.1 `src/protocol/{wire,endpoint}.rs` (see `NOTICE.md`). Bincode framing, plus decoders for surface scroll, delta and reuse. |
| `crates/herdr-client` | ~14k | Connection worker thread, handshake, revision fencing, request lane, SSH/WSL bridge, saved-host catalog, sessions list/delete, port forward, file upload. |
| `crates/herdr-gpui` | ~217k | The app: sidebar, tab strip, terminal painter, browser tabs, review/diff, PR lookup, usage meters, "Teleport", notifications, sound, settings, updater. |

Main dependencies: `gpui-pre =0.3.6`, `gpui-wry`/`lb-wry` (embedded WebKit), `bincode 2` (serde,
standard config), `serde_json`, `crossbeam-channel`, `rodio` (sounds), `syntect` (diffs), `ureq`,
`rusqlite` (browser cookies for usage providers), `objc2-*` (dock badge, WKWebView snapshot),
`security-framework` (Keychain). There is **no terminal-emulator crate** (no alacritty_terminal,
vte, or libghostty).

## 2. Transport and handshake (herdr socket)

**Socket discovery** (`herdr-client` README, "Local Discovery"): first `HERDR_SOCKET_PATH` (the
client socket name is derived from its stem as `-client.sock`), then `HERDR_CLIENT_SOCKET_PATH`,
then `HERDR_SESSION` (default `default`). The path is `~/.config/herdr/herdr-client.sock`, or
`sessions/<name>/herdr-client.sock` for a named session. The docs stress: "`--socket` must name
the binary **client** socket, not the JSON API socket." If no local server is running, the app
starts `herdr server` (`src/daemon.rs`).

**Framing** (`herdr-protocol/src/codec.rs`): each frame is a `u32` little-endian length followed
by a bincode-2 `standard()` payload (varint ints; an enum is a varint variant index followed by
its fields in order). Caps: 2 MiB outbound and 32 MiB inbound (graphics). Field order and variant
order are the contract: `// Field and variant order MUST remain unchanged: bincode uses positional encoding.`

**Handshake** (`herdr-client/src/session.rs:175-197`). The client sends
`ClientMessage::EndpointControl { kind: "endpoint.hello.v1", data: <JSON> }`:

```json
{ "generation": 1, "cell_width_px": 8, "cell_height_px": 16,
  "surface_size": {"cols": 80, "rows": 24}, "pixel_mouse": true,
  "direct_graphics": false, "endpoint_keybindings": false, "mouse_capture": false,
  "surface_active": true, "surface_reuse": true, "surface_delta": true, "surface_scroll": true,
  "snapshot_codecs": ["shell.snapshot.v1"], "surface_codecs": ["shell.surface.v1"],
  "input_codecs": ["shell.input.semantic.v1"], "blob_codecs": ["shell.blob.v1"] }
```

The server replies `EndpointControl { kind: "endpoint.welcome.v1", data }`:

```json
{ "generation": 1, "server_version": "0.9.3", "snapshot_codec": "shell.snapshot.v1",
  "surface_codec": "shell.surface.v1", "input_codec": "shell.input.semantic.v1",
  "blob_codec": "shell.blob.v1", "methods": ["pane.focus", ...],
  "capabilities": ["surface_interest","presentation_effects_fence","health_check", "surface_delta", ...] }
```

`methods` is a **server allowlist** of JSON-RPC methods this connection may call. The client
refuses to send anything not listed (`Method::advertised_in`). A daemon older than 0.9.0 answers
with a legacy `ServerMessage::Welcome` and is rejected (`Error::LegacyDaemon`).

The installed herdr agrees with this (read-only check): `herdr status client --json` →
`{"version":"0.9.3","protocol":22,"endpoint_protocol_generation":1,"endpoint_capabilities":["surface_interest","presentation_effects_fence","health_check"],"remote_host_bridge":true,"remote_bridge_idle_timeout":true,...}`.

**Server → client messages** (`wire.rs: enum ServerMessage`):
- `EndpointControl{kind:"shell.snapshot.v1", data:<JSON ClientShellSnapshot>}`: the **full** state,
  pushed on every change. `revision` only goes up within one `boot_id`. A changed boot or a lower
  revision causes a disconnect.
- `PaneSurface(PaneSurfaceFrame)`: a full cell grid. `PaneSurfacePatch` carries row patches
  against `base_surface_revision`.
- Optional encodings arrive as `EndpointControl` kinds: `endpoint.surface-scroll.v1` (base64
  bincode), `endpoint.surface-delta.v1` (base64), and `endpoint.surface-reuse.v1` (JSON).
- `ClientShellEndpointResponseChunk{boot_id, request_id, final_chunk, data}`: the JSON-RPC
  response, which may arrive in chunks.
- `SemanticNotification{kind: NeedsAttention|Finished|UpdateInstalled|Custom, title, body, sound, agent, workspace_id, tab_id, pane_id, position}`.
- `Clipboard{data}` (OSC 52), `TerminalBell{count}`, `WindowTitle`, `ServerShutdown`,
  `ClientShellKeyboardReportAll`, `MouseCapture`, `GraphicsFile`, and legacy `Notify`.

**Client → server messages** (`enum ClientMessage`, the subset in use):
`ClientShellPaneInput{pane_id, events}`, `ClientShellPopupInput{terminal_id, events}`,
`ClientShellResize{cell_width_px, cell_height_px, surface_size, pixel_mouse}`,
`ClientShellEndpointRequest{boot_id, request:<JSON string>}`, `ClientShellFocus{focused}`
(window focus), `ClientShellHostTheme{update}` (lets herdr answer OSC 10/11/4 colour queries),
`ClipboardImage{target, extension, data}`, and `EndpointControl{kind:"endpoint.health.ping.v1"}`.

**JSON-RPC envelope** (`herdr-client/src/handle.rs:240`):

```rust
let request = json!({"id": id, "method": method.as_str(), "params": params}).to_string();
self.enqueue(boot_id, ClientMessage::ClientShellEndpointRequest { boot_id: boot_id.into(), request }, ...)
```

The response is the endpoint's `{id,result}` or `{id,error}`. Only **one request is in flight**
at a time; later commands wait in FIFO order (60 s request deadline).

**Methods the GUI calls** (`herdr-client/src/method.rs`, the full closed set):
`client_shell.surface.set`, `command.invoke`, `integration.list|install`, `layout.set_split_ratio`,
`pane.clear|close|copy_motion|copy_search|edit_scrollback|focus|focus_direction|input.set|link.activate|link.resolve|rename|resize|scroll|selection.read|split|swap|zoom`,
`product_announcement.dismiss`, `release_notes.dismiss`, `server.reload_config`,
`tab.close|create|focus|move|rename`, `workspace.close|create|focus|move_block|rename`,
`worktree.create|list|open|remove`.
Example param shapes from the code:

```json
{"method":"pane.split","params":{"target_pane_id":"w1:p1","direction":"right","focus":true}}
{"method":"pane.zoom","params":{"pane_id":"w1:p1","mode":"on"|"off"|"toggle"}}
{"method":"pane.swap","params":{"source_pane_id":"…","target_pane_id":"…"}}
{"method":"pane.focus_direction","params":{"pane_id":"…","direction":"left"}}
{"method":"layout.set_split_ratio","params":{"tab_id":"w1:t1","path":[true,false],"ratio":0.42}}
{"method":"tab.move","params":{"tab_id":"…","insert_index":2}}
{"method":"tab.create","params":{"workspace_id":"w1","focus":true}}
{"method":"pane.input.set","params":{"pane_id":"…","right_click":"herdr"|"pane"}}
{"method":"client_shell.surface.set","params":{"active":false}}
```

The endpoint allowlist does **not** cover layouts, process details, or agent sessions
(`teleport.rs`: "The GUI connection's method allowlist lacks layouts, process details, and agent
sessions"). For those, the app runs the `herdr` CLI, locally or over SSH: `herdr pane run`,
`herdr agent start`, `herdr session list|stop|delete --json`, `herdr machine add|rename|remove`,
and `herdr worktree remove`.

**Threading and liveness** (`herdr-client` README, "Transport Rules"): one worker thread per
connection owns connect, writes and reads. A bounded queue (64 commands, 8 events) applies
backpressure. The GUI drains every connection's inbox on a **16 ms timer**
(`window.rs:647`, `endpoint/polling.rs::poll_endpoints`). Over SSH, a quiet link triggers
`endpoint.health.ping.v1` after 5 s, and the link is declared dead 10 s later with no reply.

**Reconnect**: the client crate has none ("No reconnect or replay"). The GUI owns it per
endpoint: `Duration::from_millis(500u64 << attempts.min(8)).min(30s)` (`endpoint.rs:315`). On
reconnect the GUI does a fresh handshake and gets a full snapshot and surface. Input is never
replayed.

## 3. Live terminal content and rendering

- **No PTY bytes reach the client.** herdr has its own emulator server-side. It sends
  `PaneSurfaceFrame`:

```rust
pub struct PaneSurfaceFrame { boot_id, projection_revision: u64, surface_revision: u64,
    frame: FrameData,            // whole client-sized grid of the focused tab
    panes: Vec<PaneSurfacePane>, // per pane: pane_id, rect, inner_rect, scrollbar_rect, scroll{offset_from_bottom,max,viewport_rows}, focused, mouse_reporting, alternate_screen_active
    splits: Vec<PaneSurfaceSplit>, // direction, pos, area, hit_rect, path: Vec<bool>
    popup: Option<Box<ClientShellPopupSurface>>, graphics: SurfaceGraphicsScene }
pub struct CellData { symbol: String, fg: u32, bg: u32, modifier: u16, skip: bool, hyperlink: Option<u32> }
// colours: 0..=16 named (0 = default), 0x010000XX indexed, 0x02RRGGBB rgb
```

- **Fencing**: a surface is shown only when `(boot_id, projection_revision)` equals the latest
  snapshot's `(boot_id, revision)`. This stops cells and metadata from mixing across focus changes.
- **Graphics** (kitty/sixel images) arrive as RGB/RGBA/PNG assets in `SurfaceGraphicsScene`. They
  are sent once and kept per connection (`herdr-client/src/surface_images.rs`).
- **Rendering**: a custom GPUI cell painter (`herdr-gpui/src/terminal_painter.rs`, ~1k lines plus
  submodules). It shapes runs per row with a glyph cache. Box-drawing, block and powerline glyphs
  are drawn as geometry snapped to device pixels. It also handles selection and search tints,
  cursor shapes (DECSCUSR 0-6), hyperlinks, and an accessibility transcript
  (`terminal/accessibility.rs`).
- **Scrollback** stays server-side. The surface is only the viewport. The scrollbar comes from
  `pane.scroll` metrics. Find, copy mode and selection use the
  `pane.copy_search`/`pane.copy_motion`/`pane.selection.read` RPCs (`scrollback.rs`). Wheel input
  goes up as `Mouse{ScrollUp/Down}` events.
- **Keys** (`terminal.rs:439-480`): GPUI keystrokes become `ClientPaneInputEvent::Key{code,
  modifiers: shift=1|ctrl=2|alt=4, kind: Press|Repeat, ...}`. Printable text goes through the
  IME input handler as `TextCommit(String)`, so dead keys and IME are not sent twice. Cmd-V sends
  `Paste(String)`. Images go through `ClipboardImage`.
- **Resize**: `viewport()` turns the terminal area's pixels into cols×rows (clamped to 4096 and
  1e6 cells). Those values go up in `ClientShellResize`, and herdr re-lays out the tab to that size.

## 4. Pane layout

- herdr **owns the layout and draws it inside the grid**. The client paints one grid for the
  focused tab. It uses `panes[].rect` to hit-test clicks and route input to a `pane_id`, and
  `splits[].hit_rect` to show resize cursors. Dragging a divider sends
  `layout.set_split_ratio{tab_id, path, ratio}` (`terminal/splits.rs`, `window/mouse.rs:637`).
- **Focus is per client**: "The daemon keeps a focused tab and projects a surface per client"
  (`group_terminals.rs`). To show another tab, the client sends `tab.focus` and waits for the new
  snapshot and surface. The herdr CLI or agents can move *every* client's focus. Parked groups
  then re-focus their own tab.
- **"Editor groups"** (side-by-side views, `group_terminals.rs`, README "Editor Groups"): **each
  group that shows a herdr tab opens its own extra client connection**. Non-active groups report
  `ClientShellFocus{focused:false}` and drop notifications. "A tab is live in one group at a time:
  the daemon sizes a tab for a single client", so a second view of the same tab shows a clipped
  or padded copy. The group layout is saved locally in `editor-groups.json`.
- There is no per-pane surface stream. A single pane is shown full-size only through `pane.zoom`.

## 5. State mapping: herdr vs. local

From the snapshot (pushed, full replace): `workspaces[]` (id, label, branch, git_ahead_behind,
worktree, `agent_status`, `tokens`), `tabs[]` (workspace_id, label, zoomed, `agent_status`),
`panes[]` (cwd, foreground_cwd, label), `agents[]` (pane_id, `agent` label such as
"claude"/"codex"/"pi", display_agent, title, terminal_title, `agent_status:
idle|working|blocked|done|unknown`, `state_change_seq`, state_labels, tokens), `agent_order`,
focused ids, `commands[]` (custom commands and keybindings), and update/release-notes info.
Unknown status strings decode to `Unknown`, which keeps newer servers compatible. The sidebar
says: "Status comes from the daemon's snapshot, never from guessing at terminal output"
(`sidebar/agents.rs`). Agent icons are SVGs keyed on herdr's `agent_label` list (24 agents,
`icons.rs`).

Kept locally (`~/.local/state/herdr/gpui/` and the herdr client state dir):
`window-state.json` (window geometry), `browser-tabs.json`, `editor-groups.json`,
`preferences.json`, `agent-skill.json`, `usage-keychain.json`, `config-gpui.toml` (GUI overrides
on top of the shared `~/.config/herdr/config.toml`), `gpui-wsl.json`. It also reads and writes
herdr's own `client/endpoints.json` (saved SSH hosts, `{version, ssh:[{id,label,target,session,enabled}]}`)
and `client/endpoint-selection.json`, and re-reads the catalog every 2 s. Theme, sound and toast
settings come from the local herdr config, not from the remote daemon.

## 6. Multiple hosts and remote machines

- `ConnectTarget::{Local, Session{name}, Socket(path), Ssh{target, session}, Wsl{distro, session}}`.
- **SSH bridge** (`herdr-client/src/ssh.rs`): runs `ssh -T -C -o BatchMode=yes -o
  StrictHostKeyChecking=yes -o ConnectTimeout=10 -o ServerAliveInterval=15 -o ControlMaster=no
  host /bin/sh -c '<script>'`. The script searches PATH and known install roots for `herdr`, runs
  `herdr status client --json`, and prints `herdr-remote-output-ready:1`. The client checks
  generation and capabilities, then writes `accept` or `accept-idle`. The script then runs
  `exec herdr --session S remote-client-bridge [--idle-timeout-v1]`. **The same bincode stream
  runs over ssh stdio.** The bridge starts the remote daemon if needed. Disconnecting only detaches.
- It never prompts for passwords. MFA hosts need a user-configured `ControlMaster auto`.
- **All hosts connect at once**. The selected host has an active surface. The others send
  `client_shell.surface.set {"active":false}` and get snapshots only, which feed the cross-host
  Agents list and notifications. The capability `surface_interest` is required for this.
- Port forwarding: `ssh -N` master plus `ssh -O forward -L 127.0.0.1:L:localhost:R`
  (`forward.rs`). File upload goes over separate ssh processes (`upload.rs`).
- "Teleport" moves a worktree, its tabs and its agent sessions to another host. It copies each
  agent's session files (Claude, Codex, OpenCode, Pi, Copilot) and rewrites paths inside them
  (`teleport/sessions.rs`). This is the only place it touches agent JSONL storage.
- There is **no** iroh, relay, Tailscale integration, or remote agent of its own.

## 7. Mobile, push, chat

- **Mobile**: none. No iOS target, no pairing or QR, no relay, no auth or crypto beyond SSH.
- **Notifications**: the source is herdr's `SemanticNotification` (`NeedsAttention` /
  `Finished` / `UpdateInstalled` / `Custom`) from every connected endpoint. The app uses the
  TUI's timing rules: delayed attention needs a Blocked agent, and Finished needs projected Done.
  Finished is suppressed for the active tab while the window is focused. It shows in-app toasts
  and posts local OS notifications through GPUI (`UNUserNotificationCenter` on macOS,
  `window/system_notifications.rs`). A click routes back through boot-fenced navigation. Sounds
  play through rodio using herdr's MP3s. There is **no remote push (no APNs)**.
- **Chat view**: **none**. Agent output is shown only as terminal cells. The nearest thing is
  `agent_notes.rs`, which sends page annotations or review notes to an agent. When the agent is
  `Idle`/`Done`, it sends `ClientPaneInputEvent::Paste(text)` and then, 150 ms later, an `Enter`
  Key event. Delivery is held for up to 120 s while the agent is `Working`/`Blocked`. It never
  types into a `Blocked` prompt, and never into a plain shell (to avoid running the text).
  Otherwise the notes are queued for the agent to pull with `herdr-gpui browser feedback --wait`.
- Approvals and blocked prompts: shown only as status `blocked` (sidebar dot plus a
  NeedsAttention toast). The user answers by typing in the terminal.

## 8. Non-terminal panes (web pages)

- **Browser tabs** (`src/browser/*`): "Herdr panes are always terminals, so these tabs belong to
  this client alone; the daemon and its other clients never see them." They are native WKWebViews
  (wry) drawn above the GPUI window, and hidden while overlays are open. They are stored in
  `browser-tabs.json` as `{id, scope: "local:<socket>"|"<profile-id>", workspace_id, location, title, pane_id?}`.
  They are removed when herdr closes that workspace. They appear in the tab strip next to herdr
  tabs.
- Agents open pages through a **local control socket** owned by the app (`src/control/*`). The
  protocol is one JSON line in and one JSON line out:
  `{"method":"browser.open","page":{"url":"…"},"caller":{"pane_id":"$HERDR_PANE_ID","workspace_id":"$HERDR_WORKSPACE_ID","daemon_socket":"…"},"focus":true}`,
  plus `browser.reload` and `browser.feedback`. The CLI wrapper is `herdr-gpui browser open URL`.
  The app installs a skill (`skills/herdr-gpui-browser/SKILL.md`) into `~/.claude/skills` and
  `~/.agents/skills` so agents know about it. Remote agents cannot reach this socket.
- Other client-only views: the diff/review tab (syntect), PR badges (GitHub), usage meters for
  about 60 providers, and listening ports.
