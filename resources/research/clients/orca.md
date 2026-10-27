# Orca (stablyai/orca): an agent IDE with two chat modes

Repo: https://github.com/stablyai/orca (v1.4.214, MIT). Electron 43, React 19, TypeScript, xterm.js, node-pty,
SQLite. Not a herdr client: it runs its own PTYs in a daemon. Read for its chat view, which is experimental and off
by default (`docs/site/content/docs/agents/native-chat.mdx`). The options for Oriel are in
[../ui/chat-view.md](../ui/chat-view.md).

## Two chat modes

| | Terminal-backed chat | Structured chat |
|---|---|---|
| Process | the agent's TUI in its PTY, unchanged | a headless child in a machine protocol |
| Data | the transcript file, tailed; hook previews and a screen scrape as fallbacks | the protocol's events, written to Orca's SQLite journal |
| Send | keys into the PTY | protocol calls |
| Switch to terminal | in place, `Cmd+Shift+J`, same process | a **new** process on a **fork** of the conversation |
| Remote | over plain SSH for Claude and Codex | only where a whole Orca runtime runs (`orca serve`) |

## Terminal-backed chat (the cheap one)

- **Sources, by priority** (`src/shared/native-chat-types.ts`, `NATIVE_CHAT_SOURCE_PRIORITY`): transcript 3 > hook 2
  > scrape 1.
  - Transcript files: Claude `~/.claude/projects/**.jsonl`, Codex `~/.codex/sessions/**`, Grok, omp; OpenCode from its
    SQLite database (`src/main/native-chat/transcript-*.ts`, one line decoder per agent).
  - Hooks that Orca installs POST to a loopback server: the session id and `transcriptPath` (which picks the file),
    state, the tool and its input, approval prompts, and a live "streaming" preview until the transcript catches up
    (`src/main/agent-hooks/README.md`). The file comes from the hook, never from a guess by cwd.
  - Scrape: ANSI-stripped scrollback cut into turns at prompt markers, the last resort.
- **Send** (`src/renderer/src/components/native-chat/native-chat-runtime-send.ts`): clear the unsent input, paste the
  body (bracketed paste, escapes removed), then `\r` as a **separate write 500 ms later**, because a TUI treats a CR
  in the same write as pasted text. Images go as a pasted path. One queue per PTY.
- **Approvals:** the hook reports `{approval:{tool,summary}}`; the card types `1` (allow) or Esc (deny); a question is
  answered by stepping arrow keys. omp questions must be answered in the terminal. Interrupt is Esc.
- Agents: claude, codex, grok, omp, opencode, zcode. pi is structured only.
- Its own warning: a hidden view "cannot prove what arrived while hidden".

## Structured chat (the expensive one)

- Claude: the Agent SDK `query()` driving the user's `claude` (stream-json under it), `includePartialMessages`,
  `--replay-user-messages`, `resume`/`forkSession`; approvals through `canUseTool`
  (`src/main/claude/claude-stream-json-connection.ts`).
- Codex: `codex app-server` over stdio (`thread/start|resume`, `turn/start|steer|interrupt`, approval requests
  `item/commandExecution/requestApproval`, `item/fileChange/requestApproval`).
- pi: `pi --mode rpc` (`prompt`, `steer`, `abort`, `extension_ui_response`; `src/main/pi/rpc-*.ts`).
- Grok, OpenCode, omp, Antigravity: ACP, one JSON-RPC peer plus a small "dialect" per agent (`src/main/acp/`).
- Every event goes to a SQLite journal; the UI pages and catches up from it. Messages typed while busy go to a
  durable queue. Children close after 30 min idle and resume on the next send. They die with the app (PTYs do not).
- **Fork, not resume:** "Continue with Terminal Agent" runs `claude --resume <id> --fork-session`, `codex fork <id>`,
  `pi --fork <file>` or ACP `session/fork` (`src/shared/agent-resume-argv.ts`), so two processes never write one
  conversation. The other way, "Continue in Chat UI" opens a structured chat on a copy of the transcript and leaves
  the TUI running; only continuing from Agent Session History asks you to exit the TUI first.

## Size

About 150–170k lines of chat code without tests: `src/main/native-chat/` 57k, the renderer's `native-chat/` 51k,
ACP 11.5k, Codex structured 11k, Claude structured 7.5k, pi RPC 3.8k. Tests are 1.5–2 times that.

## For Oriel

- Copy: the terminal-backed mode is the cheap 80 %: same process, toggle in place, transcript found from the
  agent's own report, sends as a paste then a late Enter.
- Copy: fork, not resume, if a structured mode ever comes.
- Avoid: the structured layer's size; children tied to the app's lifetime.
- Note: Orca answers the OSC 7501 probe, and Claude Code then stops drawing its title glyph, which broke Orca's
  title-based status.
