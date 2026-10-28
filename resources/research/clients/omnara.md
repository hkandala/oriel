# Omnara (omnara-ai/omnara): a PTY wrapper that scraped Claude's screen, then left the business

Repo: https://github.com/omnara-ai/omnara (Apache-2.0, active). **The current repo is a different product**: a Go
"managed agent platform" with its own harness (`internal/harness`, `cmd/daemon`), no Claude Code wrapper. The part
that matters here is the old Python CLI (PyPI `omnara`, last real release 1.7.0; 1.7.x after it only prints a
deprecation notice). Sources below are from the 1.7.0 sdist, unpacked under `src/omnara-py/omnara-1.7.0/`.
You ran `omnara` instead of `claude`; it ran Claude in its own PTY, so the terminal kept working, and mirrored the
session to a web and mobile dashboard.

## How it worked (1.7.0)

| Concern | How |
|---|---|
| Process | `pty.fork()` + `execvp claude --session-id <instance id>`; `select()` loop copies keys and output between the real terminal and the PTY (`integrations/cli_wrappers/claude_code/claude_wrapper_v3.py:868-934`) |
| Chat data | the transcript `~/.claude/projects/<dir>/<instance id>.jsonl`, read by a thread (`:429-520`); the file name is known because Omnara picked the id |
| Send | write the text into the PTY, sleep 250 ms, write `\r` (`:1268-1273`) |
| Working / idle | screen scrape: "idle" means no `esc to interrupt` or `ctrl+b to run in background` seen for `idle_delay` seconds (`:631-636`, `:1055-1075`) |
| Approvals | after a tool_use line and idle, wait 0.5 s, look for `Do you want` + `(esc` or `Would you like to proceed` in the ANSI-stripped screen, parse numbered options and send them as a question (`:940-1005`, parser at `:708`) |
| Answer | the web reply is mapped back to the option number and typed; an unknown reply picks the **last** option (`:1235-1257`) |
| `/clear` | detect `/clear`/`/reset` sent from the web, then find the new JSONL whose first lines hold `<command-name>/clear</command-name>` (`session_reset_handler.py:22-60`) |
| Remote view | `omnara/session_sharing.py:239` streams the raw PTY through a WebSocket relay, so the dashboard also had a terminal |

The web side long-polls for replies (`request_user_input`, 24 h timeout, 3 s poll; `claude_wrapper_v3.py:645-700`).
Codex used a packaged fork of the Codex binary (`omnara/agents/codex.py`), Amp a similar PTY wrapper.

## What went wrong (from the code)

- Every approval depends on English UI strings that Claude changes. The fallback after 1 s is a generic "Waiting for
  your input..." with no options (`:1006-1030`).
- A fixed 250 ms gap between text and Enter; long pastes or a busy TUI break it.
- Defaulting an unmatched answer to the last option means a typo can answer "No" (or worse, in other dialogs).
- The PTY loop handles its own resize, raw mode, `EAGAIN` buffering and Ctrl-Z; about 1,600 lines for Claude alone.

## Size

`claude_wrapper_v3.py` 1,633 lines, `format_utils.py` 403, reset handler 114. The whole 1.7.0 package is about 13k
lines with server and SDK.

## For Oriel

- Copy: choose the session id up front (`--session-id <uuid>`) so the transcript path is known before the first
  line; Oriel launches agents, so it can do this too.
- Copy: Enter as a separate write after the text.
- Avoid: approvals parsed from the screen. When the chat cannot be sure, show the TUI.
- Note: the team dropped wrapping Claude Code altogether for its own harness; the wrapper did not last.
