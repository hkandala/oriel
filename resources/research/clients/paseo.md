# Paseo (getpaseo/paseo): a daemon that drives agents headless

Repo: https://github.com/getpaseo/paseo (commit b9f624f, Apache-2.0). TypeScript: a Node daemon, an Expo and React
Native app, an Electron desktop. Not a herdr client. Read for its chat view; the options for Oriel are in
[../ui/chat-view.md](../ui/chat-view.md).

## How chat works

- The chat view never reads a PTY. The daemon starts each agent headless in its structured mode, and one contract
  normalizes them (`packages/server/src/server/agent/agent-sdk-types.ts`: `startTurn`, `steerActiveTurn`,
  `subscribe`, `streamHistory`, `interrupt`, `respondToPermission`, `close`):
  - Claude: `@anthropic-ai/claude-agent-sdk` `query()`, which runs the user's `claude` in stream-json; permissions
    through `canUseTool`.
  - Codex: `codex app-server` JSON-RPC (`turn/start`, `turn/steer`, `turn/interrupt`).
  - pi: `pi --mode rpc` (JSONL). OpenCode: `opencode serve` (HTTP and SSE).
  - ACP for Copilot (`copilot --acp`), Cursor, Kimi, Gemini and others, about 40 in all.
- **Send:** a WebSocket call to the daemon, then the adapter's call. Mid-turn messages "steer" where the agent allows
  it (`turn/steer`, pi `steer`); otherwise interrupt and replace, or a client-side queue.
- **Approvals:** one shape, `AgentPermissionRequest {kind: tool|plan|question|mode|other, actions[]}`, pinned above
  the stream (`packages/app/src/agent-stream/view.tsx`). Tool calls are typed (shell, read, edit with a unified diff,
  write, search, fetch, sub_agent); shell output is capped at 64 KiB.
- **Interrupt:** `turn/interrupt`, `query.interrupt()`, pi `clear_queue` then `abort`. Unread steers must be dropped
  first, or the stopped turn resumes (`docs/providers.md`).

## Terminal and chat

- Two tab kinds, two processes, **no live switch**. A terminal tab is a PTY in a worker; "terminal profiles" start
  agent TUIs in it (`{id:"claude", command:"claude", args:["{{{prompt}}}"]}`, `packages/protocol/src/terminal-profiles.ts`).
- A TUI agent gets only a status dot, from opt-in global hooks that do nothing outside Paseo's PTYs
  (`[ -n "$PASEO_TERMINAL_ID" ] && paseo hooks claude <event>`, POST running, idle or needs-input).
- Bridges are manual: **Copy resume command** (`claude --resume {id}`, `codex resume {id}`, `pi --session {id}`) and
  **Import session**, which scans `~/.claude/projects` and pi's session folder and resumes the session headless.
  Nothing checks that the TUI has exited first (a guess from `agent.ts:1799`).

## Remote

The daemon runs where the code is and owns every agent. Clients reach it by direct WebSocket, an end-to-end
encrypted relay (Noise NK, QR pairing), an SSH tunnel to a running daemon, or Docker. Chat travels as live
`agent_stream` messages plus a paged timeline fetch with a cursor and an epoch for catch-up.

## Size and breakage

- Provider adapters are about 58k lines (Claude 12k, Codex 10k, OpenCode 10k, omp 9k, pi 7k, ACP base 4k); the chat
  UI about 30k more.
- Most open bugs are provider state drift in those adapters: Codex items stuck "running" (#4538), pi subagent rows
  stuck (#6269), pi import truncates history (#4947), ACP prompts hang after a disconnect (#7070). A daemon started
  inside a Claude Code terminal starts `claude` children that are "Not logged in" (#3618).

## For Oriel

- Copy: status from hooks gated on the app's own terminal variable; a resume command per agent; one canonical user
  row per prompt, matched by a client message id, not by text.
- Avoid: a structured mode means owning tens of thousands of lines that chase each agent's protocol.
