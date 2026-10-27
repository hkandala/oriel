# tmux as a backend for Oriel

## Answer first

tmux fits Oriel with an adapter. tmux has all four structural levels that Oriel needs below the machine (server, session, window, pane). Its control mode (`tmux -C`) is a usable text API with commands, notifications and a live output stream. The adapter must store or fake these things: the workspace order, pane labels, agent status, linked-worktree groups, git state, the "who controls this pane" hand-off, the shared scroll offset, and the binary split tree with ratios. tmux has no agent model and no notification model. Its layout is an n-ary tree of cell sizes, not a binary tree of ratios.

The terminal stream is better than herdr's for a libghostty view. `%output` carries the raw bytes that the pane's program wrote to its PTY. It is not a re-rendering by tmux. The seed on attach is the weak part: `capture-pane` returns tmux's re-rendering of its own grid, plus mode flags read from format variables.

## 1. The hierarchy and its names

| tmux level | Id form | What it is | Source |
|---|---|---|---|
| server | socket path | One process per socket. `-L name` picks a socket in `$TMUX_TMPDIR/tmux-UID/` (here `/private/tmp/tmux-501/`). `-S path` picks any path. All sessions on a socket share one server. | man lines 5-40 (DESCRIPTION), `-L`/`-S` options |
| client | `client-<pid>` or tty name | One attached viewer: a terminal, or a control-mode process. A client shows one session at a time. | man "CLIENTS AND SESSIONS" (line 583) |
| session | `$N`, plus a unique name | A named set of windows, with a current window. | man line 583 onward |
| session group | group name | Sessions that share the same set of windows. Each session keeps its own current window and its own options. | `new-session -t`, man lines 735-752 |
| window | `@N`, plus an index per session and a name | One full-screen layout of panes. A window can be linked into several sessions (`link-window`). | man "WINDOWS AND PANES" (line 872), `link-window` line 1740 |
| pane | `%N`, plus an index per window | One PTY. Tiled panes form the layout tree. tmux 3.8 adds floating and modal panes. | man line 872, `new-pane` line 1859 |
| layout cell | none | A node of the window's layout tree: a row `{...}` or column `[...]` of children, with cell sizes. | man lines 1350-1398 |

The ids `$N`, `@N` and `%N` are stable for the life of the server. A pane keeps its `%N` when it moves to another window or another session. I saw this: after `move-pane -d -s %1 -t other:0.0 -h`, `list-panes -a` printed `other @2 %1`.

tmux has no "tab" and no "workspace" by those names. Its window is the tab-like level.

## 2. How the levels map to Oriel

Oriel's levels are machine > session > workspace > tab > pane. A herdr session is its own server, named by `--session`. The closest tmux match is the socket.

Recommended mapping (A):

| Oriel | tmux | Notes |
|---|---|---|
| machine | the host, reached over SSH or locally | Same as herdr. |
| session (sidebar page) | one server, named by `-L <name>` | `sessions()` lists the socket files in `$TMUX_TMPDIR/tmux-UID/`. A socket file with no server behind it is a session that is not running. |
| workspace | tmux session (`$N`) | The label is the session name. The cwd is `#{session_path}`. People who use tmux often keep one tmux session per project, which is what an Oriel workspace is. |
| tab | tmux window (`@N`) | The window index gives the tab order. |
| pane | tmux pane (`%N`) | The terminal id and the pane id are the same `%N`. |

Alternative mapping (B): Oriel session = tmux session, Oriel workspace = a group of windows marked by a window user option such as `@oriel_ws`, tab = window. B needs only one control client per Oriel session, because a control client sees all windows of its own tmux session. But B invents the workspace level, and a user of terminal tmux sees one flat list of windows. I recommend A. Section 3 explains the cost of A: one control client per tmux session.

What tmux has that Oriel does not show:

