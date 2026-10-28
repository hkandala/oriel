# Codex: chat view research

> Two spikes in throwaway herdr panes for the [chat view](../ui/chat-view.md). The second one settled the reliable core below; spike scripts and samples lived in `/tmp/oriel-research/` and were not kept.

Codex CLI 0.163.0 through the company launcher, herdr 0.9.5, macOS. Runs were in the throwaway session
`oriel-dev-research-codex2` (removed), `gpt-5.6-luna` at low effort.
Every agent was started by typing `/usr/local/bin/codex …` into the pane's shell with `herdr pane send-text`.

## Summary

| Feature | Mechanism | Rating | Evidence |
|---|---|---|---|
| Launch flags | Inline `-c hooks.SessionStart=…` plus `-c hooks.state={…trusted_hash…}`. No file, no trust dialog, no bypass flag | RELIABLE | No dialog; hook ran; `config.toml`/`hooks.json` hashes unchanged; user hooks still ran (herdr `agent_session` set) |
| Recognize Oriel panes | A token in the hook path, read from argv via `pane.process_info` | RELIABLE | `codex`, `dotslash`, `codex.real` argv all carry `oriel-T1` |
| Transcript discovery | SessionStart hook appends its JSON (with `transcript_path`, `source`) to `/tmp/oriel-<token>/hooks.jsonl`; last non-null path wins | RELIABLE | Followed startup, `/new`, `/clear`, `/resume`, `/fork`; compaction keeps the file |
| File watching | `tail -n +1 -F <rollout>`; parse `event_msg/item_completed` | RELIABLE | Line on disk 0.1–0.3 s after the TUI drew the final text; 0 partial chunks |
| Parser core | `parse.py`: user, assistant, thinking, tools, subagents, plan, question, turn start/end, interrupt; unknown lines skipped | RELIABLE (typed items) / FRAGILE (code-mode `exec` rows) | `python3 parse.py --demo` passes on both samples |
| Send | `herdr agent prompt` | RELIABLE when ready | Idle, working (steers), multiline: all landed as `UserMessage` |
| Confirm sent | `UserMessage` item with the same text | RELIABLE | 1.2–3 s after send (UserPromptSubmit hooks run first) |
| Ready-for-input guard | herdr `agent_status` ∈ {idle, working} **and** screen shows the composer row `› …` directly above the status row | FRAGILE | Pickers and dialogs report `idle`; the screen rule caught all I opened |
| Interrupt | `esc` key | RELIABLE | `event_msg/turn_aborted reason:"interrupted"` |
| Blocked → show TUI | herdr `agent_status == blocked` | RELIABLE | Command approval, edit approval, `request_user_input` all `blocked` |
| In-chat approvals | PermissionRequest hook that waits on an answer file | FRAGILE (do not ship by default) | Works end to end, local and over SSH, but pre-empts the launcher's Guardian reviewer and hides the TUI prompt |
| Questions in chat | none (no hook carries an answer channel) | SKIP → show TUI | — |
| Remote | Same files, `tail -F` stream, one-shot `cat`/`mv`, herdr calls | RELIABLE | User-mode sshd on 127.0.0.1: stream, prompt and approval all worked |
| Status (model, effort, mode) | `turn_context` lines | RELIABLE (read only) | Every turn |
| Model / mode change, slash commands, images | keys into pickers | SKIP → show TUI | `/model` picker writes config on Enter; a slash race opened `/model` |
| `codex --remote` + app-server | second client | SKIP now | Needs a server pane, a WS shim for remote, and loses embedded hooks' pane env |

## Launch command

What Oriel types into the pane's shell (token `7f3a`, made per pane; output of `python3 launch.py 7f3a`):

```sh
/usr/local/bin/codex -c 'hooks.SessionStart=[{hooks=[{type="command",command="mkdir -p /tmp/oriel-7f3a; umask 077; cat >> /tmp/oriel-7f3a/hooks.jsonl; echo >> /tmp/oriel-7f3a/hooks.jsonl"}]}]' -c 'hooks.state={"/<session-flags>/config.toml:session_start:0:0"={trusted_hash="sha256:…"}}'
```

Add the promo guard the user needs (`-c 'tui.model_availability_nux."gpt-6-sol"=9'`). I tested the full line in
`cmd2.txt` (this hook plus the PermissionRequest hook and the guard). The SessionStart-only line is a subset of it.

- **Full path, not `herdr agent start`.** `herdr agent start --kind codex` types `codex …`, so the shell alias adds
  `--yolo --dangerously-enable-internet-mode --dangerously-disable-osx-sandbox` (seen in argv).
