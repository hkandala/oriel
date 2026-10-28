# Crystal (stravu/crystal): headless Claude and Codex runs per turn, dead

Repo: https://github.com/stravu/crystal (v0.3.5, MIT). Electron, React, TypeScript, node-pty, better-sqlite3,
Monaco. Deprecated: the README now only points to its successor, Nimbalyst (see [nimbalyst.md](nimbalyst.md)). Read it
as the baseline that Nimbalyst grew out of. It is not a herdr client and never shows the agent's TUI.

## Shape

| | |
|---|---|
| Chat view | yes: "Rich Output" view of parsed JSON events, plus raw "Messages" and "Stats" views in dev mode (`frontend/src/components/panels/claude/ClaudePanel.tsx:17`) |
| Terminal view | yes, but a separate shell in the worktree, not the agent (`main/src/services/terminalPanelManager.ts:43`) |
| Both on one process? | no: the agent has no TUI at all |
| Chat source | stdout of a headless child: `claude --verbose --output-format stream-json -p <prompt>` (`main/src/services/panels/claude/claudeCodeManager.ts:72,123`); `codex exec --json` (`main/src/services/panels/codex/codexManager.ts:221`) |
| Input | a new process per turn: `--resume <session_id>` for Claude (`claudeCodeManager.ts:114`), `codex exec resume <id>` (`codexManager.ts:246`) |
| Approvals | `--permission-prompt-tool mcp__crystal-permissions__approve_permission` (`claudeCodeManager.ts:147`): an MCP stdio bridge talks to Crystal over a Unix socket (`main/src/services/mcpPermissionBridge.ts:33,107`) and a dialog answers `{behavior: allow/deny}`. Default mode is `--dangerously-skip-permissions` (`claudeCodeManager.ts:88-91`) |
| Remote | none |

## How it works

- The headless child still runs inside node-pty (`main/src/services/panels/cli/AbstractCliManager.ts:582`). Output is
  split on `\n` and every line goes through `parseCliOutput` as JSON (`AbstractCliManager.ts:667-683`). There is a
  retry that re-spawns through `node` when a shebang fails (`AbstractCliManager.ts:570-640`).
- "Waiting" is the process exit after a `result` message, or a `prompt` event (`main/src/events.ts:883-895`). No
  TUI means no ambiguity: the turn is over when the process ends.
- A message sent while the child runs is written raw to its PTY (`main/src/ipc/session.ts:495`); Codex stop is
  `\x03` (`main/src/services/panels/codex/codexPanelManager.ts:265`).
- Events are stored in SQLite and rendered by per-agent transformers (`frontend/src/components/panels/ai/transformers/`).

## Known problems (GitHub issues)

- #102: "session gets overwritten if using Claude Code CLI anywhere else": resume by id breaks when a TUI uses the
  same conversation.
- #178: users want to run without `--dangerously-skip-permissions`; the MCP approval path was the exception.
- #88: no mid-turn intervention or CLI interop, because there is no live process between turns.

## Size

About 14k lines of chat code without tests: main `panels/{claude,codex,cli,ai}` 4.2k, renderer `panels/ai` 5.7k,
`panels/claude` 2k, `panels/codex` 2.2k. The Codex transformer alone is 1.1k.

## What Nimbalyst changed

- The Claude default moved from `-p` per turn to the Agent SDK `query()`; Codex moved from `exec --json` to
  `codex app-server`; ACP and OpenCode's server came in.
- A new, opt-in mode runs the **real interactive `claude` TUI** in a PTY drawer under the chat. There
  `--permission-prompt-tool` is ignored, so approvals go through a `PreToolUse` hook.
- It follows transcripts of CLI sessions started outside the app (`~/.claude/projects`, Codex rollouts).

## For Oriel

- Copy: nothing structural. The per-turn headless model is the opposite of "the TUI keeps running".
- Avoid: `--permission-prompt-tool` for interactive sessions: it only works with `-p` (Nimbalyst confirmed this).
- Avoid: resuming a conversation that a live TUI owns (#102). One writer per conversation.
