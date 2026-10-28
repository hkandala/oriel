# tmux, PTY and terminal controllers used on agent TUIs

Small tools that drive any TUI by keys and read it by screen. None know what an agent is beyond a few strings.
Read from shallow clones.

| Tool | Reads | Sends | Idle / done | Agent-aware bits |
|---|---|---|---|---|
| **ht** (andyk/ht, Rust, avt emulator) | `takeSnapshot` → `{cols, rows, text, seq}`; `output` events with raw bytes; WebSocket `/ws/events` | `sendKeys` with tmux-style names (`Enter`, `C-c`, `S-A-Up`), `input` raw bytes, `resize` | none; the caller polls snapshots | none |
| **claude-squad** (`session/tmux`) | `tmux capture-pane -p -e -J`, SHA-256 per tick | text by PTY write to `tmux attach`, sleep 100 ms, then `\r` | "updated" = hash changed | strings: "No, and tell Claude what to do differently" (Claude prompt), "(Y)es/(N)o/(D)on't ask again" (Aider), "Yes, allow once" (Gemini); auto-presses Enter on "Do you trust the files…" and "new MCP server"; AutoYes daemon |
| **tmux-cli** (pchalasani/claude-code-tools) | `capture-pane` | `send-keys` text, wait 1.5 s, capture, Enter, re-capture; **retry Enter up to 3×** if nothing changed | `wait_idle`: no change for 2 s | none |
| **tmux MCP servers**: nickgnd/tmux-mcp, lox/tmux-mcp-server, bnomei/tmux-mcp (tmux-mcp-rs) | `capture-pane` | `send-keys` (nickgnd also a char-by-char raw mode), bnomei `paste-text` as bracketed paste | shell commands only: start/done markers (nickgnd), `tmux wait-for` + private exit buffer (bnomei); TUIs: none | none; bnomei warns that markers in scrollback are forgeable and raw keys during a tracked command are undefined |
| **iterm-mcp** (ferrislucas) | iTerm2 buffer by AppleScript | `write text` by AppleScript | iTerm's `is processing`, then the tty's foreground process and its CPU (`ps -t`) | none; needs Automation permission |
| **ccmanager** (`services/stateDetector`) | its own PTY's emulator, last 30 lines | keys | per-agent regexes: Claude spinner `^[✱✳…·] \S+ing…`, "esc to interrupt"; Codex "esc…interrupt", "allow command?", "[y/n]" | Claude idle is **debounced 1.5 s** because Claude "sometimes appears idle while busy" |

## Common tricks

- Text first, Enter as a separate write after a pause (100 ms to 1.5 s). Same as Orca (500 ms) and AgentAPI.
- Check that the screen moved after Enter; press again if not, a few times at most.
- Idle = the screen held still N seconds. Wrong for spinners that stop, pickers that animate, and long tool runs
  with no output.
- Prompt strings per agent version. They break on each redesign (AgentAPI #209: `───` became `╌╌╌`).

## For Oriel

herdr already does all of this better: it owns the PTY, reads the screen server-side, reports
`working|idle|blocked`, and its `agent.prompt` pastes and submits. Nothing here adds to herdr except the
"verify then retry Enter" rule, and ccmanager's note that Claude's screen lies about idle for up to 1.5 s.
