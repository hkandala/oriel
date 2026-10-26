# herdr-web-ui (devswha): browser and phone PWA, chat view, remote PCs over SSH, web push

The most complete herdr client of the four, and the only one with a real chat view. The design notes in its
`AGENTS.md`, `server/AGENTS.md` and `src/AGENTS.md` record many hard-won, live-verified herdr facts (quoted below).

## Architecture
- **Stack:** React 18 + `@xterm/xterm` 5.5.0 (patched) in the browser (`src/`). Bun.serve backend (`server/`) that
  bridges herdr's newline-JSON unix socket. `shared/` holds the wire contract (`shared/protocol.ts`, plus
  `shared/herdr-api.generated.ts`, generated from the herdr API schema "protocol 22, schema_version 1").
- **Ships as a herdr plugin** (`herdr-plugin.toml`, `min_herdr_version = "0.9.0"`): `[[build]]` runs `bun install` +
  `vite build`; `[[startup]]` runs `bun scripts/plugin.ts start` on every herdr start; `[[actions]]` start/stop/status;
  a `[[panes]]` entry `phone` opens a zoomed herdr pane that prints the phone-setup QR code.
- **Stated rule:** "The app is only a bridge: herdr owns every pty, scrollback and agent state."
- **PTY sidecar:** Bun cannot load node-pty, so `server/pty/pty-host.mjs` (Node + `@lydell/node-pty`) runs one command
  on a real PTY: `herdr terminal attach <terminal_id>`. Its stdin protocol is NDJSON
  `{"t":"i","d":text}` (write), `{"t":"r","c":cols,"r":rows}` (resize), `{"t":"p","paused":bool}` (flow control).
  Stdout is the raw PTY bytes.

## herdr socket usage (`server/herdr/client.ts`)
- **One connection per RPC.** "herdr closes the socket after each response". Frame `{"id","method","params"}\n` →
  `{"id","result"}` or `{"error":{"code","message"}}`. Timeout 10 s. No pooling.