- Session groups. Oriel has no matching level. The adapter can show each grouped session as a workspace, or hide all but one.
- Linked windows: one window in several sessions. In mapping A, this is one tab in two workspaces. Oriel has no such case. The adapter must pick one owner.
- Zoom (`resize-pane -Z`). It resizes the PTY of the zoomed pane for every client. Oriel's zoom is a UI state only, so the adapter must not call tmux zoom. If a terminal client zooms, `%layout-change` sends a flag `Z`, and the visible layout differs from the full layout. I saw this: `%layout-change @1 6650,100x30,...{...} a87f,100x30,0,0,2 Z`.
- Preset layouts (`even-horizontal`, `main-vertical`, `tiled` and others, man lines 1357-1385).
- Floating and modal panes (tmux 3.8). Old-format layout strings leave floating panes out. I saw this: after `break-pane -W -d -s %2`, the old layout of `@1` showed only `%7` and `%6`. Only the JSON format (client flag `new-layouts`) includes them.
- The current window of a session and the active pane of a window. herdr has focus too, and Oriel ignores it.
- Copy mode, choose mode and other pane modes. A mode changes what tmux draws, but it does not change `%output`.

What Oriel has that tmux does not have:

- A workspace order. tmux lists sessions sorted by name, creation time or activity (`list-sessions -O`).
- Workspace git and worktree info, and linked-worktree groups.
- Pane labels separate from the terminal title. tmux has one `pane_title`. Programs set it with OSC 0 and OSC 2, and `select-pane -T` sets it.
- Agent status and notifications per pane.
- A binary split tree with ratios. tmux has an n-ary tree with cell sizes.
- Control of a pane by one client, with a takeover. tmux has no per-pane owner (section 3.7).

## 3. The API for a native client

### 3.1 Transport: control mode

`tmux -C` reads commands on stdin and writes replies and notifications on stdout. `-CC` also turns off echo. It is for use inside a real terminal, as iTerm2 does (man line 44). On a pipe, plain `-C` is enough. Oriel can run it through its `Exec.run` envelope, locally or over SSH, as it runs herdr.

Each command gives one block: `%begin <time> <number> <flags>`, output lines, then `%end` or `%error` with the same three numbers. A notification never appears inside a block (man lines 4795-4812). `%output` blocks also hold back later lines, so the order on the wire is the order of events (`control.c` lines 32-45).

Real sample (server `oriel-research-74317`):

```text
%begin 1792804022 326 1
%1
%end 1792804022 326 1
%layout-change @0 6b8b,100x30,0,0{50x30,0,0,0,49x30,51,0,1} 6b8b,100x30,0,0{50x30,0,0,0,49x30,51,0,1} *
%output %1 sh-3.2$ 
```

Parsing caveats that I hit:

- An unquoted pane id at the start of an argument failed: `refresh-client -A %2:pause` returned `parse error: syntax error`. The quoted form `refresh-client -A '%3:pause'` worked. The adapter must quote every argument.
- A pipe inside a command is not a shell pipe: `capture-pane ... | wc` returned `parse error: command capture-pane: too many arguments`.
- `join-pane -s %2` with no `-t` joined the pane into the current window. Always pass `-t`.

A plain CLI call (not control mode) also works for one-off reads. `time tmux -L ... list-panes -a -F '...'` took 0.023 s real time on this Mac.

### 3.2 Listing state

Format strings give every field in one call per level:

```text
list-sessions -F '#{session_id}\t#{session_name}\t#{session_path}\t#{session_group}'
list-windows -a -F '#{session_id}\t#{window_id}\t#{window_index}\t#{window_name}\t#{window_layout}'
list-panes -a -F '#{session_id}\t#{window_id}\t#{pane_id}\t#{pane_active}\t#{pane_current_path}\t#{pane_current_command}\t#{pane_title}\t#{pane_pid}\t#{pane_tty}\t#{@oriel_label}\t#{@oriel_status}'
```

Real output: `main @0 0 bash %0 0 100x30 cmd=bash path=/private/tmp/tmuxr title=mbp pid=74323`.

Useful pane formats (man lines 3780-3900): `pane_current_path`, `pane_current_command`, `pane_title`, `pane_pid`, `pane_tty`, `pane_width`, `pane_height`, `pane_left`, `pane_top`, `pane_at_left` and the other edges, `pane_dead`, `pane_dead_status`, `pane_last_output_time`, `pane_floating_flag`, `pane_zoomed_flag`, `cursor_x`, `cursor_y`, `alternate_on`, `history_size`, `pane_private_modes`, `pane_key_mode`, `bracket_paste_flag`, the `mouse_*_flag` set, and from 3.8 `pane_command_running`, `pane_command_status`, `pane_pb_state` (OSC 9;4 progress: hidden, normal, error, indeterminate, paused).

