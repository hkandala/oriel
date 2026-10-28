# herdr-gpui (penso): Rust and GPUI desktop client

Repo: https://github.com/penso/herdr-gpui ("Herdr UI"), read at `b16a39b` (2026-10-28). macOS, Linux and
Windows. About 607k lines of Rust in 21 crates, 40% of it tests; the app crate alone is 395k. Apache-2.0.
Facts come from the code; guesses are marked **(guess)**. Paths are under `crates/herdr-gpui/src/` unless
they name a crate.

## Summary

- **A cell painter, not a terminal.** herdr emulates every PTY and sends one cell grid per client (the
  client's focused tab) over the private binary client socket. The app paints cells with GPUI and
  hit-tests the rectangles herdr sends. No emulator, no local scrollback.
- **Every non-terminal view is client-only.** Browser, diff review, code view, VS Code and the rest are
  tabs in the app's own JSON file, keyed by daemon and workspace id. herdr, its TUI and other devices
  never see them. There is no plugin framework: each view is a variant of one closed enum.
- **Agents talk to the app** through its own control socket (`herdr-gpui browser open URL`) and, from
  SSH hosts, through herdr workspace metadata tokens used as a mailbox.
- **Notes back to the agent** (on a diff line, a page element, a terminal selection) are one prompt,
  pasted when herdr says the agent is idle, with Enter 150 ms later.
- **Breadth far past Oriel's scope:** Teleport (move a worktree and its agent sessions to another host),
  fan-out, PR and issue lists, automations in Luau, usage meters for 94 providers, cloud sandboxes, a
  phone PWA served from the Mac, a rich chat over ACP and over running Claude Code and Codex.

## 1. Architecture

| Crate | Lines (src) | Role |
|---|---|---|
| `herdr-protocol` | 1.5k | herdr 0.9 wire types copied from herdr (bincode, positional) |
| `herdr-client` | 11k | one worker thread per connection; SSH, WSL and cloud stdio bridges; SSH master pool |
| `herdr-gpui` | 235k | the app |
| `herdr-remote` | 26k | cloud hosts (Coder, Docker, Daytona, Railway, Azure, …), Teleport (7k) |
| `herdr-remote-control` | 14k | a separate daemon that serves the phone PWA over HTTPS |
| `herdr-acp`, `herdr-chat-protocol` | 12k | an ACP agent runner in a pane, and the GUI's attach protocol |
| `herdr-vcs`, `herdr-github`, `herdr-orchestrator` | 2k, 7k, 8k | git CLI worker, checkpoints, code index; GitHub GraphQL; per-repo SQLite |
| `herdr-usage`, `herdr-automate(ion)` | 36k, 9k | plan limits for 94 providers; a Luau automation daemon |
| `herdr-control-protocol`, `herdr-commands` | 2.6k, 1.1k | the app's own CLI socket; a catalog of 118 commands with default keys |

No async runtime in the app: threads, bounded `crossbeam` queues, and a **16 ms timer** that drains every
inbox (`window/construct.rs:63`). Every feature has its own worker, with timeouts and output caps.

## 2. How it talks to herdr

Three ways in:

1. **The binary client socket** (`herdr-client.sock`): all live state. u32-LE length + bincode-2 frames.
   Handshake `endpoint.hello.v1` / `endpoint.welcome.v1` (JSON inside `EndpointControl`) negotiates codecs
   (`shell.snapshot.v1`, `shell.surface.v1`, …), optional surface encodings, and returns `methods`, an
   **allowlist** of JSON-RPC methods for this connection. herdr < 0.9.0 is refused.
2. **The `herdr` CLI in shell scripts**, locally or over SSH, for what the allowlist lacks: `api snapshot`
   (layouts, `agent_session`), `pane process-info`, `pane move`, `agent start|prompt`, `worktree add`,
   `session list|delete`. Teleport, fan-out, the orchestrator, pane moves and chat discovery all go this way
   (`herdr-remote/src/teleport.rs:5`: "The GUI connection's method allowlist lacks layouts, process details,
   and agent sessions").
3. **The JSON API socket**: only the phone daemon uses it (§9), because an inactive client connection may not
   write.

- **Requests** ride the client socket as `ClientShellEndpointRequest{boot_id, request:"{id,method,params}"}`,
  one in flight, 60 s timeout. Methods: `pane.split|close|zoom|swap|focus|focus_direction|scroll|copy_search|copy_motion|selection.read|link.resolve|link.activate|rename|input.set`,
  `layout.set_split_ratio`, `tab.create|close|focus|move|rename`, `workspace.create|close|focus|move|move_block|rename`,
  `worktree.create|list|open|remove`, `client_shell.surface.set`, `integration.*`. Every optional feature checks
  `Method::advertised_in(welcome.methods)` and hides itself rather than fail.
- **State** is a full `ClientShellSnapshot` pushed on every change: workspaces (branch, ahead/behind,
  worktree key, `tokens`), tabs, panes (label, cwd), agents (`agent_status`, `state_change_seq`,
  `state_labels`, `tokens`), custom commands, `tab_bar_right` segments. It carries no agent session ids.
- **Fencing:** a lower `revision` or a new `boot_id` drops the connection; a surface shows only if its
  `(boot_id, projection_revision)` matches the snapshot.
- **Reconnect** is the app's: `500 ms << n`, capped at 30 s, reset after 60 s up. Wake from sleep is seen
  when the wall clock jumps ahead of the monotonic clock; then every SSH link must answer a ping in 3 s.
  Remote links ping after 5 s quiet and die 10 s later. Input is never replayed.
- **Version coupling:** the bincode copy breaks on any field or variant reorder upstream. One optimization
  (a request pipelined behind a focus call) is allowed only for the exact versions 0.9.0–0.9.5 the author
  read. A refused handshake becomes "run `herdr update`" or "update Herdr UI".

## 3. Terminals and panes

- **Wire:** `PaneSurfaceFrame{frame: cells, panes[]{pane_id, rect, inner_rect, scroll, mouse_reporting,
  alternate_screen_active}, splits[]{hit_rect, path}, popup, graphics}`; `CellData{symbol, fg, bg, modifier,
  hyperlink}`. Updates as row patches, `surface-delta`, `surface-scroll` (region shifts plus changed rows) or
  `surface-reuse` (metadata only). herdr renders at most every 16 ms.
- **Painter** (`terminal_painter.rs`, ~4.7k with parts): three layers (backgrounds as runs, text, decorations),
  one `paint_layer` each. Glyphs are shaped per cell (so **no ligatures**), cached by (bold/italic, symbol),
  not by colour, with an ASCII table; 4096 entries. Box drawing and powerline glyphs are geometry. Each pane
  is a cached GPUI view per layer, and output notifies a tiny `SurfaceSignal` so the sidebar is not rebuilt.
  Measured on an M4 Max (160×50 dense grid): warm hover p95 51 → 12 ms, scroll 56 → 14 ms, warm shaping
  6,981 → 0 calls, background quads 8,000 → 50 (`PERFORMANCE.md`).
- **Smooth scroll:** herdr scrolls by whole rows at ≤ 60 Hz, which judders on a 120 Hz trackpad, so the app
  slides each delta over 48 ms, filling rows from up to 4 earlier surfaces.
- **Scrollback, find, copy mode, off-screen selection and links** are server RPCs (`pane.copy_search`,
  `pane.copy_motion`, `pane.selection.read`, `pane.link.resolve`).
- **Input:** text through the IME handler as `TextCommit`, other keys as `Key{code, modifiers}`, Cmd keys
  never reach the pane. `[pane_keys]` defaults: ⌘← ⌘→ ⌘⌫ → ⌃A ⌃E ⌃U, ⌥← ⌥→ → ⌥B ⌥F, and **⇧↩ → Esc CR**
  everywhere, because herdr sends a bare CR for Shift-Enter to apps without kitty keys, which submits an agent
  prompt. Option as Alt `"auto"`: left Option is Alt on US/ABC layouts, right Option types accents. Image
  paste goes as `ClipboardImage`; herdr writes a temp file and pastes its path.
- **Layout:** herdr owns splits and draws borders into the grid. A divider drag sends
  `layout.set_split_ratio{tab_id, path, ratio}`, newest wins, no local preview. Resizes wait 150 ms to settle
  ("agents re-rendering whole transcripts"); with two clients on one tab a window takes the size back only if
  it had input in the last 5 s.
- **Editor groups:** side-by-side groups, each with its own tab strip mixing herdr tabs and app tabs. Because
  herdr projects one focused tab per client, **every extra group showing a terminal, and every torn-off
  window, opens another client connection**. Parked groups report unfocused and re-focus their tab when an
  agent moves every client's focus.

## 4. Remote machines

- **SSH bridge:** `ssh -T -C -o BatchMode=yes -o StrictHostKeyChecking=yes … host /bin/sh -c <probe>` finds
  `herdr`, prints `status client --json`, waits for `accept`, then `exec herdr --session S
  remote-client-bridge`: the same bincode stream over ssh stdio. WSL and cloud hosts run the same script
  over their own exec channel (Azure through a WebSocket-to-stdio helper).
- **All hosts stay connected.** The shown host has an active surface; others send
  `client_shell.surface.set{active:false}` and get snapshots only, which feed the cross-host Overview, the Dock
  badge and notifications.
- **Host keys:** ssh writes the offered key to a scratch `known_hosts` (`accept-new`); after the user approves
  the fingerprint the app appends those lines to the real file.
- **Side traffic** (git, scripts, uploads) uses a private ControlMaster pool per host, two lanes (quick,
  bulk), killed by a pipe watchdog if the app dies. The terminal bridge has its own connection.
- **Port forwards:** one `ssh -N -L 127.0.0.1:L:localhost:R` each, ready when `LocalCommand=echo marker`
  prints (with `ExitOnForwardFailure`), so another process on the port cannot fool it.
- **Listening ports** come from one long-lived `sh` per host (`ss -ltnp` or `lsof`) every 5 s, and each
  listener's environment (`/proc/<pid>/environ`, `ps -E -ww`) gives its `HERDR_WORKSPACE_ID`: ports are listed
  **per workspace** with no guessing.
- **Local Network privacy:** a process in a herdr pane is its own responsible process and gets "no route to
  host" on LAN addresses (TN3179), so device setup (`ssh-copy-id`, `herdr machine add`) runs as a child of the
  app and the pane only mirrors it (`setup_relay.rs`).
- **Teleport** moves a worktree to another host: commits as a git bundle, uncommitted work as temp commits,
  tabs and splits rebuilt from `herdr api snapshot`, agent session files (Claude, Codex, OpenCode, pi, Copilot)
  copied with paths rewritten. A pane can move to another device the same way.

## 5. Non-terminal views: the model

- **Client-only tabs** (`browser/store.rs:1`: "Herdr has no browser panes, so these live only in this
  client"). One closed enum, `Location { Web{url} | Local{file} | Review{checkout} | Orchestrator | Code{file,
  line} | Devices }`, matched by hand in the tab strip, renderer, restore and CLI. Saved in
  `~/.local/state/herdr/gpui/browser-tabs.json`:
  ```json
  {"id":7,"scope":"local:/…/herdr-client.sock","workspace_id":"w7V",
   "location":{"kind":"web","url":"http://127.0.0.1:53122/app"},"title":"My app","origin":"w7V:p2","zoom":125}
  ```
  `scope` names the daemon (workspace ids mean nothing across daemons); `origin` is the agent pane that gets
  notes. Tabs are dropped when their workspace vanishes between two snapshots of one `boot_id`; a daemon
  restart changes ids, so tabs can be orphaned **(guess)**. Group layouts go in `editor-groups.json`.
- **In herdr's TUI** these views do not exist. A browser is never inside herdr's split tree: it sits in a
  GPUI column beside a terminal column.
- **herdr's own plugins** are passed through, never run: bound `plugin_action` keys (with the highlighted text
  as `selected_text`), link handlers, plugin popups as terminals, and the values plugins report.
  Settings › Plugins lists every custom `$name` from `pane.report_metadata` / `workspace.report_metadata`
  (64 keys, 48-character samples) and adds a token to the sidebar by editing `[ui.sidebar] rows` in herdr's
  **shared** `config.toml`, so the TUI changes too.
- **Durable stores avoid workspace ids:** notes, viewed marks and checkpoints key on host + repo + branch.

## 6. Built-in views

### Browser

- **Engine:** `lb-wry` 0.53 (a wry fork): WKWebView on macOS, WebView2 on Windows, nothing on Linux (system
  browser; a phased WebKitGTK plan in `herdr-gpui/docs/linux-browser-plan.md`). No engine shipped.
- **Z-order trick** (`browser/stacking.rs`): GPUI paints one layer, so the WKWebView is moved *under* GPUI's
  NSView, every background paints around the page rects, and a router NSView above answers `hitTest:` so
  menus and toasts draw over live pages. Hidden pages are parked at (-100000, -100000) because a hidden NSView
  still caught drags. A local `NSEvent` monitor hands keys to the focused page except the app's tab,
  workspace and font keys (font keys zoom the page, 50–300%).
- **Rules:** navigation only to http(s), `about:blank` and its preview scheme; downloads refused; URLs ≤ 8 KB;
  a typed bare host gets `http://` for loopback names and `https://` otherwise. **OAuth popups** are built from
  WebKit's own configuration inside `createWebViewWith` and adopted as a tab, so `window.opener` works, and
  `webViewDidClose` closes it.
- **Missing:** one default WebKit store for every host (no profiles); Web Inspector only in debug builds; no
  cap on live views (one per tab per window); the current URL is written back on every load.
- **Remote pages:** a per-port `-O forward -L` and the URL rewritten to `127.0.0.1:<random>`, which changes the
  origin (storage lost), saves a dead port on restore, and is not applied to addresses the user types.
- **Agents open pages** (§7). Page automation is small: `tab text` (`innerText`, 64 KB), `screenshot`,
  navigate, back, zoom. No click or type, no CDP.
- **Annotate:** `annotate.js` in a closed shadow root picks an element, a text selection or a region; the
  note is written in a **native** panel the page cannot read; a `takeSnapshot(afterScreenUpdates:)` PNG per
  pick; then one prompt with selector, quoted text marked as data, an HTML snippet, the screenshot path and the
  note. Screenshot paths are on the Mac even for a remote agent **(guess: a gap)**.
- **Local pages:** a custom scheme `herdr-preview://` rooted at one folder (canonicalized, no dotfiles, never
  `$HOME`, 403 to web origins). Markdown renders with pulldown-cmark, sanitized, under a no-script CSP. Local
  preview pages get `herdr.send(summary, data)` and an "explainer kit" CSS/JS themed like the window.

### Review (diff) tab

- **Data:** git CLI only, on a worker, 30 s timeout. First `--numstat` and `--name-status` (cheap at any
  size), then patch bodies in batches of 64 files or 20k lines, visible files first; a file over 20k lines or
  4 MiB shows **Load diff**. Untracked files from `ls-files --others`, generated files from
  `check-attr linguist-generated` (folded).
- **Bases:** Uncommitted (`HEAD`) and Branch (`merge-base HEAD <base>`, base = the PR's base, else
  `origin/HEAD`, else main/master; a picker lists branches most recently left first). Nothing is fetched.
- **UI:** unified or side by side (removed runs paired with the added run after them, which also gives word
  emphasis), a GitHub-like file tree with filter and **Hide viewed**, expand context (200 lines from the
  working file), find, ignore whitespace, copy hunk as patch, `e` opens `$EDITOR` in a split. syntect runs one
  hunk at a time as it scrolls in and maps tokens to **7 classes coloured from the terminal palette**, so a theme
  change needs no re-parse. One `String` per file with line ranges into it.
- **Viewed marks** keyed by (checkout, branch) store each file's +/− counts, so a file that changes again
  comes back unviewed (`review-viewed.json`).
- **Refresh:** a poll of `git diff --numstat HEAD` and `git status --porcelain` every 5 s on the focused
  checkout (30 s for others), shared with the title bar's git chip. No file watching. No reload while a note
  is being written.
- **Notes:** click any gutter; anchor = path + side + working-tree line (+ the revision for a removed line);
  50 notes × 2,000 chars; sent through the delivery below.

### Checkpoints

On by default. When an agent's status goes idle/done → working, or working/blocked → idle/done (not
blocked → working; never on the first snapshot or a new `boot_id`), a 269-line POSIX script copies the real
index to a temp index, `git add -A`, `write-tree`, skips a tree equal to the last one, then `commit-tree -p
HEAD` with a `Herdr-Branch:` trailer and `update-ref refs/herdr-gpui/checkpoints/<sha1(branch)>/<ms>`; newest
50 kept, `core.fsmonitor=false`. Restore captures the current state first, refuses during a merge or rebase
or on another branch, then `read-tree -m -u` and `reset`. The dialog shows only +/− counts, no diff.

