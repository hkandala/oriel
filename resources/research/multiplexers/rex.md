# Rex as a backend for Oriel: model fit

Rex is a terminal multiplexer for macOS (and now Linux servers) by Superlogical. This report asks one
question: can Oriel's UI (machine > session > workspace > tab > pane) run on Rex, and at what cost? It
checks the older Rex research against the current Rex and lists where the design page
`docs/content/docs/rex-backend.mdx` is now wrong or incomplete.

Verdict in one line: Rex fits with an adapter. Two Oriel features have no Rex equivalent: moving a pane to
another workspace, and moving a pane to a new workspace. Everything else maps to one or a few Rex calls.

## How this was gathered

- Version checked: `rex 0.0.1792607779-g171246`, commit `1712469f`, built 2026-10-21, API revision 5
  (`rex --autostart=false version --json`). Rex Beta.app is build 1381 (`CFBundleVersion`). The older
  research used `0.0.1792519967-gd05acf`, API revision 4, app build 1327.
- The binary is at
  `~/Library/Application Support/com.superlogical.rex/RexServer/Versions/Current/Rex Server.app/Contents/MacOS/rex`.
  It is not on `PATH`.
- The user's Rex server was not running (no `server.sock`, no process). I did not start it. Every `rex`
  command used `--autostart=false`, because the CLI starts a missing local server by default
  (`rex --help`: `--autostart  start a missing local server (default true)`).
- All writes went to an isolated server that I started and then stopped:
  `rex server run --listen unix:///tmp/oriel-research-rex/rex.sock --state-dir /tmp/oriel-research-rex/state --config /tmp/oriel-research-rex/init.lua`
  (empty `init.lua`). Its `host_id` differed from the user's, so it shared no state. I deleted the folder
  after the tests.
- Protocol sources: `GET /llms.txt` (309 KB Markdown, "It describes API revision 5") and `GET /api/help`
  (JSON with schemas) from that server. Section names below refer to `llms.txt`. Public docs:
  `https://www.superlogical.com/rex/docs/llms.txt` and the pages under it.
- Live tests: the `rex` CLI (`rex api call`, `rex block types --json`) and a small hand-written WebSocket
  client in Python over the Unix socket (control and data connections). The test client was a throwaway
  file and is not in the repo.
- Revision 5 is only `server.apple.privacy_status`. The binary lists `r0005_privacy_status` after
  `r0004_server_stop` (`strings` on the binary). So the protocol in the older research is still current.

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

Rex.app's sidebar shows host > session > tab rows (`resources/research/clients/rex-internals.md` §3.3).
Rex's agent guide maps the user's words the same way: "Session, workspace" = session, "Tab" = window,
"Pane, terminal" = block (`rex __internal skill`, "Use Rex terminology").

## 2. How Rex's levels map to Oriel's

