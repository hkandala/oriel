# Rex as a backend for Oriel

Rex is a terminal multiplexer for macOS and Linux servers by Superlogical. This report asks one question:
can Oriel's UI (machine > session > workspace > tab > pane) run on Rex, and at what cost? The second half
is Rex Server's protocol, as a reference for an adapter. The Rex app itself is in `../clients/rex.md`.

Verdict in one line: Rex fits with an adapter. Two Oriel features have no Rex equivalent: moving a pane to
another workspace, and moving a pane to a new workspace. Everything else maps to one or a few Rex calls.

## 1. Rex's hierarchy and its names

The server's manual ("How Rex Is Organized") names four kinds of things: session, window, block, client.
Layers, splits, creators, flavors and hosts complete the model.

| Rex name | What it is | Source |
|---|---|---|
| host | A Rex server that you reach by a label (`studio`). Each server keeps a host list. A device follows one "home" server for its list. A host has `label`, `endpoints`, `icon`, `host_id`. | `hosts.list`; `rex hosts --help`; `rex home --help` |
| server | One Rex server process. By default one per OS account and machine, on `~/Library/Application Support/rex/server.sock`. `host_id` names the machine and account. `instance_id` names the process. | `server.status`; `rex whoami --json` |
| session | "A group of related work, such as one project." Ordered (`session.move`). Label default is a two-word name (`quiet-meadow`). | "How Rex Is Organized"; `session.create` |
| window | "A tab within a session. It holds a layout of blocks." Ordered. Each session has one `active_window_id`. Default label `Window 89abcdef`. | `session.view`; `session.new_window` |
| layer | A window has one `tiled` layer (the split layout, always first) and zero or more `floating` layers with `bounds` `[x,y,w,h]`. | `session.view`; `session.float_block`, `new_layer`, `raise_layer`, `lower_layer`, `resize_layer`, `close_layer` |
| split | A binary node: `split_id` (stable), `direction` (`horizontal` = before on the left, `vertical` = before on top), `ratio` (share of `before`), `rect` fractions. | `session.view` |
| block | "One application in a window. Today that means a terminal. Rex.app shows a block as a pane." It has a stable id and a label. It can be detached: running, in no window. | "How Rex Is Organized"; `session.detach_block`, `session.new_block` |
| creator, flavor | The plugin that makes blocks, and one way it makes them. Today only `com.superlogical.terminal` with the flavor `com.superlogical.terminal.shell`. `--block-dir` loads more as executable plugins. | `rex block types --json`; `rex server run --help` |
| client | One connected program (Rex.app, the CLI, a script). It survives a dropped connection for 60 s. It can own blocks. | "Reconnecting"; `client.list` |

Rex.app's sidebar shows host > session > tab rows (`../clients/rex.md`).
Rex's agent guide maps the user's words the same way: "Session, workspace" = session, "Tab" = window,
"Pane, terminal" = block (`rex __internal skill`, "Use Rex terminology").

## 2. How Rex's levels map to Oriel's

| Oriel | Rex | Fit |
|---|---|---|
| machine | host (one machine and account) | Good. Rex's host list even has a label and an icon. Oriel can keep its own machine list and ignore Rex's. |
| session (a herdr server: `default`, `work`) | the server | Weak. Rex runs one server per account. A second server needs its own `--listen` socket and `--state-dir`, and Rex.app does not see it. So `sessions()` returns one entry. The Open Session panel has nothing to list. |
| workspace | session | Good: ordered, labeled, created and destroyed by the API. No git or worktree data. |
| tab | window | Good: ordered, labeled, active window per session. |
| pane | block | Good: a stable id that survives moves between windows. `Pane.id == Pane.terminalID`. |
| split tree with ratios | the tiled layer's `layout` | Very good. Binary splits, ratios, stable split ids, precomputed rects. `horizontal` = `.right`, `vertical` = `.down`. |

What Rex has that Oriel does not:

- Floating layers. A block that a Rex.app user floats leaves the tiled layout. If Oriel draws only the
  tiled layout, that pane disappears from Oriel's strip. A window can even have an empty tiled layout
  (`layout: null`) and only floating blocks (`session.float_block` notes).
- Detached blocks. They run but are in no window. `session.view` leaves them out; only
  `session.list_blocks` shows them (`placement: "detached"`).
- Server-side zoom (`zoomed_block_id`). Oriel keeps zoom its own, which still works: Oriel ignores the flag
  and draws the full layout, as it does for herdr.
- Blocks from other hosts. Each block and creator has a `host_id`. The manual says: "If it equals your
  local server's host_id, the block sees the same files you do. Otherwise treat the block as remote."
  Guess: Rex plans sessions that mix blocks from several machines. Oriel's model has one machine per
  session.
- Non-terminal blocks. Only terminals exist today, but `--block-dir` plugins can add creators. Oriel
  needs a rule for a block whose `creator_name` is not `com.superlogical.terminal`: show a card with no
  terminal.

What Oriel has that Rex does not:

