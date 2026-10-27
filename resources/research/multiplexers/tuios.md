# tuios as a backend for Oriel

## Short answer

tuios fits Oriel with an adapter. It is the closest match to herdr of the multiplexers we looked at.
Three facts make it close:

1. tuios already answers herdr's socket API (herdr 0.9.5, protocol 22) on a second socket, with the
   same names: herdr workspace = tuios session, herdr tab = tuios workspace, herdr pane = tuios window.
2. It has a per-pane raw byte stream for native clients (`stream-pane`): a snapshot first, then the
   bytes that the program wrote, with sequence numbers, resume, input and a size lease.
3. It has a hidden stdio bridge for a native GPU client (`tuios gui-bridge`). The bridge sends the
   session state as JSON, including a split tree with ratios for each workspace, and every pane's byte
   stream. It takes layout commands (set ratio, swap, move beside) and passes any daemon verb through.

The main gaps: the herdr socket does not export the split tree (`splits` is always empty) and does not
serve herdr's terminal protocol (`terminal.attach`). Tree edits (swap, resize, ratio) need an attached
tuios client. A tuios session has at most 9 tabs by default. Sessions (Oriel workspaces) cannot be
reordered. The "current workspace" (Oriel's selected tab) is shared session state.

## Sources

- Repository: <https://github.com/Gaurav-Gosain/tuios> (MIT). Young and fast-changing.
- Docs: `docs/protocol.md` (the JSON verb protocol), `docs/AGENT_STATE.md` (agents and the herdr
  compatibility layer), `docs/SESSIONS.md`, `docs/LAYOUT_MODES.md`, `docs/CLI_REFERENCE.md`,
  `docs/ghostty-vt.md`, `vt/README.md`. Hosted copy: <https://tuios.dev>.
- File references below are relative to the repository.

## 1. The hierarchy and its names

tuios has these levels, from the top:

| Level | What it is | Source |
|---|---|---|
| Host | Another machine in the `[hosts]` table, reached over ssh. A daemon links to it. | README "Machines"; `docs/SESSIONS.md` "Windows on Another Machine" (line 678) |
| Server (daemon) | One `tuios` daemon process per user. It owns every PTY and runs a terminal emulator for each one. `--server NAME` runs a separate, named daemon with its own socket and state. | `docs/SESSIONS.md` lines 65-105, 1186-1258 |
| Space | An optional label on sessions ("a named group of related sessions"). It has no record of its own. | `docs/protocol.md` "set-session-space" (line 3782) |
| Session | A persistent group of windows, with a name, an id and an optional display name. Survives detach and (as structure and history) a daemon restart. | `docs/SESSIONS.md` lines 65-105, 473-600 |
| Workspace | A numbered slot inside a session (1 to 9 by default). One workspace shows at a time. Each can have a name. Each keeps its own layout data (BSP tree or column strip). | `docs/LAYOUT_MODES.md` lines 31-35; `internal/app/factory.go` lines 175-178; `internal/session/session.go` lines 487-511 |
| Window (pane) | One terminal with one PTY. tuios uses "window" and "pane" for the same thing. A window can be tiled, floating, minimized, zoomed, stacked, a popup or a scratch pane. | `docs/protocol.md` "list-windows" (line 2299); `internal/guibridge/bridge.go` lines 264-315 |

Layouts per workspace: `bsp` (binary split tree, the default), `master-stack`, `scrolling` (niri-style
columns on a horizontal strip), or tiling off ("floating"). The mode is per session, the data is per
workspace (`docs/LAYOUT_MODES.md` lines 19-35).

## 2. How the levels map to Oriel

tuios itself publishes the mapping it uses for herdr tools (`docs/AGENT_STATE.md` lines 584-605):

| herdr | tuios | herdr id that tuios gives |
|---|---|---|
| workspace | session | `w` + first 12 hex digits of the session id |
| tab | workspace (numbered slot) | `<workspace id>:t<tab number>` |
| pane | window | `<workspace id>:p` + first 12 hex digits of the window id |

So for Oriel:

| Oriel | tuios | Notes |
|---|---|---|
| machine | host (a machine where `tuios` runs) | Oriel keeps using its own ssh `Exec`. tuios also has its own host links, which Oriel does not need. |
| session (sidebar page, one herdr server) | a daemon: the default one, or a named server (`--server NAME`) | A named server has its own socket under `<socket folder>/servers/<name>/tuios.sock` (`docs/SESSIONS.md` line 1178). |
| workspace | tuios session | Sessions list in creation order. They cannot be reordered (`workspace.move_block` answers `unsupported`, `docs/AGENT_STATE.md` line 758). |
| tab | tuios workspace | At most 9 by default (`num_workspaces`). `tab.create` fails with `tab_create_failed` when all are in use (`docs/AGENT_STATE.md` line 680). A tab number is stable across moves. The workspace number is its position. |
| pane | window | Window id and PTY id are stable. A move to another session keeps the window id and the PTY id. The herdr pane id changes (its prefix is the session), but `terminal_id` (`term_` + 12 hex digits of the PTY id) stays. I saw this in my test: `term_2001359e9c34` before and after a move to another session. |

Missing or extra, compared with Oriel:

- Extra level: spaces (labels on sessions). Oriel can ignore them, or show them as groups.
- Extra: floating windows, minimized windows, stacks, popups, scratch panes, picture in picture,
  master-stack and scrolling layouts, multifocus (typing into several panes). Oriel's strip of cards
  mirrors a split tree, so only the BSP layout maps cleanly. The gui-bridge sends a tree only when the
  layout is `bsp` (`internal/guibridge/layout.go` lines 59-66).
- Zoom: tuios zooms one pane per workspace (`docs/AGENT_STATE.md` lines 785-789). Oriel's zoom is
  per window and local, so Oriel does not need tuios zoom.
- Tab count: tuios has a fixed number of workspace slots (9 by default). herdr has no such cap.
- Focus: the current workspace and the focused window are session state shared by every client
  (`docs/protocol.md` lines 1711-1760). Oriel keeps selection per window and never moves the
  multiplexer's focus. See section 3.4.

## 3. API for a remote or native client

tuios has four ways in. All of them are local Unix sockets or a stdio process, so Oriel reaches a
remote machine through its ssh `Exec.run`.

| Way in | Where | Format | Use for Oriel |
|---|---|---|---|
| JSON verb protocol | `tuios.sock` | One JSON line per request and reply, on the same socket as the binary client protocol (`docs/protocol.md` lines 1-40). `tuios call <verb> [params]` sends one verb from a shell (`docs/CLI_REFERENCE.md` line 3226). | State, writes, events, pane streams. Documented and versioned. New verbs do not bump the version. |
| herdr socket API | `tuios.sock.herdr` | herdr's own JSON (protocol 22). | Oriel's existing `HerdrClient` calls, mostly unchanged. |
| gui-bridge | `tuios gui-bridge` on stdin/stdout | Length-prefixed frames: JSON events and commands, plus binary pane output, snapshot, resize and input frames (`internal/guibridge/bridge.go` lines 1-31). | Split trees, layout edits and all pane streams of one session, over one `Exec.run`. Hidden and "not for running by hand" (`cmd/tuios/gui_bridge_command.go` lines 11-13), so its wire can change without notice. |
| binary client protocol | `tuios.sock` | Go `gob` frames (`internal/session/codec.go` lines 1-13). | Not usable from Swift. |

The socket path on macOS is `/tmp/tuios-<uid>/tuios.sock` when `XDG_RUNTIME_DIR` is not set
(`docs/SESSIONS.md` lines 1186-1199). The socket has mode 0700 and no token. Remote access is by ssh
(`docs/protocol.md` lines 25-26).

### 3.1 Listing state

- `list-sessions`, `session-info`, `list-windows`, `get-window`, `list-workspaces`
  (`docs/protocol.md` lines 2047, 2245, 2299, 2351; `internal/session/verb_protocol.go` line 1345).
  `list-windows` gives, for each window: id, PTY id, title, name, workspace, focused, minimized,
  floating, zoomed, rectangle, `pid`, `tty`, `cwd`, `foreground_cmd`, `agent_state`, `history_rows`
  and `revision`. I saw all of these in my test, except `foreground_cmd` (omitted at a shell prompt).
- herdr socket: `session.snapshot` gives workspaces, tabs, panes and `layouts`, as herdr does. Each
  layout has pane rectangles but `splits` is always empty (`internal/session/herdr_view.go` lines
  126-137, and my test showed it).
- gui-bridge: a `state` event with every window (id, PTY, title, name, workspace, rectangle, cwd,
  foreground program, agent state, harness, repo, branch) and `trees`: each workspace's split tree
  (`internal/guibridge/bridge.go` lines 181-226 and 264-315; `layout.go` lines 29-56). A node has an
  id, an axis (`x` = left/right, `y` = top/bottom), a ratio (share of the first child) and a cell
  rectangle. A `fleet` event lists every session and every agent on the daemon.

### 3.2 Events

- `subscribe` on the verb socket turns the connection into an NDJSON event stream
  (`docs/protocol.md` lines 6889-7090). Events: `window-created`, `window-closed`, `window-exit`,
  `window-retitled`, `window-focused`, `window-moved`, `window-minimized`, `window-restored`,
  `workspace-switched`, `workspace-renamed`, `layout-changed` (opt-in), `agent-state`,
  `agent-message`, `output` (activity only, with a byte count), `bell`, `notification`
  (OSC 9, 777, 99), `mode-changed`, `session-created`, `session-closed`, `client-session-changed`,
  `attention` (Inbox items), `prompt`, `command-started`, `command-finished` (OSC 133), and more.
- Every event has a global `seq` and a `boot_id`. A subscriber can resume with `after_seq`. The
  daemon keeps 4096 events (not `output`). A slow reader gets a `gap` marker instead of blocking the
  daemon.
- I saw `window-retitled`, `workspace-renamed`, `window-moved`, `output`, `bell` and `notification`
  in my test with `tuios subscribe -s alpha`.
- herdr socket: `events.subscribe` maps these to herdr's event names (`docs/AGENT_STATE.md` lines
  1203-1228). There is no `layout.updated` in that table. Guess: a split or ratio change does not
  raise an event on the herdr socket. Oriel must read `layout-changed` on the verb socket, or the
  gui-bridge `state` event, instead.

