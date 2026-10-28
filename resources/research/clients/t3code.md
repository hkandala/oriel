# T3 Code (pingdotgg/t3code): a chat-only control surface over headless agents

Repo: https://github.com/pingdotgg/t3code (HEAD 9ebca5f7, MIT, about 31k stars, many commits a day). A Node server
(Effect, SQLite) per machine, a React web app, an Electron shell, Expo phone apps. It is the largest open-source ADE.
It never shows an agent's TUI: every agent runs headless in a machine protocol and the app draws the chat. The
terminal is a plain shell. Not a herdr client.

## How chat works

| Agent | Process | Source |
|---|---|---|
| Claude | Agent SDK `query()` driving the user's `claude` | SDK messages, `includePartialMessages: true` |
| Codex | `codex app-server` over stdio | `turn/*`, `item/*` notifications |
| pi | `pi --mode rpc` with an injected MCP bridge | RPC events |
| OpenCode | its HTTP server (1.x one per thread, 2.x one per instance) | server events |
| Cursor, Grok, fx, Muse, ACP registry agents | ACP | `session/update` |
| Antigravity | its own process, profile per instance | native events |

- Claude: `apps/server/src/orchestration-v2/Adapters/ClaudeAdapterV2.ts:1029` (`query`), `:1481` (`resume`),
  `:1517` (`includePartialMessages`), `:1527` (`canUseTool`). Codex: `CodexAdapterV2.ts:6502` (`turn/start`),
  `:6973` (`turn/steer`), `:2499` (`turn/interrupt`). ACP: `packages/effect-acp/`.
- Every event goes through an orchestrator into the server's SQLite; clients subscribe over a WebSocket. The adapter
  boundary normalizes providers (`t3code/docs/internals/providers.md`).
- **Send** is a protocol call. `t3 thread send` from a shell queues the text as the next turn; it never interrupts
  (`t3code/docs/user/outside-agents.md`).
- **Approvals** are protocol requests: `canUseTool` for Claude, `item/commandExecution/requestApproval`,
  `item/fileChange/requestApproval`, `item/permissions/requestApproval` for Codex (`CodexAdapterV2.ts:5074-5217`),
  `session/request_permission` for ACP. Claude's `AskUserQuestion` becomes a form (`ClaudeAdapterV2.ts:9372-9387`).
  A text reply to a pending Claude approval declines it and sends the text as feedback. The default mode for new
  threads is **Full access** (`t3code/docs/user/permission-modes.md`).
- **Waiting for input** is a protocol state, so it is exact. `t3 thread send --wait` exits 2 when the agent waits for
  an answer.

## Terminal

`apps/server/src/terminal/` (6.3k lines with tests): node-pty shells in the project folder, 5,000 lines or 8 MiB of
scrollback on the server, replayed on reconnect (`t3code/docs/user/terminal.md`). No agent runs there. No way found to open a
thread's agent in its TUI; Claude history is read and forked through the SDK (`apps/server/src/claudeHistoryWorker.ts`).
Agents started outside T3 Code join only through T3's MCP server, as API clients, not as viewed sessions.

## Remote

The server runs on each machine. Clients reach it over LAN, Tailscale, T3 Connect (a hosted relay with DPoP tokens),
or desktop-managed SSH: the app downloads the server into `~/.t3/runtime` on the host, starts it and forwards a port
(`docs/user/remote-access.md:172-200`). Provider CLIs must be on the non-interactive login shell's `PATH`.

## Known problems (open issues)

- #24690: a Claude approval stays pending after the CLI withdraws its request.
- #22957: approval-pending commands stay "Running" after a mode change fails the run.
- #12979: an Antigravity "no longer pending" error deadlocks the UI.
- #24901: finished or waiting threads stay in the phone's "Working" shelf.

Most open bugs are the same kind: the app's copy of "pending" drifts from the agent's.

## Size

Huge. Server orchestration 71k lines, server providers 20k, provider packages (ACP, app-server, OpenCode, pi, …)
147k, web app 278k. The Claude adapter alone is 11k lines, the Codex adapter 7.7k. Tests are extra.

## For Oriel

- Copy: nothing structural. It answers a different question (no TUI).
- Note: even with exact protocol state, its open bugs are stale "pending" and "running" flags. Oriel's "show the TUI
  when unsure" fallback avoids that class.
- Avoid: one adapter per agent at 7-11k lines each; Full access as the default.