- No level between machine and workspace. Oriel's "session" page becomes "the one server".
- No git or worktree data, and no linked-worktree groups.
- No cross-session move. A block can move only inside its session (tested, see §3).
- No agent detection. Status comes only from programs that report OSC 7501.
- No absolute scroll position on a shared viewport (herdr's `pane.scroll`).

Oriel's strip of cards mirrors a split tree with 8 pt gaps (`docs/content/docs/layout.mdx`, "Drawing and
resizing"). Rex's tiled layout is the same kind of tree, so the strip draws it with no change.

## 3. Create, split, move, swap, resize, rename, close

| Action | Rex call | Tested result |
|---|---|---|
| new workspace | `session.create {label, initial_windows: [{window_label, layout}]}`, then `session.attach` | returns `session_id` and block ids |
| new tab | `session.new_window {session_id, window_label, layout, focus: false}` | `focus` defaults to true |
| split | `session.new_split {anchor_id, direction, side, ratio, layout, focus: false}` | a nested layout and a ratio in one call worked (0.3 and an inner vertical split) |
| divider | `session.resize_pane {direction, before_block_id, after_block_id, ratio}` | the server picks the innermost split between the two blocks; they need not touch. Always raises `revision` |
| swap | `session.swap_blocks {block_id, other_block_id}` | works across windows of one session |
| move beside a block | `session.move_block {block_id, anchor_block_id, direction, side, ratio}` | works across windows of one session; returns `created_split_id`, `removed_split_id` |
| move to another session | none | `move_block` and `swap_blocks` with a block of another session fail: `not_found` "block … not found in any window" |
| move to a new tab | no direct call | worked as three calls: `new_window` with a placeholder shell, `move_block` beside it, `block.close` the placeholder |
| reorder tabs | `session.move_window {window_id, before_window_id}` | |
| reorder workspaces | `session.move {session_id, before_session_id}` | |
| rename | `session.set_label`, `session.set_window_label`, `session.set_block_label` | tested; see labels below |
| close | `block.close`, `session.close_window`, `session.destroy` | `block.close {keep_last: true}` refuses to close a window's last block |
| zoom | `session.zoom_block {window_id, zoom}` | with `window_id`, focus does not move. Tested |

Labels: a block always has a label. A new block is `shell` (the flavor's short name). A block label set
with no `label` goes back to `Block fba33045`, not to "no label" (tested). Oriel's "a nil label clears it"
(`Multiplexer.swift:52`) needs the adapter to treat both default forms as "no label".

Focus side effects (manual notes, not all tested): `swap_blocks` and `move_block` move the session's focus
and active window when the block had focus. Rex.app follows that shared focus. Oriel cannot avoid it for
those two calls, the same as herdr's `pane.swap`.

## 5. Verdict

Rex fits with an adapter. The adapter does these things on its own:

1. It shows one Oriel session per machine (the server) and names it, for example "Rex".
2. It treats the block labels `shell` and `Block xxxxxxxx` as "no label".
3. It computes the neighbor of a pane from the view's `rect` fractions. Rex has no read-only neighbor
   call (`session.focus_direction` moves focus).
4. It finds the split for `resize(heading, amount)` and `setRatio(path)` in the view tree, and sends
   `resize_pane` with one block from each side and the new absolute ratio.
5. It makes "move to a new tab" from three calls with a placeholder shell.
6. It refuses moves to another workspace and to a new workspace. The UI must not offer those drop targets
   for Rex.
7. It keeps a "seen" marker per block, record id and `updated_at`, because Rex has no `completion_seq`.
8. It reads title, process and program status per block at snapshot time, and keeps them up to date
   from block events.
9. It translates logical keys (`ctrl+c`, `enter`) into Rex key objects (W3C code in snake_case, `mods`).
   The CLI does this in `rex send-key`, but the API takes only key objects.
10. It handles stale owners: it compares `owner` with `client.list`, and uses `mode: "take"` when the
   owner is not a live client.
11. It fans one data stream out to every Oriel window that shows the block, or it opens one Rex client per
   window. One client cannot open two streams for one block.

### Multiplexer.swift, method by method

| Method (`Multiplexer.swift`) | Rex | Status |
|---|---|---|
| `sessions()` | `server.status` | Adapter: one entry |
| `snapshot()` | `session.view` per session, plus `title`, `process`, `program_status` per block | Yes |
| `updates()` | control events; read the view when `revision` is higher | Yes |
| `refresh()` | `session.view` | Yes |
| `startServer(within:)` | `rex server start`, then wait for `server.status` | Yes |
| `pane(_:)` | `describe_block`, `process`, `title` | Yes. `scroll` stays nil |
| `program(_:)` | `process.foreground` | Yes. `script` given; no argv |
| `terminal(_:cols:rows:observe:takeover:)` | `data.connect`, `own_block`, `terminal.resize` | Yes, but `TerminalStream` is herdr NDJSON frames today. It needs a new shape |
| `screen(_:)` | `format text`, last `rows` lines | Adapter: no visible-only option |
| `recent(_:lines:)` | `format text`, last N lines | Yes, up to 1 MiB |
| `scroll(_:offsetFromBottom:)` | none | No. Scroll the local surface instead |
| `neighbor(of:_:)` | rects from the view | Adapter |
| `split(_:_:)` | `new_split {focus: false}` | Yes |
| `swap(_:_:)` heading | neighbor from rects, then `swap_blocks` | Adapter |
| `swap(_:with:)` | `swap_blocks` | Yes, also across tabs |
| `resize(_:_:amount:)` | split from the tree, then `resize_pane` | Adapter |
| `setRatio(tab:path:ratio:)` | split at the path, then `resize_pane` | Adapter |
| `move(pane:to:)` `.tab` | `move_block` beside the target or the tab's focused block | Yes, same workspace only |
| `move(pane:to:)` `.newTab` | placeholder `new_window`, `move_block`, `block.close` | Adapter, same workspace only |
| `move(pane:to:)` `.newWorkspace` | none | No |
| `rename(pane:label:)` | `set_block_label` | Yes. nil gives `Block xxxxxxxx` |
| `newTab(workspace:cwd:)` | `new_window {layout.block.options.cwd, focus: false}` | Yes |
| `newWorkspace(label:cwd:)` | `session.create`, then `session.attach` | Yes |
| `rename(workspace:label:)` | `session.set_label` | Yes |
| `move(workspaces:before:)` | `session.move`, one call per workspace | Yes |
| `close(workspace:group:)` | `session.destroy` | Yes. `group` has no meaning |
| `close(pane:)` | `block.close` | Yes |
| `close(tab:)` | `session.close_window` | Yes |
| `rename(tab:label:)` | `session.set_window_label` | Yes |
| `move(tab:to:)` | `move_window {before_window_id}` | Yes |
| `sendKeys(_:pane:)` | `client.key`, one per key | Adapter: key name table |
| `sendInput(_:keys:pane:)` | `client.action terminal.write`, then `client.key` | Yes, in order |

Count: 32 rows for 30 members (`move(pane:to:)` has three rows). 22 work directly, 8 need adapter code,
and 2 cannot work (`scroll`, `.newWorkspace`). `.tab` and `.newTab` also fail when the target is another
workspace.

## Rex Server protocol

### 1. Object model

| Rex | Meaning | Oriel / herdr analogue |
|---|---|---|
| server (host) | one Rex server per user account and machine (`host_id` = machine+account; `instance_id` = process) | herdr *session* (one server) |
| session | a group of work, for example a project, ordered (`session.move`) | herdr workspace |
| window | a tab in a session, ordered. Each session has an `active_window_id` | herdr tab |
| layer | `tiled` (the layout, always first) or `floating` (`bounds` `[x,y,w,h]` fractions) | none (herdr has no floating panes) |
| block | one app instance. Today only terminals (`com.superlogical.terminal`, flavor `.shell`). It can be detached (running, in no window) | herdr pane *and* terminal |
| split | binary node: `direction` `horizontal` (before = left) / `vertical` (before = top), `ratio` = the share of before, stable `split_id` | `SplitNode` (`right` = horizontal, `down` = vertical) |
| client | one connection identity (Rex.app, CLI, script). It survives a reconnect for 60 s | the Oriel app instance |
| creator / flavor | a block plugin and its variants (`block_creator.list`); `--block-dir` loads executable plugins | none |

- IDs have the form `<kind>:<uuidv7>`, for example `block:01a16002-2d9d-74ba-b2ea-bfaa10fd61d8`. The kinds
  are `session`, `window`, `block`, `layer`, `split`, `client` and `host`. IDs never change and are never
  reused.
  - Because they are UUIDv7, the creation time is in the first 48 bits.
  - The short ID is the last 6 hex digits (`9f203e`). `target.resolve` accepts 4–32 trailing hex digits.
  - A block keeps its ID when it moves between windows. So `block_id` is Oriel's `terminal_id`, and it is
    also its `pane_id`.
- Labels: at most 128 characters, no control characters, whitespace trimmed, not unique. The defaults are:
  - session: a generated two-word name (`crisp-forest`, `quiet-meadow`)
  - window: `Window 89abcdef` (the last 8 hex digits)
  - new block: the short name of its flavor (`shell`), or `Block 89abcdef` after a reset
  - client: at most 64 bytes, for example `my-mac` (the name of the Mac).
- Focus is shared server state, as in herdr. Each session has an active window, and each window has a
  `focused_block_id` and an optional `zoomed_block_id`. Rex.app follows it.
- Revision: each session has a `revision`. It goes up by one for every change that shows in
  `session.view`.
- Limits: 64 sessions, 1024 blocks, 64 windows per session, 64 panes per window. The app starts the server
  with flags for these values, and they are also the defaults.

`session.view` output (observed, trimmed):
```json
{"revision":1,"session_id":"session:01a16002-…","label":"oriel-dev-a","active_window_id":"window:…",
 "windows":[{"window_id":"window:…","label":"Window d984af59","focused_block_id":"block:…",
   "layers":[{"layer_id":"layer:…","kind":"tiled","bounds":[0,0,1,1],
     "layout":{"rect":[0,0,1,1],"block_id":"block:…"},   // or {"rect":…, "split":{split_id,direction,ratio,before,after}}
     "blocks":[{"block_id":"block:…","label":"shell","creator_name":"com.superlogical.terminal",
                "flavor":"com.superlogical.terminal.shell","host_id":"c4798024-…","owner":"client:…"}]}]}]}
```
`session.list_blocks` adds `placement` (`placed` or `detached`) and `window_id`.

The full view shape is the render tree that a client draws:

`view{revision, session_id, label, active_window_id, windows[{window_id, label, focused_block_id, zoomed_block_id, layers[{layer_id, kind:"tiled"|"floating", bounds:[x,y,w,h] fractions, layout:{rect:[x,y,w,h], block_id | split:{split_id, direction:"horizontal"|"vertical", ratio, before, after}}, blocks[{block_id,label,creator_name,flavor,host_id,owner}]}]}]}`

- Windows are tabs, in order.
- Layers go from back to front. The first one is the tiled layer.
- Floating layers are blocks drawn above the layout.
- A zoomed block is drawn over the whole window.
- Rects are precomputed fractions, so the client does no layout math.

### 2. Endpoints, transports and auth

- Local endpoint: `unix:///Users/<u>/Library/Application%20Support/rex/server.sock`, mode 0600.
  - The same folder holds `host-id` and `servers/<sha>/runtime.json`
    (`{"endpoint","pid","instance_id"}`) with `start.lock`.
  - It also holds `terminal/<pid>/<uuid>.snap`: "parked" terminal snapshots, sealed with an in-memory key
    (magic `REXSEAL`).
  - Terminals get `REX_SERVER`, `REX_SESSION`, `REX_BLOCK` and `REX_BIN_DIR`. They also get
    `TERM=xterm-256color` (or `xterm-rex` after `rex terminfo setup`), `COLORTERM=truecolor`,
    `TERM_PROGRAM=rex` and `TERM_PROGRAM_VERSION=<ver>`.
- HTTP routes:

  | Route | Serves |
  |---|---|
  | `GET /api/control` | control WebSocket |
  | `GET /api/data` | data WebSocket |
  | `GET /api/help` | JSON |
  | `GET /llms.txt` | Markdown |
  | `GET /llms.html` | HTML |
  | anything else | 404 |

  Over a Unix socket any `Host` works.
- Server launch (by the app):
  ```
  rex server run --listen unix://…/server.sock \
      --websocket-origin-pattern https://rex.superlogical.com \
      --log-max-size 50MiB --max-sessions 64 --max-blocks 1024 --max-windows 64 --max-panes 64 \
      --log-format text
  ```
  - `rex server start` is the idempotent detached form. The CLI starts a missing local server by itself by
    default.
  - `rex server logs --follow` tails the log. The app runs the server (pid 82856 at the time).
  - `--websocket-origin-pattern` lets the hosted web client (`https://rex.superlogical.com`, the app's
    "Open Session on Web…") open browser WebSockets from another origin (Rex's hosted web client).
- Listeners (`--listen` / `--extra-listen`):
  - `unix://…` (Unix socket)
  - `http` / `:7297`, which needs `--allow-anonymous`: no auth, full access
  - `tailnet://:7297`, identified by the machine's tailscaled
  - `tailnet-serve:///run/rex/serve.sock`, behind `tailscale serve`
  - built-in tsnet (`--tailscale`, device `rex`, `https://rex.<tailnet>.ts.net`)
  - `login-server`.

  Related flags: `--tailnet-allow-identified` and `--tailscale-allow-tailnet-members`. The welcome can
  advertise extra `carriers` (`[{carrier:"quic", port, alpn:[…]}]`): other transports to the same server,
  presumably QUIC for native clients. We saw none over the Unix socket.
- Client endpoints (`-S`):
  - `unix://…`, `https://host[:port]` and `http://host:port`
  - `user@host` (or `https://root@host`), which picks an account on a login server
  - a bare host, which tries `https://host:443`, then `https://host:7297`, then `http://host:7297`
  - a host label from `rex hosts`.

  `ssh://`, `tcp://` and `ws://` are rejected: "unsupported server endpoint scheme". There is no SSH
  transport. The docs say that SSH-key auth is planned.
- Auth depends only on how a caller connects. Each client has a `principal`:
  - `peer`: uid, gid and pid from Unix socket credentials. Oriel uses this kind locally. Live example:
    `{"kind":"peer","transport":"unix","display":"uid 501","uid":501,"gid":20,"pid":82374}`.
  - `tailscale`: `user_id`, `login_name`, `node`, `tags`.
  - `windows_peer`: a Windows SID.
  - `anonymous`.

  `principal.path` records the route, such as `login-server` or `tailnet-serve`. These methods are refused
  (403) over anything but the local socket: `server.stop`, `server.config_reload`, `server.tailscale.*` and
  `server.apple.grant_file_access`.
- Origin check: the only gate for a browser is the WebSocket `Origin` check (`--websocket-origin-pattern`,
  done by the coder/websocket library). Live test:

  | Origin header | Result |
  |---|---|
  | `https://rex.superlogical.com` | `101 Switching Protocols`, `Sec-WebSocket-Protocol: rex.control.v1` |
  | `https://evil.example.com` | `403`, body `request Origin "evil.example.com" is not authorized for Host "localhost"` (coder/websocket `authenticateOrigin`) |
  | none (native client or CLI) | `101` |

  `/api/help` and `/llms.*` send no `Access-Control-Allow-Origin` header, and `OPTIONS` returns 405. So a
  browser cannot fetch them from another origin.
- Login server (`rex login-server`, runs as root): it maps callers to OS accounts through
  `/etc/rex/accounts.jsonc` (HuJSON) and PAM. It starts or reuses one server per account and proxies the
  connection to it.
- Hosts and home:
  - Each server keeps a host list: `hosts.list`, `hosts.put` and `hosts.remove`, plus `rex.host{}` in
    `init.lua`. A change sends `hosts_changed {hash}`.
  - A device follows one "home" server for its host list (`home.json`, `REX_HOME`).
  - `rex hosts check` probes whether each host answers.

### 3. Control connection (`/api/control`, `rex.control.v1`)

Observed handshake (our client, and a raw WebSocket test through `nc -U`):
```
→ GET /api/control  Upgrade: websocket  Sec-WebSocket-Protocol: rex.control.v1
← 101  Sec-Websocket-Protocol: rex.control.v1
→ {"type":"hello","api_revision":4,"client":{"kind":"other","platform":"macos","name":"oriel","version":"0","label":"…"}}
← {"type":"welcome","protocol":"rex.control.v1","limits":{"max_message_bytes":1048576},
   "client":{"id":"client:01a16003-…","reconnect_token":"KWBblu1fkBCz_gHqy31bMA"},
   "api_revision":4,"api_server_revision":4}
→ {"type":"request","id":"1","method":"session.list"}
← {"type":"response","id":"1","seq":0,"payload":{"sessions":[{"session_id":"session:…","label":"crisp-forest"},…]}}
← {"type":"event","seq":1,"payload":{"type":"session_event","payload":{"session_id":"session:…",
     "event":{"type":"block_created","payload":{"block_id":"block:…"}}}}}
error: {"type":"response","id":"2","seq":0,"error":{"code":"not_found","message":"block not found","status":404}}
```

The full shapes, from the server's manual:
```json
→ {"type":"hello","api_revision":4,"api_min_revision":0,
   "client":{"kind":"app|cli|agent|other","platform":"macos|ios|linux|windows|web|other",
             "name":"Rex Beta","version":"0.1.0 (1327)","label":"my-mac"},
   "reconnect_token":"<from last welcome, optional>"}
← {"type":"welcome","protocol":"rex.control.v1","limits":{"max_message_bytes":1048576},
   "client":{"id":"client:01a16009-…","reconnect_token":"o886HaVLgm59a5w2ZHRYNA","resumed":false},
   "api_revision":4,"api_server_revision":4,"api_min_revision":0,"features":[…],"carriers":[…]}
→ {"type":"request","id":"1","method":"session.create","payload":{…}}
← {"type":"response","id":"1","seq":0,"payload":{…}}  |  {"…","error":{"code":"not_found","message":"…","status":404}}
← {"type":"event","seq":N,"payload":{"type":"session_event","payload":{"session_id":"…","event":{"type":"block_event","payload":{"block_id":"…","creator_name":"com.superlogical.terminal","name":"size_changed","payload":{…}}}}}}
```

Frames: each WebSocket text frame holds one JSON object. A binary frame closes the connection with 1003.
Invalid UTF-8 closes it with 1007. The server offers `permessage-deflate` without context takeover.

Hello rules. Send the hello within 5 s. If you do not, the server drops the connection with no close
frame (the client sees 1006). Keep the hello under 512 bytes and do not compress it, because it can carry a
secret. Fields:

| Field | Values |
|---|---|
| `client.kind` | `app`, `cli`, `agent`, `other` |
| `client.platform` | `macos`, `ios`, `linux`, `windows`, `web`, `other` |
| `client.name`, `client.version`, `client.label` | free text |
| `api_revision`, `api_min_revision` | integers |
| `reconnect_token` | from the last welcome, to resume a client |

The server translates older revisions. The packages for the revision history are `r0001_split_anchor`,
`r0002_status_revisions`, `r0003_terminal_modes` and `r0004_server_stop`.

The real Rex.app identifies itself as
`{"kind":"app","platform":"macos","name":"Rex Beta","version":"0.1.0 (1327)","label":"my-mac"}`. It
also keeps a second connection with no client info. Its request ids look like `rex-app-<n>` (app string
`{"type":"request","id":"rex-app-…","method":"block.event","payload":`).

Requests.
- `id` is any non-empty string that is unique among the requests in flight. A reused id closes the
  connection.
- Responses can come out of order. These ordered methods run one at a time per connection, in arrival
  order:

  > `block.close`, `block.event`, `client.action`, `client.key`, `session.close_layer`,
  > `session.close_window`, `session.detach_block`, `session.disown_block`, `session.float_block`,
  > `session.focus_*`, `session.move_block`, `session.move_window`, `session.new_layer`, `session.new_split`,
  > `session.new_window`, `session.own_block`, `session.swap_blocks`, `session.zoom_block`

  Block methods (including `terminal.write`) are not ordered. To keep typed text in order with keys, send it
  as `client.action {action:"com.superlogical.terminal.write", args:{data}}`. The other way is to wait for
  the previous response before you send the next request.

Errors. Each error has `code`, `message` and `status`:

| `code` | `status` |
|---|---|
| `bad_request` | 400 |
| `not_found` | 404 |
| `method_not_found` | 404 |
| `session_not_found` | 404 |
| `conflict` | 409 |
| `not_supported` | 400 |
| `refused` | 403 |
| `client_unavailable` | 409 |
| `too_large` | 413 |
| `revision_too_low` | 400 |
| `timeout` | 504 |
| `internal` | 500 |

Branch on `code`. If you do not know a code, fall back to `status`.

Attachment. A connection must attach before it can use a session:
- `session.attach {session_id}` returns `{client_id, view}`. It makes the connection a session client, so it
  shows in `session.list_clients` and gets every session event, including `block_event`. Only this kind of
  attachment allows `data.connect`, `own_block` and `disown_block`.
- `session.attach_all {event_scope: session|all}` returns `{sessions}`. It allows server-wide events and
  calls on every session, but no data and no ownership.
- `session.bootstrap {event_scope, preferred_session_id?, attach_session_ids?}` does both in one call. An app
  makes it the first request. It returns `{client_id, server_status, attach_all:{sessions}, selected_session
  | attached_sessions}`.
  - `server_status` holds pid, instance_id, host_id, tailscale `{state, dns_name, https{state,url}, …}` and
    config `{generation, hash}`.
  - `selected_session` is `{session, view}`.
  - Without `attach_session_ids`, the server attaches one session of its own choice.

Event scope.

| Attachment | Events received |
|---|---|
| none | `keymap_changed`, `hosts_changed`, `client_call_requested`, `client_perform_requested` |
| `attach` | every event of that session |
| `attach_all` with scope `session` | `session_created`, `session_destroyed`, `session_moved`, `tailscale_status_changed`, and every session event except `block_event` |
| `attach_all` with scope `all` | also `block_event` from every session and the client directory events: `client_joined`, `client_left`, `client_changed`, `client_performed`, `client_script_events_dropped` |

With scope `session`, block events still arrive for sessions attached with `attach` or `bootstrap`.

Ordering.
- Event `seq` starts at 1 per connection, with no gaps.
- `response.seq` is the last event queued before the request started. Apply the result first. Then apply
  only the events with a higher `seq`, and drop the events with `seq` ≤ the response's `seq`.
- `session_view_changed` carries only `{revision}`, and it can arrive out of revision order. Read
  `session.view` again only when the event's revision is higher than the one you hold.
- `window_created`, `window_closed`, `window_label_changed`, `active_window_changed` and
  `session_label_changed` arrive *before* the matching `session_view_changed`.

Liveness.
- The server pings every 30 s and waits 15 s for each pong. After 2 missed pongs it closes with 1001
  `keepalive timeout`.
- If more than 8 MiB of events back up, it closes with 1008 `event backlog exceeded`.
- A request over 1 MiB, or an event over 1 MiB, closes the connection with 1009 (`event exceeds message
  limit`).
- If a connection drops without a close frame, the server keeps its client for 60 s: still attached, with
  the same id. Resume with `reconnect_token` in a new hello to get `resumed:true`. Events from the gap are
  lost and `seq` restarts at 1.
- A close frame, or a client with nothing attached and no script, ends the client at once.
- Close codes:

  | Code | Reason |
  |---|---|
  | 1002 | protocol error: bad subprotocol, first message not a hello, bad JSON, or a reused id |
  | 1003 | binary message |
  | 1007 | invalid UTF-8 |
  | 1008 | no common API revision (also `event backlog exceeded`) |
  | 1009 | message too large |

Timing. A direct request takes about 0.3 ms on the server, according to the log. `rex api call`, which
starts the CLI as a new process, takes 83 ms median and 129 ms p90 (measured).

### 4. Events (shapes observed)

The outer message is `{"type":"event","seq":N,"payload":{"type":"session_event","payload":{"session_id":…,"event":{"type":…,"payload":…}}}}`.
`rex events --json` prints the inner `payload` object, one per line. Without `--json` it prints one line
per event for people, for example
`13:00:17  block_owner_changed  …32c397  owner none previous …822784 reason disconnect`.

Session events:

| Event | Payload |
|---|---|
| `block_created` | `{block_id}` |
| `block_closed` | `{block_id}` |
| `block_owner_changed` | `{block_id, owner?, previous?, reason: create\|take\|request\|disown\|lost\|disconnect\|restore}` |
| `window_created` | `{window_id, label}` |
| `window_closed` | `{window_id}` |
| `window_label_changed` | `{window_id, label}` |
| `active_window_changed` | `{window_id?}` |
| `session_label_changed` | `{label}` |
| `session_view_changed` | `{revision}` |
| `client_connected` | `{client_id, principal, connected_at}` |
| `client_connection_changed` | `{client_id, principal, connection_state, connection_lost_at}` |
| `client_disconnected` | `{client_id, principal}` |
| `creator_changed` | `{}` |
| `block_event` | `{block_id, creator_name, name, payload}` |

Server events:

| Event | Payload |
|---|---|
| `session_created` | `{session:{session_id,label}}` |
| `session_destroyed` | `{session_id}` |
| `session_moved` | `{session_id, before_session_id?}` |
| `keymap_changed` | `{generation, hash}` |
| `hosts_changed` | `{hash}` |
| `tailscale_status_changed` | full status |
| `client_joined`, `client_changed` | `{client}` |
| `client_left` | `{client_id}` |
| `client_performed` | `{client_id, action, requester, outcome, error?}` |
| `client_script_events_dropped` | (client directory event) |
| `client_call_requested`, `client_perform_requested` | requests to this client; answer with `client.reply` |

Terminal block events (the `name` field; the schemas come from `block_creator.list`):

| `name` | Payload | Observed trigger |
|---|---|---|
| `bell` | `{}` (coalesced) | `printf '\a'` |
| `title_changed` | `{title, owner?:{pid,name}}` (coalesced) | OSC 0/2 |
| `pwd_changed` | `{pwd, owner?}` (coalesced) | OSC 7 → `file://host/tmp`, also OSC 9 / OSC 1337 |
| `process_changed` | `{generation, foreground{pid,user_id,user,name,path,invoked_path,argv0,script,cwd}, ancestors?}` | each foreground change, cd, program start, and each new data connection |
| `child_exited` | `{exit_code, error?}` | `exit 3` → `{"exit_code":3,"error":"exit status 3"}` |
| `program_status_changed` | `{id, record, reason:"report"}` | OSC 7501 |
| `program_status_removed` | `{ids, reason: clear\|child_exited\|reset\|prompt\|evicted}` | |
| `progress_report` | `{state: set\|indeterminate\|pause\|error\|remove, progress?}` | OSC 9;4 → `{"state":"set","progress":55}` |
| `desktop_notification` | `{title, body}` | OSC 9 → `{"title":"","body":"hello notif"}`; OSC 777 → `{"title":"T","body":"B"}` |
| `clipboard_written` | `{text?, id, bytes}` | OSC 52 → `{"text":"copied text","id":1,"bytes":11}`; read big copies with `clipboard_read` |
| `selection_copied` | `{text}` | a mouse selection made on the server (§6) |
| `size_changed` | `{columns, rows, cell_width_px, cell_height_px, owner, principal?}` | |
| `url_clicked` | `{url}` | the server never opens links |

Example sequence for `rex window new … -- sh -c 'sleep 1; exit 0'`: `block_created` → `block_owner_changed`
(create) → `process_changed` (gen 1, foreground null) → `window_created` → `session_view_changed` 11 → the
CLI exits → `block_owner_changed` (disconnect) → `session_view_changed` 12 → `process_changed` →
`child_exited {exit_code:0}` → `block_closed` → `window_closed` → `session_view_changed` 13.

A second live sequence (`oriel-dev-web`): printing
`OSC 7501;state=working:app=demo:progress=40:msg=<b64>` produced `program_status_changed` with
`{state:"working",progress:40,app:"demo",effective_app:"demo",msg:"Building the thing",owner:{pid:955,name:"zsh"}}`.
Then came `title_changed{"oriel title"}`, `bell{}` and `process_changed` (cwd `/private/tmp`). A later
`blocked/kind=permission` report replaced the root record. `exit` produced
`program_status_removed{ids:[""],reason:"child_exited"}`, then `child_exited{0}`, then `block_closed`,
`window_closed` and `session_view_changed`.

### 5. Data connection and terminal streaming (`/api/data`, `rex.data.terminal.v1`)

1. Get a ticket. The control connection must be attached with `session.attach` or `bootstrap`.
   `attach_all` is not enough.
   ```
   data.connect {session_id, block_id, data_ref_id:"terminal", subprotocol:"rex.data.terminal.v1"}
     → {"ticket":"MLk6BuVI0lOPBNAHcqTMDw","expires_in_ms":60000}
   ```
   The ticket is 16 bytes, base64url without padding. It works once, within 60 s, and only for the same
   principal.
2. Open the WebSocket: `GET /api/data` with the same subprotocol, never compressed. Within 5 s, send a
   binary HELLO.
3. Handshake messages (little-endian):

   | Message | Bytes |
   |---|---|
   | HELLO | `01` + 16 ticket bytes |
   | RESUME | `02` + 16-byte token + u64 count of stream bytes received |
   | WELCOME | `81` + 16-byte reconnect token + `00 00 00` + u32 keep-ms + u64 nonce (≠ 0), always 32 bytes |
   | REJECT | `82` + reason byte |

   As a formula: WELCOME = `0x81 ‖ reconnect_token[16] ‖ 000000 ‖ u32le resume_grace_ms ‖ u64le channel_nonce`.

   Observed WELCOMEs:
   - `81 0837d31c…d449 000000 60ea0000 (60000 ms) 61dca79ed46e4c0f` → nonce 1102377868272852065.
   - `81 2deeaa2f7deef17e4d5755e10868c40e 000000 60ea0000 (=60000) dd2826898b40d674` → nonce
     8418987521461332189.

   A REJECT is followed by close 1008 `data handshake rejected`. REJECT reasons:

   | Reason | Meaning |
   |---|---|
   | 01 | bad, expired, used or foreign ticket |
   | 02 | this client already streams this block. Use RESUME instead. Observed: a second HELLO from the same client gave `8202`, then close 1008 (`0x03f0`) `data handshake rejected` |
   | 03 | stream unavailable, or a RESUME counted too few bytes |
   | 04 | limit reached |
   | 05 | malformed handshake, too late, or a RESUME counted too many bytes |
   | 06 | server error |
   | 07 | wrong subprotocol |

4. The stream: every later binary message (1–65536 bytes) is a slice of one byte stream. Message
   boundaries mean nothing. The stream has three parts in order.

   a. The GHOSTSNP snapshot. It is libghostty-vt's native format (upstream `include/ghostty/vt/snapshot.h`,
   `src/terminal/snapshot/`, and ghostty discussions #14185 and #14186). Upstream says "format v1 is a work
   in progress, no binary-compatibility guarantee". The Rex binary links `ghostty_snapshot_decoder_*` and
   `ghostty_go_snapshot_encode*`.
      - A 10-byte header: `"GHOSTSNP"` + u16 version (1).
      - Then records, each `[u16 tag][u32 len][u32 crc32c(tag‖len‖payload)][payload]`. Verified: the CRC32C
        covers the first 6 header bytes plus the payload. In one capture the first bytes after the magic
        were `u16 1, u16 1, u32 len=924`: version 1, then a TERMINAL record of 924 bytes.
      - Observed record order and tags:

        | Tag | Record |
        |---|---|
        | 1 | TERMINAL (cols, rows, modes, 256-color palette …) |
        | 2 | SCREEN manifest, one per screen |
        | 3 | PAGE, one per active page |
        | 7 | CONTINUATION (unfinished VT input, empty at ground) |
        | 5 | READY (empty: the renderable prefix ends here) |
        | 4 | HISTORY manifest |
        | 3 | PAGE × n (scrollback, newest to oldest) |
        | 6 | FINISH (empty) |

      - Size: about 1.5 KB for a fresh 80×24 shell. With 20 000 lines of 50 characters in scrollback it was
        972 392 bytes: 1 active page and 69 history pages, delivered in about 6 ms locally.
      - In one capture the snapshot held cols 100 and rows 30, the palette, the foreground, background and
        cursor colors, and the screen.

   b. Right after the snapshot: a `resize` APC, then a `theme` APC unless every color is the default.

   c. Raw PTY output, byte for byte as the program wrote it, plus Rex APCs at safe points:
      `ESC _ rex1;<nonce decimal>;<json> ESC \`. Ignore an APC whose nonce does not match, because a
      program printed it. Skip APC types that you do not know.
      - `{"type":"resize","cols":163,"rows":47,"cell_width_px":14,"cell_height_px":28,"owner":"client:…"}`.
        A new `resize` arrives on every size change. An owner change alone sends none.
      - `{"type":"theme","foreground":"#e6edf3","background":"#0d1117","cursor":"#2f81f7","palette":["0=#484f58",…,"255=#dce3e9"],"scheme":"dark"}`
        (the owner's theme. Rex.app pushes all 256 entries).
      - `{"type":"child_exited","exit_code":3}`. The stream stays open. It closes with 4000 `block closed`
        when the block closes.
      - Live, from a second capture:
        ```
        ESC_rex1;8418987521461332189;{"type":"resize","cols":100,"rows":30,"cell_width_px":16,"cell_height_px":34,"owner":"client:01a1600a-…"}ESC\
        ESC_rex1;8418987521461332189;{"type":"theme","foreground":"#d6deeb","background":"#011627","cursor":"#80a4c2","palette":["1=#ef5350"],"scheme":"dark"}ESC\
        ESC_rex1;…;{"type":"child_exited","exit_code":0}ESC\
        ```
      - OSC 7501, OSC 2 and BEL stay in the byte stream, so the client's VT sees them. The server also
        parses them into block events (§4).
5. Resume (verified).
   - Drop the socket. The server keeps the stream for 60 s.
   - Send RESUME with the latest token and the exact count of stream bytes consumed.
   - The server answers with a WELCOME that has a new token and the same nonce, then continues exactly where
     you left off. Output written while the client was away (`echo during-drop`, `after-drop`) arrived
     intact.
   - RESUME needs no ticket and no control connection.
   - A close with status 1000 ends the stream. Any other close leaves the stream waiting for a resume.
6. Close codes:

   | Code | Reason |
   |---|---|
   | 1000 | ended |
   | 1001 | keepalive timeout, or `data provider canceled` (the server stopped the stream) |
   | 1008 | `data provider unavailable` |
   | 1011 | provider failed |
   | 1013 | `data reconnect required` (backlog too large. Start again with a new ticket) |
   | 4000 | `block closed`. Do not reconnect |

   The server ignores data from the client after the WELCOME. Input goes through the control connection.
7. To get text without a VT, call `com.superlogical.terminal.format {format:"text"|"html"|"vt", trim,
   unwrap, extra_*}` (§7).
8. CLI: `rex attach SESSION` is a view-only CLI. It decodes the snapshot on the client (package
   `internal/terminalreplay`) and prints a VT replay:
   `ESC[3J ESC[2J ESC[H ESC[?2004h ESC[3g` + tab stops + content + cursor `ESC[3;32H`. Then it pipes the live
   output. It shows only the "oldest visible terminal block" and does not take keys. `rex block stream` and
   `rex block attach` print "not implemented".

Rendering model: the server runs one emulator per block, and the client runs a second copy in sync with it.
- Resize is in-band. The client must resize its emulator when the `resize` APC arrives, so that its reflow
  matches the server's. No forced redraw happens. The program redraws after SIGWINCH.
- Scrollback is the client's own copy, built from the snapshot's history pages plus live output. The server
  keeps its own copy too: `format` returns the full scrollback.

The server answers terminal queries. With no client streaming, `printf '\e[c'` got `ESC[?62;22c` and
`OSC 11 ?` got `rgb:1010/1010/1010`, which is the background set by `set_theme`. So a client emulator must
not answer queries. Oriel still needs its `suppressesTerminalResponses` patch.

### 6. Input, mouse, scrollback, focus, multiple clients

- `client.key {session_id, block_id?, key:{…}, prefix?}` → `{handled}`. `prefix` is a list of keys already
  typed in a sequence, for example `["ctrl+b"]`.
  - Lua bindings in the client's scripts and in `init.lua` get the key first. Anything else goes to the
    block.
  - The key object has these fields:
    - `key`: the W3C `KeyboardEvent.code` in snake_case, 190+ values (`key_a`, `digit_1`, `arrow_up`,
      `enter`, `numpad_enter`, `f1`–`f25`, `copy`, `paste`, `numpad_*` …).
    - `mods`: joined with `+` in the fixed order
      `shift+ctrl+alt+super+caps_lock+num_lock+shift_side+ctrl_side+alt_side+super_side`.
    - `consumed_mods`, `text`, `unshifted_codepoint`, `composing`.
    - `action`: `press`, `release` or `repeat`.
  - The server encodes the key for the program's modes (kitty, modifyOtherKeys) itself.
  - Observed: `arrow_up` → `ESC[A`, `key_x` with text `x` → `x`, `key_c` with `mods:"ctrl"` → SIGINT. `echo
    hi` + `enter` sent key by key printed `hi`.
- `block.event {session_id, block_id, event:{type, payload}}` → `null`. It goes straight to the block (no
  Lua) and is ordered with `client.key`. Clients can send `key`, `paste`, `mouse`, `wheel` and `focus`. The
  shapes are partly inferred from struct tags and confirmed by the encoded output:

  | Event | Payload | Observed output |
  |---|---|---|
  | `key` | the same object as `client.key.key` | `y` |
  | `paste` | `{text}` | bracketed or not, following the program's mode 2004 |
  | `focus` | `{action:"in"\|"out"}` | `ESC[I` / `ESC[O` with mode 1004 on |
  | `mouse` | `{action:"press"\|"release"\|"motion", button:"left"\|"right"\|"middle"\|"four"…"eleven"\|"unknown", buttons:{"left":true}, x:<col>, y:<row>, mods:"shift", pixel?:{x,y}}` | SGR mode: press `ESC[<0;6;4M`, release `…m`, right+shift `ESC[<6;8;3M`, drag `ESC[<32;10;5M` |
  | `wheel` | `{delta_x, delta_y (+ = down), delta_z, delta_mode:"pixel"\|"line"\|"page", x, y, mods, pixel?}` | in mouse mode `ESC[<65;3;3M` (down) / `ESC[<64;…` (up) |

  - `x` and `y` are the cell column and row, counted from 0. `pixel` can be `null`.
  - The server ignores unknown payload fields silently: `{"bogus":1}` returns `{}`. Unknown event types fail
    with `bad_request`.
  - Validation errors seen live: `unknown mouse action "bogus"`, `unknown wheel delta mode "furlong"`,
    `unknown focus action "sideways"` (`bad_request: unknown focus action`).
  - `resize` is not a client event ("not supported by this server").
- Viewport and selection on the server:
  - With no mouse mode, a wheel event scrolls the server's viewport.
  - A press, drag and release with no mouse mode makes a selection on the server and sends
    `selection_copied {"text":"156\n157\n158"}`. The rows came from the scrolled viewport. This proves that
    the viewport is shared server state.
  - Inference: Rex.app selects and scrolls on its own copy and forwards mouse events only when a program asks
    for them. This server path exists for thin clients. A second reading of the app strings
    (`RexSyncTerminal/TerminalInput.swift`) suggests that the app sends mouse, wheel and paste this way and
    that the server's libghostty does the selection, which explains `selection_copied` and
    `url_clicked`. This is not settled (see Open questions).
- Text: `com.superlogical.terminal.write {data}` queues raw bytes to the PTY (not ordered, see §3). For
  ordered text, use `client.action` with that name. The CLI equivalents are `rex send TEXT` and
  `rex send-key ctrl+c shift+left [KeyQ] --action press|release|repeat`. `send-key` spells keys on a US
  layout.
- Ownership and size:
  - `session.own_block {block_ids, mode: take|request}` returns `{blocks:[{block_id, owner}]}`.
    `session.disown_block` gives a claim up.
  - The block follows its owner's `resize` and `set_theme`. A resize or theme applies at once only if the
    caller owns the block or no one owns it. A non-owner's resize goes into `size.desired[]` and changes
    nothing. Observed: the owner was Rex.app at 163×47 (cell 14×28 px, Retina). Our 70×20 request was only
    listed in `desired`.
  - The queue: when the owner leaves, the block goes to the most recent claimant, with any `take` ahead of
    any `request`. An owner that reconnects gets its blocks back (`restore`) unless they changed hands.
    Each change sends `block_owner_changed`.
  - The block's creator becomes its owner (`create`). When a CLI exits, the reason is `disconnect`.
  - Observed: after the creating CLI left, the Rex app became owner of our new session's block without a
    visible `take`. Inference: the app claims the blocks it shows with `request`.
  - A new block starts at 80×24, or at `options.size`, until an owner resizes it.
  - Owning a block gives no other rights. Any attached client can type, stream or close.
  - This is herdr's takeover concept. Map Oriel's `takeover:` flag to `mode:"take"`, and `observe:` to not
    owning.
- Multiple clients: any number of clients can stream one block, but each client can open only one stream
  per block (REJECT 02). All of them see the owner's size, so a smaller watcher must clip or scale.

### 7. Terminal block methods (`com.superlogical.terminal.*`)

Call each method by its full name (or through `block.method {method:"write"}`) with
`{session_id, block_id, args:{…}}`.

| Method | Args → result (observed) |
|---|---|
| `write` | `{data}` → `{bytes_written}` |
| `resize` | `{columns, rows, cell_width_px?, cell_height_px?}` → `{}` |
| `set_theme` | `{foreground, background, cursor, palette:["1=#ef5350"], scheme: light\|dark}` → `{}` |
| `size` | → `{columns, rows, cell_width_px, cell_height_px, owner, desired:[{client_id,columns,rows,updated_at}]}` |
| `format` | `{format: text\|html\|vt, trim, unwrap, extra_charsets, extra_cursor, extra_hyperlink, extra_keyboard, extra_kitty_keyboard, extra_modes, extra_palette, extra_protection, extra_pwd, extra_scrolling_region, extra_style, extra_tabstops}` → `{content}`: screen and scrollback. Fails with `too_large` over 1 MiB. |
| `process` | → `{last_exit, child, foreground, ancestors?, home}`; each process is `{pid,user_id,user,name,path,invoked_path,argv0,script?,cwd}`. Observed `child` = `login` (root); `foreground` = `zsh` with `argv0:"-zsh"`, `cwd:"/private/tmp/rex-re"`. Other arguments are never returned, because they can hold secrets. |
| `pwd` | → `{pwd?, owner?}` (OSC 7 URL or plain path) |
| `title` | → `{title, owner?}` |
| `program_status` | → `{records:[{id?, state, kind?, progress?, app?, effective_app?, title?, msg?, updated_at, owner?}]}` |
| `modes` | → `{screen: primary\|alternate, modes:[{name (Ghostty name), number, ansi?, set, default?}]}` |
| `input_mode` | → `{echo, canonical, signals}` (termios) |
| `list_dir` | `{path, prefix, limit, files}` → `{path, home, status: ok\|missing\|not_dir\|denied, entries:[{name,symlink?,file?}], truncated}` (backs "Go to Directory…" and "Insert Path…") |
| `clipboard_read` | `{id, offset, max_bytes}` → `{id, data, total, eof}` (copies are kept for about 1 minute) |
| `clear` | → `{}`; the `clear` action (Cmd+K / ctrl+L) |
| `reset` | → `{}`; the `reset` action |

Shell flavor options (in `layout.block.options` for `session.new_window`, `new_split`, `new_layer`,
`new_block` and `create`):

| Option | Meaning |
|---|---|
| `shell` | `none` runs the command directly |
| `command` | `[argv]` |
| `args` | deprecated |
| `login` | login shell or not |
| `cwd` | start folder |
| `path_prepend` | `[]` folders to put in front of `PATH` |
| `size` | `{columns, rows, cell_*}` |
| `theme` | `{…}` |
| `initial_input` | text typed once the program starts |
| `exit` | `{on_completion: true, quick_exit_threshold_ms: 250}`: close when the program exits, except after a quick failure |

### 8. Program activity (OSC 7501) and how Rex.app uses it

The full spec is in the public docs (Program Status Protocol, spec revision 0.4, 2026-10-10,
`llms-full.txt` lines 2322–2640).

- Syntax: `OSC 7501 ; key=value:key=value ST`. Values use the charset `[A-Za-z0-9_.,+/=-]`. The keys are:

  | Key | Values |
  |---|---|
  | `state` | `idle`, `working`, `done`, `blocked`, `error`, `clear` |
  | `id` | `a/b/c` path, up to 8 levels of 32 characters each |
  | `kind` | `permission`, `question`, `auth` (only with `blocked`) |
  | `progress` | 0–100. Absent means indeterminate |
  | `app` | a stable program id, for example `claude-code`. Child ids inherit it |
  | `title`, `msg` | base64 UTF-8, no control characters |

- Feature query: `OSC 7501;? ST`. The server's reply was observed:
  `ESC]7501;?:states=idle,working,done,blocked,error:kinds=permission,question,auth ESC\`. The same literal
  reply string is in Rex.app. Spec revision 0.4 removed the terminfo capability (`Pst`); the query is the
  only way to detect support.
- Limits: 4096 B per sequence, `msg` ≤ 2048 B decoded, `title` ≤ 192 B, 256 records per terminal. The
  server's event text says 64 records (`evicted`).
- Records: each report replaces its record. `working` and `blocked` are dropped when the program exits or a
  new prompt starts (OSC 133 A). `done` and `error` survive until the user returns. RIS clears all records.
- Observed: `state=working:app=demo:progress=40:msg=…` gave
  `program_status_changed {"id":"","record":{"state":"working","progress":40,"app":"demo","effective_app":"demo","msg":"Doing it","updated_at":"…","owner":{"pid":34123,"name":"zsh"}},"reason":"report"}`.
  A child record `id=sub/a` inherited `effective_app:"demo"`.
- In `crisp-forest`:
  `{"records":[{"state":"idle","app":"codex","effective_app":"codex","updated_at":"…","owner":{"pid":13129,"name":"codex"}}]}`.
  Codex emits OSC 7501 itself. Rex does no agent detection based on processes.
- `Workspace.programActivitySeen` (app defaults, model file `ProgramActivity+SeenLedger.swift`) has
  `alerted`, `receipts` and `announcements`: arrays of `{block:"block:…", record:"" (record id; root = ""), date}`.
  - Inference: `receipts` is when the user saw a record (focused that block), and `alerted` is when the app
    raised an alert for it. A record is "unseen" if its `updated_at` is later than the receipt date.
  - The docs say: sessions with completed or blocked records get an indicator in the session picker, and
    unfocused tab headers show a spinner or "a variety symbols for blocked states". Lua gets
    `terminal.program_status_changed`. Planned: mobile push and "a unified priority inbox".
  - Rex.app has settings per state (working, waiting for you, finished, errors) for tab indicators, system
    notifications, Dock badges and sounds, and "Include idle processes in activity"
    (`showsIdleProgramsInActivity`). The activity UI is in [../clients/rex.md](../clients/rex.md).
- Other activity sources: `bell`, `desktop_notification` (OSC 9/777), `progress_report` (OSC 9;4) and
  `child_exited`.
- Agents: `rex skill setup` installs a skill plus a session-start hook (Other CLI surface). The server has
  `internal/agentharness`, with the strings `claude`, `codex`, `SubagentStart` and `hooks`. Rex.app has the
  toggles "Let agents name sessions" and "Agent integration".

### 9. Other CLI surface

- `rex capture [-s][-w][-b] --format text|html|vt --trim --unwrap` wraps `format`.
- `rex wait TARGET [--for D] [--json]` returns the exit status of the terminal's child (mod 256), or success
  when a window or session closes. `rex run --wait -- sh -c 'sleep .5; exit 7'` exited with 7.
- `rex run`, `rex split`, `rex window new` and `rex new` take `--split right|left|above|below`,
  `--ratio PCT`, `-c CWD`, `--keep-open`, `--shell`, `--label`, `--focus=false`, `--json` and `--wait`.
  - `rex new --json` → `{session_id, initial_windows:[{window_id, block_ids, revision}]}`.
  - `rex new` does not attach (tmux does). The new shell's cwd is the caller's cwd.
- Other commands: `rex focus`, `zoom --on/--off`, `move`, `swap`, `kill`, `rex session|window|block
  ls|inspect|rename|close …`, `rex client ls|inspect`, `rex events [-s] [--all] [--json]` and `rex whoami`.
  `rex whoami` prints `you: uid 501 over unix, acting as <user>`, plus the endpoint, pid, instance, host,
  version, `exit-empty`, sessions and Tailscale.
- Not implemented (they print "is not implemented"): `rex resize`, `rex block new`, `rex block stream`,
  `rex block attach`.
- `rex terminfo`: Rex ships `xterm-rex`.
  - `rex terminfo setup` installs it in `~/.terminfo` and adds an ssh guard (`~/.config/rex/ssh_config`, an
    Include in `~/.ssh/config`, or `/etc/ssh/ssh_config.d/50-rex.conf`). The guard downgrades TERM for hosts
    that do not have the entry.
  - `rex terminfo host` installs the entry on remote machines.
  - It is not set up here, so terminals get `xterm-256color`.
- `rex skill setup|status|remove|show` installs a skill (`~/.claude/skills/rex`, `~/.agents/skills/rex`)
  and a session-start hook for Claude Code (`settings.json`) and Codex (`hooks.json`). OpenCode and Pi get
  the skill only.
  - The hook runs an internal command (`rex __internal …`, "commands run by the files that rex skill setup
    installs"). It tells the agent its `REX_SESSION` and `REX_BLOCK`, and asks it to name the session after
    its task, "e.g. fix-login-redirect".
- Source tree (565 files, from the file names in the binary's pclntab):
  - `internal/server`, `internal/netapi/control` (dispatch, ordered, websocket), `internal/session`
  - `blocks/terminal/internal/mux/{apc,chunk,park,suspend,compress,queue,resize,theme,client}`
  - `blocks/terminal/internal/sealfile`
  - `internal/terminalreplay`
  - `internal/agentharness/known/{claude,codex,opencode,pi}`
  - `internal/loginserver`, `internal/tailscale`
  - `sdk/{apiclient,apitypes,apihistory,block,blockcmd,blockexec,blockremote,blockserver}`: a public SDK for
    block plugins and clients.
  - Dependencies: coder/websocket, gopher-lua, cobra, tailscale.com v1.102.3,
    `go.mitchellh.com/libghostty` 2026-10-14.

### 10. Actions, `rex do` and Lua

- Three kinds of action:
  - Client actions. Each client provides its own, and `client.inspect` / `rex -C <client> actions` lists
    them. Rex.app has 83, for example `session.select {session_id, window_id?}`, `pane.split {direction}`,
    `pane.resize {direction, amount?}`, `pane.send_key {key}`, `client.tab.goto {index}`,
    `client.mode.enter {name, once?}`, `client.font.*`, `client.theme.change`, `client.palette.toggle`.
  - `init.lua` actions (`rex.action{name,title,run,args,category,keywords,repeats}`).
  - Block actions and methods (`com.superlogical.terminal.clear` / `reset` are actions with fixed args).
- The action IDs in Rex.app (from its string table). A web client is expected to mirror them:
  ```
  client.window.new/.close/.fullscreen.toggle  client.close  client.palette.toggle  client.settings
  client.diagnostics  client.version.copy  client.debug.copy  client.pair_device  client.update.accept
  client.notice.dismiss  client.shortcuts.edit  client.agents.setup  client.appearance.switch_mode
  client.config.copy_path  client.config.reload  client.find.open/.next/.previous  client.font.increase/.decrease/.reset
  client.host.add/.switch/.remove  client.key.forward  client.mode.enter/.exit/.exit_all  client.prompt.next/.previous
  client.sidebar.toggle  client.sidebar.activity.toggle  client.tab_style.toggle  client.theme.change/.import
  client.tab.new/.close/.rename/.next/.previous/.goto/.move.backward/.move.forward/.move_to_new_window
  session.new/.switch/.select/.next/.previous/.rename/.close/.refresh/.open_on_web
  pane.split(.left/.right/.up/.down/.auto)  pane.focus(.left/.right/.up/.down)  pane.focus_next/.focus_previous
  pane.move(.left/.right/.up/.down)  pane.move_to_new_tab  pane.move_to_tab  pane.zoom  pane.close  pane.balance
  pane.resize  pane.send_key  pane.go_to_directory  pane.insert_path
  ```
- API:
  - `client.action {action, args?, session_id?, block_id?, origin?, servers?, server?}` runs a config or
    block action as this client.
  - `client.perform {client_id, action, args, timeout_ms}` asks *another* client, such as Rex.app, to run
    one of its actions. It needs "Remote Control" on in the app. The other client answers through
    `client_perform_requested` → `client.reply`.
- `rex do`: `rex do NAME k=v…`, `rex do script.lua`, `rex do -e 'return rex.call("session.list")'`, or `-`
  for stdin.
  - Options: `--args JSON`, `-s`, `-b`, `--origin key|palette|api|cli`, `--action NAME`, `--all`, `--for D`,
    `--fail-fast`, `--json`.
  - A script with `rex.on` handlers keeps running until `rex.stop(code)`, `--for`, or the destruction of the
    last session it listens to.
  - Tested: `rex do -e 'local v=rex.session.view{}; return {rev=v.revision,n=#v.windows}' -s oriel-dev-a --json`
    → `{"n":1,"rev":13}`.
- Lua 5.1 (gopher-lua) API:
  - Keys and modes: `rex.bind`, `rex.unbind`, `rex.mode`, `rex.bindings`, `rex.modes`.
  - Actions: `rex.action`, `rex.invoke`, `rex.client.queue`.
  - API calls: `rex.session.<method>{}`, `rex.call(method,args)`, `rex.block.call(creator,method,args)`.
  - Layout builders: `rex.layout.block{flavor,options}`, `rex.layout.horizontal(r,a,b)`,
    `rex.layout.vertical(r,a,b)`.
  - Events and waiting: `rex.on`, `rex.wait`, `rex.sleep`, `rex.stop`, `rex.after`, `rex.every`.
  - Commands: `rex.exec`, `rex.exec.start` (`io.popen` and `os.execute` are disabled).
  - Other: `rex.json.encode/decode`, `rex.log`, `rex.host{}`, `rex.servers()`, `rex.server(label)`, and
    `rex.args`, `rex.session_id`, `rex.block_id`.
  - Lua event names: `block_closed`, `com.superlogical.terminal.bell`,
    `terminal.program_status_changed`, ….
  - The public docs have the full table of where each function works (`llms-full.txt` lines 2643–3109).
- Per-client scripts (`client.set_script`) bind keys for one client. Keys bound to Lua functions come back
  from `client.keymap` as `client.key.forward` bindings.

### 11. Configuration (`rex config`) and keymap

- File: `init.lua` at `$XDG_CONFIG_HOME/rex/init.lua` or `~/.config/rex/init.lua`. `REX_CONFIG` in the
  *server's* environment overrides the path. `require` loads files next to it. `rex config check` reports whether it exists and
  how many bindings it has.
  - The server reads the file.
  - `rex config reload` (local socket only) sends `keymap_changed {generation, hash}`.
  - The server does not watch the file.
- What the configuration covers: key bindings, sequences (`ctrl+b>c`), modes (`resize/left`,
  `rex.mode(name, {exclusive})`), custom actions (`rex.action{name,title,description,category,keywords,run}`,
  with `ctx.origin key|palette|cli|api|script`) and hosts (`rex.host{label, endpoints, id, icon}`).
  `init.lua` has no visual settings. Theme, fonts and density are client preferences
  (`defaults read com.superlogical.rex`).
- Key syntax:
  - Modifiers: `cmd`/`super`/`meta`/`win`, `ctrl`/`control`, `alt`/`opt`/`option`, `shift`.
  - Keys follow the keyboard layout. `[KeyA]` names a physical key. Write keys unshifted (`cmd+shift+=`).
  - Sequences use `>`. Escape cancels a sequence.
- Precedence, from bottom to top: the client's `defaults` layer, then `init.lua`, then the client's
  scripts, then the client's `overrides` (shortcuts set in the app). `client.keymap {defaults:[layers],
  overrides:[layers], actions, server_actions}` returns the merged stack with diagnostics, `config.hash` and
  `instance_id`.
- The default keymap ships inside the client, not the server: `rex keymap` prints an empty table. The
  defaults, rebuilt from Rex.app's menus, are in `../clients/rex.md` §13.2.

### 12. The hosted web client (`rex.superlogical.com`)

- It is an internal deployment: every path redirects to Vercel SSO and the Superlogical Okta, so its code was
  not read. The announcement says "Sessions can be accessed through the web and native macOS/iOS
  applications"; the privacy page lists only Rex for Mac, Rex for iOS and the server.
- Rex.app allows it by default. Developer settings → Web Client Origins adds more ("Wildcards match
  subdomains, e.g. https://*.vercel.app"; key `rex.server.web-client-origin-patterns`). The palette has
  "Open Session on Web…" (`session.open_on_web`); its URL format is unknown.
- It speaks the same protocol as Rex.app over the two WebSockets only, because the HTTP endpoints send no
  CORS headers (§2). Inference: it decodes `GHOSTSNP` with libghostty-vt compiled to WASM.
- A local server listens only on its Unix socket, so a browser needs a TCP listener. Inference: it connects to
  `wss://rex.<tailnet>.ts.net/api/control` (Tailscale gives real TLS and the user's identity). A
  `ws://localhost:7297` target also works from an https page, with `--extra-listen :7297 --allow-anonymous`.
- Pairing ("Pair Device with QR Code", `client.pair_device`) requires Tailscale. Inference: the QR code holds
  the tailnet HTTPS URL with no secret, because identity comes from Tailscale.
- Clients: Mac only in public preview (version 0.1.0, minimum macOS 15.0, from
  `https://blob.superlogical.com/public/rex-app/preview/appcast.xml`). Servers exist for Linux and Windows;
  iOS, Linux and Windows clients are in progress. Rex is free and needs no account.

### Open questions

- Mapping choice: server = Oriel session, Rex session = workspace. The other choice (Rex session = Oriel
  session page) removes the workspace level, which Oriel's sidebar needs. Both lose cross-workspace moves,
  because blocks never leave a Rex session.
- Guess: Rex sessions do not survive a server restart. The Linux docs say "A package upgrade restarts the
  service, which automatically ends every session on it" (`linux/server-modes.md`). herdr keeps its layout
  across restarts.
- Rex.app claiming the blocks it shows is inferred, not observed.
- The exact pixel → cell mapping for `mouse.pixel` (40,40 at 9×18 px cells gave column 3, row 2).
- The exact mouse field names beyond `x`, `y`, `pixel`, `button`, `buttons` and `action`. The server
  ignores unknown fields, so the accepted payloads do not prove that it honors `mods`.
- Whether Rex.app forwards mouse events only in mouse mode and keeps selection local, or sends them all and
  lets the server select (§6). The app's `GhosttyVT.SnapshotDecoder` and the `mouse` / `wheel` call sites
  can settle it.
- The app's exact default keymap request (the `defaults` layer in its `client.keymap` call). It is not
  visible from the server. The keymap table in `../clients/rex.md` is partly inferred.
- The URL format behind `session.open_on_web`, and how the hosted web client reaches a local server:
  through Tailscale HTTPS, or through the app ("Pair Device with QR Code…"). The URL needs a decompile of
  the action handler or one observation of the opened URL.
- What the welcome's `features` and `carriers` contain on a Tailscale or TCP listener. We saw neither over
  the Unix socket.
- Whether OSC 133 prompt marks (zsh or fish shell integration) are needed to clear `working` records by
  themselves. With no integration here, records stayed across prompts.
- Whether libghostty-vt's snapshot format stays stable across Rex updates. A version mismatch breaks option
  (a). Option (b) does not depend on it.