`pane_current_path` follows a `cd` with no OSC 7. After `cd /usr/bin` in the pane, `display -p "#{pane_current_path}"` printed `/usr/bin`.

`pane_current_command` is only the process name (`bash`, `sleep`). For Oriel's `Program` (argv, script), the adapter must run `ps -t <pane_tty> -o pid,stat,args` and pick the process with `+` in its state.

### 3.3 Events

Notifications (man lines 4813-4910): `%sessions-changed`, `%session-changed`, `%session-renamed`, `%session-window-changed`, `%client-session-changed`, `%client-detached`, `%window-add`, `%window-close`, `%window-renamed`, `%window-pane-changed`, `%unlinked-window-add`, `%unlinked-window-close`, `%unlinked-window-renamed`, `%layout-change`, `%pane-mode-changed`, `%paste-buffer-changed`, `%paste-buffer-deleted`, `%subscription-changed`, `%message`, `%output`, `%extended-output`, `%pause`, `%continue`, `%config-error`, `%exit`.

A control client gets full events only for its own tmux session:

- `%layout-change` goes only to clients whose session holds the window (`control-notify.c` lines 64-106).
- `%output` goes only for panes in windows of the client's session (`control.c` line 627: `winlink_find_by_window(&c->session->windows, wp->window) == NULL` returns).
- Other sessions give only `%unlinked-window-*` and `%sessions-changed`.

I tested this. A client attached to session `a` ran `split-window -d -t b:`. It got no `%layout-change`. `rename-window -t b:0 bw` gave only `%unlinked-window-renamed @1 bw`.

So with mapping A, the adapter runs one control client per tmux session that it shows or watches. That is one process per workspace. Over SSH, all of them can share one ControlMaster connection.

Other event sources:

- `refresh-client -B name:what:format` subscribes to a format. `what` is empty (the session), `%N`, `%*` (all panes of the session), `@N` or `@*`. tmux checks it at most once per second and sends `%subscription-changed` (man lines 790-800). Real sample: `%subscription-changed cmds $0 @0 0 %1 : bash|done`. `%*` covers only the attached session.
- Hooks run tmux commands on events (man "HOOKS", line 3292). A hook that runs `display-message` reaches a control client as `%message`. Real sample: `set-hook -g pane-command-finished "display-message \"finished #{pane_id} status=#{pane_command_status}\""` gave `%message finished %3 status=0`. Guess: with several clients, the message goes to one client that tmux picks. The adapter must not rely on hooks to reach a given client.
- `wait-for -E -v <event>` (3.8) waits for one event on the whole server and prints its keys. Real sample: `tmux wait-for -E -v pane-title-changed` printed `event=pane-title-changed`, `new_title=hello`, `pane=%1`, `window=@1`. It returns after one event, so events between two calls are lost. It is usable as a "something changed, read again" trigger only.

The herdr rule "any event line means: read the snapshot again" carries over. Every notification except `%output` starts a paced snapshot read.

### 3.4 Actions

| Action | tmux command | Tested |
|---|---|---|
| split | `split-window -d -h|-v [-b] [-l size] -t %N -c cwd -P -F '#{pane_id}'`. `-h` is side by side, `-v` is top and bottom, `-b` puts the new pane left or above. `-d` keeps focus. | yes: returned `%1` |
| swap two panes | `swap-pane -d -s %A -t %B`. Works across windows and sessions. `-d` keeps the active pane. | yes, in one window |
| resize a divider | `resize-pane -t %N -L|-R|-U|-D <cells>` or `-x|-y <cells or %>` | yes: `-x 70` gave `{70x30,...,29x30,...}` |
| set an exact layout | `select-layout -t @N '<layout string>'` | yes: JSON layout with widths 25 and 74 applied |
| move a pane into another window, any session | `move-pane` / `join-pane -d -s %A -t %B -h|-v [-b] [-l size]` | yes: `%1` moved to session `other` and kept its id |
| move a pane to a new window | `break-pane -d -s %N -t <session>: -P -F '#{window_id} #{pane_id}'` | yes: `@3 %1` |
| move a window to another session | `move-window -d -s <src> -t <session>:[index]`. `-a`/`-b` insert after or before. | yes |
| new window | `new-window -d -t <session>: -c cwd -n name -P -F '#{window_id} #{pane_id}'` | yes |
| new session | `new-session -d -s name -c cwd -P -F '#{session_id} #{window_id} #{pane_id}'` | yes |
| rename | `rename-session`, `rename-window` (turns off `automatic-rename` for it), `select-pane -T` | yes: `%session-renamed $0 mainx`, `%window-renamed @0 first` |
| close | `kill-pane`, `kill-window`, `kill-session` | yes: `%window-close @0` |
| reorder windows | `move-window -s @A -t <session>:<index>` with `-a`/`-b`, `swap-window`, `move-window -r` (renumber) | not tested |

