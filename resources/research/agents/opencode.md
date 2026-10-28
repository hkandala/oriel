# opencode: chat view research

> Spiked in throwaway herdr sessions for the [chat view](../ui/chat-view.md). The spike files named below lived in `/tmp/oriel-research/opencode/` and were not kept.

Tested two builds:

- **v1.19.4**: the npm `latest` release (2026-10-22), the one users run today. Installed with
  `npm i --prefix /tmp/oriel-research/opencode/v1 opencode-ai@1.19.4`. The source is the tag, in `src-v1/`.
- **v2.2.0 dev**: `github.com/anomalyco/opencode` HEAD. `sst/opencode` redirects to the same repo. It was built from
  source in `src/` with bun 1.4.4 and run as `bun run --cwd packages/cli src/index.ts`. It is not on npm `latest` yet
  (npm tags `dev` and `beta` only). The architecture changes a lot, so it is covered too.

Setup: a herdr session `oriel-dev-research-opencode` and the scratch folder `work/` with a project
`.opencode/opencode.json`. The model is `anthropic/claude-haiku-4-5` through the company gateway, using `{env:...}`
substitution, so no secrets are on disk. Permissions are set to `bash: ask` and `edit: ask`. `XDG_*` points under
`/tmp`. The free opencode zen models answered "Free usage limit reached" (HTTP 429).

For the herdr integration, I copied herdr's installed opencode plugins into the project `.opencode/` (nothing global
changed). Note: the herdr session was also created under the `/tmp` `XDG_CONFIG_HOME`.

Spike files in `/tmp/oriel-research/opencode/`:
- `v1-events.sse`, `v2-events.sse`: raw SSE from my runs.
- `v1-parts-sample.jsonl`, `v1-messages-sample.jsonl`: database rows.
- `v1-routes.txt`: the v1 route list.
- Helpers: `hr.sh`, `v2c.sh` (reads the v2 registration file and never prints the password).

## 0. The one fact that decides the design

| Build | Where the server lives | Reachable from outside? |
|---|---|---|
| v1, plain `opencode` | The server runs in a **worker thread inside the TUI process**. The TUI talks to it through in-process RPC (`url: "http://opencode.internal"`, `cli/cmd/tui.ts:273`). | **No.** `lsof -iTCP -sTCP:LISTEN` on the pane's pid shows no listener. Config `server.port` is ignored: only argv `--port`, `--hostname` or `--mdns` turn on the HTTP listener. |
| v1, `opencode --port N` (or `--hostname`, `--mdns`) | The same TUI also listens on `127.0.0.1:N`. It has no auth unless `OPENCODE_SERVER_PASSWORD` is set. | Yes, full API. Tested on `--port 47801`. |
| v1, `opencode serve` + `opencode attach <url>` | A shared server. The TUI is a client. | Yes. Tested: the attached TUI showed a prompt sent through the API. |
| v2 dev, plain `opencode` | **Every TUI connects to one background service** (`opencode serve --service`). The service is found through `$XDG_STATE_HOME/opencode/service.json` (`service-<channel>.json`, mode 0600, holding `{id, version, url, pid, password}`). The default port is 0xC0DE = 49374 (`local` channel 49375). | **Yes, always.** HTTP Basic auth, user `opencode`, password from that file. Without auth: 401. |

So on v1 a running plain TUI **cannot** be joined. The chat must read the SQLite database and drive the TUI with
herdr keys. On v1 with `--port`, and on all of v2, a full side connection exists, and the TUI shows everything it
does. The only working way to find the port of a v1 `--port` TUI is
`lsof -nP -a -p <pane pid> -iTCP -sTCP:LISTEN`, or its argv from `pane.process_info`. There is no state file.

## 1. Transcript

