# Nimbalyst (nimbalyst/nimbalyst): a structured agent workspace with an opt-in real-TUI Claude mode

Repo: https://github.com/nimbalyst/nimbalyst (desktop v0.82.4, MIT). Electron 43, React, Lexical, TypeScript,
node-pty, ghostty-web for terminals, PGLite/SQLite, `@anthropic-ai/claude-agent-sdk`, `@openai/codex-sdk`. iOS and
Android companions. Very active (long changelog, many open issues). Successor of Crystal
([crystal.md](crystal.md)). Not a herdr client. Its `claude-code-cli` mode is the closest thing to Oriel's plan
found so far: the genuine `claude` TUI keeps running and a chat view sits on top.

## Three ways to get a chat

| | Structured (default) | `claude-code-cli` (opt-in) | Follow external sessions (opt-in) |
|---|---|---|---|
| Process | headless child per session | the real interactive `claude` in a PTY | a CLI the user started elsewhere |
| Data | SDK / app-server / ACP events | a loopback API proxy; turn state from Claude's PID file | the agent's JSONL transcript, tailed |
| Send | protocol calls | bracketed paste into the PTY, then a late `\r` | none: sending claims the session and runs it locally |
| Terminal view | no (only shell terminals) | yes: a drawer under the chat, same process | no |
| Agents | Claude (Agent SDK), Codex (app-server; ACP, SDK), OpenCode (server), Copilot/Grok (ACP), Cursor (`-p` stream-json) | Claude only | Claude, Codex |

## `claude-code-cli`: the real TUI with a chat on top

- **Launch** (`packages/electron/src/main/services/ai/ClaudeCliSessionLauncher.ts`): Nimbalyst picks the session id
  first and passes `--session-id <uuid>`; if `<config>/projects/<cwd with non-alnum→->/<id>.jsonl` already exists it
  passes `--resume <id>` instead, because the CLI rejects a used id (`:186-205`, `claudeCliJsonlPath.ts:28-48`). It
  also adds `--mcp-config`, `--settings` (the hook), `--disallowedTools AskUserQuestion`, `--append-system-prompt`
  (`claudeCliSpawnConfig.ts:203,290,304,354-358`). Never `-p`.
- **Chat source: an API proxy, not the transcript.** `ANTHROPIC_BASE_URL` points at a loopback proxy that tees the
  SSE stream, rebuilds each assistant message, dedups by `msg_…` id, and takes `tool_result`s from the next request
  body (`claudeCliObservation/claudeCliProxyObservation.ts`, `claudeCliObservationSingleton.ts:1-26`). The user row
  is logged at send time, because the request's last user message is full of injected context (`:22-26`). The jsonl
  is only used for the resume check.
- **Turn state: Claude's PID file.** `~/.claude/sessions/<pid>.json` (what `claude ps` reads) has `status`
  `busy|shell|idle|waiting` and `waitingFor`; polled every 500 ms, unknown shapes keep the last state
  (`claudeCliPidState.ts:1-16,124,208-209`; wired at `TerminalSessionManager.ts:1046-1054`). `shell` (a turn ended
  with a background bash still alive) was once unknown and pinned sessions on "Thinking". The company launcher's
  Claude writes it too (keys include `sessionId`, `status`, `statusUpdatedAt`).
