# Sculptor (imbue-ai/sculptor): a desktop agent app with chat agents and separate terminal agents

Repo: https://github.com/imbue-ai/sculptor (backend 0.50.0.dev0, MIT, active: commits daily, about 240 stars, few public
issues). Electron and React frontend (`sculptor/frontend/`), Python FastAPI backend (`sculptor/sculptor/`), SQLite.
Not a herdr client. Each agent is **either** a chat agent **or** a terminal agent. There is no chat|term switch on one
process. The terminal agent path is the part most like Oriel.

## Two agent kinds

| | Chat agent (integrated harness) | Terminal agent (registered TUI) |
|---|---|---|
| Agents | Claude Code, pi | any TUI; Claude Code ships as a sample |
| Process | headless child: `claude -p` stream-json, `pi --mode rpc` | the TUI in a PTY owned by the backend |
| Chat data | the child's stdout events, stored in Sculptor's DB | none: "Sculptor never parses their output" |
| Input | stream-json on stdin, pi RPC lines | bracketed paste, then `\r` 0.75 s later |
| Status | from the protocol | hooks call `sculpt signal busy/idle/waiting` |
| Resume after restart | `--resume <id>` (Claude), `--session-id` (pi) | `resume_command_template` with the hook-reported id |

- The panel picks one or the other on the capability `supports_chat_interface`
  (`frontend/src/pages/workspace/chat/ChatPanelContent.tsx:34`). Terminal agents return all capabilities false
  (`sculptor/agents/terminal_agent/harness.py:18`).

## Chat agents

- Claude: one CLI per turn, `--input-format stream-json --output-format=stream-json --include-hook-events
  --permission-prompt-tool stdio --dangerously-skip-permissions`, then `--resume <id>`
  (`sculptor/agents/default/claude_code_sdk/process_manager_utils.py:62`).
- Before resume it checks that `~/.claude/projects/.../<id>.jsonl` exists and holds the id; else it falls back to the
  last valid id and warns that the last message may be lost (`process_manager_utils.py:501`, `process_manager.py:677`).
- Questions and plan approval: built-in `AskUserQuestion` and `ExitPlanMode` are disabled with `--disallowed-tools`.
  An in-process SDK MCP server offers replacements; the call blocks until the user answers in a native panel
  (`claude_code_sdk/mcp_server.py:1`). Tool permissions are skipped, so there are no approval cards.
- pi: a long-lived `pi --mode rpc --session-dir --session-id --no-extensions -e <pinned extension>`; questions come
  from Sculptor's own pi extension (`sculptor/agents/pi_agent/agent_wrapper.py:1`, `backchannel.py`).
- Sculptor logs every stdin/stdout line to its own `transcript.jsonl` for debugging (`process_manager.py:152`). The UI
  never reads Claude's transcript.

## Terminal agents (the part to study)

- A registration is a TOML file in `~/.sculptor/terminal_agents/`: `launch_command`, `resume_command_template`,
  `accepts_automated_prompts` (`samples/terminal_agents/claude-code/claude-code.toml`).
- The backend opens a login shell in a PTY, waits for its first output byte, then types the launch command
  (`sculptor/tasks/handlers/run_terminal_agent/terminal_session.py:207`). Like Oriel's new pane chooser.
- Claude gets `--settings <hooks json>` per run, so the user's config is untouched. Hooks
  (`claude-code-hooks.json`): `SessionStart` → idle; `UserPromptSubmit` → busy and the session id (pulled from the
  stdin JSON with `sed`, no python needed); `Stop` → idle; `PreToolUse AskUserQuestion|ExitPlanMode` → waiting,
  `PostToolUse` on them → busy; `Notification permission_prompt` → waiting, `idle_prompt` → idle; file edits →
  `files-changed`. Every hook ends in `|| true`.
- The session id is taken at the first prompt, not at `SessionStart`, because Claude writes no resumable transcript
  before a message exists (sample `README.md`).
- Signals post over HTTP to the backend (`tools/sculpt/sculpt/commands/signal.py:100`). Only signals after the latest
  run start count (`sculptor/web/derived.py:102`).
- Send (`sculptor/web/terminal_input.py:55`): three guards (opted in; latest signal is IDLE or WAITING; PTY alive),
  then bracketed paste, sleep 0.75 s, then `\r` as its own write. Claude shows "Pasting text…" and swallows an
  Enter that comes sooner; a back-to-back write fails, 0.2 s works, 0.75 s is margin. With no signals yet, it refuses to write: broken
  hooks degrade to a plain terminal.
- The chat composer, the API and the CI babysitter all use this one helper (`sculptor/web/app.py:2766`).
- The PTY dies with the backend. On the next start the backend reaps a stale shell only if it is a session leader and
  older than the backend, then relaunches with `--resume` (`terminal_session.py:172`, `run_terminal_agent/v1.py:66`).
- `CLAUDE_CODE_NO_FLICKER=1` forces Claude's alt-screen renderer in the embedded xterm.

## Remote

- No per-agent remote. A "custom backend command" runs the whole backend elsewhere (Docker recipe, SSH, VM) and
  prints a URL the app connects to (`sculptor/docs/help/experimental/container_backend.md`).

## Size

Claude chat backend 6.6k lines, pi 5.9k, message conversion and streams 2.5k, frontend chat 17.5k (no tests).
The terminal agent path is about 1.2k lines in total, plus a 39-line panel.

## For Oriel

- Copy: hooks through a per-run `--settings` file, every hook fail-open; status only from signals of the current run.
- Copy: write into the TUI only when the last signal is idle or waiting; no signal means "show the terminal".
- Copy: bracketed paste, then Enter as a separate write after a delay (0.75 s); same finding as Orca.
- Copy: take the Claude session id at `UserPromptSubmit`, and check the transcript file before `--resume`.
- Avoid: the split into two agent kinds. Sculptor's terminal agents get no chat at all; Oriel wants the transcript
  chat over the same TUI.