tmux never needs focus to change for these. Every listed command takes `-d` or ignores focus. This is better than herdr 0.9.5, whose `pane.swap` moves focus.

### 3.5 Output streaming

Fact: `%output` carries the pane's own PTY bytes. tmux does not re-render them.

- `window_pane_read_callback` reads the PTY into `wp->event->input`. It calls `control_write_output` for each control client before it calls `input_parse_pane`, which is tmux's own emulator (`window.c` lines 1633-1656).
- `control_append_data` takes the bytes from that same buffer with `window_pane_get_new_data` (`window.c` lines 2563-2570). It writes bytes below 0x20 and `\` as octal `\ooo` and other bytes as they are (`control.c` lines 826-840). UTF-8 bytes pass through unchanged.
- Test: the pane ran `printf "abc\rX\n\033[31mred\033[0m\n"`. `%output` carried `abc\015X\015\012\033[31mred\033[0m\015\012`, which is the exact bytes. `capture-pane -p -e` of the same screen returned `Xbc` and `^[[31mred` then `^[[39m`, which is tmux's re-rendering.

So the first guess ("tmux's re-rendering") was wrong for the live stream. It is right for the seed. Comparison:

| Backend | Live stream | Seed on attach |
|---|---|---|
| herdr | herdr's rendering of the visible screen, as ANSI frames at the client's size (`TerminalStream.swift` lines 13-18) | a full frame |
| Rex | raw PTY bytes | a GHOSTSNP snapshot from its libghostty-vt |
| tmux | raw PTY bytes, octal-escaped, one `%output` line per read | none. The client must build it from `capture-pane` and format variables |

How a client seeds a pane. iTerm2 does these steps for each pane it opens (`TmuxWindowOpener.m` lines 218-233 and 259-310):

1. `capture-pane -peqJN -t %N -S -<max>` for the history and screen, and the same with `-a` for the alternate screen.
2. `list-panes -t %N -F <state>` for the cursor, scroll region, tab stops, cursor keys, keypad, wrap, mouse modes, bracketed paste and `pane_key_mode`. The field list is in `TmuxStateParser.m` lines 30-47 and 87-100.
3. `capture-pane -p -P -C -t %N` for the start of an escape sequence that tmux has read but not finished.
4. `refresh-client -A '%N:continue'` if the pane was paused.

The order of the wire makes this safe. Output from before the capture's `%begin` is already in the capture. Output after its `%end` is new. The adapter drops a pane's `%output` until the capture's `%end`, then feeds the rest.

What the seed loses, because it is tmux's re-rendering of its grid:

- The exact bytes. Colors come back as tmux chooses to write them (for example `\033[39m` instead of `\033[0m`).
- Anything that tmux's grid does not store or that `-e` does not write. Hyperlinks need a separate `capture-pane -H`. Guess: images and other sequences that tmux does not parse do not come back.
- Modes that tmux does not report. iTerm2 says bracketed paste state "requires tmux patch (not yet in any release)" (`TmuxStateParser.m` line 45). tmux 3.8 lists `bracket_paste_flag` in its man page (line 3714), so this can be out of date in the comment.

What is lost or changed in the live stream too:

- The program talks to tmux, not to Oriel. `TERM` in a pane is `screen` or `tmux` (man, `new-window`, and `default-terminal` line 2366). tmux answers terminal queries (DA, DSR, OSC 10 and 11). libghostty will also see those queries in the raw bytes and try to answer. The adapter must drop libghostty's replies, or tmux and Oriel both answer. `refresh-client -r '%N:<report>'` lets a client give tmux a report, such as an OSC 10 answer (man line 803).
- Guess: a program limits itself to what tmux supports, for example no Kitty graphics. Sequences that tmux does not know still reach Oriel raw, but tmux's grid ignores them, so a later seed will not show them.
- The pane size is tmux's. If Oriel's surface size differs from `pane_width` x `pane_height`, the bytes draw wrong. Oriel must size the surface to the pane, then clip or scale, as herdr's `observe` does.

Scrollback: `capture-pane -S -<n>` or `-S -` reads history (`history-limit` lines). Real sample: `capture-pane -p -J -t %3 -S -5 -E 2` returned lines `87` to `94` of a `seq 1 120` run. Because the stream is raw, libghostty keeps its own scrollback after the seed. tmux copy mode does not change `%output`, so Oriel scrolls locally. It never needs tmux's scroll.

Flow control (all from `control.c` and `server-client.c` at tag 3.8):

- Without `pause-after`, a client that falls 300 s behind is cut off with "too far behind" (`CONTROL_MAXIMUM_AGE 300000`, line 134, and lines 606-612).
- `refresh-client -f pause-after=<s>` changes `%output` to `%extended-output %N <age ms> : <data>`. When a pane's oldest unsent output is older than that, tmux drops it for this client and sends `%pause %N` (lines 600-605). Output while paused is lost for this client. Test: client A paused `%3`. Client B saw `hi-after-pause`. After `continue`, A got `%continue %3` and no replay. The client must seed the pane again.
- `refresh-client -A '%N:off'` stops output of that pane to this client. If every attached client is a control client that has the pane off or is slow, tmux stops reading the PTY (`server-client.c` lines 2045-2130). Test: with one client, `echo off` typed while off did not appear until `'%N:on'`, then it came in one chunk. Do not use `off` for hidden panes when Oriel is the only client. The program blocks when the kernel PTY buffer fills.
- `refresh-client -f no-output` drops all output for this client. Output in that time is lost for it, and tmux keeps reading the PTY.

### 3.6 Input

- Text: `send-keys -l -t %N '<text>'` sends literal UTF-8 (man lines 2164-2187).
- Logical keys: `send-keys -t %N C-c Enter Up F1 M-x`. tmux encodes each key for the pane's modes (cursor keys, keypad, `extended-keys`). This is the same job as herdr's `pane.send_keys`. The adapter needs a name map (`ctrl+c` to `C-c`, `enter` to `Enter`).
- Raw bytes: `send-keys -H -t %N 61 62 63` (tested: `abc` appeared). iTerm2 sends ASCII with `send -lt`, other code points as key tokens, and C0 bytes with `send -H`, because tmux 3.5+ rewrites C0 bytes under modifyOtherKeys (`TmuxGateway.m` lines 1087-1100 and 1233-1241).
- Paste: `set-buffer -b <name> '<text>'` then `paste-buffer -p -d -b <name> -t %N`. `-p` adds bracketed-paste markers when the pane asked for them. Test: after the pane sent `\033[?2004h`, the pane received `\033[200~pasted text\033[201~`.
- Mouse: no command lets a control client inject a mouse event. `send-keys -M` works only from a mouse key binding. The adapter can read `mouse_sgr_flag` and the other mouse flags, encode the report itself, and send it with `send-keys -H`.

### 3.7 Size and several clients

tmux sizes windows, not panes. A pane's size comes from its window's size and the layout.

- `window-size` (window option, default `latest`, man line 3199): `largest`, `smallest`, `manual` or `latest` (the client with the most recent activity). `aggressive-resize` changes which sessions count.
- `refresh-client -C WxH` sets a control client's size. `refresh-client -C @N:WxH` sets the size of one window for this client.
- Client flags (`attach-session -f`, man lines 610-640): `ignore-size` (the client does not affect sizes), `read-only`, `no-output`, `pause-after=<s>`, `new-layouts`, `wait-exit`, `no-detach-on-destroy`. `-r` is `read-only,ignore-size`. `refresh-client -f '!flag'` turns a flag off.

Tests:

- Client A at 120x40, then client B at 80x20 with `latest`: the shared current window `@2` became 80x20. The other windows stayed 120x40.
- B ran `refresh-client -C @2:90x25`: `@2` became 90x25. After B detached, all windows went back to 120x40.
- A client attached with `-r` (read-only, ignore-size): `send-keys` failed with `client is read-only`, but `split-window` worked. As the only client, its 60x15 size still resized every window.

tmux has no per-pane owner and no takeover. Every client that is not read-only can type, and its activity can change the size under `latest`. The adapter can build Oriel's control hand-off from flags:

1. The Oriel window that controls a session uses a normal control client and sets each tab's size with `refresh-client -C @N:WxH`.
2. A watching Oriel window, or an iPhone, attaches with `-f read-only,ignore-size`. It sizes its surfaces to `pane_width` x `pane_height`.
3. Take Back: the watcher runs `refresh-client -f '!read-only,!ignore-size'`, and the old controller runs `refresh-client -f read-only,ignore-size`.
4. tmux cannot refuse a second controller. To show "In use elsewhere", the adapter reads `list-clients -F '#{client_name} #{client_flags}'` and a marker of its own, for example a window option `@oriel_controller=<client name>`.
5. A person in terminal tmux on the same session also counts. With `latest`, that person's typing takes the size back. Oriel cannot stop this.

Oriel's strip of cards and tmux borders: tmux puts a one-cell border between panes. A window of width W with two side-by-side panes gives widths `a + 1 + b = W` (real sample: `{50x30,...,49x30,51,...}` in a 100-wide window). To give each card an exact cols x rows, the adapter sets the window to the sum of the card sizes plus one cell per divider. It then sets the layout with `select-layout`, because tmux keeps its cells, not Oriel's ratios. Guess: a card strip that does not tile one rectangle (for example, one that scrolls sideways past the window width) cannot map to one tmux window size.

### 3.8 Metadata

- Titles: `pane_title` (OSC 0 and 2, or `select-pane -T`). The hook `pane-title-changed` fires. Test: `printf '\033]2;agent: working\007'` gave `%message title %3 agent: working` through a hook.
- Window names: `automatic-rename` sets the window name to the foreground command. Test: `%window-renamed @2 sleep`, then `%window-renamed @2 bash`.
- cwd and command: `pane_current_path`, `pane_current_command` (section 3.2).
- User options: any name that starts with `@`, on the server (`-s`), a session, a window (`-w`) or a pane (`-p`). They hold any string, show in formats as `#{@name}`, and can be watched with `refresh-client -B` (man lines 2233-2240). Tests: `set -p -t %1 @agent_status working`, then `list-panes -a -F "#{pane_id} @agent_status=#{@agent_status}"` printed `%1 @agent_status=working`. `set -s @oriel_order '$0'` and `show -sv @oriel_order` printed `$0`.
- iTerm2 uses session user options as its own store: `@iterm2_id`, `@iterm2_size`, `@affinities`, `@per_window_settings`, `@buried_indexes`, `@origins`, `@hidden` (`TmuxController.m` lines 791-851). It keeps pane user variables in the pane option `@uservars` (`TmuxWindowOpener.m` lines 269-279).

### 3.9 Agent status and notifications

tmux has neither. What exists:

- OSC 133 (3.8): `pane_command_running`, `pane_command_status`, `pane_command_start_time`, `pane_last_prompt_time`, and the hooks `pane-command-started`, `pane-command-finished`, `pane-shell-prompt`. Test: `printf '\033]133;D;3\007'` gave `pane_command_status=3`.
- Progress (OSC 9;4): `pane_pb_state`, `pane_pb_progress`.
- Bells and activity: `window_bell_flag`, `window_activity_flag`, `session_alerts`, and the hooks `alert-bell`, `pane-bell`, `alert-activity`, `alert-silence`.
- `pane_last_output_time` and `pane_output_generation` can show "working" (new output) against "idle".
- Monitor hooks (3.8): `set-hook -B '@name:%*:<format>'` checks a format each second and runs a hook when it changes.
- Because `%output` is raw, desktop notification sequences (OSC 9, OSC 777) and bells reach Oriel's libghostty, but only for panes that Oriel streams.

The adapter must make agent status itself. Two ways, which can work together:

1. Agents report: an agent hook runs `tmux set -p -t "$TMUX_PANE" @oriel_status working`. The adapter subscribes with `refresh-client -B 'st:%*:#{@oriel_status}'`. Latency is up to 1 s. herdr reports faster.
2. The adapter detects, as herdr does: it polls `pane_current_command`, `pane_title` and `capture-pane` text for known agents.

## 5. Verdict

tmux fits with an adapter. It does not fit as-is, and nothing in Oriel's design is impossible on it.

The adapter fakes or stores:

1. The workspace order, in the server option `@oriel_order`.
2. Pane labels, in the pane option `@oriel_label`.
3. Agent status, in the pane option `@oriel_status` (set by agent hooks), or found by polling.
4. Linked-worktree groups, in session options. Git state comes from Oriel's own `git` runs.
5. The binary split tree and its ratios, converted from and to tmux's n-ary cell layout.
6. The control hand-off, from client flags and a `@oriel_controller` window option.
7. The scroll offset and `PaneScroll`, in libghostty on the client.
8. `neighbor`, from pane geometry (`pane_left`, `pane_top`, `pane_width`, `pane_height`). tmux's `{left-of}` targets work only from the active pane (man lines 496-499).
9. `program`, from `ps -t <pane_tty>`.
10. One control client per tmux session that Oriel shows, plus a seed per pane.

The biggest costs:

- Event coverage needs a control client per tmux session (mapping A).
- The seed per pane is a re-rendering and loses some state.
- Size is per window, not per pane, and cards must add up to one window rectangle.
- tmux has no agent model.

Strengths over herdr: raw PTY bytes for libghostty, ids that survive every move, no forced focus changes, left and top splits, and very fast commands (23 ms for a full pane list from the CLI).

### Multiplexer.swift method by method

Fit: Direct (one tmux command), Adapter (several commands or stored data), Local (computed in Oriel), No.

| Member | tmux | Fit |
|---|---|---|
| `sessions()` | list socket files, then `list-sessions` on each | Adapter |
| `snapshot()` | `list-sessions`, `list-windows -a`, `list-panes -a` with formats, `show -s @oriel_order` | Adapter (n-ary to binary tree, agents from `@` options) |
| `updates()` | notification lines from the control clients, paced snapshot reads | Adapter |
| `refresh()` | the same reads | Direct |
| `startServer(within:)` | `tmux -L name new-session -d` (or `set -g exit-empty off` first) | Direct |
| `pane(_:)` | `display -p -t %N -F ...` | Direct |
| `program(_:)` | `#{pane_tty}`, then `ps -t <tty> -o pid,stat,args` | Adapter |
| `terminal(_:cols:rows:observe:takeover:)` | control client, seed, `%output`, `refresh-client -C @N:WxH`, flags | Adapter |
| `screen(_:)` | `capture-pane -p -J -t %N` | Direct |
| `recent(_:lines:)` | `capture-pane -p -J -t %N -S -<lines>`, trim blank rows | Direct |
| `scroll(_:offsetFromBottom:)` | none. Scroll in libghostty. | Local |
| `neighbor(of:_:)` | geometry from `list-panes` | Local |
| `split(_:_:)` | `split-window -d -h|-v -t %N -P -F '#{pane_id}'` | Direct |
| `swap(_:_:)` heading | neighbor, then `swap-pane -d -s %A -t %B` | Adapter |
| `swap(_:with:)` | `swap-pane -d -s %A -t %B` (tmux also allows two tabs) | Direct |
| `resize(_:_:amount:)` | `resize-pane -L|-R|-U|-D <amount x split cells>` | Adapter |
| `setRatio(tab:path:ratio:)` | `resize-pane -x|-y` on the first child, or `select-layout` with a built string | Adapter |
| `move(pane:to:)` `.tab` | `join-pane -d -s %A -t %B -h|-v` | Direct |
| `move(pane:to:)` `.newTab` | `break-pane -d -s %N -t <session>:` | Direct |
| `move(pane:to:)` `.newWorkspace` | `new-session -d`, `join-pane`, `kill-pane` of the placeholder | Adapter |
| `rename(pane:label:)` | `set -p @oriel_label` (or `-u` to clear) | Adapter |
| `newTab(workspace:cwd:)` | `new-window -d -t $N: -c cwd -P -F '#{window_id}'` | Direct |
| `newWorkspace(label:cwd:)` | `new-session -d [-s label] -c cwd -P -F ...` | Direct |
| `rename(workspace:label:)` | `rename-session -t $N` | Direct |
| `move(workspaces:before:)` | `set -s @oriel_order` | Adapter |
| `close(workspace:group:)` | `kill-session`. Group from `@oriel_repo`. | Adapter for `group` |
| `close(pane:)` | `kill-pane -t %N` | Direct |
| `close(tab:)` | `kill-window -t @N` | Direct |
| `rename(tab:label:)` | `rename-window -t @N` | Direct |
| `move(tab:to:)` | `move-window -b|-a -s @N -t <target>` | Adapter (indexes can have gaps) |
| `sendKeys(_:pane:)` | `send-keys -t %N <tmux key names>` | Adapter (name map) |
| `sendInput(_:keys:pane:)` | `send-keys -l` then `send-keys` | Direct |

Count: 16 Direct, 14 Adapter, 2 Local, 0 No. In the table, `move(pane:to:)` has one row per destination, so the rows add up to 32.

## 6. How iTerm2 maps tmux to native UI

Sources: the iTerm2 docs page above and `sources/tmux/` at commit `7f4ff739`.

- `tmux -CC` in a terminal starts the gateway. iTerm2 opens native windows for the tmux session's windows. "Close a session, tab, or window: Kills the tmux session or window. Split a pane: ... split-window. Resize a split pane: ... resize-pane." (docs, "Usage").
- One gateway shows one tmux session. To show another, iTerm2 sends `attach-session -t $N` inside control mode (`TmuxController.m` lines 3161-3166), or `new-session` (lines 3151-3159).
- A tmux window becomes a native tab or a native window. iTerm2 stores which windows share a native window in the session option `@affinities` (`TmuxController.m` line 3333).
- A tmux pane becomes a native split pane. A divider drag sends `select-layout` with an edited layout, then `list-windows` (`TmuxController.m` lines 2498-2530).
- Moves: `move-pane -s %A -t %B -h|-v [-b]` (lines 2734-2744), `break-pane` to a new tab (lines 2933-2941), `swap-pane` (lines 3513-3530), `link-window` and `move-window` across sessions (lines 3096-3112). Pane rename: `select-pane -T` (lines 2798-2807).
- Size: per-window sizes with `refresh-client -C @N:WxH` when the server supports it, else `resize-window` (lines 1270-1290). The docs say "Windows are never larger than the smallest attached client", which describes older servers.
- Flags: `refresh-client -fpause-after=<age>` (line 1416) and `refresh-client -f new-layouts` (lines 1425-1433).
- Notification dispatch: `TmuxGateway.m` lines 914-958 handle `%output`, `%extended-output`, `%layout-change`, the window and session notifications, `%pause`, `%continue`, `%subscription-changed` and `%pane-mode-changed`. `%output` data is decoded from octal escapes (`decodeEscapedOutput`, lines 155-170) and fed to iTerm2's own emulator.
- Seed per pane: section 3.5.
- Limits from the docs: "A tab with a tmux window may not contain non-tmux split panes", and "A tab with split panes may have 'empty' areas ... our split pane dividers are not exactly one cell by one cell in size". Oriel's cards will hit the same border problem (section 3.7).

iTerm2 is proof that a native app with its own emulator can run on control mode alone, with raw `%output` and a `capture-pane` seed. Oriel would follow the same plan.

## Assumptions

- Mapping A (workspace = tmux session) is the default in this report. Mapping B is the alternative.
- Oriel would require tmux 3.4 or later for `refresh-client -C @N:WxH`. Some features (`new-layouts`, OSC 133 hooks, monitor hooks, `wait-for -E`) need 3.8. I did not test older servers.
- Untested: mouse injection, `move-window` reordering, very large output with `pause-after`, or several control clients over SSH.
