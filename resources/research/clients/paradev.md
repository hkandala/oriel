# Paradev (paradevai/paradev): ACP chats in a host daemon

Repo: https://github.com/paradevai/paradev (HEAD 2c586e1c, Elastic License 2.0). A rebrand of Superset
(`@superset/*` packages). Bun and Turbo monorepo: Electron and React desktop with xterm.js, an Expo app, a Node
`host-service` daemon per machine and a `pty-daemon` that owns the PTYs. Not a herdr client. The chat is behind the
experimental `acp-chat` flag. The options for Oriel are in [../ui/chat-view.md](../ui/chat-view.md).

## How chat works

- **ACP over stdio** for every agent the UI opens (`packages/host-service/src/chat-v3/acpCatalogue.ts`):

  | Agent | Process |
  |---|---|
  | Claude | `node claude-agent-acp` with `CLAUDE_CODE_EXECUTABLE=<user's claude>` (the Agent SDK under it) |
  | Codex | `node codex-acp` with `CODEX_PATH=<codex>` (drives `codex app-server`) |
  | pi | `node pi-acp` with `PI_ACP_PI_COMMAND=pi` |
  | OpenCode | `opencode acp` |
  | Gemini | `gemini --acp` (registered, but no preset opens it) |

  The translators are npm packages bundled with the app and pointed at the user's own binary, so the user's login
  and config apply. Older native Claude SDK and app-server adapters remain, marked legacy.
- `initialize` advertises **no fs and no terminal capabilities**, so the agent uses its own tools headless, and
  advertises `elicitation.form`, without which claude-agent-acp drops AskUserQuestion (`harness/acp/acpAdapter.ts`).
- No PTY parsing, no transcript reading for chat. Transcripts are read only for "hand off to another agent".
- Every event is journaled in SQLite (`chat.db`) with `(epoch, seq)` cursors; clients subscribe over a WebSocket with
  `since=` and replay. Text deltas are a separate channel that is dropped first under load.
- **Send:** tRPC `prompt`, deduped by command id, a FIFO queue, then `session/prompt`. Steering only where the agent
  advertises it.
- **Approvals:** `session/request_permission` becomes an approval row on its tool call; options not starting with
  "Allow" become a question form. Chats **start in bypass mode** by default. Interrupt is `session/cancel`.

## Terminal and chat

- Separate processes (a TUI in `pty-daemon`, a headless ACP child of `host-service`). **No live switch.** They share
  only the agent session id (`session/load` or `session/resume`; `claude --resume <id>` in a terminal).
- If the session continues in a terminal, the chat says "This chat stopped because the conversation continued in a
  terminal" and stops recovering (`AcpChatPane.tsx`). Detected after the fact; no lock found.
- Each chat gets a synthetic terminal id in the same binding store as terminal agents, so status, notifications and
  ports treat both the same.
- A "Warp-style" rich input box over the terminal reuses the chat composer and writes into the PTY as one block.

## Remote

The agent runs where `host-service` runs. Remote clients come through a Cloudflare Worker relay that the host dials
out to (JWT auth). No SSH transport for chat.

## Size

About 30k lines for desktop chat: the runtime 10.8k (ACP adapter 4.2k), the protocol and client 3k, the desktop UI
16k; 38k with the host mount (1.3k) and the shared composer (6.3k).

## For Oriel

- Copy: if a structured mode ever comes, ACP with the official translators pointed at the user's binary is the
  cheapest way to many agents; no fs or terminal capabilities; `elicitation.form`.
- Copy: a reply box over the terminal that pastes one block, without any chat.
- Avoid: npm translators would have to be installed on every machine, which Oriel does not do; bypass mode by
  default.