### Others

| View | What | Source | Cost (src lines) |
|---|---|---|---|
| Code view | read-only file at a line, outline | syntect, a ctags-like line scanner | 0.8k |
| Go to File / Symbol | empty query lists uncommitted files first | git ls-files, line scanner (≤ 300k symbols) | 1.7k |
| Open in editor | `pane.split` then types `exec sh -c …` into the new shell; reuses Neovim via `--listen` / `--remote-expr` | local only | 0.5k |
| VS Code tab | `code serve-web` on loopback with a token file, license consent | local only | 3.7k |
| px0 tab | px0.ai's review workbench | local only | 1k |
| Overview | needs-you first across hosts; pin, snooze, settle; a Closed shelf reopens agents with `--continue` | snapshots | 2.7k |
| PRs and Issues | GitHub/GitLab lists, merge, dispatch an agent on branch `agent/<id>-<slug>-<hash8>` | GraphQL, SQLite per repo | 16k |
| Fan-out | one prompt to ≤ 6 agents in their own worktrees, compare, keep one | herdr CLI scripts | 3.2k |
| Worktree scripts | `.herdr/worktree.toml` setup/run/archive, trusted by file digest | `tab.create` with the script in env | 1.2k |
| Usage, load, ports, caffeine | status bar meters | 94 providers; sysinfo; `ss`/`lsof` | 40k |