- **Send** (`claudeCliSubmit.ts`): payload wrapped in bracketed paste, so a large write is one paste, not many
  `[Pasted text #N]` (`:33-40`). Enter goes as a separate write after a gap of 25 ms + 1 ms per 100 **bytes**
  (max 1 s; CJK broke a char-based gap, #1387) (`:42-63`). `/` and `#` must be real keystrokes to open their modes; a
  bare `/cmd` gets a trailing space so the autocomplete menu does not run the highlighted row instead (`:105-140`).
  Prompts sent while busy queue and flush on the PID watcher's running→idle edge (`claudeCliQueueDispatch.ts:1-17`).
- **Approvals:** `--permission-prompt-tool` is "silently ignored by the interactive CLI", so a `PreToolUse` hook
  (matcher `Bash|Edit|Write|MultiEdit|NotebookEdit|WebFetch`, timeout 600 s) POSTs to Nimbalyst and returns
  `allow`/`deny`; on any error it returns `ask` and the native TUI prompt appears (`resources/claudeCliPermissionHook.cjs:1-24`,
  `claudeCliPermissionHookConfig.ts:19-21`). Questions: the built-in `AskUserQuestion` is disallowed and the model is
  told to use Nimbalyst's MCP question tool.
- **Fallback to the TUI:** the drawer reveals itself for slash commands with native pickers (`/model`, `/config`,
  `/login`, `/permissions`, `/mcp`, …) and when PTY output shows Ink's `❯ ` caret; the output check is
  "version-fragile" and must never steal focus (`claudeCliInteractiveCommands.ts:22-34,55-82`). Toggle Ctrl+Shift+`.
- **Stop:** Ctrl-C, Ctrl-C, then SIGINT, rechecking the PID file between steps (`claudeCliInterrupt.ts:1-24,80`).
  **Lifetime:** the PTY lives in the main process; switching sessions reattaches. The CLI spawns only when its strip
  is on screen in the key window, after a restart stampede hit rate limits (`ClaudeCliTerminalStrip.tsx:23-56`).
  App quit ends it; the next launch resumes. Model switch types `/model <x>` into the TUI (`claudeCliModelSwitch.ts`).

## Following external transcripts

`externalSessions/` (4.4k lines) watches `~/.claude/projects` and Codex rollouts with one directory watcher per
root plus a bounded periodic scan as the recovery path (`ExternalSessionWatcher.ts:40-50`). Reads go by byte cursor at
newline boundaries; a SHA-256 of the first and last 4 KiB before the cursor detects a replaced file
(`jsonlReader.ts:30-48`). Failing files back off 1→30 min (#1812, `ExternalSessionWatcher.ts:31-35`). Sending from Nimbalyst first claims
"local ownership" and stops ingesting (`MessageStreamingHandler.ts:450`, `claudeCliLauncherSingleton.ts:263`).

## Remote

No SSH. Phones mirror desktop sessions through an encrypted sync relay (`wss://sync.nimbalyst.com`,
`SyncManager.ts:276`). A headless `nimbalyst-node` can run on a Cloudflare sandbox; the desktop shows its transcript
and can send and stop, but "interactive tool answers are not supported" (`packages/cloudflare-sandbox/README.md`).

## Known problems

#1219/#1220: a CLI session that crashes the renderer relaunches on reload, in a loop. #903: deleting a CLI session
leaves the `claude` tree running. Changelog: stuck "Processing…" after turns, a hang on the model-switch confirm.

## Size

`claude-code-cli` about 6.7k lines. The structured stack about 120k (runtime `ai/server` 55k, Electron `services/ai`
26k, transcript UI 28k, `UnifiedAI` 11k). Tests not counted.

## For Oriel

- Copy: the PID file `~/.claude/sessions/<pid>.json` as Claude's busy/idle/waiting signal; cheap, no flags, works
  over the relay with `cat` (find it by pid, or scan the folder for the `sessionId`).
- Copy: the send recipe: bracketed paste, Enter later with a byte-scaled gap, `/` as its own keystroke, a space after a
  bare slash command; queue while busy, flush on idle.
- Copy: a `PreToolUse` hook via `--settings` for approvals, failing to `ask` so the TUI prompt is the fallback.
- Copy: `--session-id <uuid>` at launch, so the transcript path is known before the first byte.
- Copy: reveal the TUI on known picker commands, with a caret sniff only as a hint.
- Avoid: the API proxy. It fights the company launcher's own `ANTHROPIC_BASE_URL` and does not reach remote
  machines. Tail the jsonl instead.
- Avoid: typing `/model` to switch models (it writes the user's Claude settings). Avoid disallowing
  `AskUserQuestion` unless Oriel ships its own question tool; show the TUI for it instead.
