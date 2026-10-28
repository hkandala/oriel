# Terragon (terragon-labs/terragon-oss): cloud agents with a web chat, handoff to a local TUI

Repo: https://github.com/terragon-labs/terragon-oss (snapshot at shutdown, Apache-2.0, no longer maintained, about
260 stars, one issue). Next.js web app (`apps/www`), PartyKit WebSocket service (`apps/broadcast`), a Node daemon that
runs inside each sandbox (`packages/daemon`), the `terry` CLI (`apps/cli`), Postgres, Redis, R2. Sandboxes on E2B,
Daytona or Docker. Not a herdr client, and no TUI at all: agents run headless in the cloud. Read it for its headless
pipeline and the "pull to a local TUI" handoff.

## Views

| | Chat view | Terminal view |
|---|---|---|
| What | the main thread UI in the browser | a floating panel with a plain shell in the sandbox |
| Process | one headless agent run per message | a new PTY via the E2B SDK (`apps/broadcast/src/sandbox.ts`) |
| Agent's TUI | never runs | never runs; the terminal does not show the agent |
| Support | all agents | E2B only (`apps/www/src/lib/sandbox-terminal.ts:3`) |

So there is no chat|term switch over one agent process.

## How chat data is obtained

- The daemon runs one shell line per user message: `cat <prompt file> | <agent> <headless flags>` under
  `bash -lc`, detached (`packages/daemon/src/runtime.ts:283`).
  - Claude: `claude -p --output-format stream-json --verbose --dangerously-skip-permissions`, `--resume <id>`
    (`packages/daemon/src/claude.ts:177`).
  - Codex: `codex exec --dangerously-bypass-approvals-and-sandbox --json ... resume <id>`
    (`packages/daemon/src/codex.ts:233`).
  - Gemini `--output-format stream-json`, Amp `--execute --stream-json`, OpenCode `run --format json`.
- Every agent's lines are converted to Claude's stream-json message shape, so the UI has one renderer
  (`codex.ts:380`, `parseCodexLine`).
- The daemon buffers lines and POSTs them in batches to the server, grouped per chat, with retry and backoff
  (`packages/daemon/src/daemon.ts:1033`). The server stores them and broadcasts over WebSocket.
- The agent's own transcript is read only for handoff and checkpoints: the server copies
  `~/.claude/projects/<cwd>/<id>.jsonl` out of the sandbox to R2 (`apps/www/src/server-lib/claude-session-internal.ts:34`).

## Input, approvals, waits

- Input: the server writes a JSON message to a temp file in the sandbox, then runs
  `cat <file> | node terragon-daemon.mjs --write`, which forwards it over a unix socket to the daemon
  (`packages/sandbox/src/daemon.ts:238`). Messages sent while busy go to a server-side follow-up queue
  (`apps/www/src/server-lib/process-follow-up-queue.ts`).
- Approvals: none. All agents run with permissions bypassed. In plan mode Claude gets
  `--permission-prompt-tool mcp__terry__PermissionPrompt`; the MCP tool **denies** `ExitPlanMode` with "User is
  reviewing the plan", the run ends, and the user approves in the web UI with a new message
  (`packages/mcp-server/src/index.ts:84`). Behind a feature flag.
- "Waits for input" = the process exited. There are no questions mid-turn.
- Stop: a `stop` socket message kills the process group (`daemon.ts:212`).

## Reliability tricks

- Idle watchdog: no stdout or stderr for 15 min kills the run and posts an error result (`daemon.ts:513`).
- Before `--resume`, the daemon `find`s the session JSONL; if it is missing it uses `--continue` instead
  (`claude.ts:37`).
- After a killed run, Claude's JSONL can end with a `tool_use` that has no `tool_result`, and resume then fails. The
  daemon appends a fake error `tool_result` line for each dangling call before resuming (`claude.ts:67`,
  `maybeFixLogsForSessionId`).
- The prompt goes in through a temp file and `cat |`, never as an argv string.

## Handoff to a local TUI

- `terry pull <task>` downloads the Claude JSONL, writes it to `~/.claude/projects/<local cwd>/<id>.jsonl`, checks
  out the branch, and with `--resume` runs `claude --resume <id>` locally (`apps/cli/src/commands/pull.tsx:96`).
- That is a second process on a copy of the conversation; the cloud side does not see later local turns.

## Remote and size

- All remote by design: the web UI never talks to a sandbox; the server and the broadcast service do.
- Daemon and parsers 5.4k lines; web chat components 8.2k (`apps/www/src/components/chat`); sandbox terminal 1k.

## For Oriel

- Copy: before resuming Claude, check the JSONL exists and patch dangling `tool_use` entries. Oriel never resumes,
  but the same dangling state shows up when a turn is interrupted. The chat parser must accept a `tool_use` with no
  result as "interrupted", not "running forever".
- Copy: one normalized message shape for all agents, decoded per agent at the edge.
- Copy: an idle watchdog as a last resort when no event arrives.
- Avoid: headless one-shot runs per message. They lose the TUI, so live questions and approvals cannot exist.
- Avoid: a terminal that is not the agent. It does not help when the chat cannot parse something.