### 3.3 Writes

| Action | Verb (verb socket) | herdr method | Needs an attached client? |
|---|---|---|---|
| Create window | `new-window` (`focus` defaults to true: pass `false`) | `tab.create`, `pane.split` | No |
| Split | `split-window` (`direction` or `side`) | `pane.split` | `split-window` yes. `pane.split` without a client makes a plain new window on the same workspace (`docs/AGENT_STATE.md` line 676). |
| Swap | gui-bridge `layout` op `swap` | `pane.swap` | Yes (`no_client` in my test without one) |
| Resize border | gui-bridge `set-ratio` | `pane.resize` | Yes |
| Set split ratio | gui-bridge `layout` op `set-ratio` with the node id | `layout.set_split_ratio` answers `unsupported` | Yes |
| Move pane to another tab | `move-window` with `workspace` | `pane.move` to a tab or a new tab | No. tuios places the pane itself; `target_pane_id`, `split` and `ratio` are ignored (`docs/AGENT_STATE.md` line 684). The gui-bridge `move` op puts a pane beside a target pane on a side (`layout.go` lines 146-155). |
| Move pane to another Oriel workspace | `move-window` with `to_session` | `pane.move` to a tab of another workspace | No. The program keeps running. |
| Move pane to a new Oriel workspace | none in one call | `new_workspace` answers `unsupported` | Make the session first, then move. |
| Rename pane | `set-window` with `name` | `pane.rename` | No |
| Rename tab | `set-workspace-name` | `tab.rename` | No |
| Reorder tabs | `set-workspace-order` | `tab.move` | No |
| Rename Oriel workspace | `set-session-name` | `workspace.rename` | No |
| Reorder Oriel workspaces | none | `workspace.move_block` answers `unsupported` | n/a |
| Close | `close-window`, `close-workspace`, `kill-session` | `pane.close`, `tab.close`, `workspace.close` | No |
| Zoom, equalize, rotate, tiling on/off | `run-command ToggleZoom`, `set-layout` | `pane.zoom` | Yes |

