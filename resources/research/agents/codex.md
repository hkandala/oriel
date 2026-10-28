# Codex CLI: chat view research

> Spiked in throwaway herdr sessions for the [chat view](../ui/chat-view.md). The spike files named below lived in `/tmp/oriel-research/codex/` and were not kept.

Codex CLI 0.163.0 through the company launcher (`/usr/local/bin/codex`), herdr 0.9.5, macOS. All runs were in
the throwaway session `oriel-dev-research-codex` (removed at the end), in `/tmp/oriel-research/codex/work`, with
`gpt-5.6-luna` at low effort. Files in this folder:

- `wsclient.mjs`: the second app-server client used in the spikes (Node 24 global `WebSocket`, JSON-RPC in on stdin).
- `proxy_probe.py`: shows that `codex app-server proxy` speaks WebSocket, not JSON lines.
- `hook.sh`, `notify.sh`: hooks and the notify hook, set for one run with `-c`.
- `hooks.log`, `notify.log`: their payloads.
- `rollout-sample-*.jsonl`: trimmed rollouts. Instruction text, `world_state` and encrypted reasoning are removed.
- `ws-client-B-sample.jsonl`: the live event stream that client B received.
- `schema/`: the output of `codex app-server generate-json-schema`.

## Read this first: three things that change the design

1. **A second client can fully drive a running Codex TUI. Works today, with one condition: the TUI must be started
   with `--remote`.** Start `codex app-server --listen ws://127.0.0.1:P` (or `unix://PATH`), then start the TUI as
   `codex --remote ws://127.0.0.1:P`. A second client then gets all of the following, and the TUI shows each action
   live:
   - `thread/resume` on the TUI's thread. It returns the history, then streams live `item/*` events, including
     per-token `item/agentMessage/delta`.
   - The approval request (`item/commandExecution/requestApproval`), which it can answer. The TUI's prompt then
     clears.
   - `item/tool/requestUserInput` questions, which it can also answer.
   - `turn/start`, `turn/steer` and `turn/interrupt`.
   - Model and effort changes (`turn/start {model, effort}`). The TUI's status line updates.

   A plain `codex` TUI runs its app-server inside its own process and listens on no socket. You cannot attach to it.
2. **This build starts no daemon.** `daemon_auto_start` reads `stable true`, but a plain TUI ran no daemon:
   `~/.codex/app-server-daemon/` is missing, `codex app-server daemon version` gets "No such file", and the TUI
   process held its own rollout open. The same holds without `--no-daemon`. The design's `lsof` step therefore
   covers a default TUI on this Mac.
3. **The company launcher changes approvals.** `/etc/codex/managed_config.toml` forces
   `approvals_reviewer = "auto_review"` (the Guardian reviewer), and `-c approvals_reviewer=user` cannot override
   it. `/etc/codex/meta-approved.rules` allows common commands (`touch`, `rm`, `mkdir`…) and prompts for others
   (`rm -rf`…). By default, most commands never ask a human. After `/permissions` → "Ask for approval" or
   "Read Only", the thread runs with `approvals_reviewer:"user"` and prompts show. Upstream defaults to `user`.

Also: the user's shell alias `codex` adds `--yolo`. The spikes used the full path, `/usr/local/bin/codex`.

## 1. Transcript