| | v1.19.4 | v2 dev |
|---|---|---|
| File | `$XDG_DATA_HOME/opencode/opencode.db` (SQLite, WAL) | `$XDG_DATA_HOME/opencode/opencode[-channel].db` (`opencode-local.db` here) |
| Tables | `session`, `message` (`data` JSON with `role`), `part` (`data` JSON with `type`), `todo`, `permission` (saved "always" rules only) | `session_v2`, `session_message` (`type`, `seq`, `data`), `session_inbox` (queued prompts). The `event` table stayed empty. |
| Find the pane's session | herdr `agent_session` `{kind:"id", value:"ses_…", source:"herdr:opencode"}`. It is reported by herdr's **TUI plugin** (`herdr-tui-session.js`) from the TUI route. Works today. | The same plugin has a v2 `setup()` path. Not verified: herdr did not detect my source build as opencode (process name `bun`), so it stayed `agent_status: unknown`. A compiled binary should behave like v1. |
| Find the database | `lsof -p <pid> -Fn` shows `…/opencode.db`. `opencode db path` also works. | The service pid in `service.json` holds the database. |
| Read without sqlite3 | `opencode db "<sql>"` (prints TSV), `opencode export <ses>` (JSON) | The API: `GET /api/session/:id/message` |

Session changes (v1, tested):
- `/new` keeps the old `agent_session` until the first prompt, then a new `ses_…` appears.
- `/sessions` (also `/resume`, `/continue`) and `POST /tui/select-session` switch the route, and herdr's
  `agent_session` follows within about 1 s.
- `/compact` keeps the **same** session id. It adds a user message with a `compaction` part and an assistant summary
  message (agent `compaction`). The SSE event is `session.compacted`.
- Fork (`/fork`) makes a new session. Subagents (the `task` tool) make child sessions with `parent_id`. herdr's
  plugin keeps the root id.

## 2. Events

**When data reaches the disk (both builds, tested by polling during a long reply):**
- A text part row is created empty when the text starts.
- The full text is written once, when the text block ends (v1: `length(text)` stayed 0 while the TUI streamed).
- An abort flushes the partial text.
- Tool parts are written at each state change. A tool that waits for approval sits in `running` (v1) on disk.
- **Pending permissions and questions are never on disk.** They are in memory and in SSE only.
- **Live per-token data exists only in SSE** (`message.part.delta` in v1, `session.text.delta` in v2).

| Event | v1 storage (`part.data.type` or `message.data`) | v1 SSE (`GET /event`) | v2 storage / SSE (`GET /api/event`) |
|---|---|---|---|
| User text | user message + `text` part | `message.updated`, `message.part.updated` | `session_message type=user {text, files, agents, skills}` |
| Assistant text | `text` {text, time} | `message.part.delta {partID, field:"text", delta}` | `assistant.content[] type=text`; `session.text.started/delta/ended` |
| Thinking | `reasoning` | delta on the reasoning part | `content type=reasoning`; `session.reasoning.*` |
| Tool call and result | `tool` {tool, callID, state: pending, running, completed (output) or error} | `message.part.updated` | `content type=tool` {id, name, state: streaming, running, completed or error}; `session.tool.called/success/failed`. Call and result pair by `callID` / `id`. |
| Step usage and cost | `step-start`, `step-finish` {tokens, cost, reason}; message `cost`/`tokens`/`modelID`/`agent` | — | assistant `cost`, `tokens`, `finish`; `session.step.ended`, `session.usage.updated` |
| Subagent | `subtask` and `agent` parts; child session | `session.created` with `parentID` | `parent_id`; `session.created` |
| Todos | `todo` table | `todo.updated` | — |
| Files and images | `file` part {mime, url, filename} | | `user.files[]` |
| Snapshot and patch | `snapshot` and `patch` parts | `session.diff`, `file.edited` | `assistant.snapshot` |
| Compaction | `compaction` part | `session.compacted` | `type=compaction` (running, completed, failed); `session.compaction.*` |
| Error | message `error` {name, data} | `session.error` | `assistant.error`; `idle.outcome=failed` |
| Abort | message `error.name = "MessageAbortedError"` | `session.status idle` | `type=idle outcome:"interrupted"`; `session.execution.interrupted` |
| Turn done | — | `session.idle`, `session.status {type: idle, busy or retry}` | `type=idle`; `session.execution.succeeded` |
| Model and agent | per message `agent`, `modelID`, `providerID` | | `agent-switched`, `model-switched` messages; `session.agent.selected`, `session.model.selected` |
| Permission | — | `permission.asked {id, sessionID, permission, patterns, metadata.diff, always, tool{messageID, callID}}`, `permission.replied {requestID, reply}` | `permission.asked {id, action, resources, save, metadata.files[].patch, source}` |
| Question | — | `question.asked {id, questions[{question, header, options[{label, description}]}], tool}`, `question.replied {answers}` | **`form.created`** {form{id, fields[{key, title, options, custom}], metadata.kind:"question"}}, `form.replied` |