Sources: `internal/session/verb_protocol.go` lines 1251-1400; `docs/AGENT_STATE.md` lines 660-752.
I tested `pane.split`, `pane.swap`, `pane.resize`, `layout.set_split_ratio`, `workspace.move_block`,
`pane.scroll`, `pane.move` (new tab, new workspace), `tab.create` and `workspace.create` on the herdr
socket. I tested `set-ratio`, `swap` and the `split-window` verb through `gui-bridge`. All three
worked and the next `state` event showed the new tree.

### 3.4 What "needs an attached client" means

The daemon stores the layout intent: the layout mode, the BSP tree per workspace and the split ratios
(`docs/protocol.md` lines 1735-1745; `internal/session/session.go` lines 341-355 and 511). It does not
compute tiling. A tuios client (the TUI, or the gui-bridge, which runs the same client model without a
screen) edits the tree and sends the whole tree for that workspace back to the daemon
(`internal/session/layout_tree.go` lines 11-36). So:

- Without a client, swap, resize and ratio edits fail with `no_client`, and herdr's `pane.neighbor`
  finds nothing ("a session with no attached client has no layout", `docs/AGENT_STATE.md` lines
  780-784).
- A window made by a verb while no client shows its workspace is `unplaced`. A client places it when it
  shows that workspace (`docs/protocol.md` lines 1690-1697). In my test, the trees for workspaces 3
  and 4 did not exist until the gui-bridge showed those workspaces with the `workspace` command.
