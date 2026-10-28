# Claude Code: chat view research

> Spiked in throwaway herdr sessions for the [chat view](../ui/chat-view.md). The spike files named below lived in `/tmp/oriel-research/claude/` and were not kept.

Agent: Claude Code 2.1.310 (native binary behind the company launcher `/usr/local/bin/claude`; the user's
zsh alias resolves "latest" = 2.1.311). Throwaway herdr session `oriel-dev-research-claude`, cwd
`/tmp/oriel-research/claude/work`, models Haiku 5.5 / Sonnet 5.5. Session deleted, processes killed.

Files here: `hook.py` (spike hook: logs every event, waits for a decision file), `statusline.py`,
`settings.json` (the per-run `--settings` file), `events.jsonl` (every hook input from my runs),
`statusline.jsonl` (102 statusline payloads), `sample-transcript-types.jsonl` (one trimmed line per
transcript entry kind), `sample-*.json` (hook inputs for PermissionRequest / AskUserQuestion /
ExitPlanMode), `tail-timing.log` (when lines hit disk).

## 0. Environment traps found first (they change every result)

| Trap | Evidence | Effect for Oriel |
|---|---|---|
| The user's zsh alias adds `--dangerously-skip-permissions` (and two more `--dangerously-*` flags) | first launch through the shell showed `⏵⏵ bypass permissions on` | A `claude` typed in a pane shell runs in **bypass** mode: no approval prompts at all. |
| Managed settings set `permissions.defaultMode: auto`. A `--settings` file with `defaultMode: default` does not override it. The `--permission-mode default` flag does. | footer `⏵⏵ auto mode on` until I passed the flag | Mode at start depends on managed policy. |
| The launcher injects its own `--settings {json}` (model `claude-opus-5-5[1m]`, `--autocompact`, env) and merges my file into it. | `pgrep -fl` argv | Per-run `--settings` works, but it merges with the launcher's settings. |
| The OS sandbox auto-allows Bash inside the cwd (`mkdir`, `rm -r` ran with no prompt in "manual" mode). | `rm -r d2` ran with no PermissionRequest | Real approval prompts are rarer than upstream. I used `permissions.ask` rules to force them. |
| Company plugins add **PermissionRequest hooks that return `allow`** (`agent-security-guardrails`, plus `bento` and `planning-with-files` from the user's plugins). The builtin `cc-plugin-sec-default` module waits for all hooks. **An `allow` from any hook beat my hook's `deny`.** | debug log: guardrails `{"behavior":"allow"}` at +70 ms; my `deny` at +2.9 s; TUI showed "Allowed by PermissionRequest hook" | A chat "Deny" button cannot win against guardrails. Disabling them per run (`"enabledPlugins": {"agent-security-guardrails@agent-market": false, ...}` in `--settings`) made deny work. |
| `/model <name>` (direct form) **writes `"model"` into `~/.claude/settings.json`**, even with `--setting-sources project,local`. | `diff` against the backup Claude made; **I reverted it at once** (copied the backup back; only that key differed) | Don't send `/model <name>`. Use the picker plus `s` ("this session only"). See §6. |

User config (read only, names only): `~/.claude/settings.json` has hooks: Notification
(`permission_prompt`) / PreToolUse / SessionEnd / SessionStart / Stop / UserPromptSubmit →
`agentbar-hook.sh`. It also has SessionStart → `herdr-agent-state.sh session` and SessionStart → `rex
__internal session-start`. It has **no statusLine**, `askUserQuestionTimeout: 5m`, `tui: fullscreen`,
and 58 enabled plugins. Managed settings have 2 PreToolUse hooks (web-tool guards) and 1 PostToolUse hook
(Write chmod), and no statusLine. Hooks merge across levels, so a per-run `--settings` adds to all of these.
In practice 28 to 37 hooks run per event (`running PreToolUse hooks… 23/28`, `hookCount: 37`).

herdr integration: `herdr integration status` → `claude: current (v11)`. The hook
(`~/.claude/hooks/herdr-agent-state.sh`) runs on SessionStart only. It sends `pane.report_agent_session`
with `agent_session_id`, `agent_session_path` (= transcript_path) and `session_start_source`. herdr keeps
only `{kind:"id", value:<uuid>}` (path dropped). Busy/idle/blocked status comes from screen detection.

## 1. Transcript

- **Where:** `~/.claude/projects/<cwd with every / and . → ->/<session-uuid>.jsonl` (here
  `-private-tmp-oriel-research-claude-work`). Subagents:
  `<uuid>/subagents/agent-<agentId>.jsonl` + `agent-<id>.meta.json`
  (`agentType, description, toolUseId, requestShape:"background", finished`).
- **Created lazily:** no file (not even the project folder) until the first prompt. herdr already
  reports the id at startup, so the path can be missing for a while.
- **Finding the pane's file** (works today, with caveats):
  1. herdr `agent_session.value` on `pane.get` (needs the integration; stale after `/branch`, see below;
     cleared to null when claude exits).
  2. Any hook input carries `session_id` + `transcript_path` (exact, live).
  3. The **statusLine** stdin carries `session_id` + `transcript_path` on every redraw (best live source).
  4. `lsof` is useless: Claude does not keep the jsonl open (checked).
  5. Newest-mtime `*.jsonl` in the cwd's project folder (racy with two panes in one cwd).
- **Session changes** (tested):

| Action | Session id / file | SessionStart `source` | herdr `agent_session` |
|---|---|---|---|
| `--resume <id>` | same id, same file (appends) | `resume` | updated |
| `/clear` | **new id**, new file (written at the next prompt) | `clear` (+ SessionEnd `reason: clear`) | updated at once |
| `/branch` (fork) | **new id**, file written at once with copied history | `fork` | **stays on the old id** (hook ran and reported; herdr ignored it) |
| `/compact` | same id, same file; `system/compact_boundary` + `user` with `isCompactSummary:true` | `compact` (+ Pre/PostCompact) | unchanged (correct) |
| exit (ctrl+c ×2) | — | SessionEnd | `agent_session` → null |

## 2. Event types

**When it hits disk:** one line per finished content block / message, not per token. Measured
(`tail-timing.log`): the screen showed streamed text at t+4.8 s, and the assistant line landed at t+8.5 s.
The only live partial stream in interactive mode is the screen (`pane.read`). Hooks are per event,
not per token. `--include-partial-messages` is `-p` only.

Transcript `type`s seen (2.1.310 has many more than older docs):

| Entry | How to show | Fields we need |
|---|---|---|
| `user`, `content` string | user bubble | `message.content`, `uuid`, `parentUuid`, `timestamp`, `permissionMode` (mode at send), `promptId`, `origin.kind`, `promptSource:"typed"` |
| `user`, content `[text, image]` | bubble + image | image is inline `{"type":"image","source":{"type":"base64","media_type":"image/png","data":…}}`, `imagePasteIds` |
| `user` with `isMeta` / `<command-name>/model</command-name><command-args>…` / `<local-command-stdout>` | slash command row | parse the tags; hide `<local-command-caveat>` |
| `user`, content `[tool_result]` | fill the matching tool row | `tool_use_id` ↔ assistant `tool_use.id`; `is_error`; `toolUseResult` (structured: `{type:"create",filePath,structuredPatch}`, Bash stdout, Agent `{isAsync,agentId,…}`); `permissionDecision {decision:"accept"/"reject", source:"hook"}`; `toolDenialKind: "user-rejected"/"permission-rule"` |
| `user` `[text "[Request interrupted by user for tool use]"]` | "Interrupted" row | `interruptedMessageId` |
| `user` with `<task-notification>` | background subagent finished | task-id, tool-use-id, output-file |
| `user` with `isCompactSummary` | "Conversation compacted" summary (collapsed) | |
| `assistant` content `text` / `tool_use` / `thinking` | Markdown / collapsed tool row / thinking | one content block per line, same `message.id` across lines; `message.model` (**model per message**), `message.usage` (input/output/cache tokens, `thinking_tokens`), `stop_reason`, `requestedModel`, `perTurnEffort`. **Thinking text is empty** (`thinking:""` + `signature`): only a "thought for N" row is possible (`thinkingDurationMs`). |
| `attachment` (many kinds) | mostly hide | show `queued_command` (a message queued mid-turn, **not** a `user` line!), `file` (@mention), `hook_permission_decision`, `plan_mode` / `plan_mode_exit` (`planFilePath`), `hook_system_message`; hide `hook_success`, `skill_listing`, `instructions`, `prompt_snapshot`, `deferred_tools_*`, `total_tokens_reminder`, `environment`, `model`, `date` |
| `system` `turn_duration` | end-of-turn marker ("Worked for 9s") | `durationMs`, `messageCount` |
| `system` `stop_hook_summary`, `informational`, `compact_boundary` | hide / notice / divider | `compactMetadata {trigger, preTokens, postTokens}` |
| `permission-mode`, `mode` | current mode (lags: written at turn end, not on shift+tab) | `permissionMode` |
| `cost-state` | cost | `totalCostUSD`, `modelUsage{model:{inputTokens,…,costUSD}}` |
| `ai-title`, `agent-name`, `last-prompt` | tab title | `aiTitle` |
| `queue-operation` | queue UI | `operation: enqueue/remove`, `reason: absorbed_mid_turn`, `content` |
| `file-history-snapshot` / `-delta`, `api-request*`, `atis-latch` | ignore | |
| subagent file lines | nested under the Agent tool row | `isSidechain:true`, `agentId` |

TodoWrite / TaskCreate: **not offered** in this session (the model searched with ToolSearch and found
none). Upstream would write `tool_use` name `TodoWrite`/`TaskCreate`. Treat todos as a tool row. Plan
mode writes the plan to `~/.claude/plans/<slug>.md` with a normal `Write` tool call, then `ExitPlanMode`.

Hooks seen live (`events.jsonl`): SessionStart (`source`, `model`), UserPromptSubmit (`prompt`),
PreToolUse (`tool_name`, `tool_input`, `tool_use_id`), PermissionRequest (`tool_name`, `tool_input`,
`permission_suggestions` (often null), **no `tool_use_id`**), PostToolUse, Notification
(`notification_type: permission_prompt`, about 6 s after a dialog opens), Stop (`last_assistant_message`;
**not fired on Esc interrupt**), SubagentStart/Stop (`agent_id`, `agent_type`, `agent_transcript_path`,
`last_assistant_message`), PreCompact/PostCompact (`trigger`, `compact_summary`), PostModelSwitch
(`from_model`, `to_model`, `requested_model`, `source: auto` when plan mode or auto mode swaps the model),
SessionEnd (`reason`). Most carry `permission_mode` and `prompt_id`.

## 3. Blocked states

| State | TUI shows | herdr `agent_status` | Hook | Answer without the TUI |
|---|---|---|---|---|
| Tool approval (Bash/Write/Edit) | box: "Do you want to create b.txt? ❯ 1. Yes / 2. Yes, and switch to accept edits… / 3. No · Esc to cancel · Tab to amend" | `blocked` | **PermissionRequest** (dialog already open while the hook runs) | **hook decision (works, with caveats)**; keys: `enter` = option 1, `escape` = reject **and end the turn** ("User rejected write to e.txt") |
| AskUserQuestion | "☐ Fruit / Which fruit…? ❯ 1. Apple … 4. Type something. 5. Chat about this · Enter to select · ↑/↓ · Esc to cancel" | `blocked` | PreToolUse, then PermissionRequest | **hook with `answers` (works today)**; keys: `down`…`enter` (tested), Esc = "User declined to answer" |
| ExitPlanMode | "Ready to code? Here is Claude's plan: … ❯ 1. Yes, and use auto mode / 2. Yes, manually approve edits / 3. Tell Claude what to change" | `blocked` | PreToolUse (input has `plan` + `planFilePath` injected), then PermissionRequest | **PreToolUse allow + updatedInput works**; PermissionRequest `allow` was **parsed but the dialog stayed** (not possible that way); keys: `down`,`enter` (tested) |
| `/model` confirm ("Switch model? ❯ 1. Yes…") and `/model` picker | picker | confirm: `idle`; picker: **`idle`** | none | keys only; `agent.prompt` would type into the picker |

- `agent.prompt` while blocked → `{"code":"agent_blocked"}` before it sends anything (tested).
- **KEY SPIKE: can a hook wait for an outside decision?** Yes. `hook.py` writes `pending.json`,
  polls `decision.json` every 0.2 s for N s, then prints the decision. Results:
  - **PermissionRequest:** the TUI **shows the normal dialog right away while the hook waits** (it does
    not hide it). Writing `{"behavior":"allow"}` closed the dialog and the tool ran ("Allowed by
    PermissionRequest hook"). `{"behavior":"deny","message":"Denied from Oriel chat"}` → tool_result
    `is_error`, the model read the message (only after guardrails was disabled, §0).
    `{"behavior":"allow","updatedPermissions":[{"type":"setMode","mode":"acceptEdits","destination":"session"}]}`
    → footer switched to `⏵⏵ accept edits on`. **Timeout** (no output, exit 0) → the dialog simply stays.
    That is the fallback for free. The default hook timeout is 600 s (I set 120).
  - **Race:** if the user answers in the TUI first, Claude goes on, but **the hook process is not
    killed**. It keeps polling until its own timeout (seen with `pgrep`) and would eat a later decision
    file. The protocol needs a per-request id, and the hook must give up when the request is gone.
    PermissionRequest has no `tool_use_id`: match on `prompt_id` + `tool_name` + `tool_input`, or pair it
    with the preceding PreToolUse's `tool_use_id`, and treat a tool_result for that id as "answered".
  - **AskUserQuestion via PreToolUse:** the TUI shows a spinner `running PreToolUse hooks… 3/4`
    (status `working`, no dialog). Returning `permissionDecision:"allow"` +
    `updatedInput = {questions (echoed), answers:{"Which color do you prefer?":"Blue"}}` → "User
    answered Claude's questions: → Blue". The dialog never appeared. On timeout, PermissionRequest
    fires next, then the dialog.
  - **AskUserQuestion via PermissionRequest** (better): the dialog is visible while waiting, and
    `{"behavior":"allow","updatedInput":{questions, answers}}` answered it ("Dog") and closed it. So
    the chat and the TUI can both answer, and the first one wins.
  - **ExitPlanMode via PreToolUse** `{"permissionDecision":"allow","updatedInput":<echo tool_input>}` →
    plan approved with no dialog. The mode went back to the mode before plan mode (acceptEdits). Via
    PermissionRequest `allow` (with or without setMode): the hook result was logged, but the TUI kept
    the dialog, so I answered with keys. Not tried: PermissionRequest `allow` + `updatedInput`.
    Plan feedback ("Tell Claude what to change") through a hook = `deny` + `message` (not tested).
  - **Esc while a PreToolUse hook waits** interrupts the turn and **kills** the hook.
- **Chat buttons:** yes. The hook input carries everything: tool + input (command / file_path +
  content), questions + options + multiSelect, plan markdown. The option labels of the TUI dialog
  ("Yes, and switch to accept edits") are not in the input; synthesise them (Allow / Allow + accept
  edits via setMode / Deny with message).

## 4. Sending

`herdr agent prompt` (bracketed paste + Enter), all tested:
- idle → normal turn. Multiline (`\n`) stays one message. `@a.txt` resolves (attachment `file`, Read
  shown). A pasted absolute **image path** becomes `[Image #1]` and is sent as a base64 image block. A
  text starting with `/` runs the command (`/clear`, `/compact`, `/branch`, `/model`).
- **while working → queued**: the TUI shows the text above the prompt with "ctrl+enter to send now" and
  "Press up to edit queued messages". It is absorbed at the next tool boundary ("The user sent a new
  message while you were working"), recorded as `queue-operation` + `attachment/queued_command`.
- blocked → `agent_blocked`. A picker open → status `idle`, so a prompt would go into the picker (risk).
- No server call makes the TUI show a message (only Remote Control, which goes through Anthropic's cloud
  and was not tested).

## 5. Interrupt

`escape` while working → "Interrupted · What should Claude do instead?". Transcript: a `tool_result`
"The user doesn't want to proceed…" (`toolUseResult: "User rejected tool use"`) + a user text
`[Request interrupted by user for tool use]` with `interruptedMessageId`. **No Stop hook.** In a
dialog, Esc = reject + end of turn. ctrl+c twice = exit the TUI (never send it from the chat).

## 6. Model and mode

| Want | How | Status |
|---|---|---|
| Change model, this session only | `/model` (picker: "Enter to set as default · **s to use this session only** · Esc"), move with `up`/`down` (read the `❯` row first; the start row varies), press `s` → "Set model to Sonnet 5.5 for this session only"; user settings md5 unchanged | works with caveats (screen-driven) |
| `/model sonnet` typed | asks "Switch model? 1. Yes" (cache warning), then **saves to `~/.claude/settings.json`** | avoid |
| Effort | `--effort` at launch; `/effort` (footer shows `◐ medium · /effort`). Not run, because it probably persists like `/model` | untested |
| Mode | `shift+tab` cycles **auto → manual(default) → accept edits → plan → auto** (bypass only when launched with it). Also a PermissionRequest hook `updatedPermissions setMode` (tested) | works today |
| Plan mode swaps the model | entering plan/auto fired PostModelSwitch haiku→sonnet `source:auto` | note |
| **Read model** | statusLine `model.id/display_name` (live), PostModelSwitch hook, `assistant.message.model` (per message), screen | works today |
| **Read mode** | **screen footer** (`⏸ manual mode on`, `⏵⏵ accept edits on`, `⏸ plan mode on`, `⏵⏵ auto mode on`, `bypass permissions on`), hook `permission_mode` (at events only), transcript `permissionMode` (at send / turn end). **The statusLine has no mode field** in 2.1.310 | works with caveats |

StatusLine stdin keys: `session_id, session_name, prompt_id, transcript_path, cwd, workspace{current_dir,
project_dir, added_dirs}, model{id, display_name}, version, output_style{name}, cost{total_cost_usd,
total_duration_ms, total_api_duration_ms, total_lines_added/removed}, context_window{total_input_tokens,
total_output_tokens, context_window_size, current_usage{…}, used_percentage, remaining_percentage},
exceeds_200k_tokens, effort{level}, prompt_cache{warm, ttl, expires_at, hit_ratio,…}, fast_mode,
thinking{enabled}`. It runs on redraws (gaps 0.4 s to a few s while active). It is a good live
model/cost/context/session-id feed: our script appends a JSON line to a file, and Oriel tails it.

## 7. Other interactive elements

- Slash commands typed as text work (`/clear`, `/compact`, `/branch`, `/add-dir <p>`, `/cd`,
  `/model <n>` (persists!), `/btw`, `/background`). The `/` menu is huge (built-ins + about 700 skills).
  Pickers/panels that need the TUI: `/model` (no arg), `/resume`, `/rewind`, `/config`, `/permissions`,
  `/mcp`, `/agents`, `/plugin`, `/hooks`, `/tasks`, `/export`, `/theme`, `/output-style`, `/effort`.
  Show the TUI for these.
- Subagents: Agent tool runs **async/background** by default (`isAsync:true`), the footer says
  `/tasks to see subagents`, completion comes back as a `<task-notification>` user line. The detail is in
  `subagents/agent-<id>.jsonl`.
- Context / cost: statusLine (above), `cost-state` lines, `usage` per assistant message.
- Compaction: `/compact` and auto; the boundary is in the transcript.

## 8. Remote over SSH

- Transcript: `ssh host tail -c +N -F ~/.claude/projects/<slug>/<id>.jsonl` works (plain file, append
  only). The `<slug>` rule (`/` and `.` → `-`) can be computed from the pane cwd.
- Hooks and statusLine are just commands on the remote host. They can write request/status lines to a
  file under `/tmp/oriel-<pane>/` (tailed over a line stream). Decisions go back as a one-shot
  `printf … > decision-<id>.json`. **No port, no daemon.** The settings can be **inline JSON**
  (`--settings '{"hooks":…}'`) with `python3 -c`/sh commands, so nothing has to be installed except
  what the launch argv carries.
- The hard limit: `--settings` only applies at **launch**. A TUI that is already running picks up hook
  changes only from watched files: user `~/.claude/settings.json`, `<cwd>/.claude/settings.json`,
  `<cwd>/.claude/settings.local.json`. I confirmed that creating `work/.claude/settings.local.json`
  mid-session made its UserPromptSubmit hook fire on the next prompt ("Detected change to …"). Editing
  my `--settings` file mid-session did **not** apply new `ask` rules. Writing into the user's project or
  global settings breaks the "no config edits" rule. So for already-running panes the fallback is keys +
  screen.

## 9. Recommendation

**Events:** tail the transcript (path from statusLine/hooks; herdr `agent_session` as a fallback).
Parse `user`/`assistant`/`tool_result`/`queued_command`/`compact_boundary`/`turn_duration` and skip the
rest. Show "Working" + screen text while `agent_status=working` (no token stream on disk).

**Live side channel (for panes Oriel launches):** start Claude with an Oriel `--settings` (inline JSON):
- `statusLine` → appends stdin JSON to `/tmp/oriel/<pane>/status.jsonl` (model, cost, context,
  session_id, transcript_path). Careful: this **replaces the screen statusline** if the user has one
  (this user has none). The script can run the user's own statusline command and pass its output through.
- `SessionStart` / `PostModelSwitch` / `Stop` / `SubagentStop` → event lines (fixes the stale `/branch` id).
- `PermissionRequest` (all tools) → writes `req-<id>.json`, polls `dec-<id>.json`, gives up on timeout
  or when the request is answered elsewhere. That gives chat **Approve / Deny / Allow + mode** buttons,
  with the TUI dialog visible as the fallback, and **AskUserQuestion options** (answers via
  `updatedInput`).
- `PreToolUse` matcher `ExitPlanMode` only → plan **Approve** button (allow + echoed `updatedInput`).
  Keep it short or async, because it shows a spinner, not the dialog, while it waits.

**Actions out:** `agent.prompt` for messages (queues while working), `agent.send_keys escape` to
interrupt, `shift+tab` for mode (read back from the footer), `/model` picker + `s` for model,
`/clear`, `/compact`, `/branch` as text. Pickers and panels → "show the TUI".

**Already-running panes / no Oriel launch:** transcript + screen. Blocked dialogs are answered with keys
(`enter` = first option, `escape` = reject, arrows + `enter` for AskUserQuestion / plan). Parse the
options from `pane.read --source visible`.

**Top 5 risks**
1. **Other PermissionRequest hooks win.** The company guardrails `allow` beats our `deny`, and user
   plugins (bento, planning-with-files) also decide. Deny/approve buttons can lie unless we detect it
   (watch `permissionDecision.source` / the tool_result) or disable those plugins per run.
2. **Launch-only control.** `--settings` hooks/statusLine need Oriel to start the agent. Existing panes
   (and the user's alias with `--dangerously-skip-permissions`, managed `auto` mode) get keys + screen only.
3. **Orphan hooks and races.** A hook that keeps waiting after a TUI answer must not swallow a later
   decision. There is no `tool_use_id` on PermissionRequest. Each hook process also costs ~0.1–1 s, and
   every event already runs ~30 hooks.
4. **Session identity drift.** herdr ignores `/branch` (fork), the file does not exist until the
   first prompt, and `agent_session` becomes null on exit. Use the statusLine/hook session_id.
5. **Format churn and side effects.** 2.1.x adds entry types often (`queued_command` instead of
   `user`, empty thinking, `permission-mode` lines that lag). `/model <name>` and probably `/effort`
   write the user's global settings. Plan mode/auto mode swap models silently. A picker leaves
   `agent_status` at `idle`, so `agent.prompt` can type into it.
