# pi: chat view research

> Spiked in throwaway herdr sessions for the [chat view](../ui/chat-view.md). The spike files named below lived in `/tmp/oriel-research/pi/` and were not kept; the bridge's design is under [The bridge](#the-bridge).

Agent: `/usr/local/bin/pi` (company launcher, Mach-O) → `/usr/local/bin/pi_cli/pi.real`, a compiled build of
upstream `@earendil-works/pi-coding-agent` **1.4.0** (`/usr/local/bin/pi_cli/package.json`). Docs read:
`/usr/local/bin/pi_cli/docs/{extensions,session-format,rpc,rpc-commands,rpc-extension-ui,keybindings,slash-commands,sessions,message-types}.md`.
Exact types read from upstream `main` on GitHub (`core/extensions/types.ts`, `session-manager.ts`,
`rpc-mode.ts`, `extensions/runner.ts`); 1.4.0 behaved the same in every test below.

Throwaway run: herdr session `oriel-dev-research-pi`, pane `w1:p1`, cwd `/tmp/oriel-research/pi/work`,
`herdr agent start pi-r --kind pi --pane w1:p1 -- --model anthropic/claude-sonnet-5-5 --session-dir /tmp/oriel-research/pi/sessions -e /tmp/oriel-research/pi/bridge.ts [-e asker.ts]`.
Session torn down, processes killed.

