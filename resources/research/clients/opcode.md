# opcode (winfunc/opcode, formerly getAsterisk/claudia): a Claude Code GUI over `claude -p`

Repo: https://github.com/winfunc/opcode (v0.2.1, AGPL-3.0, about 22k stars). Tauri 2 (Rust) with React and
TypeScript; an optional axum web server for phones. Claude Code only. Little activity: issue #398 asks "Is this
project dead?" and users answer yes. It is not a herdr client. Read it as the simplest possible chat, and for what
it misses.

## Views

| | Chat | Terminal |
|---|---|---|
| Exists | yes (`src/components/ClaudeCodeSession.tsx`) | **no** (no xterm, no PTY anywhere) |
| Process | a new `claude -p` child per prompt | none |

No TUI is ever started, so the "switch views" question does not apply.

## How chat data is obtained

- **Live:** stdout of `claude -p <prompt> --output-format stream-json --verbose --dangerously-skip-permissions`
  (`src-tauri/src/commands/claude.rs:921-1017`). Each line goes out as a Tauri event `claude-output:<session>`, plus
  a generic `claude-output` (`claude.rs:1174` onward, the `emit` calls). Exit sends `claude-complete`.
- **History:** reads the agent's own transcript `~/.claude/projects/<encoded cwd>/<id>.jsonl` line by line
  (`claude.rs:882-917`). The live and history paths both feed one renderer (`StreamMessage.tsx`, `ToolWidgets.tsx`).
- **Agent runs** (saved "CC agents"): the same `claude -p`, and a file watcher that polls the transcript JSONL every
  500 ms and re-sends the **whole file** when it grows (`src-tauri/src/commands/agents.rs:1444-1520`).
- It finds the session id from the first `system/init` line (`claude.rs`, `spawn_claude_process`). Claude may give a
  new id on `--resume`, so the UI listens on the generic channel until `init` arrives, then switches to the scoped
  one (`ClaudeCodeSession.tsx:531-538`).
- Project folder names are decoded with `replace('-', "/")` (`claude.rs:186-190`), which breaks on paths with a
  dash.

## Input

- No stdin protocol. Every prompt is a new process: first `-p`, then `-c` or `--resume <id>`
  (`claude.rs:952-1017`). Model per prompt (`sonnet`/`opus`).
- Prompts typed while busy go to a local queue in React state (`ClaudeCodeSession.tsx:127-144`).
- Cancel kills the child: registry, then `child.kill()`, then `kill <pid>` (`claude.rs:1019-1150`).
- One global "current process": starting a new session **kills the running one** (`claude.rs:1204-1215`).

## Approvals and questions

- **None.** Every run has `--dangerously-skip-permissions`. Issue #292: "claudia changing files without asking for
  permission". There is no question UI and no "waits for input" state; the only states are running and complete.

## Remote

- `web_server.rs` serves the same UI over REST and a websocket on the host. Its own design notes say session events
  are not scoped and cancel is a stub, so it is "functional for single-session use" only
  (`web_server.design.md:172-200`, `:366-373`). No SSH.

## Other features

- Checkpoints: file snapshots per message, restore, fork from a checkpoint (`src-tauri/src/checkpoint/manager.rs:188`,
  `:452`, `:661`). Separate from Claude's own rewind.

## Known bugs (GitHub issues)

- #398: since Claude Code became a full TUI, a stream-only wrapper cannot follow it.
- #71, #409: the UI spins forever or shows no output while the backend works.
- #50: navigating away interrupts the conversation.
- #302: it expects old `.claude` folder layouts.

## Size

Chat UI about 7.2k lines (`ClaudeCodeSession.tsx` 1.8k, `ToolWidgets.tsx` 3.0k, `StreamMessage.tsx` 0.7k,
`FloatingPromptInput.tsx` 1.3k). Rust `commands/claude.rs` 2.3k. Whole backend 11k.

## For Oriel

- Copy: one renderer for both the live stream and the transcript file. The stream-json line and the transcript
  line share types, so tool widgets work on both.
- Copy: take the session id from the agent (the `init` line), and expect it to change on resume.
- Avoid: `--dangerously-skip-permissions` as the answer to approvals. Oriel keeps the TUI for that.
- Avoid: re-reading the whole transcript on every change, polling, and `-`→`/` path decoding. Tail by offset and get
  the transcript path from the agent.
- Avoid: one process per prompt. It is why opcode died when Claude Code's TUI moved on (#398).