- Showing a workspace changes the session's current workspace for every client. This is a focus
  change, which Oriel's rules forbid against herdr.

### 3.5 Terminal output for a native view

`stream-pane` on the verb socket (`docs/protocol.md` lines 3076-3242, and
`internal/session/verb_stream_pane.go` lines 20-55 and 403-470):

- One JSON reply line, then binary frames both ways: type byte, 4-byte big-endian length, payload.
- From the daemon: `S` snapshot (seq, cols, rows, then VT bytes that paint the pane on a fresh
  emulator, with up to 500 rows of history, colours, cursor, alternate screen and the input modes),
  `O` output (seq, then the raw bytes the program wrote), `R` resize, `E` error, `X` end with a reason.
- From the client: `I` input bytes (the client encodes keys and mouse itself), `L` size lease.
- Resume: send `from_seq` and `boot_id`. The daemon keeps the last 64 KiB of each pane's output, and
  sends a new snapshot when that is not enough.
- The daemon answers the program's terminal queries itself (OSC 10/11/4, DA1, kitty graphics query),
  from the newest viewer's colours when no TUI client is attached. The client emulator's own replies
  must be dropped.

I confirmed this in my test: the snapshot came first, then `R (170, 100, 30)` after my lease, then `O`
frames with the program's raw bytes, for example `hello\x1b[31m red\x1b[0m\r\n`. `tput cols; tput lines`
printed `100` and `30`.

This is a better fit for libghostty than herdr's model. herdr sends its own re-rendered screen.
tuios sends the program's real bytes, so the local surface keeps real scrollback, selection, links,
OSC 133 marks and kitty graphics. Oriel's `scroll` call becomes local to the surface.

The gui-bridge sends the same kind of stream for every pane of the attached session on one stdio
channel: `SNAP`, `OUTPUT`, `RESIZE` frames keyed by PTY id, and `INPUT` frames back
(`internal/guibridge/bridge.go` lines 14-31). Its snapshot carries 1000 history rows by default
(`--scrollback`). At attach I saw one `SNAP` for each of the 5 windows, on all workspaces.

Other ways to read text:

- `capture-pane`: `visible`, `recent` or `last-command-output`, plain or styled, with `lines`,
  `start`/`end`, `unwrap` and `trim` (`docs/protocol.md` line 3484). herdr's `pane.read` maps to it.
- `search-panes`: find text in the history and screen of every pane on the machine
  (`docs/protocol.md` line 3587).
- `screenshot`: a pane as PNG, SVG, ANSI, HTML or text.

### 3.6 Input

- Raw bytes: `I` frames on `stream-pane`, or `INPUT` frames on the gui-bridge.
- Keys by name: `send-keys`. With a window, the keys follow the pane's application cursor mode, kitty
  keyboard flags and modifyOtherKeys (`internal/session/sendkeys.go` lines 74-75 and 264-330,
  `docs/protocol.md` lines 2720-2764). herdr's `pane.send_keys` maps to it.
- Text: `send-text`, with `paste` (bracketed when the program asks) and `submit`. herdr's
  `pane.send_text` and `pane.send_input` always send the text as a paste (`docs/AGENT_STATE.md` lines
  770-777). That differs from herdr.
- Mouse: no mouse verb. Because the snapshot restores the mouse modes, the local libghostty surface can
  encode mouse events itself and send them as raw input bytes.

### 3.7 Size and several clients

- A pane has one size. The session size follows `[daemon] window_size`: `latest` (default: the client
  with the last key, paste or click), `smallest` or `largest` (`docs/SESSIONS.md` lines 152-226). A
  resize or a focus change is not input, so a viewer does not take the size.