## 7. Agents talking to the app

- **Local:** `$XDG_STATE_HOME/herdr/gpui/control.sock` (0700 folder), one JSON line in, one out, 256 KiB,
  `PROTOCOL_VERSION` 9 reported by `status`. The CLI is the app binary; the caller comes from
  `HERDR_PANE_ID` / `HERDR_WORKSPACE_ID`, which also picks the window (exit 5 if none shows that workspace).
  Stable exit codes 0–8, long-poll `events wait`.
  ```json
  {"method":"browser.open","page":{"url":"http://localhost:3000/"},"caller":{"pane_id":"w_1:p1","workspace_id":"w_1"},"focus":true}
  {"method":"browser.feedback","pane_id":"w_1:p1","wait_seconds":600}   ← {"status":"feedback","text":"…"}
  ```
  A managed `SKILL.md` (marker `herdr-gpui-managed-skill v1`) goes into `~/.claude/skills` and `~/.agents/skills`
  after one consent; a user's own file without the marker is never touched.
- **SSH hosts: metadata tokens as a mailbox.** The app installs a 185-line `sh` shim on each host. It runs
  `herdr workspace report-metadata $HERDR_WORKSPACE_ID --source herdr-gpui --ttl-ms 30000 --token
  herdr-gpui-<id>=open <pane> --token herdr-gpui-<id>_0=<80 chars> …` (≤ 12 chunks, because herdr keeps 80
  characters per value and 16 tokens per report). Windows read it from the next snapshot, serve each id once
  (a 256-entry seen ring), and accept only http(s) in that workspace.