Files here:
- `bridge.ts`: the spike extension ([The bridge](#the-bridge)). `asker.ts`: a stand-in third-party extension with a
  confirm/select/input. `linearize.py`: prints the current branch of a session file.
- `samples/session-*.jsonl`: my 4 session files (system prompt, signatures and base64 redacted).
  `samples/bridge-events*.jsonl`: what the bridge streamed.

## The bridge

A one-file pi extension (~200 lines), loaded with `-e` or from the extensions folder plus `/reload`. On
`session_start` in TUI mode it listens on a unix socket (`ORIEL_BRIDGE_SOCK`) and greets each client with
`{"type":"hello","state":…}`. JSON lines both ways; every client gets every event.

- **In:** `prompt {text, deliverAs?: steer|followUp}` (`pi.sendUserMessage`), `command {text}` (extension,
  template and skill commands only), `abort`, `compact {instructions?}`, `new_session` (through its own
  `/oriel-new` command), `set_model {provider, modelId}`, `set_thinking {level}`, `get_state`,
  `ui_response {id, value}`. Each gets `{"type":"response", id, ok, …}`.
- **Out:** `event` (pi's agent, turn, message, tool, model, thinking, compaction and tree events, with
  `message_update.partial` and `turn_end.context` trimmed); `ui_request {id, kind: select|confirm|input, title,
  options|message|placeholder, approval?: {toolCallId, toolName, input}}`; `ui_resolved {id, by: client|tui, value}`.
- **Dialogs:** it wraps the shared `ctx.ui.select/confirm/input` and races the TUI dialog against the clients;
  the first answer wins and the loser is dismissed (the TUI through an `AbortSignal`). While one is open it
  emits `herdr:blocked`. A `tool_call` gate on `bash`, `write`, `edit` (`ORIEL_GATE_TOOLS`), active only
  while a client is connected, asks Allow/Deny the same way.
- On `session_shutdown` it closes the clients and removes the socket.

Company-build differences from upstream: extra extensions are always loaded (meta, provenance, trajectory,
dss4_guardrails, llm-rules). The model catalog is quirky (haiku-4-5 400s on max_tokens, sonnet-4-5 400s on
thinking, sonnet-5-5 refuses thinking `off`). The user's own packages add `pi-retry` (writes `context_edit`
entries after errors) and `pi-time-sense` (a `custom_message` on every prompt).

## Summary table

| Need | Mechanism | Verdict |
|---|---|---|
| Find transcript | herdr `agent_session {kind:"path"}` (from herdr's pi extension) | **works today** |
| Parse transcript | JSONL tree; linearize from last entry via `parentId` | **works with caveats** (/tree moves the leaf in memory only) |
| Live tokens, tool start/end | in-TUI extension `bridge.ts` → unix socket | **works today (spike)**, needs the extension loaded |
| Send message shown in TUI | `agent.prompt` (keys) or bridge `pi.sendUserMessage` | **works today** |
| Steer / follow-up | Enter = steer, Alt+Enter = follow-up; bridge `deliverAs` | **works today** |
| Abort | `Esc` key or bridge `ctx.abort()` | **works today** |
| Model / thinking | bridge `pi.setModel`/`setThinkingLevel`; `/model <exact scoped id>`; ctrl+p; shift+tab | **works today** (picker for non-exact names) |
| Approvals / questions | pi has none built in; bridge races TUI dialog against the chat | **works today (spike)** |
| Same without the bridge | screen keys only; herdr says `idle`, **agent.prompt is not refused** | **works with caveats (unsafe)** |
| Built-in slash commands from the bridge | not possible (`sendUserMessage` sends them to the model) | keys only |
| `pi --mode rpc` on the TUI's session | second process, splits the tree | **not possible** |

## 1. Transcript

- **Where:** `~/.pi/agent/sessions/--<cwd with / → ->--/<ISO-ts>_<uuid>.jsonl` (or `--session-dir`).
  The company `pi-herd` launcher uses `~/.pi/agent/pi-herd/sessions/`, so don't guess the folder; use the path.
- **Which pane:** herdr's installed pi integration (`herdr integration status` → `pi: current (v9)`,
  `~/.pi/agent/extensions/herdr-agent-state.ts`) calls `pane.report_agent_session` with
  `agent_session_path = ctx.sessionManager.getSessionFile()` on `session_start` and every `agent_start`.
  `pane get` showed `"agent_session":{"agent":"pi","kind":"path","source":"herdr:pi","value":"/tmp/oriel-research/pi/sessions/2026-10-28T01-57-30-338Z_01a1803a-….jsonl"}`
  right after start. No lsof or cwd search is needed.
- **The file can be missing at first:** pi writes nothing until the first user or assistant message
  (`_persist` → `_hasConversation()`). Then it writes the header and all buffered entries at once.
  herdr reports the path before the file exists. Custom entries made before that (`asker-result`) showed
  up only at the first flush. Oriel must handle "path known, file not there yet" (use `tail -F`).
- **When the file changes:**

| Action | File | Seen in test |
|---|---|---|
| `/new` | new file; `agent_session` updates at once (new file not yet on disk) | yes (via bridge `/oriel-new`) |
| `/fork` | new file written at once, header has `parentSession` | yes |
| `/clone` | new file with `parentSession` (docs) | no |
| `/resume` | switches to the other file; `session_start` → herdr reports the new path | docs + integration source |
| `/tree` | **same file, nothing written**; leaf moves in memory. A `branch_summary` is written only if you pick "Summarize" | yes |
| compaction | same file, appends a `compaction` entry | docs ("Nothing to compact (session too small)" in my run) |
| `/clear` | does not exist in pi (ctrl+c clears the editor) | — |

- **Format:** first line `{"type":"session","version":3,"id","timestamp","cwd"[,"parentSession"]}`. Then
  entries `{type,id(8 hex),parentId,timestamp,…}` that form a **tree**.
- **Linearize:** on load pi sets the leaf to the **last entry in the file**. Walk `parentId` from there to
  the root (`linearize.py`). In my run: 66 entries, one branch point (`364010d0`), active branch 48 entries.
  Caveat: after `/tree` with "No summary" the in-memory leaf is `364010d0`, but the file's last entry
  is on the old branch until the next append. The bridge sees this as
  `{"type":"session_tree","newLeafId":"364010d0","oldLeafId":"33964b0d"}`.
  Other caveat: apply `context_edit` (`replacement:null` hides the target from the model; the UI still
  shows it) and the compaction window if you want "what the model sees". For a chat view, show the raw branch.

## 2. Event types

Transcript entry types: `session`, `message`, `model_change`, `thinking_level_change`, `compaction`,
`branch_summary`, `custom` (extension state, not in context), `custom_message` (in context, `display` flag),
`label`, `session_info` (name), `context_edit`, `usage` (e.g. cache warm).

| Event | Where | Fields we need |
|---|---|---|
| system prompt / tools | `message` role `system` (first one complete, later ones patch `sections`, `toolsAdded/Removed`) | skip in chat |
| user text, images | `message` role `user`, `content` string or `[{type:"text"},{type:"image",data(base64),mimeType}]` | text, images |
| assistant text | role `assistant`, `content[{type:"text",text}]` | text |
| thinking | `content[{type:"thinking",thinking,thinkingSignature}]` | thinking (collapsed) |
| tool call | `content[{type:"toolCall",id,name,arguments}]`, `stopReason:"toolUse"` | id, name, arguments |
| tool result | role `toolResult`, `toolCallId` (pairs with toolCall.id), `toolName`, `content`, `isError`, `details` | pair by id |
| user `!cmd` | role `bashExecution` `{command,output,exitCode,cancelled,truncated}` | yes (tested `!echo hi-from-bang`) |
| errors | assistant with `stopReason:"error"`, `errorMessage` (e.g. a 400 body), empty content | show as error row |
| abort | assistant with `stopReason:"aborted"`, `errorMessage:"Operation aborted"`, partial text kept | tested with Esc |
| usage / cost | every assistant `usage{input,output,cacheRead,cacheWrite,totalTokens,cost{…,total}}`; also `usage` entries and compaction/branch-summary `usage` | sum for cost |
| model | assistant `provider`,`model`,`thinkingLevel`; `model_change{provider,modelId}`; `thinking_level_change{thinkingLevel}` | read back current |
| compaction | `compaction{summary,firstKeptEntryId,tokensBefore}` | divider row |
| branch summary | `branch_summary{fromId,summary}` | divider row |
| extension messages | `custom_message{customType,content,display}` (e.g. `pi-time-sense`) | show if `display` |
| session name | `session_info{name}` | header |
| subagents / todos / plan mode | **not built in**; only as extension tools and examples (`subagent/`, `todo.ts`, `plan-mode/`) | generic tool rows |
| file mentions | none: `@note.txt` stays literal text (the TUI's `@` is only path autocomplete) | — |

**When it hits disk:** once per **finished message** (`appendMessage` at `message_end`: user, then the
assistant after its stream ends, then each tool result). There are no partials in the file. The tool-call
assistant line is written before the tool runs (ts 01:59:17, result 01:59:30 behind an approval).

**Live partial stream:** only inside the process. Extension events (`message_update` with
`assistantMessageEvent` = `text_start/delta/end`, `thinking_*`, `toolcall_*`, plus `tool_execution_*`,
`agent_*`, `turn_*`) are what the bridge forwards. Counts from one run: 30 `text_delta`, 8 `thinking_delta`,
11 `toolcall_delta`. Trim the payloads: `message_update.partial` repeats the whole message on every token,
and `turn_end.context` was 42 KB per turn.

## 3. Blocked states

pi has **no built-in permission prompts**. Installed extensions (from `~/.pi/agent/settings.json`
`packages: ["../../code/pi-hkandala"]`, plus company `/usr/local/bin/pi_cli/extensions`): **none ask before
tool calls.** `meta/command-policy.ts` *blocks* some shell commands with no prompt. `dss4_guardrails` never
blocks. `pi-bash-bg` has a `ui.select` only in a job-picker command. Questions come only from extensions
(`ctx.ui.select/confirm/input/editor/custom`) and from built-in pickers (`/model`, `/tree`, `/fork`, `/resume`, `/settings`).

**Without a bridge (what herdr sees):**
- A third-party `ctx.ui.confirm` (`asker.ts`, `/ask-me`): `pane get` → `"agent_status":"idle"`. herdr's pi
  extension reports `blocked` only when some extension emits `pi.events "herdr:blocked"`; pi's own
  `ui_prompt_start` event is not used. Then `herdr agent prompt w1:p1 "hello"` → **`agent_prompted`, not
  `agent_blocked`**. The paste+Enter **answered the dialog** (result `ok=true`). Built-in pickers (the
  /tree "Summarize branch?" select, the /model picker) also show `idle`.
- Answering by keys works: `herdr agent send-keys w1:p1 down enter` (select 2nd), `enter`, `esc`
  (= cancel → `undefined`/false). Screen text (`pane read --source visible`) shows the title, options, and
  `↑↓ navigate  enter select  escape/ctrl+c cancel`.

**With the bridge (spike, works today):**
- `tool_call` gate (bash/write/edit, only while a client is connected) calls `raceDialog`. It shows the TUI
  select **and** sends `{"type":"ui_request","id":"ui-1","kind":"select","title":"Oriel bridge: allow bash?…","options":["Allow","Deny"],"approval":{"toolCallId":"toolu_…","toolName":"bash","input":{"command":"ls -la"}}}`.
  The first answer wins. A client answer aborts the TUI dialog through its `AbortSignal`. A TUI answer
  sends `{"type":"ui_resolved","id":…,"by":"tui","value":"Deny"}`. A late client answer gets
  `"no such request (already answered?)"`. All three were tested: client Allow, TUI `down enter` (Deny),
  TUI `esc` (cancel → deny).
- It emits `herdr:blocked` while waiting, so `agent_status` = **blocked**, and `agent prompt` →
  `{"code":"agent_blocked"}`. That fixes the hole above.
- **Every extension's dialog:** `ctx.ui` is one shared object (`runner.uiContext`), so the bridge wraps
  `select/confirm/input` once and forwards them all. Tested with `asker.ts`: confirm answered by the
  client (`true`), select by the TUI (`green`), input by the client (`"Ada"`) → `asker got ok=true color=green name=Ada`.
  This is a monkeypatch, not an API. `editor()` and `custom()` components are not forwarded; built-in
  pickers are not extension dialogs and cannot be forwarded.
- Chat can show real buttons: kind + title + options/message/placeholder + tool input.

## 4. Sending a message

| Case | Keys (`herdr agent prompt`) | Bridge (`pi.sendUserMessage`) |
|---|---|---|
| idle | paste + Enter, shows as a user box | shows as a normal user box; `input` event `source:"extension"`; transcript identical to typed |
| working | Enter = **steer** ("Steering: …" row, delivered after the current tool) | `deliverAs:"steer"` |
| working, queue | Alt+Enter = follow-up (keys only; `agent.prompt` always presses Enter) | `deliverAs:"followUp"` ("Follow-up: …" row, runs after the turn) |
| multiline | works (bracketed paste) | works |
| `/cmd` | runs built-in and extension commands | only extension/template/skill commands (`expandPromptTemplates:true`); **built-ins go to the model as text** (`/name via-bridge` became a user message) |
| `@path` | literal text | literal text |
| image | pasted path stays text; the model then used `read` on it (worked) | `[{type:"text"},{type:"image",data,mimeType}]` → real image block (model answered "Red.") |

Steer test: during `sleep 10`, steer "apple" via keys and follow-up "banana" via the bridge. Transcript order:
toolResult → user STEER → assistant "done apple" → user FOLLOWUP → assistant "banana".
Gotcha: `agent prompt --wait` after `/compact` returned `agent_prompt_stalled` (no `working` report during compaction).

## 5. Interrupt

- `Esc` (`app.interrupt`) aborts the run. It also cancels pi-retry's backoff and dismisses an open dialog
  (it does not abort the run then). ctrl+c clears the editor (twice = exit). **Don't send ctrl+c.**
- Transcript: partial assistant message with `stopReason:"aborted"`, `errorMessage:"Operation aborted"`.
  Live: `agent_settled {aborted:true}`.
- Bridge `{"type":"abort"}` → `ctx.abort()`: same result.

## 6. Model and thinking

- **Bridge (best):** `set_model {provider,modelId}` → `ctx.modelRegistry.find` + `pi.setModel`, and
  `set_thinking {level}` → `pi.setThinkingLevel` (clamped). The TUI footer updates and the transcript gets
  `model_change` and `thinking_level_change`. **Order matters:** a model switch resets thinking to the
  default (`high`), so wait for the set_model response, then set thinking. My thinking-first try was
  clamped to `off` on haiku and then replaced by `high`.
- `/model anthropic/claude-opus-5-5` (exact id **in the scoped list** `enabledModels`) switches directly.
  `/model sonnet-5-5` or a model outside the scope opens the **picker** with the text pre-filled
  ("No matching models"). Then `tab` (scope all/scoped) + `enter` chooses. `/thinking [level]` is the
  direct form (docs).
- Keys: `ctrl+p` cycles scoped models (`model_select source:"cycle"`, went to `openai/gpt-6-sol`),
  `shift+ctrl+p` cycles back, `shift+tab` cycles thinking (`low→medium`), `ctrl+l` opens the model selector.
- Modes: pi has no plan or approval mode built in (plan-mode is an example extension).
- **Read back:** bridge `get_state` → `{model, thinking, idle, sessionFile, sessionId, leafId, contextUsage, pendingMessages, commands}`.
  Also the last `model_change`/`thinking_level_change` on the branch (but `--model`/`--thinking` at startup
  write one too), or the footer text `… · sonnet-5.5 · low`. Live: `model_select{model,previous,source}`,
  `thinking_level_select{level,previousLevel}`.

## 7. Other interactive elements

Built-in commands (pi's slash-commands doc): `/settings`, `/model [p/m]`, `/thinking [lvl]`,
`/scoped-models`, `/login`, `/logout`, `/llama`, `/new`, `/resume`, `/name [n]`, `/session`, `/tree`,
`/fork`, `/clone`, `/compact [instr]`, `/import <path>`, `/copy`, `/export [path]`, `/share`, `/bug`,
`/trust`, `/reload`, `/hotkeys`, `/changelog`, `/quit`. Plus extension commands, prompt templates and
`/skill:name`. `pi.getCommands()` lists only the non-built-ins.

| Headless as typed text | Opens a picker or dialog |
|---|---|
| `/new`, `/name x`, `/compact [x]`, `/thinking lvl`, `/model <exact scoped>`, `/clone`, `/session`, `/export p`, `/reload`, `/quit`, `/copy`, `!cmd` | `/model` (no arg or no exact match), `/tree` (list + "Summarize branch?"), `/fork` (pick a user message), `/resume`, `/settings`, `/scoped-models`, `/login`, `/hotkeys` |

- Pickers show `agent_status: idle`, so the chat can't tell they are open. Use the bridge's knowledge of
  what it sent, or screen text.
- Command-only APIs (`newSession`, `fork`, `navigateTree`, `switchSession`) are available to the bridge
  through a trick. It registers a command (`/oriel-new`) and triggers it with
  `sendUserMessage("/oriel-new",{expandPromptTemplates:true})`. Tested: a new session started, and herdr
  updated `agent_session`. The same trick works for fork/tree/resume with a target id, with no picker.
- Cost/context: footer (`󰝦 11.1k/1M`, `cold (~$0.03)`), bridge `contextUsage`, or summed `usage.cost`.
- **Hot-loading:** `/reload` (typed) reloads extensions **without restarting the process**. A new
  `work/.pi/extensions/late.ts` was live afterwards (`late-hello` in `getCommands`). So a bridge installed
  in `~/.pi/agent/extensions` (or a project dir) can be attached to an already running TUI.
  Side effect seen: `/reload` wrote `~/.pi/agent/trust.json` for the project folder (I deleted it). Any
  reload or session switch restarts the bridge and drops clients; clients must reconnect.

### Why not `pi --mode rpc`

It is a separate process with its own `SessionManager`. It loads the file once and keeps its own leaf; pi
has no file watching or locking. Test: `pi --mode rpc --session <tui file>` + `set_session_name` appended
`session_info a013bd64 parent 5ab8ebdc`. Then `/name from-tui` in the TUI appended `db2f959a`, **also with
parent 5ab8ebdc**. The tree split into two sibling branches, and neither process sees the other's
entries, live events or queue. It also can't show anything in the TUI. RPC is only usable for a
*different* session (or after the TUI quits).

## 8. Remote over SSH

| Piece | Over a plain SSH relay |
|---|---|
| `agent_session` path | herdr API, works as-is |
| transcript tail | `tail -c +N -F <path>` line stream, **works** |
| send / keys / abort / pickers | herdr `agent.prompt` / `send_keys`, works |
| bridge events | `ssh host nc -U <sock>` as a long-lived line stream (stdout = events). **Works with caveats**: needs `nc` with `-U` (BSD/openbsd nc; not GNU netcat), or `socat`, or `python3 -c`. No local port, no daemon. |
| bridge commands | one-shot `echo '{…}' \| nc -U -w1 <sock>`. Tested: a one-shot connection answered `ui-4` while another client listened (pending answers are global, events go to all clients). |
| install | the bridge file must exist on the remote and be loaded: `-e` at launch, or `~/.pi/agent/extensions/` + `/reload`. That is an install on the remote (one file, no daemon). |

If `nc -U` is a problem, the same bridge could use a file pair (append commands to `cmd.jsonl`, the bridge
watches it; events to `events.jsonl` for `tail -F`). Not built.

## 9. Recommendation

**Adapter, two tiers:**
1. **Baseline (works on any pi today, no install):** `agent_session` path → `tail -F` → parser
   (linearize from the last entry; handle missing file, `context_edit`, compaction, `session_tree` gap).
   Send with `agent.prompt` (Enter = steer while working). Abort with `send_keys esc`. Model by
   `/model <exact scoped id>` typed, else picker + "show the TUI". Blocked: **no reliable signal** (herdr
   says idle), so show the screen-text panel and guard keys.
2. **Bridge tier (when `bridge.ts` is loaded):** a socket per pi (path keyed by session id or pid, e.g.
   `$TMPDIR/oriel-pi-<sessionId>.sock`, found by `pane.process_info` pid or a small discovery file). It
   gives live deltas ("Working" row with real text), real Approve/Deny and option buttons for every
   extension dialog (race with the TUI, first answer wins), `herdr:blocked` so `agent.prompt` is refused
   safely, `set_model`/`set_thinking`/`abort`/`compact`, steer vs follow-up, images, and
   new/fork/tree/resume without pickers. The transcript stays the source of truth for history; the bridge
   adds the live layer.

**In chat:** messages, tool rows, thinking, errors/aborts, approvals and extension
select/confirm/input (bridge), model/thinking menus (bridge or exact `/model`), steer/follow-up, images
(bridge). **Show the TUI:** built-in pickers (`/tree`, `/fork`, `/resume`, `/settings`, `/login`, `/model`
search), `ctx.ui.editor/custom` components, anything while no bridge is loaded and the screen looks like a dialog.

**Top 5 risks**
1. **Typing into an unreported dialog.** Without a `herdr:blocked` emitter, herdr reports `idle` and
   `agent.prompt` paste+Enter **answers the dialog** (proven: `ok=true`). Built-in pickers are the same.
   The key guard must not rely on `agent_status` for pi.
2. **The bridge must be loaded in the TUI.** `-e` only at launch. Otherwise it needs a file in the
   extensions dir + `/reload` (writes trust.json; restarts the runtime and drops clients). It is an install
   on remote machines, and the `ctx.ui` wrap is a monkeypatch that may break across pi versions.
3. **Tree vs file order.** `/tree` moves the leaf without writing. Linearize from the last entry and fix
   up with `session_tree` (bridge) or re-read on the next append. Reading "in file order" shows abandoned
   branches.
4. **Session churn.** `/new`, `/fork`, `/resume`, `/reload` change the file and/or restart the bridge.
   `agent_session` updates, but the new file may not exist until the first message. The tail and the
   socket must retry.
5. **Payload size and the company build.** Live events carry full messages and context (trim
   `partial`, `turn_end.context`); images are inline base64 in the transcript. The launcher's catalog and
   extra extensions (pi-retry `context_edit`, time-sense `custom_message`) add entry types the parser must
   skip politely. Model switches reset thinking.