- `stream-pane` does not resize by default. A lease (`L` frame) holds one pane at a size, but never
  larger than the clients ask for. A `fit` lease, while no TUI client shows the session, makes the
  pane the size of the largest viewer. Leases expire after 30 s unless renewed every 10 s
  (`docs/protocol.md` lines 3202-3242).
- A tool that only uses the verb socket is not a client with a size (`docs/SESSIONS.md` lines
  224-226).
- There is no exclusive "controller". Any stream with the `write` grant can type. `detach-client` and
  `[daemon] single_client` can force one TUI client per session (`docs/protocol.md` lines 2127-2160).

### 3.8 Metadata

- Titles: shell title and a custom name per window (`title`, `display_name`, `custom_name`).
- cwd: read from the process (`proc_pidinfo` on macOS) on each list (`docs/SESSIONS.md` lines
  1272-1278). herdr's `cwd` and `foreground_cwd` are filled.
- Foreground process: `foreground_cmd` in `list-windows`; herdr `pane.process_info` gives pid, name,
  argv and cwd of the foreground process group (seen in my test).
- Git: herdr workspace `worktree` (repo key, checkout path, `is_linked_worktree`) from the session's
  folder (`internal/session/herdr_view.go` lines 35-41, 353-392, 562-580). The gui-bridge gives repo and
  branch per window. Verbs `new-worktree`, `list-worktrees`, `remove-worktree`.
- User data: session accent, session display name, space, `set-agent-meta` tokens, and herdr
  `workspace.report_metadata` tokens are kept in memory.

### 3.9 Agent status and notifications

This is a strong area of tuios (`docs/AGENT_STATE.md`, 5344 lines):

- States: `working`, `needs_input`, `idle`, `done`, `errored`, `unknown`. Sources: hooks for 19
  harnesses (`tuios integration install`), detection of 24 agent CLIs by process and screen, herdr's
  pane report protocol, and OSC 7501 "Program Status" for any program (README "Agents").
- herdr mapping: `needs_input` → `blocked`, `done` and `errored` → `done`. Tabs and workspaces show
  their most urgent pane (`docs/AGENT_STATE.md` lines 606-626). In my test, a state set with no
  harness showed in `list-windows` but as `unknown` on the herdr socket. With
  `"harness":"claude-code"` it showed `agent: claude, agent_status: working`.
- Notifications: `notification` and `bell` events. The Inbox (`list-attention`, `attention` events)
  lists approvals, questions, errors and finished turns, with `respond` and `reply-approval` to answer
  from a client.

## 5. Verdict

Fits with an adapter. Two adapter designs are possible. I recommend design B.

### Design A: herdr socket plus `stream-pane`

Point `HerdrClient` at `tuios.sock.herdr` (through a small stdio relay, for example `nc -U`, because
tuios has no `remote-api-bridge` command). Replace `TerminalStream` with a `stream-pane` client.

What the adapter fakes or stores:

- The split tree. The herdr socket gives only pane rectangles. The adapter rebuilds a tree from the
  rectangles (guillotine cuts) and cannot set ratios. Resize, swap and ratio fail without a tuios
  client attached.
- Workspace order (stored by Oriel, per machine).
- "New workspace" as a pane destination (create the session, then move).
- Control hand-off, in Oriel only. tuios has no owner that refuses a second controller.

Design A is quick but loses the dividers, the most visible part of Oriel's strip.

### Design B: one `tuios gui-bridge` per open Oriel workspace

Run `tuios [--server S] gui-bridge --session-id <id> --cols C --rows R --cell-width W --cell-height H`
through `Exec.run`. One stdio channel then carries the state (with trees and ratios), the layout
commands, any verb (`{"cmd":"verb"}`), and every pane's byte stream. Use the verb socket (`tuios call`,
`tuios subscribe`) for the daemon-wide list of sessions and for events of sessions with no bridge.

What the adapter fakes or stores:

- Workspace order and worktree groups (tuios has neither).
- The mapping from Oriel's split path (`[Bool]`) to tuios node ids, rebuilt from each `state` event.
  The axis maps `x` → `right` and `y` → `down`.
- Tab selection: Oriel's selection stays local. The adapter must not send `workspace` commands except
  to place a pane that is still `unplaced`. That one step moves the session's shared focus, and the
  adapter moves it back. Guess: this flickers in a tuios TUI that is attached at the same time.
- Card sizes: the bridge lays out every tree over one grid. The adapter sends the strip size in cells
  as the grid (and `--insets` for card padding), so each pane's PTY size matches its card within one
  cell. tuios keeps a gap of 1 cell between panes, not 8 pt.