- **Delivery to an agent** (`agent_notes.rs`), shared by review notes, page notes and terminal-selection
  notes: if the agent waits in `browser feedback --wait`, it takes the batch; else once herdr reports the
  agent idle or done (or after 120 s), the text is pasted (controls but `\n` stripped), then Enter 150 ms
  later. Never into a pane with no agent (a shell would run it) or a blocked one; those wait for `feedback`.
  **Withdraw** takes back a queued batch; sent notes stay dimmed; Send resends only new or edited notes.

## 8. Chat view

Oriel's decisions are in [../ui/chat-view.md](../ui/chat-view.md). In short (`herdr-gpui/docs/rich-chat.md`): native ACP chats
run by `herdr-acp` inside a pane (found through the pane token `acp`; the GUI derives the socket path itself),
and, opt-in, **running Claude Code and Codex sessions drawn as rich messages above the CLI's own input
rows**: only the upper terminal cells are replaced, the bottom rows (editor, approvals, IME, image paste) stay
the real program (`chat/terminal.rs:1`), and a blocked prompt expands them. The session is found by probing
herdr metadata and the process every 2–30 s; Linux hosts only. Six layouts, Markdown, TeX, Mermaid, and
`herdr-ui` fenced widget cards.


Details, read at `b16a39b`:

### Two chat paths

| | Native ACP chat | Existing CLI session ("observe") |
|---|---|---|
| Process | `herdr-acp` runs in the pane and drives the agent headless; it draws **its own** TUI there | the agent's own TUI, unchanged |
| Agents | Claude, Codex, pi, Copilot, Gemini, opencode, any ACP command | **Claude and Codex only** (`herdr-gpui/src/chat/existing.rs:375-379`) |
| Data | ACP or a translated headless protocol, live, with text deltas (`Change::Append`) | the agent's own JSONL, read-only, no live text |
| Send, approvals | GUI composer, permission cards, model/mode menus | none: the original TUI editor stays visible below the chat |
| Hosts | local socket; SSH via `herdr-acp connect ID` over ssh stdio | **Linux agent hosts only** (local or SSH) |

Both feed one wire, `herdr-chat-protocol` (u32 length + JSON frames, `Hello/Welcome/Snapshot/Change/Ack/Bye`, cursor
with epoch and seq). Client and server share one reducer, `Transcript::apply`; a change that does not fit makes the
client ask for a fresh snapshot (`herdr-gpui/src/chat/session.rs:183-197`).

### Native ACP chat (replaces the TUI)

- Start: `tab.create` with `env.HERDR_ACP=<path>`, then one fixed line typed into the new shell,
  ` sh -c 'exec "$HERDR_ACP" claude'` (`herdr-gpui/src/chat/start.rs:101-150`). Same idea as Oriel's chooser.
- Claude runs as `claude -p --input-format stream-json --output-format stream-json --include-partial-messages
  --permission-prompt-tool stdio --session-id <id>` (`herdr-acp/src/claude.rs:31-45`); approvals arrive as
  `can_use_tool` control requests. Codex runs as `codex app-server`, pi as `pi --mode rpc` (pi extension
  `select`/`confirm` become permission cards). Others go through ACP adapters (`herdr-acp/README.md`).
- Subagent messages are dropped from the stream (`herdr-acp/src/claude/bridge.rs:113-118`); `TodoWrite` becomes the plan.
- Discovery: `herdr-acp` sets pane metadata token `acp=<endpoint id>` and `pane.report_agent` state; the GUI derives the
  socket path from the id, never from daemon text (`herdr-gpui/src/chat/discovery.rs:40-69`).
- So the agent's real TUI is gone. The "terminal" for this chat is `herdr-acp`'s own ratatui view
  (`herdr-acp/src/tui/view.rs`). `herdr-gpui chat show|hide|toggle` flips the GUI overlay off that view.

### Existing CLI session (the part that matches Oriel)

