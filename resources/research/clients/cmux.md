# cmux (manaflow-ai/cmux): a Ghostty terminal whose chat view tails the running agent's transcript

Repo: https://github.com/manaflow-ai/cmux (commit 97e8a228, GPL-3.0-or-later; server parts BUSL-1.1). A native macOS
terminal built on libghostty (Swift, about 14k Swift files), plus an iOS app, a Bun/React web sidecar
(`agent-chat/`) and a Go remote daemon. Very active. It is the closest project to Oriel's plan: a **terminal-backed
chat** over the agent's TUI, same process, with hooks for state and the transcript for content. It also has a
separate structured chat (new processes over stream-json, app-server, pi RPC, ACP), like Orca.

## Three chat surfaces

| | Terminal chat view (web) | iOS chat | Structured chat (web) |
|---|---|---|---|
| Process | the TUI in the cmux terminal, unchanged | the same TUI on the Mac | a new headless child per session |
| Data | the agent's JSONL, polled every 500 ms | the same JSONL, parsed in Swift (`CmuxAgentChat`) | `claude -p` stream-json, `codex app-server`, `pi --mode rpc`, ACP |
| Send | `cmux rpc mobile.chat.send` (paste + submit key) | the same RPC | protocol calls |
| Agents | Claude, Codex | Claude, Codex (pi missing, #14479) | claude, codex, pi, opencode, gemini, goose, cursor |

The terminal stays the source of truth: "renders the JSONL transcript ... without starting a second agent process"
(`agent-chat/adapters/transcript.ts:1-5`). The view is opened with "Open terminal as chat" at
`/terminal/<surface-id>` (`agent-chat/server.ts:2187`).

## Finding the transcript

- Launch: cmux puts wrapper scripts first on PATH in its terminals: `Resources/bin/cmux-claude-wrapper` (2,459 lines
  of bash) adds `--session-id` and `--settings` with hooks; `cmux-codex-wrapper` adds `-c hooks.X=...` and
  `--enable hooks` per run and "never rewrites the user's Codex settings" (lines 1-16); `cmux-pi-wrapper` adds a pi
  extension. Outside cmux, or on any failure, the wrapper just execs the real binary. A re-exec guard handles other
  shims such as company launchers (lines 41-283).
- Hooks write `~/.cmuxterm/{claude,codex}-hook-sessions.json`: session id, surface id, cwd, `transcriptPath`,
  `runtimeStatus` (running, idle, needsInput, error), `lastBody` (`agent-chat/transcript-sources.ts:19-30`).
- Resolution: the hook's `transcriptPath` first; else Claude `projects/<cwd slug>/<id>.jsonl`, Codex a bounded walk
  of `sessions/YYYY/MM/DD` for `rollout-*-<id>.jsonl` (`transcript-sources.ts:100-140`). An active binding per
  surface beats older sessions (`:164-183`); misses are cached 30 s (`:187`).

## Tailing (`agent-chat/adapters/transcript.ts:458-578`)

- Poll every 500 ms by byte offset; the first load reads only the last 8 MB and skips the partial first line. Keep
  a partial last line until its newline; a stream `TextDecoder` keeps split UTF-8 intact.
- Track `dev`+`ino` of the **opened** handle, not the path (an atomic rename can swap the file between stat and
  open). A new inode or a smaller size resets parser and history. Late reads after a restart are dropped.
- "Running" is a guess: the last event is not a turn end **and** the file was written in the last 30 s (`:582-592`).
- A view with no open page stops tailing after 5 min (`server.ts:676`).

## Input (`Sources/TerminalController+MobileChat.swift:275-349`, `Sources/TerminalController.swift:16682-16800`)

1. Clear the TUI's input line: `ctrl+a`, `ctrl+k`, `ctrl+u` (`Sources/TerminalController+AgentPromptDelivery.swift:8`).
2. Images: paste each as a file path, a space between.
3. Paste, wait **150 ms**, check the surface is still the same process, then the submit key (Gemini's 40 ms paste
   guard; React TUIs that read a stale buffer).
4. Claude with a multi-line prompt submits with `ctrl+enter`, else `return` (`Sources/TextBoxAgentDetection.swift:82-97`).
5. Once the text is accepted, a failed submit key is `submitted:false`, not an error, so a retry never pastes twice.
   One paste in flight per surface. The prompt shows at once; the transcript's copy replaces it.

Interrupt: `escape`, or `ctrl+c` when "hard" (`MobileChat.swift:353`).

## Approvals and "waits for input"

- Detection comes only from hooks: `runtimeStatus == "needsInput"` with the notification body
  (`transcript-sources.ts:213-218`). Comment: prompts "are not in the transcript until answered"
  (`server.ts:730-732`). Seeded before the first replay, because a waiting agent writes no file tick.
- Web view: shows the request and an "Answer in terminal" button that focuses the pane (`transcript.ts:36-44`).
- iOS: `mobile.chat.answer` types the option's digit; Codex's picker also needs `\r` (`MobileChat.swift:376-391`).
- Liveness: a live pid (`kill(pid,0)`), never the title or a screen scrape (`MobileChat.swift:470-492`).
- iOS scrapes a "streaming" preview from the screen above the spinner line, always replaced by the JSONL line
  (`cmux/Packages/Shared/CmuxAgentChat/Sources/CmuxAgentChat/Parsing/AgentChatProseScreenExtractor.swift`).

## Remote
`cmux ssh` runs a Go daemon on the host (`daemon/remote`, PTYs survive reconnect, a reverse forward relays `cmux`
commands back). The terminal chat view reads files on the Mac only; no code reads a remote transcript. A multi-machine
design (`cmux/docs/multi-machine-sessions.md`) is a draft.

## Known bugs and size

- Only Claude and Codex in the terminal chat (#15663, #14479). A chat on a recreated session keeps the old rows
  (#25968). Auto-resume once typed a literal `cmux restore claude <id>` into a new Claude (#9831).
- Size: the terminal chat view is about 1.2k lines (`transcript-sources.ts` 218, `adapters/transcript.ts` 704, part
  of `server.ts`, `cmux-rpc.ts` 38). The whole web sidecar is 7.8k + 6.7k UI; the shared Swift chat package 21k;
  the wrappers 3.5k lines of bash.

## For Oriel

- Copy: the whole terminal-chat design. Hooks give the session id and transcript path; the JSONL is tailed by offset
  with inode checks; prompts are pasted; questions stay in the terminal behind an "Answer in terminal" button.
- Copy: clear line, paste, short delay, re-check the process, then submit; never resend after the text was accepted.
- Copy: pid liveness, not titles, to decide that the chat still belongs to the pane.
- Avoid: a 2,459-line bash wrapper. Oriel types its own flags into the shell, so it needs no PATH shim.
- Avoid: guessing "running" from file age alone; herdr's agent state is better.