## 3. Blocked states

All of these were tested.

| | What happens |
|---|---|
| TUI screen | Permission: `△ Permission required → Edit a.txt / diff / Allow once  Allow always  Reject  ⇆ select enter confirm`. Question: a numbered list plus "Type your own answer", `↑↓ select enter submit esc dismiss`. |
| herdr `agent_status` | `blocked` for both, through the TUI plugin. `agent.prompt` returns `{"code":"agent_blocked"}`. **Works today.** |
| **Answer with keys** (works today, also on a plain v1 TUI) | Permission: `enter` = the selected option (Allow once by default); `left`/`right` or `h`/`l` move; `esc` = Reject. Question: a **digit key picks and submits** (`3` → "Plum"); `up`/`down` + `enter`; `esc` dismisses. Tested on a no-port v1 pane. |
| Answer through the server (v1 `--port`) | `GET /permission` → `POST /permission/:id/reply {"reply":"once\|always\|reject","message"?}`. `GET /question` → `POST /question/:id/reply {"answers":[["Blue"]]}` or `/reject`. The TUI dialog **closed on its own** and the turn went on. Tested. The old `/session/:id/permissions/:pid` route still exists. |
| Answer through the server (v2) | `POST /api/session/:id/permission/:rid/reply {"decision":"once"}`. `POST /api/session/:id/form/:fid/reply {"answer":{"q0":"Blue"}}`. Tested; the TUI followed. |