- Control: the window that controls a session runs the bridge with input. Other windows watch with
  `stream-pane` and no lease, which never resizes. "Take Back" means the watching window starts to
  send input. Under `latest` it then sets the session size.

Risks:

- `gui-bridge` is hidden and has no stability promise. Pin a tuios version, and test the wire in
  Oriel's e2e suite.
- A tuios session has 9 tab slots by default.
- Only the `bsp` layout gives a tree. A session in `master-stack`, `scrolling` or floating mode has
  rectangles only.
- The project changes fast. The verb protocol is versioned and additive (`docs/protocol.md` lines
  106-110), and `list-verbs` describes every verb at run time.

### Multiplexer.swift, method by method

| Method | Possible? | How |
|---|---|---|
| `sessions()` | Yes, with adapter | List the default socket and `servers/*/tuios.sock`. |
| `snapshot()` | Partly (A) / Yes (B) | herdr `session.snapshot` has no splits; bridge `state` has trees. |
| `updates()` | Yes | `subscribe` (verb socket) or `events.subscribe` (herdr), then read the snapshot again. |
| `refresh()` | Yes | Adapter logic, as today. |
| `startServer(within:)` | Yes | `tuios [--server S] daemon`, or any command, which starts the daemon. |
| `pane(_:)` | Yes | herdr `pane.get`; `list-windows` (cwd read live). |
| `program(_:)` | Yes | herdr `pane.process_info`; `foreground_cmd`. |
| `terminal(...)` | Yes, new client | `stream-pane` or bridge frames. Raw bytes, not herdr frames. `observe` = no `I` frames and no lease. `takeover` has no tuios meaning. |
| `screen(_:)` | Yes | `capture-pane` `visible`, or herdr `pane.read`. |
| `recent(_:lines:)` | Yes | `capture-pane` `recent` with `lines` and `trim`. |
| `scroll(_:offsetFromBottom:)` | No (not needed) | herdr `pane.scroll` is `unsupported`. Scroll the local surface instead. |
| `neighbor(of:_:)` | Yes, needs a client | herdr `pane.neighbor` (from rectangles), or compute from the bridge tree. |
| `split(_:_:)` | Yes | `split-window` (needs a client) or herdr `pane.split`. |
| `swap(_:_:)` | Yes, needs a client | herdr `pane.swap` with direction, or bridge `swap`. |
| `swap(_:with:)` | Yes, needs a client | herdr `pane.swap` with source and target, or bridge `swap`. |
| `resize(_:_:amount:)` | Yes, needs a client | herdr `pane.resize`, or bridge `set-ratio`. |
| `setRatio(tab:path:ratio:)` | Bridge only | bridge `layout` `set-ratio` with the node id. herdr method is `unsupported`. |
| `move(pane:to:)` | Mostly | `.newTab` and `.tab`: `move-window` or herdr `pane.move`; `beside` only through the bridge `move` op. `.newWorkspace`: two steps. |
| `rename(pane:label:)` | Yes | herdr `pane.rename` (`null` clears). |
| `newTab(workspace:cwd:)` | Yes, up to 9 | herdr `tab.create`. |
| `newWorkspace(label:cwd:)` | Yes | herdr `workspace.create` (a new tuios session). |
| `rename(workspace:label:)` | Yes | herdr `workspace.rename`. |
| `move(workspaces:before:)` | No | Store the order in Oriel. |
| `close(workspace:group:)` | Partly | herdr `workspace.close` (`kill-session`). No worktree groups. |
| `close(pane:)` | Yes | herdr `pane.close`. |
| `close(tab:)` | Yes | herdr `tab.close`. |
| `rename(tab:label:)` | Yes | herdr `tab.rename`. |
| `move(tab:to:)` | Yes | herdr `tab.move` (renumbers workspaces, tab ids stay). |
| `sendKeys(_:pane:)` | Yes | herdr `pane.send_keys`; `send-keys` with a window. |
| `sendInput(_:keys:pane:)` | Yes, as a paste | herdr `pane.send_input`. Text always goes as a paste. |

Count: 30 methods. 25 work directly or through the bridge. 3 work partly (`snapshot` on design A,
`move(pane:to:)`, `close(workspace:group:)`). 2 are not available: `scroll`, which the local surface
replaces, and `move(workspaces:before:)`, which Oriel stores itself.
