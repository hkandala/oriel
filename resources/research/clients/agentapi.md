# AgentAPI (coder/agentapi): an HTTP API made from a screen scraper

Repo: https://github.com/coder/agentapi (v0.12.2, MIT, Go, about 5k lines without the chat UI). **Deprecated and
unmaintained.** Coder's own Claude Code module (v5) dropped it and now only installs the CLI. Read for how it turns a
TUI screen into messages and why that broke. Clone: a shallow clone.

## Shape

`agentapi server -- claude` starts the agent itself in a PTY inside an in-memory terminal emulator, then serves HTTP
on port 3284:

| Endpoint | What it does |
|---|---|
| `POST /message {type:"user"}` | paste the text, press Enter, return when the agent started working |
| `POST /message {type:"raw"}` | write bytes as keys (for pickers, Esc); not kept in history |
| `GET /messages` | the conversation as `{id, role, message, time}` |
| `GET /status` | `stable` or `running` |
| `GET /events` | SSE: `message_update`, `status_change`, `agent_error`; `/internal/screen` streams the screen |
| `POST /upload` | files into a temp dir, so the prompt can name a path |

It cannot attach to a running TUI: it owns the process. `agentapi attach` only shows its screen.

## Reading the screen (`lib/screentracker`, `lib/msgfmt`)

- **Emulator:** `ActiveState/termtest/xpty` (vt10x) at 80×1000, `TERM=vt100`. The tall screen means nothing scrolls off.
- **"vsync":** `ReadScreen` waits until no byte arrived for 16 ms (at most 48 ms), so it never reads half a redraw.
- **Snapshot loop:** every 25 ms. A ring buffer holds 2 s of snapshots. **Stable = all snapshots equal.** That is
  the only idle signal. `running` is "the screen changed in the last 2 s".
- **Message = screen diff.** Before each user message it saves the screen. The agent's reply is every line of the
  new screen from the first line that did not exist in the old one (`screenDiff`, a set of old lines, not a real
  diff). opencode skips its top two header lines because the token counter changes.
- **Cleanup per agent** (`FormatAgentMessage`): remove the echoed user input (fuzzy: the first 6 runes of the input
  searched in the first 5 lines, then a 5×5 rune lookahead, because Codex reformats code fences); cut the input box at
  the bottom (Claude/Goose/Aider: a `>` or `❯` line between `───` rules; Codex: a `›` line; opencode: the `╹▀▀▀` bar;
  Amp: a `╭…╮` box; Gemini/Cursor: one more box line).
- **Ready for the first prompt** = the input box was found. Tool calls are found only for Coder's own
  `coder_report_task` MCP tool, by text, so they can be hidden.

## Sending (`writeStabilize`)

1. Wait until the screen is stable and the readiness check passed; one message at a time (queue of 1). A `user`
   message while `running` is refused.
2. Write the text as **bracketed paste** (`ESC[200~ … ESC[201~`).
3. Phase 1, echo: wait up to 2 s for the screen to change and then hold still 1 s. A timeout is fine (many TUIs do
   not draw a paste at once).
4. Phase 2, submit: send `\r`, and **send it again every 3 s** until the screen changes, for at most 15 s. Not more
   often, because Aider takes each extra `\r` as input.
5. The user message enters history only after the screen moved.

## Agents

claude, goose, aider, codex, gemini, copilot, amp, cursor, auggie, amazonq, opencode, custom. Codex, Gemini, Amp,
Cursor need `--type`. An experimental `--experimental-acp` mode drives an ACP agent instead (chunks become text,
tool calls become `[Tool: kind] title` lines).

## Failure modes (from its issues)

| Issue | What broke |
|---|---|
| #207 | Claude Code 2.1.83 stopped updating the captured screen at all (input still worked). Fix: pin Claude 2.1.78. |
| #209 | Claude 2.1.87's onboarding used `╌╌╌` instead of `───`; the box was never found, so every send hung while `/status` said `stable`. |
| #171 | `AskUserQuestion` keeps redrawing, so the screen is never stable; sends time out. |
| #205 | Old and new messages merged into one id (the diff baseline raced the send). |
| #174, #146 | opencode: header and old lines leak into replies; users asked for its SDK or ACP instead. |
| #223 | A stray `x` after every prompt: a workaround for a Claude 0.2.70 paste bug left in for a year. |
| (code) | Bracketed paste starts with ESC, which **cancels** Claude's numbered pickers; answers must go as `raw`. |

## For Oriel

- Copy: paste, then Enter as its own write, then **verify the screen moved and retry Enter** (3 s apart, capped).
- Copy: wait for "no output for 16 ms" before reading a screen.
- Avoid: messages from screen diffs, idle from "screen still for 2 s", input-box detection by box glyphs. Each
  agent release broke one of them, and the authors gave the project up.
