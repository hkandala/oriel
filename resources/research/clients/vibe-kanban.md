# Vibe Kanban (BloopAI/vibe-kanban): a kanban board that runs agents headless, one process per turn

Repo: https://github.com/BloopAI/vibe-kanban (v0.1.45, Apache-2.0, about 28k stars). Rust (axum, tokio, SQLite)
backend with a React web UI; also a Tauri app. It is still active, but the README says the project is
**sunsetting**. It is not a herdr client. It runs every agent as a headless child in a machine protocol. Read it
for its normalizer and its approval flow, not for a chat over a TUI.

## Views

| | Chat (workspace "session") | Terminal |
|---|---|---|
| What | normalized entries: messages, tool cards, diffs, todos, approval cards | a plain login shell in the worktree |
| Process | a headless agent child, per turn | `portable-pty` shell (`crates/local-deployment/src/pty.rs:56`) |
| Agent TUI | **never shown** | the user can start a TUI there by hand; the chat does not see it |

Both views exist, but not of one agent. Feature request #1809 asks for a TUI.

## How chat data is obtained

One executor per agent in `crates/executors/src/executors/`, each with its own protocol and log normalizer:

| Agent | Child | Reference |
|---|---|---|
| Claude Code | `claude -p --input-format=stream-json --output-format=stream-json --include-partial-messages --replay-user-messages`, control protocol on stdin/stdout | `claude.rs:157-196`, `claude/protocol.rs` |
| Codex | `codex app-server` (JSON-RPC: `thread/start`, `thread/fork`, `turn/start`) | `codex.rs:453`, `codex.rs:606-631` |
| OpenCode | `opencode serve --port 0` plus its HTTP SDK, password in env | `opencode.rs:95-135`, `opencode/sdk.rs` |
| Gemini, Qwen, Copilot | ACP (`--experimental-acp`, `--acp`) | `gemini.rs:60`, `qwen.rs:54`, `copilot.rs:82`, `acp/` |
| Amp, Cursor, Droid | stream-json style stdout | `amp.rs`, `cursor.rs`, `droid.rs` |

- Raw stdout lines go to a `MsgStore` and to a per-process JSONL file of Vibe Kanban's own
  (`<asset_dir>/.../processes/<id>.jsonl`, `crates/utils/src/execution_logs.rs:18-22`). Older installs kept them in
  SQLite and migrate (`crates/services/src/services/execution_process.rs:30`).
- A normalizer per agent turns lines into `NormalizedEntry` items and streams JSON patches to the UI over a websocket (`crates/executors/src/logs/utils/patch.rs`).
- It never reads the agent's own transcript (`~/.claude/projects/...`).

## Input, turns and interrupts

- **One process per turn.** The Claude reader stops at the `result` message (`claude/protocol.rs:89-91`). A
  follow-up spawns a new child with `--resume <id>`. `--resume-session-at <uuid>` cuts history for "retry from
  here" (`claude.rs:360-380`).
- Codex follow-ups always `thread/fork` the old thread, never resume it (`codex.rs:606-617`).
- Messages typed while busy: **one** queued message per session, replaced by the next (`queued_message.rs:33-53`).
- Interrupt: a cancel token sends the control `interrupt` and keeps reading until `result`
  (`claude/protocol.rs:62-68`). Stop kills the process group (`group_spawn_no_window`, `claude.rs:650`).

## Approvals and questions

- Claude: Vibe Kanban starts with `--permission-prompt-tool=stdio --permission-mode=bypassPermissions`, then routes
  tools through its own `PreToolUse` hook callbacks sent in the SDK `initialize` message (`claude.rs:166-172`,
  `claude.rs:209-258`). Read-only tools skip approval. `AskUserQuestion` becomes a question card; answers go back
  as `updated_input.answers` (`claude/client.rs:204-220`).
- A deny returns Claude CLI's own rejection text, so the model reacts as in the TUI (`claude/client.rs:28`).
- Codex: `item/*/requestApproval` and `ToolRequestUserInput` server requests (`codex/client.rs:379-456`).
- Approvals time out after **10 hours** (`crates/utils/src/approvals.rs:6`).
- "Waits for input" is explicit: the client logs `ApprovalRequested`, the normalizer sets
  `ToolStatus::PendingApproval` (`claude.rs:1851`). No screen reading anywhere.

## Remote

- The server runs on the host with the agents. Other devices pair through Vibe Kanban cloud and a relay tunnel
  (`vibe-kanban/docs/remote-access.mdx`, `crates/relay-*`); an embedded SSH server serves editors over it. No plain SSH.

## Known bugs (GitHub issues)

- #3327: the SDK `initialize` hooks **replace** the project's `.claude/settings.json` hooks.
- #2783: the Stop hook (commit reminder) fires while Claude waits on `Task` sub-agents.
- #3218: replaying a long Codex log through the normalizer OOMs the backend (55-60 GB).

## Size

Executors (spawn, protocols, normalizers) 26k lines of Rust; `claude.rs` alone 3.3k, Codex normalizer 2.9k. The
chat UI (`packages/web-core/src/features/workspace-chat/` plus `packages/ui/src/components/Chat*.tsx`) 9.5k lines.

## For Oriel

- Copy: the `NormalizedEntry` shape (user, assistant, thinking, tool with `ActionType` and status, error) as a
  model for Oriel's chat items. It covers ten agents with one renderer.
- Copy: a deny message in the agent's own words, and "pending approval" as an explicit item state, not a guess.
- Avoid: one headless process per turn. It drops the TUI, and `initialize` hooks override the user's hooks
  (#3327). Oriel's TUI-first frame is the opposite design.
- Avoid: replaying a whole raw log through the normalizer on open (#3218). Page or cap history.
- Note: Codex follow-ups fork, so the thread id (and file) changes every turn.
