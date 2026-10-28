# CloudCLI / Claude Code UI (siteboon/claudecodeui): headless chat runs beside a separate shell TUI

Repo: https://github.com/siteboon/claudecodeui (AGPL-3.0, v1.37.x, about 14k stars, very active). Node server
(TypeScript, Express, WebSocket, node-pty, SQLite) plus a React/Vite web client that also ships as an Electron app.
Providers: Claude Code, Codex, Cursor CLI, OpenCode. It does **not** wrap a running TUI: chat turns run as new
headless processes, and the "Shell" tab is another PTY. Both point at the same session id.

## Chat view

- **Claude:** each turn is an Agent SDK `query()` with `resume: <session id>`; `resumeSessionAt` rewinds to an
  edited message (`server/modules/providers/list/claude/claude-runtime.provider.ts:370-382`).
- **Codex:** `@openai/codex-sdk` `resumeThread`/`startThread`, which is `codex exec` under it; exec cannot ask, so it
  keeps the sandbox on and has no approvals (`codex/codex-runtime.provider.ts:247`, `:320-325`). A small
  `codex app-server` client is used for side jobs (`codex/codex-app-server.client.ts:65-77`).
- **Cursor / OpenCode:** spawn `cursor-agent` / `opencode` per turn and parse their JSON output
  (`cursor/cursor-runtime.provider.js:159`).
- **History:** read from the agents' own files. `sessions-watcher.service.ts:13-30` watches `~/.claude/projects`,
  `~/.codex/sessions`, `~/.cursor/projects` and OpenCode's data dir with chokidar (`:250`), indexes sessions in
  SQLite and pushes `session_upserted`; an open chat reloads on `externalMessageUpdate`
  (`src/modules/chat/hooks/useChatSessionState.ts:198`). So a turn typed in a real terminal shows up, after the fact.

## Terminal view

The Shell tab opens a node-pty login shell and types `claude --resume "<id>" || claude` (or `codex resume <id>`,
`opencode --session <id>`, `cursor-agent --resume=<id>`) (`server/modules/websocket/services/shell-websocket.service.ts:216-271`).
That is a **second process** on the same conversation. Nothing stops the chat and the shell from writing one session
at once; there is no fork.

## Approvals and questions

Claude only: SDK `canUseTool` sends `permission_request` over the WebSocket and waits; `AskUserQuestion` and
`ExitPlanMode` always go to the user, even with bypass (`claude-runtime.provider.ts:126`, `:1146-1175`). Settings
allow/deny lists are matched first.

## Waiting, remote, reliability

- "Waiting" is just "the headless turn ended" or "a permission request is open". No TUI state.
- Remote: the server runs on the machine; you reach it over your own network or a tunnel. The hosted CloudCLI runs
  the same server in a cloud box.
- Known bugs: one session id with two transcript files; the indexer keeps whichever it saw last, and the chat shows a
  stale copy that looks hung (#1170, fix in #1379); subagent files under `subagents/` once overwrote the parent row
  (`claude-session-synchronizer.provider.ts`, `isSubagentTranscript`); all assistant text of a turn merged into one
  row while streaming (#1136); PTY output split across WebSocket frames on Windows (#888).

## Size

Server about 70k lines with tests; the client chat module about 23k lines, the whole client about 72k.

## For Oriel

- Copy: a file watcher over the agents' own session folders is enough to keep a chat current with a terminal
  session; that is what Oriel plans.
- Copy: skip `subagents/` and `tool-results/` files when indexing Claude sessions; they repeat the parent id.
- Avoid: sending chat turns through a second headless process while a TUI may run on the same session.
- Avoid: choosing the transcript by scan order. Take the path from the agent (hook) or pick by newest write.