- **No file is installed.** The hook is a shell one-liner in a `-c` value. Codex runs it with `$SHELL -c` (zsh
  here), so it uses POSIX syntax only.
- **Trust without the bypass flag.** Codex skips untrusted hooks and shows a "Hooks need review" picker at
  startup. "Trust all" there writes `hooks.state` into `~/.codex/config.toml`. Codex also reads `hooks.state` from the
  `-c` layer (`codex-rs/hooks/src/config_rules.rs`). The hash is sha256 of sorted compact JSON
  `{"event_name":"session_start","hooks":[{"async":false,"command":…,"timeout":600,"type":"command"}]}`.
  `hookhash.py` reproduces the user's own trusted hash for herdr's hook exactly. The key needs the inline table form
  because the `-c` parser splits dotted keys on every `.`. The same thing broke `-c 'tui.model_availability_nux."gpt-6.1-sol"=9'`
  ("invalid type: map").
- **Fallback:** `--dangerously-bypass-hook-trust` also works (tested), but it runs every untrusted hook, including a
  cloned repo's `.codex/hooks.json`. Use it only if the hash form stops matching. A mismatch shows the "Hooks need
  review" picker: treat it as "show the TUI" and tell the user never to press "Trust all".
- **User settings stay intact.** Hooks load per config layer (`discovery.rs`), so the `-c` hook is added beside
  `hooks.json`, config.toml hooks, plugin hooks and managed hooks; none is replaced. `hooks.state` merges per key.
- **Side effect:** any `-c` makes Codex run in embedded mode, not on the shared background server (a startup warning
  sits behind "⚠ 1 warning · f2"). That is what makes hooks run with the pane's env and the TUI hold the rollout.
- **Recognition after an Oriel relaunch.** `pane.process_info` gives the argv. A `/tmp/oriel-([0-9a-z]+)/` match
  gives the token and the file, so no Oriel-side state is needed. A pane where the user quit and restarted plain
  `codex` has no token, so it gets no chat switch (correct). Delete `/tmp/oriel-<token>` when the pane closes.

## 1–2. Transcript discovery

The hooks payload holds `session_id`, `transcript_path`, `cwd`, `model`, `permission_mode`, and `source`. Results
from `hooks.log` and `run/oriel-T1/hooks.jsonl`:

| Action | SessionStart `source` | File | When the hook fires |
|---|---|---|---|
| Start | `startup` | new | At the first prompt (lazy), not at launch |
| `/new` | `startup` | new | First prompt in the new thread |
| `/clear` | `clear` | new | First prompt |
| `/resume` (picker) | `resume` | the old file, appended | First prompt after the resume |
| `/fork` | `fork` | new; `session_meta.forked_from_id` + `forked_from_ordinal_exclusive` | First prompt. herdr's `agent_session` stayed on the parent |
| `/compact` | no SessionStart (PreCompact/PostCompact) | same file: `compacted` + `item_completed/ContextCompaction` | — |
| Subagent | `SubagentStart` (not SessionStart) carries the **child's** path | child file, `session_meta.source.subagent` | — |

Rules:

- Record **only SessionStart**. With every event logged, `SubagentStart` would have switched to the child file.
- Skip entries with `transcript_path: null`. One appeared in pane 2 with a second session id and no file (likely
  the hidden title thread).
- Check that `head -1` of the file is `session_meta` with `source == "cli"`.
- When a SessionStart fires, the file already exists (`exists 72375` bytes).
- **Lag:** after `/new`, `/resume` or `/fork`, the chat keeps the old thread until the next prompt. Those actions
  are pickers in the TUI anyway.
- **Forks hold no copied history** (`history_mode:"paginated"`). For older rows, read the parent
  (`~/.codex/sessions/*/*/*/*<forked_from_id>.jsonl`) up to the `ordinal` in `forked_from_ordinal_exclusive`.

## 3. File watching and parser

- **Latency** (`latency.py`, polling the screen and the file every 50 ms, 4 runs). The user message reached disk
  1.2–3.0 s after `agent prompt`. The assistant text reached disk 0.1–0.3 s after it showed on screen. That text is
  written once, when the whole message is done.
- **Partial lines:** every read chunk ended in `\n` (0 partial). Still buffer to the newline: `parse.py` reads lines.
- **File created late / replaced:** macOS `tail -n +1 -F` waits for a missing file, then follows `mv` and recreate
  (tested `a`, `b`, `c`). Rollouts are not rotated.