- **Finding the file** (`herdr-gpui/src/chat/existing.rs:237-346`): `herdr api snapshot` gives the pane's
  `agent_session` (must be a UUID and name the same agent as the pane); `herdr pane process-info` gives the foreground
  processes; a shell script reads `/proc/<pid>/stat` for parent, group and start ticks (`:294`, `:352-359`). The snapshot
  is read again after, and the binding drops if the session changed. Probes every 2 s, backing off to 30 s (`:25-26`).
- Then it spawns `herdr-acp observe <agent> <session> <pid> <start-ticks> --pane <id>` locally, or the same over
  `ssh` (`herdr-gpui/src/chat/chats.rs:41-70`). The observer re-checks the start ticks, then looks for the file:
  open fds in `/proc/<pid>/fd`; for Claude `<CLAUDE_CONFIG_DIR or ~/.claude>/projects/*/<session>.jsonl` (Claude
  opens its log only while writing); for Codex, rollouts in three date folders from the UUIDv7 timestamp
  (`herdr-acp/src/observe/identity.rs:48-92`). Exactly one match or it fails. It reads only `CLAUDE_CONFIG_DIR` /
  `CODEX_HOME` from `/proc/<pid>/environ` (`:150-186`). No cwd search, no newest-file guess, no hooks.
- **Following**: polls every 1 s (`herdr-acp/src/mirror.rs:27`). On a size or mtime change it **re-parses the last
  8 MiB** (`mirror/transcript.rs:151-194`, with a `ponytail` note that an incremental reader may come later), then diffs
  old and new entry lists into `Push/Replace/Truncate`, or sends a new snapshot when history was rewritten
  (`mirror.rs:130-211`). It pins the file by dev+inode and stops when the process start ticks change
  (`observe.rs:146-159`, `identity.rs:115-129`). A partial last line waits for its newline (`transcript.rs:512-514`).
- **Parsing** (`herdr-acp/src/mirror/transcript.rs`): Claude: `user`/`assistant` records, blocks `text`, `thinking`,
  `tool_use`, `tool_result` (`is_error` → failed); dedupe by `uuid`; `isSidechain` skipped, so no subagents
  (`:431-483`). Codex: `session_meta`, `turn_context` (model, effort), `compacted`, `event_msg/token_count` (context
  use), `response_item` `message`/`reasoning`/`function_call`/`custom_tool_call`/`*_output`; other `event_msg` ignored to
  avoid duplicates (`:314-391`). Tool results pair by call id through a map (`:277-312`); an output without a call is
  dropped. Unknown records, oversized lines (>1 MiB) and bad JSON are skipped and set `truncated`. Caps: 2,000 entries,
  2 MiB text, 128 KiB per field. Tool kind is always `Other`: cards show the raw JSON input.
- **Input and approvals**: the transcript is read-only; `submit` fails with "use the agent's terminal"
  (`session.rs:141-144`). The GUI replaces only the upper rows of the real pane; the **bottom 8 rows stay the live TUI
  editor**, and it grows to the whole pane minus 3 rows while herdr reports `blocked` (`chat/terminal.rs:15-47`). A
  draggable divider sets its height. Status comes from the herdr snapshot, not the log (`session.rs:85-91`).
- Failures: one failed probe keeps the overlay, two drop it and the pane is a plain terminal again
  (`existing.rs:181-188`). Non-Linux hosts fail the `uname` check, so macOS agents never get this view.

### UI (shared by both paths)

- Entry kinds: user, agent, thought, image, tool, turn summary, notice (`herdr-chat-protocol/src/model.rs:138-164`).
- Tool card: header with a status dot (pending, running, done, failed), folded by default; folded it shows diff `+/−`
  counts, images, the first locations and output lines; open shows full text (`view/entries.rs:232-460`). **No
  grouping** of consecutive tool calls and no detail levels. Issue #595 asks for "each turn's tool work folded into one
  row"; #837 proposes clearer tool cards, live tool progress and a "Jump to latest" button.
- Thoughts fold to their first line (`view/entries.rs:191-229`). Plan and changed files sit in a side rail (`view/rail.rs`).
- Six layouts: Timeline, Bubbles, Terminal (Claude Code look), Document, Cards (one card per turn), iMessage.
- Rich text: Markdown, TeX (RaTeX), syntax colors, tables, Mermaid, inline HTML pages, a `herdr-ui` widget fence.
- Composer (ACP only): `/` completion, history, attachments, queued prompts, header buttons for model, thinking, mode;
  context use and cost; permission cards above the composer (`view/panels.rs`).

### Size and issues

Without tests: GUI chat 16.2k lines (`herdr-gpui/src/chat`), `herdr-acp` 10.7k (of which the log mirror and observer
~1.8k), protocol 1.6k. About 28.5k, or 48k with tests; the phone app adds 13.8k. No TODOs in the chat code. The README
still says the view "is never offered for SSH", but the code routes SSH (`chat/discovery.rs:28-37`). Open: #595
(chat lens beside the terminal; the user runs Claude/Codex on macOS, which observe does not cover), #837 (follow-ups).