| Question | Finding | Status |
|---|---|---|
| Where | `~/.codex/sessions/YYYY/MM/DD/rollout-<local ts>-<thread uuid>.jsonl`, one JSON object per line: `{timestamp, ordinal, type, payload}` | works today |
| herdr `agent_session` | `kind:"id"`, the thread uuid. Comes from herdr's installed hook (`~/.codex/hooks.json` → `herdr-agent-state.sh session`, integration v10, SessionStart only; read only, I did not reinstall it) | works with caveats |
| `lsof -p <pid> -Fn` on the `codex.real` pid from `pane.process_info` | Finds the rollout. **But the TUI keeps every rollout it opened in this process:** older threads after `/new`, `/resume` and `/fork`, plus Guardian sub-threads (`session_meta.source = {subagent:{other:"guardian"}}`). Pick the file whose `session_meta.source == "cli"` and whose mtime is newest | works with caveats |
| Hook payloads | Every hook (`SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `Stop`) carries `session_id` and **`transcript_path`**. herdr's hook gets the path but reports only the id | works today |
| `--remote` / daemon | The **server** writes and holds the rollout and runs the hooks. The TUI pids hold nothing, and hooks run with the server's environment (no `HERDR_PANE_ID`), so the pane got **no `agent_session`**. The server reports the path itself (`thread.path` in `thread/started` / `thread/resume`) | see §3 |
| `/new` | New file. Written only at the first turn (lazy). herdr's id switched after the first turn | changes |
| `/resume` (picker) | Switches to the old file. herdr's id switched after the next turn | changes |
| `/fork` | New file with `session_meta.forked_from_id` and `forked_from_ordinal_exclusive`. **It does not copy the parent's history** (paginated history mode), so a chat must read the parent file for older rows. **herdr's id stayed on the parent**, even after a turn | changes, herdr stale |
| `/compact` | Same file. Writes a `compacted` line (`replacement_history`, `window_id`) and `item_completed/ContextCompaction` | same file |
| When lines hit disk | Per item, flushed at once. The user message is on disk within 2 s. Assistant text appears only when the whole message is done. No partial text in the file | per message |

## 2. Event types

The 0.163 rollout has two layers. `response_item` lines hold the raw model I/O. `event_msg/item_completed` lines
hold clean typed items. **Parse `item_completed`; use `response_item` only for pairing.** Older builds (0.145)
wrote `event_msg/user_message`, `agent_message`, `patch_apply_end` and `exec_command_end` instead. Those names
are gone in 0.163.

| Event | Rollout line | Live stream (app-server) | Fields we need |
|---|---|---|---|
| Session meta | `session_meta` | `thread/started`, `thread/resume` result | `id`, `cwd`, `cli_version`, `source` (cli / guardian sub-agent), `forked_from_id`, `history_mode:"paginated"` |
| Model, effort, mode, permissions | `turn_context` (per turn), `event_msg/thread_settings_applied` | `thread/settings/updated` (also pushed at once by `/model`, `/permissions`, shift+tab) | `model`, `effort`, `approval_policy`, `approvals_reviewer`, `sandbox_policy`, `collaboration_mode.mode` (`default` / `plan`) |
| User text | `item_completed/UserMessage` (`content[].text`, `client_id`) | `item/started` and `item/completed` `userMessage` | text, images (`type:"image"`, data URL) |
| Assistant text | `item_completed/AgentMessage` (`content[].text`, `phase: commentary / final_answer`) | `item/agentMessage/delta` (per token), then `item/completed` | text, phase |
| Thinking | `item_completed/Reasoning`. `summary_text` and `raw_content` were empty here (`summary:"none"`); `encrypted_content` only | `item/reasoning/*Delta` | usually nothing to show |
| Tool calls | Tools are wrapped in code mode: `response_item/custom_tool_call name:"exec"`, whose `input` is JS calling `tools.exec_command({cmd, sandbox_permissions, justification})`. Paired with `custom_tool_call_output` by `call_id`. Also `function_call` / `function_call_output` (`update_plan`, `request_user_input`, `spawn_agent`, `wait_agent`…) | `item/started` / `item/completed` | — |
| Command | `item_completed/CommandExecution` (`command[]`, `cwd`, `exit_code`, `aggregated_output`, `duration`, `parsed_cmd`) | `commandExecution` items, `item/commandExecution/outputDelta` (live output) | cmd, exit, output |
| File edit | `item_completed/FileChange` (`changes`, `status`) | `fileChange`, `item/fileChange/patchUpdated`, `turn/diff/updated` | paths, diff |
| MCP / image view | `item_completed/McpToolCall`, `ImageView` (`path`) | same items | — |
| Plan (plan mode) | `item_completed/Plan` (`text`, Markdown) | `item/plan/delta`, `turn/plan/updated` | text |
| Sub-agents | `item_completed/SubAgentActivity`, `CollabAgentToolCall`; `event_msg/sub_agent_activity` | `subagentStart/Stop` hooks | agent path, thread id |
| Turn start / end | `event_msg/task_started`, `task_complete` (`last_agent_message`, `duration_ms`) | `turn/started`, `turn/completed` (`status: completed / interrupted`), `thread/status/changed` | — |
| Abort | `event_msg/turn_aborted reason:"interrupted"`, plus a developer `<turn_aborted>` message. The interrupted tool's output is `"aborted by user after 2.8s"` | `turn/completed status:"interrupted"` | — |
| Usage | `event_msg/token_count` (`total_token_usage`, `last_token_usage`, `model_context_window`, `rate_limits`), `token_usage_record` (per response) | `thread/tokenUsage/updated` | tokens, context %. No cost |
| Compaction | `compacted`, `item_completed/ContextCompaction` | `thread/compacted` | — |
| Goal | `event_msg/thread_goal_updated` | `thread/goal/*` | — |
| **Approval asked / answered** | **Not in the rollout.** Only the tool input shows `sandbox_permissions:"require_escalated"` and `justification` | `item/commandExecution/requestApproval` (server request), `serverRequest/resolved`, `thread/status/changed activeFlags:["waitingOnApproval"]` | see §3 |
| Errors | `error` notification. Failed commands appear as `CommandExecution` with `exit_code` | `error`, `warning`, `guardianWarning` | — |

## 3. Blocked states

| State | TUI shows (`pane read --source visible`) | herdr `agent_status` | Transcript / hooks | Answer without the TUI |
|---|---|---|---|---|
| Command approval | "Would you like to run the following command? … Reason: … `$ rm -rf c.txt` › 1. Yes, proceed (y) 2. No, and tell Codex what to do differently (esc)". A "don't ask again for `<prefix>`" option appears when the model proposes a `prefix_rule` | **blocked** | Not in the rollout. Hook `PermissionRequest` gets `{tool_name:"Bash", tool_input:{command, description}, session_id, turn_id, transcript_path}` | Keys: `y` approves (verified), `esc` denies **and aborts the turn** (`turn_aborted`). `agent.prompt` refuses with `agent_blocked` (verified). app-server: reply `{decision:"accept"}` (or `acceptForSession`, `acceptWithExecpolicyAmendment`, `decline`, `cancel`); `availableDecisions` lists what is allowed |
| `request_user_input` question (plan mode) | "Question 1/1 … › 1. English (Recommended) 2. French 3. None of the above … tab to add notes / enter to submit / esc to interrupt" | **blocked** | Rollout: `function_call request_user_input`. Live: `item/tool/requestUserInput {questions:[{id, header, question, options[{label, description}], isOther}]}` | Keys: digits / arrows + enter. app-server: `{answers:{<id>:{answers:["French"]}}}`. The TUI cleared (verified) |
| "Implement this plan?" after a plan | Picker: 1 implement / 2 clear context and implement / 3 stay in Plan | **idle** (not blocked) | TUI-only, not a server request | Keys only (digit / esc), or a server `turn/start` that ignores the picker |
| `/permissions`, `/model`, `/resume` pickers | Menus | idle | — | Keys (digits / arrows / enter / esc) |
| Startup model promo ("Meet GPT-6 Sol 1. Try new model 2. Use existing") | Full-screen menu | **idle** | — | Keys. **Danger: Esc chose "Try new model" and wrote `model`/effort to `~/.codex/config.toml`.** I restored the two lines at once. `-c 'tui.model_availability_nux."gpt-6-sol"=9'` hides it |

**Who gets the approval with two clients:** both. The TUI and client B (which ran `thread/resume`) each got the
same request id. The first answer wins, and every client gets `serverRequest/resolved`. Verified both ways:

- B answered `accept`: the TUI's prompt vanished, the command ran, and herdr went blocked → working.
- `y` in the TUI: B got `serverRequest/resolved`.

B also gets requests for turns that the TUI started, and the TUI shows requests for turns that B started.

**Hook decisions:** a per-run `PermissionRequest` hook that prints
`{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` approved the
command with no TUI prompt. With no output, the TUI prompt appeared (verified). The hook was set with
`-c 'hooks.PermissionRequest=[{hooks=[{type="command",command="…/hook.sh"}]}]' --dangerously-bypass-hook-trust`;
hooks not yet trusted are skipped unless that flag is given.

**Most reliable mechanism for real Approve / Deny buttons:**

- With `--remote`: the app-server request. It carries the command, the reason and the allowed decisions, it
  clears the TUI, and the result is acknowledged.
- Without `--remote`: keys, guarded by screen text. `y` approves. `esc` denies, and that also interrupts the turn.
  The chat can label the buttons from the screen. The rollout has no request to parse.

## 4. Sending a message

| Case | Result | Status |
|---|---|---|
| `herdr agent prompt` while idle | Shows as the user's message and runs | works today |
| While working | **Steers**: the text goes into the running turn as a second user message, not into a queue. Verified: "add cherry" mid-`sleep` → "done cherry" | works today |
| Multiline | Bracketed paste keeps the newlines | works today |
| Starts with `/` | A known command runs (`/status`, `/new`, `/quit`, `/permissions`). Arguments are not parsed: `/model gpt-6-luna` was **sent to the model as text** | works with caveats |
| `@path` | Pasted as literal text. The model read the file. No mention popup | works today |
| Image | A pasted path *by itself* (`pane.send_text`) turns into `[Image #1]` and is attached (data URL). A path inside a longer `agent.prompt` stays text; the model used `view_image` instead | works with caveats |
| Server | `turn/start` (idle) and `turn/steer {expectedTurnId}` (working). Both appear in the TUI as `›` user rows and stream live | works today (`--remote` only) |
| `codex queue --thread <id> --message` | Exists ("Queue a message for an existing session"); not tested | untested |

## 5. Interrupt

- **Keys:** `esc` or `ctrl+c` while working. Both write `event_msg/turn_aborted reason:"interrupted"` plus a
  developer `<turn_aborted>` message. The TUI shows "■ Conversation interrupted".
- **Leftover processes:** background terminals keep running ("1 background terminal running"). `/stop` closes them.
- **`ctrl+c` caution:** on an idle, empty composer it starts quitting.
- **Server:** `turn/interrupt {threadId, turnId}` works and shows in the TUI (verified).

## 6. Model and mode

| Setting | How to change from outside | How to read it back |
|---|---|---|
| Model and effort | `/model` opens a picker (numbered list, then an effort list). In the effort list, **`enter` saves the default to the global `config.toml`; `s` applies it to this session only.** No direct `/model <name>` form. Server: `turn/start {model, effort}`; the TUI status line updated to "GPT 6 Luna medium" and config was untouched | `turn_context.model/effort`, `thread/settings/updated`, status line `GPT-5.6 Luna low · cwd`, `/status` |
| Approval mode | `/permissions` picker: 1 Ask for approval, 2 Approve for me, 3 Full Access, 4 Read Only (digit keys). Server: `turn/start {approvalPolicy, approvalsReviewer, sandboxPolicy}` (schema; not tested) | `turn_context.approval_policy / approvals_reviewer / sandbox_policy`, `/status` "Permissions: Workspace (Ask for approval)" |
| Plan mode | `shift+tab` cycles Default ↔ Plan (`herdr send-keys shift+tab` works); `/plan` also exists | Status line "Plan mode (⇧tab to cycle)", `thread/settings/updated collaborationMode.mode:"plan"`, `turn_context.collaboration_mode` |
| Everything at once | — | `/status` prints server URL, model, effort, permissions, collaboration mode, **session id**, tokens and context % |

## 7. Other interactive elements

Slash commands in 0.163 (from the `/` popup):

- **Plain actions:** `/init`, `/status`, `/new`, `/compact`, `/recap`, `/plan`, `/diff`, `/copy`, `/export`,
  `/raw`, `/vim`, `/stop`, `/ps`, `/pwd`, `/quit`, `/exit`, `/logout`, `/approve` (retries one Guardian denial).
- **Open a picker or panel:** `/model`, `/permissions`, `/resume`, `/fork`, `/review`, `/skills`, `/hooks`,
  `/mcp`, `/plugins`, `/agents`, `/side`, `/goal`, `/rename`, `/archive`, `/delete`, `/worktree`, `/config`,
  `/statusline`, `/title`, `/theme`, `/pets`, `/tui`, `/keymap`, `/experimental`, `/memories`, `/import`, `/ide`,
  `/mention`, `/daemon`, `/cd`, `/warnings`, `/feedback`, `/app`.

Notes for the chat:

- **Pickers:** the chat should show those as "open terminal", or as key buttons.
- **Indicators:** context % (`token_count.model_context_window`), "N background terminals", plan mode and Guardian
  warnings all show in the status area and in `/status`.
- **No cost figure** anywhere; tokens only.

**notify hook** (`-c 'notify=["…/notify.sh"]'`) works today but is thin:

- It fires only `agent-turn-complete` (`thread-id`, `turn-id`, `cwd`, `input-messages`, `last-assistant-message`).
- It also fires for the hidden title-generator thread.
- It does not fire for aborted turns or approvals.

**Hooks** (stable, on): `preToolUse`, `permissionRequest`, `postToolUse`, `preCompact`, `postCompact`,
`sessionStart`, `sessionEnd`, `userPromptSubmit`, `subagentStart`, `subagentStop`, `stop`, `interrupt`.

## 8. Remote over SSH

- **Rollout tail:** `tail -c +N -F` on the rollout works over a line stream (one JSON object per line). Finding the
  file is a one-shot `lsof -p <pid> -Fn` (or `/proc/<pid>/fd` on Linux) plus a `head -1` filter on
  `session_meta.source`. herdr's id also works for plain TUIs but goes stale after `/fork`. Works today.
- **`agent.prompt`, `send-keys`, `pane.read`:** go through herdr, unchanged. Works today.
- **App-server join:** `ws://127.0.0.1:P` binds localhost only. The server prints "use SSH port-forwarding for
  remote access", so this needs a forwarded local port. `unix://PATH` plus `codex app-server proxy --sock PATH` gives
  a stdio pipe, but **the bytes are WebSocket frames** (HTTP 101 upgrade, then masked binary frames; see
  `proxy_probe.py`), not lines. Oriel's line relay would need either a byte-stream channel or a small line↔WS shim
  run on the remote (a ~30-line Python or Node script piped in, not installed). Nothing new to install: `codex` is
  already there.
- **Lifetime:** the app-server must outlive the SSH link, so run it in its own herdr pane or tab, not as a relay job.
  If the server dies, the TUI stays up ("Reconnecting to server… (18s)", herdr says `working`). It reconnects when
  the server comes back on the same address, **but into a fresh thread with config defaults** (the `-m` override
  was lost).

## 9. Recommendation

**Adapter v1. No server; matches the current design, with fixes:**

- **Events:**
  - Find the rollout with `lsof` on the pane's `codex.real` pid, keeping only `session_meta.source == "cli"`
    files and taking the newest mtime.
  - Re-check after each send and on each `agent_session` change. Use herdr's id only as a hint: it is stale after
    `/fork`.
  - Tail the file and parse `event_msg/item_completed` items, plus `turn_context` (model, effort, mode,
    permissions), `token_count` (context %), `task_started` / `task_complete` / `turn_aborted` (working row), and
    `compacted`.
  - For forks, also read the parent file (`forked_from_id`) up to `forked_from_ordinal_exclusive`.
- **Actions:**
  - Send with `agent.prompt` (it steers while working).
  - Interrupt with `esc`.
  - Model with keys (`/model`, digit, `s`), or show the terminal.
  - Plan mode with `shift+tab`.
  - Blocked: the screen-text panel. `y` = approve, `esc` = deny and abort, digits for questions.
- **In chat:** messages, tool rows, plan text, status (model, effort, mode, context %), the blocked panel.
  **Show the terminal for:** pickers (`/model`, `/permissions`, `/resume`, `/fork`, "Implement this plan?",
  startup promos).

**Adapter v2. Worth doing; it is the only path to per-token text and real buttons:**

- Oriel starts Codex panes itself as two parts: a hidden herdr pane running
  `codex app-server --listen unix://<per-pane sock>`, and the TUI pane running
  `codex --remote unix://<sock> -C <cwd>` (`-C` because the TUI otherwise takes the server's cwd; I saw this but
  did not test `-C`).
- Oriel joins as a second client with `thread/loaded/list` + `thread/resume`. **Use one server per pane**: the
  server broadcasts `thread/started` to every client, so on a shared server a pane cannot be mapped to its thread.
  `thread.path` gives the rollout path.
- It gets live deltas and real Approve / Deny / question buttons (`requestApproval`, `requestUserInput`), plus
  `turn/start`, `turn/steer`, `turn/interrupt` and `turn/start {model, effort}`, all reflected in the TUI.
- An existing plain `codex` pane cannot be joined. It stays on v1.

**Top 5 risks:**

1. **Format churn.** `user_message` / `agent_message` / `exec_command_end` were replaced by `item_completed` in about
   10 minor releases. Tools are wrapped in code-mode `exec`. Paginated forks hold no copied history. The parser must
   be lenient and versioned by `session_meta.cli_version`.
2. **Wrong file.** One TUI process holds many rollouts (old threads, Guardian sub-agents). herdr's id is stale after
   `/fork`, and it is missing under `--remote` (hooks run in the server's environment).
3. **Approvals are invisible in the transcript.** In v1 they are screen and keys only. `esc` (deny) also aborts the
   turn. The launcher's managed `auto_review` means prompts are rare and differ from upstream; "Approve for me" can
   deny on its own (`/approve` retries).
4. **Pickers write global config.** `/model` + `enter`, and Esc on the startup model promo, wrote
   `~/.codex/config.toml`. Use `s` (session only) or server `turn/start {model}`.
5. **v2 needs a server lifetime and WebSocket.** The app-server must live in a herdr pane. A restart puts the TUI on
   a fresh thread. Remote needs a WS-capable byte channel or a shim. app-server is still labelled "[experimental]"
   and has deprecation notices (e.g. "full-history hydration is deprecated; use `excludeTurns:true` + `thread/turns/list`").

## Housekeeping

- **Session:** `oriel-dev-research-codex` was removed with `herdr-session.sh down`.
- **Processes:** all of mine were killed. No codex, app-server, wsclient or proxy processes are left.
- **One accidental global write:** the startup promo (Esc) changed `model`/`model_reasoning_effort` in
  `~/.codex/config.toml`. I restored the two lines at once. Nothing else changed, and later `/model` changes used `s` (session only).
- **New threads:** the spikes left about 9 small throwaway threads in `~/.codex/sessions/2026/10/27/` (cwd under
  `/tmp/oriel-research/codex`).
- **Not done:** I never started the user's managed daemon (`codex app-server daemon start` writes
  `~/.codex/app-server-daemon/`). The daemon path is the same app-server protocol as the `--remote` spike.