- **Parser** (`parse.py`, ~100 lines; the self-check is `python3 parse.py --demo`):
  - `item_completed` types: `UserMessage`, `AgentMessage` (phase `commentary`/`final_answer`), `Reasoning`
    (thinking row; the text is empty here), `CommandExecution` (command, exit, output), `FileChange` (paths),
    `McpToolCall`/`ImageView`, `Plan`, `SubAgentActivity` (started/completed, path, thread id),
    `ContextCompaction`.
  - Questions: `function_call request_user_input` paired with its output by `call_id`. Todos: the same for
    `update_plan` (not produced in my runs).
  - Turn rows: `task_started`, `task_complete`, `turn_aborted`. Errors: `event_msg error`. Status: `turn_context`.
  - Everything else is skipped and counted.
- **Robust:** the `item_completed` envelope and its typed items carry everything the chat needs, self-contained, so
  no pairing is needed. Unknown types fall through to "skipped".
- **Fragile:**
  - Tools are wrapped in code-mode `custom_tool_call name:"exec"` whose input is JS. An interrupted or hook-denied
    call writes no typed item, only `custom_tool_call_output` ("aborted by user after 19.5s"). The parser shows those
    as an `incomplete` exec row with raw JS.
  - A background command can complete *after* `turn_aborted` (`sleep 30` did).
  - Older builds used other event names (round 1). Key the parser on `session_meta.cli_version` and show the TUI
    when "skipped" grows inside a turn.

## 4. Send

- **Works:**
  - Idle: runs.
  - Working: steers into the turn (round 1).
  - Multiline: `UserMessage.content[0].text == "Line one.\nLine two.\n…"`.
  - Confirm: wait for a `UserMessage` with the same text. 5 s without it means "not sent: show the TUI".
- **Failures seen:**
  - **Picker open:** `agent prompt` returns OK and types into the picker. In `/resume`, "zzqq" became the search
    text. In the `/model` picker, the digits in "1) … 2) …" picked a model, then an effort row. The delayed Enter
    would have saved the model to `config.toml` ("enter default · s session"). It did not land; the hashes were
    unchanged.
  - **Agent starting:** status `unknown`. The text reached the composer but the Enter was lost.
  - **Draft in composer:** the text is appended. `ctrl+u` did not clear the composer, so a later `/quit` was sent
    as "early/quit".
  - **Blocked:** herdr refuses with `agent_blocked` (round 1).