- **Methods used:** `ping` (→ `{version, protocol, capabilities}`; `capabilities.direct_terminal_attach`),
  `session.snapshot` (→ `{snapshot:{workspaces,tabs,panes,agents,layouts,...}}`), `server.agent_manifests`,
  `workspace.create {cwd,label,focus:false}`, `workspace.rename/move{insert_index}/close{close_group}`,
  `tab.create {workspace_id,cwd,label,focus:false}`, `tab.rename`, `tab.close`, `pane.rename`, `pane.close`,
  `pane.read {pane_id, source: "visible"|"recent"|"recent_unwrapped"|"detection", format:"text"|"ansi", strip_ansi, lines}`,
  `pane.get` (for `pane.scroll` info), `pane.scroll {pane_id, offset_from_bottom}`,
  `pane.selection.read {pane_id, anchor:{row,col}, cursor:{row,col}}`, `pane.send_text {pane_id,text}`,
  `pane.send_keys {pane_id, keys:[...]}`, `pane.process_info {pane_id}` ("takes `pane_id`, not `target`. Given
  `target`, it silently answers for the focused pane"), `agent.get {target}`, `agent.start {name,kind,pane_id,args,timeout_ms}`,
  `agent.prompt {target,text}`, `worktree.create/list/open/remove`.
- **Events:** `events.subscribe {subscriptions:[...]}` keeps the socket open. First frame `result.type =
  "subscription_started"`, then event frames. Facts from `server/collector.ts`:
  - `pane.agent_status_changed` REQUIRES `pane_id`; one connection can carry many per-pane subscriptions.
  - A second `events.subscribe` on an open connection is silently ignored → reopen with the full set when panes change.
  - `pane.created` / `pane.closed` / `pane.exited` / `pane.focused` subscribe globally (no pane_id).
  - Status frames are flat `{event:"pane.agent_status_changed", data:{pane_id, agent_status,...}}`; structure frames
    carry snake_case `data.type`, e.g. `{event:"pane_focused", data:{type, pane_id, workspace_id}}`.
  - herdr ≥0.9.2 closes a subscriber that falls behind (`events_lost`, which may not arrive). Correct order:
    subscribe → wait for `subscription_started` → `session.snapshot` → diff against last-told status.
  - `server/collector.ts` is the ONLY status subscription. It fans out over the browser WS and SSE. There is a 60 s
    backstop snapshot. The browser also polls `/api/session` every 5 s.

## Live terminal bytes and rendering
- **Attach, not polling.** One `herdr terminal attach <terminal_id>` child per pane per bridge (through the PTY
  sidecar). It is shared by all browser clients of that bridge, and late joiners get a 256 KiB replay tail.
  The attach stream is a screen-diff stream that herdr renders: "herdr's screen-diff attach stream consumes OSC 52
  before clients".
- **One direct-attach slot per terminal.** A second attacher gets `attach_held` ("already has an attached client …
  retry with --takeover"). They never pass `--takeover` on their own. Only an explicit user "Open here" does.
  "The herdr TUI stays connected" during a takeover. Only another `terminal attach` client is displaced.
- **xterm.js in the browser** with `scrollback: 0`: "never rebuild an attached terminal from `pane.read`. The attach
  byte stream is the source of truth". herdr owns scrollback. The browser scrolls it with `pane.scroll` and copies
  with `pane.selection.read`. Unicode width table "15-herdr" so wide glyphs match herdr's layout.
- **Flow control** (`docs/terminal-flow-control.md`): the client acks after xterm's write callback (`pty-ack
  {stream_id, offset}`). The bridge pauses PTY reads at 256 KiB outstanding and resumes at ≤64 KiB. A client stalled
  for 2 s is closed with WS code 4008.
- **Input:** WS `input {pane_id,text}` → written to the attach PTY (the fast path). WS `keys {pane_id, keys}` →
  `pane.send_keys`, "so Herdr encodes the target pane's keyboard protocol". `resize` → PTY resize. The resize of the
  attach PTY resizes the herdr pane's terminal.
- **Roles:** `interact` vs `observe`. An observer cannot type or resize, and it adopts the pane geometry (`pane-geometry`).
- **Mirror fallback** (`server/mirror.ts`) where attach is missing (Windows): poll `pane.read source:visible
  format:ansi` a few times a second, send only changed rows, and type through `pane.send_text`.
- WS frames (`shared/protocol.ts`), client→server: `attach{pane_id,cols,rows,flow_control?}`, `detach`, `take-over`,
  `input`, `keys`, `resize`, `submit{id,pane_id,text,payload,delivery:"immediate"|"queue"}`, `pending-action`,
  `secret`, `pty-ack`, `role`. Server→client: `snapshot{snapshot,features}`, `pty-data{pane_id,data,flow}`, `pty-exit`,
  `pane-geometry`, `pane-status`, `pane-exited`, `session-changed`, `submit-result`, `pending-messages`, `error`.

## Layout / UI ↔ herdr mapping
- **One pane at a time.** `src/components/TabStrip.tsx`: "The app shows one pane at a time, so a tab with several
  panes" gets a pane menu. herdr splits are NOT drawn. A tab opens the last-viewed pane, else
  `snapshot.layouts[].focused_pane_id`, else the first.
- **Sidebar:** PC → workspace → pane. Status roll-up per workspace in herdr's order: blocked > done > working > idle
  (`rollupStatus`, `src/lib/status.ts`). Labels: idle→READY, working→RUN, blocked→INPUT, done→DONE. There is also a
  separate "Agents" list joined from `snapshot.agents`. Workspace drag uses `workspace.move`. Worktree groups come from
  `worktree.list`.
- **Local storage:** UI preferences in one localStorage record. Per-pane view (`chat`/`terminal`), drafts and the
  last-viewed pane per tab are keyed `paneStorageId(machineId, paneId)`. The server stores push subscriptions, VAPID
  keys, paired devices (token hashes) and `machines.json` (remote PC registrations + last snapshot). Everything else is
  fetched from herdr.

## CHAT view (the key part)
**Where messages come from: the agent's own session transcript files, read-only, located through herdr.** Terminal
screen scraping is only the fallback. `server/conversation.ts` header:
- **Claude Code:** `agent.get {target: pane_id}` → `agent.agent_session.value` = session UUID (reported by herdr's
  Claude hook). File: `~/.claude/projects/<project>/<session>.jsonl` (`server/claude-store.ts`). It honours
  `CLAUDE_CONFIG_DIR` from the process's environment, found through `pane.process_info.foreground_processes[].pid`. If
  herdr has no id, it falls back to Claude's own PID record for that process.
- **pi / omp:** `agent.get` → `agent_session = {agent, kind:"path", source, value:"/abs/…jsonl"}`. It accepts only
  paths inside `~/.pi/agent/sessions/` (or `PI_CODING_AGENT_SESSION_DIR`/`PI_CODING_AGENT_DIR`) or
  `~/.omp/agent/sessions/`. "herdr's integration re-reports the session file on every `session_start`, so `/new`,
  `/resume`, `/fork` and `/clone` need no inference". pi's file is an entry tree (the `/tree` command moves the leaf),
  so `server/pi-tree.ts` projects it onto the active branch.
- **Codex:** the hardest case. `agent.get` gives a thread id from Codex's SessionStart hook, but "a hint, not proof":
  since Codex 0.157 the hook runs in a shared app-server daemon and reports every TUI's thread to the first pane. So
  `server/codex.ts` checks the rollout files the Codex processes hold open (`lsof -nPbw -a -p <pids> -Fn` on macOS,
  `/proc/<pid>/fd` on Linux), reads `CODEX_HOME` from the process environment, and matches on unique pane text as a
  tiebreaker. Rollouts can be hundreds of MB, so reads are paged (`TRANSCRIPT_WINDOW_BYTES = 16 MiB`).
- **omo / gjc:** found through the pane's process tree (`pane.process_info`). herdr's label is unreliable for them.
- **Fallback for unrecognised panes** (shells, unknown agents): `/api/pane/conversation` answers `{source:"scrollback"}`.
  The client then fetches `pane.read source:"recent" format:text` and splits it into bubbles with heuristics
  (`src/lib/transcript.ts`: the `❯` prompt echo = user, full-width `─━═` rules = turn breaks, status chrome dimmed).
- **Wire shape:** `GET /api/pane/conversation?pane_id&before|since|from` →
  `{source, turns:[{role:"user"|"assistant", ts, end_ts, parts:[...]}], metadata:{model, reasoning_effort}, cursor,
  history_id}` with an ETag (304 when unchanged). Part kinds: `text{phase?}`, `thinking`, `tool{name,summary,input,
  output,error,output_ref,images}`, `image{media_type,ref}`, `compact`, `notice`, `skill`, `task_result`. The client
  polls every 2 s (`ChatView.tsx POLL_MS = 2000`). A cache keyed by inode/size/mtime makes unchanged polls cheap. Long
  tool output is cut and fetched on demand (`/api/pane/conversation/tool-output`). Images come from
  `/api/pane/conversation/image`.
- **Rendering:** `splitTurn` folds tool calls, thinking and narration into one collapsible "work block" per turn.
  Each tool row is "verb + object" (`lib/toolVerbs.ts`). Markdown with KaTeX. A session panel lists derived activity.

**Sending a chat message** (`server/index.ts submitText`):
1. If an agent is in front: herdr's **`agent.prompt {target, text}`**. "pastes `text` into the pane's agent
   (bracketed), then its Enter 300ms later … Refuses with `agent_blocked` while the agent waits for an answer,
   `agent_not_found` / `agent_not_ready` without an agent".
2. Otherwise (or after `agent_not_found`/`agent_not_ready`): `pane.send_text` with the text wrapped in bracketed
   paste `\e[200~…\e[201~`, then `pane.send_keys ["Enter"]` `SUBMIT_DELAY_MS` later.
- **Messages typed while the agent works:** a server-owned "pending input" list (`server/pending-input.ts`). It is
  delivered automatically on the next idle/done only while the original connection is live. It is never resent after
  a disconnect, and an unknown delivery outcome is never retried. Before delivery it re-reads the screen
  (`pane.read source:"detection"`) and refuses if a menu, a password prompt or `blocked` status shows.
- Composer extras: `/` slash commands (per-agent built-ins + `.claude/commands/**/*.md`), `@` file mentions (git
  inventory), image paste (saved under `<pane cwd>/.herdr-web-ui/`, path inserted), voice dictation, Stop = Escape key.

**Approvals, questions, blocked prompts** (`server/prompt.ts`, 3k LOC): these come from the **visible screen**, not from
transcripts or hooks. `GET /api/pane/prompt` reads `pane.read source:"detection"` and runs per-agent regex parsers.
There are 27 "responders" (`claude-approval`, `claude-question`, `claude-plan`, `codex-approval`, `codex-question`,
`omp-*`, `pi-question/confirm/input/model`, `omo-*`, `fallback-menu`, `fallback-keys`…). Each turns the screen into
`InteractivePrompt {id (hash of text + asking), agent, kind: question|approval|plan|menu, title, question, body,
options[{label,description}], multi_select, custom_option_index}`. ChatView polls it every 2 s **whatever the status**:
"a menu can wait while herdr reports idle". The card answers with
`POST /api/pane/prompt/answer {pane_id, prompt_id, option_index|option_indices|custom_text}`. The server turns this into
**`pane.send_keys` navigation (↑/↓ then Enter/space, never digits)** and re-reads the screen between moves. A stale
`prompt_id` gets 409. There are special cases, for example Claude's `/model` list is answered with `s`, never Enter.
Masked password prompts use a separate `secret` WS frame (`send_text` + Enter; the value is never stored).

## Multi-host (remote PCs)
`docs/remote-pcs.md`: `Browser → connection server → OpenSSH local forward → remote loopback bridge → herdr Unix socket`.
- "Add PC" takes an SSH alias. The server uses its own OpenSSH config and ssh-agent. Host-key and password prompts are
  relayed through an askpass unix socket. It can register an app-specific ed25519 key (`<stateDir>/ssh/<machine-id>`).
- Setup installs a private, checksum-pinned runtime bundle (Bun + Node + node-pty + a pinned herdr fallback) on the
  remote and starts the **same bridge** there on loopback. It never stops a running herdr.
- The local server keeps one status-only WS per remote PC and merges rosters into SSE `/api/machines/events`. Terminal
  WSs are `/ws?machine_id=…`. Allowlisted routes go through a proxy at `/api/machines/:id/{session,agents,pane/*,workspace/*}`.
- So the design is a daemon on every host plus an SSH tunnel to it, with one "connection server" as the hub.

## Mobile connection and auth
- PWA (installable, service worker `public/sw.js`), with a key bar (Esc/Tab/Ctrl/Alt/arrows) above the soft keyboard.
- **Transport:** it ships no relay or tunnel of its own. The user brings Tailscale, an SSH tunnel, a VPN or a
  reverse proxy. The installer runs `tailscale serve --bg --https=<port> http://127.0.0.1:7317` and prints a QR code
  of the tailnet HTTPS URL. HTTPS is needed for PWA install and push.
- **Auth** (`server/access.ts`, `auth.ts`, `devices.ts`): trust by origin. Loopback is allowed. Through `tailscale
  serve`, the `Tailscale-User-Login` header must equal the PC's own login. Other devices pair with a **six-digit code
  valid 10 minutes** (`?pair=CODE` in the QR); the device token is stored only as a hash, in an HttpOnly SameSite=Strict
  cookie. An optional shared token exists too. Device roles: `drive` | `watch`.

## Push notifications
- **Web Push (VAPID)** from the server (`server/push.ts`, `web-push` lib, `generateRequestDetails` + `fetch`). Keys and
  subscriptions are stored server-side.
- **Trigger:** the collector's status events. `shouldNotifyStatus(prev,next)` = changed AND next ∈ {blocked, done}. The
  first sighting is ignored. "done" only after a long turn by default (`prefs.done: off|long|always`). Urgency is high
  for blocked, TTL 12 h. Tag = one notification slot per pane. Payload `{machine_id?, pane_id, title, body, tag}`.
- Tab-level notifications use the same policy (`shared/notify-policy.ts`) and are skipped when the device has push.

---