### For Oriel

- Copy: find the file from herdr's `agent_session` id plus the agent's config dir, an exact-name lookup, never a
  newest-file guess. Fail closed to the terminal on zero or several matches.
- Copy: keep the live TUI's bottom rows under a read-only chat, and expand them when herdr says `blocked`. It is a cheap,
  agent-neutral answer to approvals, and a nicer fallback than a full "Show Terminal" switch.
- Copy: pin the file (dev+inode), skip a partial last line, skip unknown records, pair tool results by id in a map,
  and send a fresh snapshot when the file was rewritten.
- Copy: Codex reads only `response_item`, never the duplicated `event_msg` text; Claude dedupes by `uuid`.
- Avoid: re-parsing an 8 MiB tail on every change; tail from an offset instead (Oriel's `tail -F`).
- Avoid: `/proc`-only process checks (Linux only); Oriel's own launch flags give the session id directly.
- Avoid: a headless replacement for the TUI (the native ACP path); it loses the real TUI, which Oriel keeps.
- Note: their sends need the ACP path; the observed chat has no composer. Oriel's `agent.prompt` composer on the real
  TUI is something neither path has.

## 9. Settings, keys, notifications, phone

- **Settings:** `config-gpui.toml` (managed, rewritten each start), `config-gpui.local.toml` (user), and
  herdr's shared `config.toml` (theme, sounds, toasts, `[keys]`), edited with `toml_edit`, polled every 250 ms
  and taken after two equal reads. Each row says "Herdr" (shared) or "Herdr UI". A search box over a static
  row catalog. Themes: herdr's 18 plus Ghostty's theme files; the host theme goes to herdr so OSC 10/11
  queries get answers.
- **Keys:** catalog defaults → herdr `[keys]` (prefix chords too) → app overrides; per device, a host's own
  `[keys]`. Palette with fzf syntax (nucleo) and frecency keyed on host + path + branch.
- **Notifications:** herdr's `SemanticNotification` from every host, with the TUI's timing (delayed attention
  needs Blocked; Finished waits ≤ 1 s for Done; hidden for the visible tab of the focused window). Dock badge
  counts Done + Blocked once per `(host, boot_id, pane_id)`, highest `state_change_seq` wins. Sounds per agent.
- **Accessibility:** one pane's rows as AccessKit text; F6 moves between regions; `ink()` shifts only the
  lightness of status colours to WCAG 3:1 / 4.5:1 against the chrome.
- **Phone:** a separate per-user daemon serves a PWA over HTTPS on the LAN or Tailscale, with its own CA
  name-constrained to private ranges. Pairing: a QR with a 60 s one-time token and the CA fingerprint, a device
  P-256 key, a 6-digit code from `sha256(token‖key‖nonce)` approved on the desktop, then signed challenges
  for short bearer tokens. Reads through an inactive client connection; every write on the JSON API with
  `focus:false`; `pane.read` every 300 ms while a phone shows a pane. Web Push works; the iOS app is only a
  Live Activity companion and its APNs path is not wired.

## 10. License

Apache-2.0 (`LICENSE`, `NOTICE`). Code may be reused, in Swift translation or verbatim (scripts, JS), with the
license and a notice of changes. `herdr-protocol` and the settings schema are themselves adapted from herdr
(Apache-2.0). Small, self-contained pieces worth taking as text: `annotate.js` (374 lines), the checkpoint
script (`herdr-vcs/src/checkpoint/script.rs`), the remote shim (`remote_browser/herdr-gpui.sh`), the review
prompt wording. Bundled RaTeX is MIT, KaTeX fonts OFL.

## 11. Compared with Oriel

| Topic | herdr-gpui | Oriel | Verdict |
|---|---|---|---|
| Terminal bytes | herdr's cell grid, painted by GPUI | ANSI on `terminal session control`, libghostty | Oriel's: ligatures, local scrollback and find, no painter to keep |
| herdr access | binary socket, method allowlist, CLI for the rest | JSON API through `remote-api-bridge`, events then snapshot | Oriel's: no positional wire copy, no CLI detour |
| Panes on screen | one focused tab per connection; a connection per extra group | every pane of the shown tab streamed on its own | Oriel's |
| Non-terminal panes | client-only tabs in a local JSON, a closed enum | a labelled placeholder herdr pane, one kind registry | Oriel's: other devices and the TUI see it, it survives restarts |
| Browser profiles | one store for all hosts | one `WKWebsiteDataStore` per machine | Oriel's |
| Remote localhost | per-port `-L`, URL rewritten | one SOCKS `-D` per machine, `<machine>.localhost` | Oriel's |
| Web Inspector | debug builds only | ⌥⌘I, `isInspectable` | Oriel's |
| OAuth popups | adopted with `window.opener` | opened in the same card | **theirs** |
| Ports | per workspace via `HERDR_WORKSPACE_ID`, every 5 s | menu on click, by process name | **theirs** for grouping; Oriel's for no timer |
| Diff | review tab: two-phase load, side by side, viewed marks, notes | changes drawer, read-only, unified | combine: Oriel's drawer, their loading and marks |
| Last turn | commit + hidden ref, restore | loose `write-tree`, id in a state file | **theirs** |
| Agent → app | control socket; token mailbox from SSH hosts | float and copy tokens; none for pages | same pattern; theirs reaches further |
| Notes → agent | paste when idle, Enter 150 ms later | "Later" | **theirs** as the rule |
| Chat | rich view above the CLI's own input rows; ACP | transcript tail + composer (design) | see [../ui/chat-view.md](../ui/chat-view.md) |
| Phone | PWA served by a Mac daemon | native iOS app over SSH (design) | Oriel's direction; their pairing is a good reference |

## 12. For Oriel

### Reuse

1. **Checkpoints as commit + hidden ref** for the changes panel's Last turn: `commit-tree -p HEAD` under
   `refs/oriel/checkpoints/<sha1(branch)>/<stamp>` with a branch trailer, keep 50, real index copied to a temp
   index, `core.fsmonitor=false`, skip an unchanged tree, ignore blocked → working. Every device sees the refs,
   `git gc` cannot prune them, and no state file holds the tree id. Cost: about 1 day.
2. **The delivery rule for notes to an agent:** paste when herdr says idle or done (hold up to 120 s), Enter
   150 ms later, never into a shell or a blocked agent, Withdraw while queued, resend only new or edited. The
   prompt marks quoted code as data. Fits `pane.send_input` with bracketed paste. Cost: 1–2 days with the
   Changes panel's Comments.
3. **Two-phase diff loading** (`--numstat`/`--name-status`, then bodies in bounded batches, visible first,
   "Load diff" past 20k lines or 4 MiB) and **viewed marks with +/− counts**. Cost: in the drawer's budget,
   +0.5 day for marks.
4. **Ports per workspace** from `HERDR_WORKSPACE_ID` in each listener's environment, one more line in the
   ports chip's shell run. Cost: 2 hours.
5. **OAuth popup adoption** in the browser card: build the popup from WebKit's configuration in
   `createWebViewWith` and show it as a sheet over the card until `webViewDidClose`. Cost: half a day.
6. **The metadata-token mailbox** for a later "agent opens a page in a card": an id per request, URL in
   80-character chunks, 30 s TTL, served once, http(s) only, only the request's own workspace, then Oriel's
   load rule. Same channel as Oriel's float requests. Cost: 1 day plus a small shim or pi-hkandala tool.
7. **Small habits:** navigation filter (http(s) and `about:blank` only, downloads refused); per-card page zoom on
   ⌘+/⌘−; hidden web views out of the hierarchy so they take no drops; `LocalCommand=echo marker` +
   `ExitOnForwardFailure` for forward readiness; host-key approval through a scratch `known_hosts`; wake
   detection by wall vs monotonic clock; `ink()` for status colours on Glass.
8. **Terminal key defaults** to check against libghostty: ⇧↩ → Esc CR for agents, Option as Alt "auto".

### Avoid

- The binary client socket and its allowlist (and the CLI detours it forces), one connection per visible tab,
  a 16 ms polling tick, server-rendered cells.
- Client-only tabs keyed by daemon workspace ids, and a closed enum per surface.
- Writing herdr's shared `config.toml` from the app.
- Per-port forwards that rewrite the page origin; a web view per tab per window with no cap.
- Typing a command into a fresh shell to start a program (their editor path): Oriel's `layout.apply` with a
  command is better.
- The breadth (usage meters, automations, cloud sandboxes, orchestrator, VS Code server): each is a product.

### Worth adding (cost guess)

| Feature | Why | Cost |
|---|---|---|
| Restore a checkpoint, diff first in the drawer | undo an agent's turn | 1–2 days after item 1 |
| Branch base picker with fallback PR base → `origin/HEAD` → main/master | the drawer plans only `origin/<default>` | half a day |
| Side by side and word emphasis in the drawer | reading big edits | 2 days |
| Annotate a page and send to the agent | their most-used browser loop | 3–4 days; needs a bridge, so after the first slice |
| Show a local `.md`/`.html` an agent wrote (scheme handler, no-script CSP) | no dev server needed | 1 day local; more over SSH |
| Back/Forward pane history (⌘[ ⌘]) and reopen closed tab (⌘⇧T) | navigation | 1 day each |
| Plugin values: show `agents[].tokens`, `state_labels`, `tab_bar_right` as herdr's TUI does | herdr plugins show something in Oriel | 1 day |
| Closed-agents shelf that reopens with `--continue` | recover a closed agent | 1 day |