- **Ready guard** (FRAGILE, but it caught every case above). Send only if both hold:
  - herdr status is `idle` or `working`.
  - In the last 4 non-empty visible rows, a row starting with `› ` is followed by the status row
    (`<model> <effort> · <cwd>…`), not by a numbered option.

  Pickers, approvals, questions and "Implement this plan?" all hide the status row (footers like "enter select ·
  esc back", "Press enter to confirm", "enter to submit answer"). `/statusline` can change the status row, so
  allow an empty match to fall back to "show the TUI".

## 5. Interrupt

`esc` while working. The transcript gets `event_msg/turn_aborted {reason:"interrupted"}` plus a developer
`<turn_aborted>` message. An interrupted tool gets only `custom_tool_call_output "aborted by user after Ns"`.
`esc` during our waiting PermissionRequest hook killed the hook process and aborted the turn. Avoid `ctrl+c`:
on an empty idle composer it starts quitting.

## 6. Approvals and questions

**Tested end to end** with the PermissionRequest hook in `launch.py --perm`. It writes `perm.<pid>.req`, waits up
to 120 s for `perm.<pid>.ans`, prints the answer, and exits.

| Case | Result |
|---|---|
| Request seen | `.req` has `tool_name:"Bash"`, `tool_input {command:"rm -rf g1", description:"Do you want to allow…"}`. Edits come as `apply_patch` |
| Allow from outside (`mv` of a `.tmp` into `.ans`) | Command ran, the TUI showed "Ran rm -rf g1" |
| Deny | "Blocked by hook · PermissionRequest hook denied approval"; **the turn goes on** (unlike TUI `esc`) |
| Timeout / "ask in terminal" (exit with no output) | The TUI prompt appears, herdr `blocked`; `y` approved |
| User at the TUI first | The TUI shows only "Working · Running hooks", no prompt to answer. Its only move is `esc`, which kills the hook (the `.req` stays; check `kill -0 <pid>`) |
| Remote | `.req` read and `.ans` written over SSH one-shots; the command ran |

**Why it stays off by default** (from `core/src/tools/approvals.rs` and `hooks/src/events/permission_request.rs`):

- **Hooks run before the reviewer.** The order is hooks, then Guardian (`auto_review`, forced by
  `/etc/codex/managed_config.toml`), then the user. Under default permissions the hook fired for `rm -rf g1`, so a
  waiting hook takes over every escalation that Guardian would have reviewed. That changes the user's policy.
- **All PermissionRequest hooks are awaited in parallel, and any deny wins.** A slow Oriel hook delays the user's
  other hooks too. `/hooks` lists 3 installed PermissionRequest hooks from plugins and admin config.
- **The TUI cannot answer while the hook waits.**

**Rule for v1:**

- When herdr says `blocked`, show the TUI. That covers command and edit approvals and `request_user_input`
  questions.
- For idle-but-not-ready states (pickers, "Implement this plan?", the hooks-review dialog), the ready guard shows
  the TUI on send.
- Questions have no answer channel outside the TUI. `PreToolUse tool_name:"request_user_input"` sees the question
  text, but nothing can answer it.

## 7. Remote (one SSH connection, line streams, one-shot commands)

I ran a user-mode `sshd` on 127.0.0.1:22722 with a temp host key, user key and `AuthorizedKeysFile` under `sshd/`,
and killed it afterwards. The client was `ssh -F /dev/null -i … -o UserKnownHostsFile=sshd/known_hosts`; I did not
touch `~/.ssh`.

- **Launch:** the same line typed into the remote pane. The hook is inline, nothing is installed, and the token dir
  is `/tmp/oriel-<token>` on the remote.
- **Recognize:** `herdr pane.process_info` (remote herdr) argv → token.
- **Discover:** one-shot `grep -v '"transcript_path":null' /tmp/oriel-<token>/hooks.jsonl | tail -1`.
- **Stream:** `tail -n 0 -F <rollout>` over SSH into local `parse.py` gave `turn_start`, `status`,
  `user "remote-ok"`, `assistant "remote-ok"`, `turn_end`. To follow a SessionStart switch, stream
  `tail -F hooks.jsonl` as well (second stream), or re-run the one-shot after each Stop or send.
- **Send / interrupt / blocked:** herdr calls, unchanged. The remote `herdr` was not on the non-interactive SSH
  `PATH` (`~/.local/bin`). Use a full path.
- **Answer files** (if ever enabled): `ls`, `cat`, `kill -0`, `mv` one-shots worked.
- **Caveat:** a remote `tail -F` can outlive a dropped SSH link until its next write (SIGPIPE). The relay should
  kill its jobs.

## 8. Everything else

| Item | Rating | Note |
|---|---|---|
| Model / effort / mode / approval display | RELIABLE | `turn_context.model/effort/collaboration_mode.mode/approval_policy` |
| Context % | RELIABLE | `event_msg/token_count` (`model_context_window`); no cost |
| Model change | SKIP → TUI | Picker; Enter = global default (config write), `s` = session |
| Plan mode toggle | FRAGILE | `shift+tab` works; read back from `turn_context` |
| Slash commands | SKIP → TUI | `send-text '/new'` + Enter once opened `/model` instead; most commands open pickers |
| Images | SKIP | A lone pasted path becomes `[Image #1]` (round 1) |
| Subagents | RELIABLE rows, SKIP detail | `SubAgentActivity` started/completed with `agent_thread_id`; the child rollout exists (`source.subagent`) if detail is ever wanted |
| `codex --remote` + app-server | SKIP | Round 1: full control and live deltas. Without live text it adds a server pane and lifetime, a WS↔line shim for remote, hooks running in the server's env (no pane id), and a fresh thread after a server restart. The hook path gives the same core with no server |

## From the first spike

- A TUI started as `codex --remote <app-server>` can be fully driven by a second client: `thread/resume`, per-token deltas, approvals (`requestApproval`, both clients get it, the first answer wins), `requestUserInput`, `turn/start`, `turn/steer`, `turn/interrupt`, model and effort. A plain TUI listens on nothing. Without live text this is not worth a server pane.
- The company launcher forces `approvals_reviewer = auto_review` (the Guardian reviewer) and allows common commands, so most commands never ask a human.
- `/model` is a picker only; `/model x` goes to the model as text; Return at the effort step writes `~/.codex/config.toml`, `s` keeps it to the session. Esc on the startup model promo also wrote the config.
- `/permissions` (1 Ask, 2 Approve for me, 3 Full Access, 4 Read Only) and shift+tab (Plan) change the mode; `turn_context` reads it back. There is no cost figure, only tokens.