| Oriel | Rex | Fit |
|---|---|---|
| machine | host (one machine and account) | Good. Rex's host list even has a label and an icon. Oriel can keep its own machine list and ignore Rex's. |
| session (a herdr server: `default`, `pi-herd`) | the server | Weak. Rex runs one server per account. A second server needs its own `--listen` socket and `--state-dir`, and Rex.app does not see it. So `sessions()` returns one entry. The Open Session panel has nothing to list. |
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
- No cross-session move. A block can move only inside its session (tested, see section 3).
- No agent detection. Status comes only from programs that report OSC 7501.
- No absolute scroll position on a shared viewport (herdr's `pane.scroll`).

Oriel's strip of cards mirrors a split tree with 8 pt gaps (`docs/content/docs/layout.mdx`, "Drawing and
resizing"). Rex's tiled layout is the same kind of tree, so the strip draws it with no change.

## 3. The API for a native client

All of this was read in `llms.txt` and tested on the isolated server unless marked.

### Transport

- HTTP/1.1 on a Unix socket. `GET /api/control` is a JSON WebSocket (subprotocol `rex.control.v1`). `GET
  /api/data` is a binary WebSocket per streamed block (`rex.data.terminal.v1`). Tested with a raw client.
- No SSH transport. `-S` accepts `unix://`, `https://`, `http://`, a host label, `user@host`. Remote access
  is Tailscale or plain HTTP with `--allow-anonymous` (`linux/remote-access.md`). The docs say "support for
  existing SSH keys" is planned. So Oriel still needs `nc -U <socket>` over SSH, as the design says.
- New since the design: a Linux server exists (`linux/installation.md`, `linux/server-modes.md`). The
  shared server listens on `/run/rex/server.sock`. So the socket path differs per machine: read it from
  `rex server status --json` (`endpoint`).

### Listing state

- `session.bootstrap {event_scope: "all", attach_session_ids: [...]}` returns `client_id`,
  `server_status`, the session list and the views of the attached sessions. Tested.
- `session.view {session_id}` returns the whole tree: windows in order, `focused_block_id`,
  `zoomed_block_id`, layers, the split tree with ratios, and per block `label`, `creator_name`, `flavor`,
  `host_id`, `owner`. Tested.
- Not in the view: the terminal title, the cwd, the foreground process, the program status. Each needs a
  block method per block: `com.superlogical.terminal.title`, `.process`, `.program_status`.

### Events

- One control connection carries everything. `seq` starts at 1 with no gaps. A response carries the `seq`
  of the last event before it. Tested.
- `session_view_changed {revision}` says "read the view again". It carries no state. Label changes of a
  block send only `session_view_changed`. Windows and sessions also send `window_label_changed` and
  `session_label_changed`. Tested.
- Block events: `bell`, `child_exited`, `clipboard_written`, `desktop_notification`, `process_changed`,
  `program_status_changed`, `program_status_removed`, `progress_report`, `pwd_changed`,
  `selection_copied`, `size_changed`, `title_changed`, `url_clicked` (`rex block types --json`). Seen
  live: `program_status_changed`, `title_changed`, `process_changed` (with the new cwd after `cd /usr`),
  `size_changed`.

### Create, split, move, swap, resize, rename, close

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

### Output stream for a native terminal view

Tested end to end with one block:

1. `data.connect` gives a one-time ticket (16 bytes, 60 s).
2. HELLO `01` + ticket. WELCOME is 32 bytes: `81`, a resume token, a keep time of 60000 ms, a nonce.
3. The stream starts with a `GHOSTSNP` snapshot, version 1. Records seen: tags 1, 2, 3, 3, 7, 5, 4, 6
   (1462 bytes, empty shell). With 300 lines of history: 1, 2, 3, 7, 5, 4, 3, 3, 6 (2893 bytes).
4. Then raw PTY bytes, with Rex messages as APC `ESC _ rex1;<nonce>;<json> ESC \`. Seen:
   `{"type":"resize","cols":100,"rows":30,"cell_width_px":8,"cell_height_px":16,"owner":"client:…"}` right
   after the snapshot and after each size change. No `theme` APC came, because the colors were the
   defaults.

So the snapshot on attach includes the scrollback, and the live part is raw bytes, not a redrawn screen.
The client must run its own emulator and keep the grid at the APC size. OSC 7501, OSC 2 and BEL stay in
the byte stream.

New finding: a client can have only one stream per block. A second HELLO for the same block from the same
client got REJECT `82 02` and close 1008 `data handshake rejected`. A second client could stream the same
block (tested).

Reading text: `com.superlogical.terminal.format {format: "text", trim, unwrap}` returns screen and
scrollback. 300 lines of `seq` came back as 301 lines, line 1 first (tested). There is no "visible only"
option. `format` fails with `too_large` above 1 MiB.

### Input

`client.key` (a key object with the fields of `ghostty_input_key_s`), `client.action
{action: "com.superlogical.terminal.write", args: {data}}` for typed text in order with keys,
`block.event` `paste`, `mouse`, `wheel`, `focus`. Typed text through `client.action` reached the shell
(tested). The key, paste and mouse shapes are as in `rex-server.md` §6. I did not retest them.

### Size and ownership with several clients

Tested with two clients on one block:

- `own_block {mode: "take"}` moved the owner at once and sent `block_owner_changed {reason: "take"}`.
- The owner's `terminal.resize` applied (60×20). A non-owner's resize (120×40) went only into
  `size.desired[]`.
- When the owner closed its connection, the block went back to the first client (`reason: "disconnect"`).
  The size then changed to that client's last desired size, 120×40, with a new `size_changed` event. So
  Rex applies the next owner's stored size by itself.
- `disown_block` left the block with no owner.

New finding, a stale owner: a block that `session.create` makes is owned by the creating client. If that
client never attached (the `rex new` CLI, `rex api call`), it stays the owner after it exits. `client.list`
did not list it, but `session.view` still showed it as `owner`. Then `own_block {mode: "request"}` returned
that dead owner and did not give Oriel the block. Tested twice (`rex api call session.create`, `rex new`).
Guess: this is a Rex bug that a later build fixes.

### Metadata

- Title: `terminal.title` and `title_changed`.
- cwd: `terminal.process` → `foreground.cwd` is the real cwd. `terminal.pwd` was empty in the test,
  because zsh sent no OSC 7. Use `process`.
- Foreground program: `process.foreground` has `name`, `path`, `argv0`, `script` (for node or python,
  "the absolute path of the script"), `cwd`. Rex never returns other arguments. Oriel's `Program.script`
  maps to `script`.
- No user options or free metadata on blocks. Only the label.

### Agent status and notifications

- OSC 7501 (Program Status Protocol, spec revision 0.4, 2026-10-10, unchanged since the older research).
  The server keeps records per block: `state` (`idle`, `working`, `done`, `blocked`, `error`), `kind`,
  `progress`, `app`, `effective_app`, `title`, `msg`, `updated_at`, `owner`. Tested: `working` with
  progress 40, then `blocked` with `kind=permission`.
- No agent detection. `rex skill setup` installs a skill and a SessionStart hook that only tells the
  agent its session and block (`rex skill --help`, `rex __internal --help`). The hook reports no status.
  So an agent that does not send OSC 7501 has no status in Rex.
- Other signals: `desktop_notification` (OSC 9 and 777), `bell`, `progress_report` (OSC 9;4),
  `child_exited`.

## 4. Mapping table

| Oriel level or feature | Rex concept | API call | Notes |
|---|---|---|---|
| machine | host (server on a machine and account) | `server.status`, `hosts.list` | Socket path per machine from `rex server status --json` |
| session | the one server | `server.status` | One entry. More servers need their own socket and state dir |
| workspace | session | `session.list`, `session.create`, `session.destroy`, `session.move` | Ordered; labeled |
| workspace git info | none | none | Oriel runs git itself, root = `process.foreground.cwd` of the first block. No worktree groups |
| tab | window | `session.new_window`, `session.close_window`, `session.move_window` | Send `focus: false` |
| pane | block | `session.new_split`, `block.close`, `session.describe_block` | `Pane.id == terminalID == block_id` |
| split tree with ratios | tiled layer `layout` | `session.view`, `session.resize_pane` | Floating and detached blocks are outside the tree |
| agent status | program status records | `terminal.program_status`, `program_status_changed`, `program_status_removed` | Only for programs that send OSC 7501. `error` has no Oriel status |
| notifications | status changes, plus OSC 9/777 | the events above, `desktop_notification`, `bell` | No `completion_seq`. Use `updated_at` of a `done` record |
| drag and drop: pane to another tab | move between windows | `session.move_block`, `session.swap_blocks` | Same session only. A move into its own tab is allowed (herdr refuses) |
| drag and drop: pane to a new tab | none direct | `new_window` (placeholder), `move_block`, `block.close` | A placeholder shell starts for a moment |
| drag and drop: pane to another workspace or a new workspace | none | none | Cannot be done: blocks never leave their session |
| rename | labels | `set_label`, `set_window_label`, `set_block_label` | A block label cannot be empty |
| terminal byte stream | data connection | `data.connect`, `/api/data` | GHOSTSNP snapshot, then raw bytes and Rex APCs. One stream per block per client |
| multi-client control hand-off | block owner | `session.own_block`, `session.disown_block`, `block_owner_changed` | Per block, per client. Stale owners after `session.create` |
| find in pane, read pane text | server emulator text, or the local surface | `terminal.format {format: "text"}` | Screen and scrollback together. The local surface has the real scrollback too |

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
| `sessions()` (l. 8) | `server.status` | Adapter: one entry |
| `snapshot()` (l. 10) | `session.view` per session, plus `title`, `process`, `program_status` per block | Yes |
| `updates()` (l. 12) | control events; read the view when `revision` is higher | Yes |
| `refresh()` (l. 14) | `session.view` | Yes |
| `startServer(within:)` (l. 18) | `rex server start`, then wait for `server.status` | Yes |
| `pane(_:)` (l. 22) | `describe_block`, `process`, `title` | Yes. `scroll` stays nil |
| `program(_:)` (l. 24) | `process.foreground` | Yes. `script` given; no argv |
| `terminal(_:cols:rows:observe:takeover:)` (l. 26) | `data.connect`, `own_block`, `terminal.resize` | Yes, but `TerminalStream` is herdr NDJSON frames today. It needs a new shape |
| `screen(_:)` (l. 30) | `format text`, last `rows` lines | Adapter: no visible-only option |
| `recent(_:lines:)` (l. 32) | `format text`, last N lines | Yes, up to 1 MiB |
| `scroll(_:offsetFromBottom:)` (l. 34) | none | No. Scroll the local surface instead |
| `neighbor(of:_:)` (l. 37) | rects from the view | Adapter |
| `split(_:_:)` (l. 40) | `new_split {focus: false}` | Yes |
| `swap(_:_:)` heading (l. 43) | neighbor from rects, then `swap_blocks` | Adapter |
| `swap(_:with:)` (l. 45) | `swap_blocks` | Yes, also across tabs |
| `resize(_:_:amount:)` (l. 47) | split from the tree, then `resize_pane` | Adapter |
| `setRatio(tab:path:ratio:)` (l. 49) | split at the path, then `resize_pane` | Adapter |
| `move(pane:to:)` `.tab` (l. 51) | `move_block` beside the target or the tab's focused block | Yes, same workspace only |
| `move(pane:to:)` `.newTab` | placeholder `new_window`, `move_block`, `block.close` | Adapter, same workspace only |
| `move(pane:to:)` `.newWorkspace` | none | No |
| `rename(pane:label:)` (l. 53) | `set_block_label` | Yes. nil gives `Block xxxxxxxx` |
| `newTab(workspace:cwd:)` (l. 55) | `new_window {layout.block.options.cwd, focus: false}` | Yes |
| `newWorkspace(label:cwd:)` (l. 57) | `session.create`, then `session.attach` | Yes |
| `rename(workspace:label:)` (l. 58) | `session.set_label` | Yes |
| `move(workspaces:before:)` (l. 60) | `session.move`, one call per workspace | Yes |
| `close(workspace:group:)` (l. 63) | `session.destroy` | Yes. `group` has no meaning |
| `close(pane:)` (l. 64) | `block.close` | Yes |
| `close(tab:)` (l. 65) | `session.close_window` | Yes |
| `rename(tab:label:)` (l. 66) | `session.set_window_label` | Yes |
| `move(tab:to:)` (l. 68) | `move_window {before_window_id}` | Yes |
| `sendKeys(_:pane:)` (l. 70) | `client.key`, one per key | Adapter: key name table |
| `sendInput(_:keys:pane:)` (l. 72) | `client.action terminal.write`, then `client.key` | Yes, in order |

Count: 32 rows for 30 members (`move(pane:to:)` has three rows). 22 work directly, 8 need adapter code,
and 2 cannot work (`scroll`, `.newWorkspace`). `.tab` and `.newTab` also fail when the target is another
workspace.

## 6. Where the design page is now wrong or incomplete

These refer to `docs/content/docs/rex-backend.mdx`.

1. Version (line 28): it names `0.0.1792519967-gd05acf`, API revision 4. Current is
   `0.0.1792607779-g171246`, revision 5. Revision 5 adds only `server.apple.privacy_status`, so a hello with
   `api_revision: 4` still works.
2. The `RexClient` table (lines 75-95) covers 12 members. `Multiplexer` now has 30 (see the table above).
   The "designed actions that are not in the interface yet" (line 97) are now in the interface.
3. Moves (line 97ff.) say "move ... map one to one". They do not: Rex has no cross-session move, so a pane
   cannot go to another workspace or a new workspace. "Move to a new tab" needs a placeholder block.
4. The data socket row (line 66) says "one per shown terminal". It is at most one per block per client.
   Two Oriel windows on one block need one shared stream or two Rex clients. The page does not cover D66
   (control between windows) at all.
5. Ownership (line 254): "Mac opens without takeover = `own_block {mode: "request"}`" breaks for blocks
   made by `session.create` from a short-lived client. Their dead creator stays the owner, so `request`
   never succeeds. The adapter must check `client.list` and `take`.
6. Ownership hand-back: when the owner leaves, Rex also resizes the block to the next owner's last
   desired size. The page says only that Rex hands the block on.
7. Labels: the page does not say that block labels cannot be cleared, or that titles, cwd and status are
   not in `session.view` and cost one call each per block.
8. Floating layers (line 38): "skipped" hides the blocks in them. A Rex.app user who floats a pane makes it
   vanish from Oriel. The page also does not mention detached blocks, blocks from other hosts
   (`host_id`), or non-terminal creators.
9. Workspace git info and worktree groups are not covered. Rex gives none.
10. `neighbor`, `scroll` and `screen` are not covered: no read-only neighbor call, no absolute viewport
   offset, no visible-only text.
11. Transport: a Linux Rex server now exists. Its socket can be `/run/rex/server.sock`, so the path must
   come from `rex server status --json`. The page reads it there already, but assumes macOS.
12. Testing (line 320): `rex server run --listen unix:///tmp/oriel-e2e.sock` alone is not clearly isolated.
   Add `--state-dir` and `--config` with an empty file, as this research did. Also pass
   `--autostart=false` to every `rex` command in tests, or the CLI can start the user's server.
13. Small: the older research says the terminfo capability `Pst` advertises OSC 7501. Spec revision 0.4
   says "Remove terminfo".

What still holds: the control and data handshakes, GHOSTSNP framing, the APC format and nonce, resume,
input by key objects, event ordering by `seq` and `revision`, the status record fields, `focus: false` on
create calls, and zoom with `window_id` that leaves focus alone.

## Assumptions and open points

- I assumed the mapping server = Oriel session, Rex session = workspace. The other choice (Rex session =
  Oriel session page) removes the workspace level, which Oriel's sidebar needs. Both choices lose
  cross-workspace moves, because blocks never leave a Rex session.
- I did not run Rex.app. Its own claiming of blocks ("Rex.app claims the blocks that it shows",
  rex-backend.mdx line 270) is still an inference from the older research.
- Guess: Rex sessions do not survive a server restart. The Linux docs say "A package upgrade restarts the
  service, which automatically ends every session on it" (`linux/server-modes.md`). herdr keeps its layout
  across restarts.