Verdict: real Approve / Deny / option buttons are possible.
- **Reliable:** structured data from SSE or `GET /permission`, and the answer sent through the API. Needs v1 `--port` or v2.
- **Fallback for a plain v1 TUI:** draw buttons from the screen (the design's blocked panel) and send keys.
  The keys are fixed (enter, esc, left/right, digits), so the panel can label them.

## 4. Sending messages

| Case | Result |
|---|---|
| `agent.prompt` while idle | Works. The text shows and the turn starts. |
| While working | Works: the TUI **queues** it (shown with a `QUEUED` tag) and runs it after the turn. This is not a steer. |
| Multiline | Works: bracketed paste keeps the newlines. |
| `/command` | Works when the command exists. `/compact` and `/new` run directly. `/models`, `/sessions` and `/agents` open pickers. |
| `@file` | **Caveat.** Pasted `@a.txt` stays plain text (no `file` part), because a mention needs the autocomplete pick. The API can attach it instead: a v1 `parts:[{type:"file", mime, url:"file://…"}]`, or v2 `files[]`. |
| Image | Only as a pasted path, or through an API file part. |
| v1 `POST /session/:id/prompt_async {parts:[{type:"text", text}]}` | 204. **The TUI showed the message and the reply** when it was on that session. Tested. Also accepts `model`, `agent`, `variant`. |
| v1 `POST /tui/append-prompt {text}` + `POST /tui/submit-prompt` | Fills and submits the TUI's own input box. Tested. |
| v2 `POST /api/session/:id/prompt {text, delivery:"queue"\|"steer"}` | Shown in the TUI. Tested with queue. **v2 adds a real steer.** |

**Danger:** pickers and dialogs that are not approvals do **not** set `blocked`. After `/models` I picked Sonnet, and a
second "Select variant" (reasoning effort) dialog opened. herdr still said `idle`, so the next `agent.prompt` text went
into the dialog's search box.

## 5. Interrupt

- Keys: `esc` once shows "esc again to interrupt"; a **second `esc`** cancels. Tested.
- On disk: the assistant message gets `error {name:"MessageAbortedError"}` and the TUI shows "· interrupted".
- v1 server: `POST /session/:id/abort` → `true`. The TUI shows interrupted. Tested.
- v2 server: `POST /api/session/:id/interrupt` → `{"interrupted":true}`. An `idle outcome:"interrupted"` message is
  written. Tested.

## 6. Model and mode

**v1, by keys:**
- `tab` / `shift+tab` cycle the agents build ↔ plan (v2 hint: `shift+tab agents`).
- `/models` opens a picker. Typing filters it and `enter` picks. Some models then open a second **variant** picker.
- `/variants` opens the reasoning-effort picker.
- There is no direct `/model <name>` form.
- The model is kept **per agent** in the TUI's memory. Switching back to Build restored Haiku. `state/opencode/model.json`
  holds recent models and variants for the whole TUI, not per pane.

**v1, by server:**
- `POST /tui/execute-command {"command":"agent_cycle"}` switches Build → Plan. Tested. Only legacy aliases work here.
- `POST /tui/publish {type:"tui.command.execute", properties:{command:"<any keymap id>"}}` dispatches any TUI command:
  `agent.cycle`, `model.list`, `model.cycle_recent`, `variant.cycle`, `permission.mode` (toggles auto-approve),
  `session.interrupt`, `session.compact`, `session.new`…
- `prompt_async` can set `model`, `agent` and `variant` for one message, without changing the TUI selector.

**v2:** `POST /api/session/:id/agent {"agent":"plan"}` and `/model {"model":{providerID, id}}` change the **session**
state. The TUI footer followed at once ("Plan · Claude Sonnet 4.5"). Tested.

**Read back:**
- The footer on screen (`Build · Claude Haiku 4.5 (latest) Anthropic`, then tokens, % and $).
- The last assistant message's `agent`, `modelID` and `providerID` (v1).
- `session_v2.agent` and `session_v2.model` (v2).
- `GET /config/providers` (v1) or `/api/model` (v2) for the model list.

Approval mode: `--auto` at start, or the `permission.mode` command. Plan mode is the `plan` agent.

## 7. Other interactive elements

- **Slash commands that open a picker:** `/sessions` (`resume`, `continue`), `/models`, `/agents`, `/variants`,
  `/mcps`, `/themes`, `/connect`, `/workspaces`, `/skills`, `/help`, `/timeline`.
- **Slash commands that run directly:** `/new` (`clear`), `/compact` (`summarize`), `/undo`, `/redo`, `/fork`,
  `/rename`, `/copy`, `/export`, `/thinking`, `/timestamps`, `/diff`, `/status`, `/exit`, and custom commands
  (`GET /command`).
- Other pickers: the `@` file mention and `/` autocomplete.
- Context and cost: the footer `14.0K (7%) · $0.02`; `step-finish` tokens and cost.
- Todos: `todo` table and `todo.updated`.
- Subagents: child sessions; the TUI moves between them with `session.child.*`.
- Every picker needs the TUI ("show terminal"), unless the chat rebuilds it from API data (models, agents, sessions,
  which v1 `--port` and v2 can list).

## 8. Remote over SSH

| Need | How over the relay | Extra install? |
|---|---|---|
| Transcript, v1 plain | Polled one-shot commands: `sqlite3 -json <db> "select … where time_updated > ?"`, or `opencode db "<sql>"` (TSV). No `tail -F`: the data is in SQLite. | `sqlite3` or the opencode CLI, which is already there. |
| Live events, v1 `--port` / v2 | `curl -sN http://127.0.0.1:<port>/event` is **line-based SSE**, so a relay line stream carries it directly. v2 needs the Basic header, built on the host from `service.json`, so the password never leaves the host. | `curl` only. No port forward. |
| Actions | One-shot `curl -XPOST …/permission/:id/reply`, `/prompt_async`, `/abort`, `/tui/*` | `curl` |
| Keys and screen | herdr `agent.send_keys` and `pane.read`, as today | none |

Nothing needs a local port, a daemon or an install beyond `curl` and `sqlite3`.

## 9. Recommendation: the opencode adapter

1. **Find:** the pane's `agent_session.value` (`ses_…`) from herdr. For the database, use `lsof -p <pid> -Fn | grep
   opencode.*\.db`, or `opencode db path`. For the server, check in this order: v2 `service.json` → v1
   `lsof -iTCP -sTCP:LISTEN` on the pane pid (or `--port` in argv) → no server.
2. **Events:** when a server exists, one `curl -N /event` stream filtered to the session. This gives live text,
   tools, `permission.asked` and `question.asked` / `form.created`, status and idle. Read history once from
   `GET /session/:id/message` (v1) or `/api/session/:id/message` (v2). With no server (plain v1, the common case
   today), **poll SQLite** about every 1 s on `part.time_updated`. Text then appears per block, not per token, and
   the "Working" row comes from herdr's `agent_status`.
3. **Actions with a server:**
   - Permissions and questions become real buttons through `/permission/:id/reply` and `/question/:id/reply` (v2:
     `…/permission/:rid/reply`, `…/form/:fid/reply`).
   - Send with `prompt_async` (v2 `prompt` with `delivery` steer or queue). Interrupt with `/abort` (v2 `/interrupt`).
   - Agent and model switching: v2 API, or v1 `/tui/publish` commands.
4. **Actions without a server (plain v1):**
   - `agent.prompt` to send. The TUI queues it when busy.
   - Blocked panel keys: `enter`, `esc`, `left`, `right`, digits. Interrupt is `esc esc`. Mode is `tab`.
   - Model changes go to "show the TUI", because the picker chain needs it.
5. **In chat:** messages, tools, approvals and questions (structured when a server exists, keys otherwise), send,
   interrupt, agent toggle. **Show the TUI for:** model and variant pickers on v1, the session picker, `@`
   autocomplete, diff view and themes.

**Top 5 risks**
1. **A plain v1 TUI has no side door.** We get disk data per block, no pending-permission details on disk, and
   key-driven answers only. Asking users to run `opencode --port 0`… changes how they launch it, and `--port 0` picks
   a random port, so it must be found with `lsof`.
2. **v2 is a different API and storage** (`/api/*`, `session_message`, forms instead of questions, a background
   service with Basic auth, no `/tui/*` control routes). The adapter needs two parsers and two clients, and the switch
   could land in any release.
3. **Non-approval dialogs are not "blocked".** Model, variant and session pickers left `agent_status: idle`, and a
   prompt typed into the variant search box. The key guard, plus a screen check for `esc`-able dialogs, is needed
   before sending.
4. **Shared servers.** One v2 service, or one v1 `serve`, holds many sessions and TUIs. `/tui/*` events reach every
   TUI attached to that workspace. Filter strictly by `sessionID` and prefer session-scoped calls over TUI-scoped ones.
5. **herdr detection and plugin coverage.** `agent_session` comes only from herdr's opencode TUI plugin. It was
   installed here as v13; without it there is no session id, and a `cwd` plus latest-`time_updated` guess is ambiguous.
   herdr did not detect a source-run v2 (`bun`) as opencode at all.

Not verified: herdr's v2 plugin reporting (blocked by the `bun` process name); images; `todo` and subagent events
(read from source, not run); question custom-text answers.
