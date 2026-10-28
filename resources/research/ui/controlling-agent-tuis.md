# Controlling agent TUIs: libraries, CLIs and agent surfaces

Survey of tools that read and drive an agent's TUI from outside, for Oriel's chat view (brief: `brief2.md`). Source
read from shallow clones under `round2/src/`, issues read on GitHub, docs read on the vendors' sites, and one spike
on Claude Code 2.1.310 in a throwaway herdr session. Per-project notes: [clients/](../clients/).

## Answer in one screen

1. **Screen scraping is the common way, and it is brittle.** AgentAPI, the biggest one, turned screen diffs into
   messages and "screen still for 2 s" into idle. Claude releases broke it again and again; Coder deprecated it.
2. **Every tool sends the same way:** paste the text, press Enter as a separate write, check the screen moved, press
   Enter again if not. herdr's `agent.prompt` already does the first two.
3. **The vendors now publish state themselves.** Claude Code writes `~/.claude/sessions/<pid>.json` for every
   interactive TUI with `status` = `busy | idle | waiting` and `waitingFor`. In the spike it reported
   `waiting / dialog open` for the `/config` picker while herdr said `idle`. That closes the "pickers look idle"
   trap for Claude, with no launch flags.
4. **Claude Code also takes messages over a Unix socket** (its cross-session inbox). It works on a running TUI and
   starts a turn, but the model reads it as "from another session, not your user". Fine for automation, wrong for
   the chat composer.
5. **Codex:** `codex queue --thread <id> --message` adds to a thread's queue through an app-server
   (`thread/queue/add`). It reaches a TUI only when that TUI runs on the shared daemon or `--remote`.
6. **No bridge attaches to a running TUI.** ACP adapters, the Agent SDK, happy, AgentAPI all start their own agent.

## Comparison

"Attach" = works on a TUI that is already running in someone else's PTY (herdr's).

| Project | Reads state | Sends input | Idle / working / waiting | Approvals | Agents | Attach |
|---|---|---|---|---|---|---|
| [AgentAPI](../clients/agentapi.md) (deprecated) | own PTY + vt10x; message = screen diff minus echo and input box | bracketed paste, Enter, re-Enter every 3 s until the screen moves | stable = 2 s of equal 25 ms snapshots | `raw` keys only | 11 TUIs + ACP | no |
| [ht](../clients/tmux-and-pty-controllers.md) | own PTY + avt; JSON snapshots, raw output events | `sendKeys` names, raw `input` | none | keys | any | no |
| [claude-squad](../clients/tmux-and-pty-controllers.md) | `tmux capture-pane`, hash per tick | text, 100 ms, `\r` | hash changed; prompt strings for Claude, Aider, Gemini | AutoYes presses Enter | claude, aider, gemini, codex | tmux panes it made |
| [tmux-cli](../clients/tmux-and-pty-controllers.md) | `capture-pane` | text, 1.5 s, Enter, verify, retry ×3 | no change for 2 s | keys | any | any tmux pane |
| [tmux MCP servers](../clients/tmux-and-pty-controllers.md) | `capture-pane` | `send-keys`, bracketed `paste-text` | shell commands only (markers, `wait-for`) | keys | any | any tmux pane |
| [iterm-mcp](../clients/tmux-and-pty-controllers.md) | AppleScript buffer | AppleScript `write text` | `is processing`, tty foreground process CPU | keys | any | the front iTerm tab |
| [ccmanager](../clients/tmux-and-pty-controllers.md) | own PTY, last 30 lines | keys | per-agent regex; Claude idle debounced 1.5 s | keys | 10 agents | no |
| [agent-deck](../clients/agent-deck.md) | hooks, statusline, pane title, screen; Claude session record | tmux framed paste + verify + Enter gate; Claude inbox socket (opt-in) | hooks, screen fallback | keys | ~10 | its tmux panes |
| [happy-cli](../clients/acp-bridges.md) | tails the Claude transcript; hook gives the id | phone message **kills the TUI**, resumes with the SDK | SDK events | SDK `canUseTool` | claude, codex | no |
| [ACP bridges](../clients/acp-bridges.md) | protocol events | protocol | protocol | protocol requests | claude, codex, pi | no |
| [Claude session record](../clients/claude-code-own-surfaces.md) | `~/.claude/sessions/<pid>.json`, `claude agents --json` | — | `busy`, `idle`, `waiting` + `permission prompt`, `input needed`, `sandbox request`, `worker request`, `dialog open` | tells you one waits | Claude ≥ 2.1.224 | **yes** |
| [Claude inbox socket](../clients/claude-code-own-surfaces.md) | — | one JSON line to `messagingSocketPath` | starts a turn when idle, else between tool calls | cannot answer prompts | Claude | **yes** |
| Claude agent view | `claude agents --json`, `claude logs` | `claude --resume <id> "<prompt>"` | as above | — | background sessions only | no (pane `claude`) |
| Claude channels | — | MCP server named in `--channels` | — | can relay permission prompts | claude.ai/Console auth only | launch flag |
| Claude Remote Control | claude.ai only | claude.ai only | — | — | not with a gateway | `/rc` |
| Codex `--remote` / daemon | app-server events | `turn/start`, `turn/steer` | protocol | `requestApproval` | Codex | launch flag |
| `codex queue` | — | `thread/queue/add` on the daemon or `--remote` | — | — | Codex ≥ 0.149 | only TUIs on an app-server |
| opencode `/tui/*` | — | `append-prompt` + `submit-prompt` fill the TUI's own box | SSE (server) | `/permission/:id/reply` | opencode 1.x with `--port`, 2.x | yes (see `agents/opencode.md`) |
| herdr | server-side screen detection | `agent.prompt` (paste + Enter), `send_keys` | `working`, `idle`, `blocked`; pickers read `idle` | keys | many (claude, codex, pi, opencode, …) | yes |

## How state is read, from weakest to strongest

| Source | Used by | Fails when |
|---|---|---|
| Screen stillness | AgentAPI, tmux-cli, claude-squad | spinners stop, pickers animate (AgentAPI #171), tools run silent |
| Screen strings per agent | ccmanager, agent-deck, claude-squad, herdr | each redesign (AgentAPI #209 `───` → `╌╌╌`; #207 Claude 2.1.83 stopped redrawing into vt10x) |
| Screen diff as messages | AgentAPI | always somewhat: echo removal is fuzzy, headers leak (#174), ids merge (#205) |
| Transcript tail | Orca, happy, Oriel's plan | fine for messages; says nothing about pickers |
| Hooks | Orca, agent-deck, happy | need launch flags; company hooks may answer first |
| Agent-published state | Claude session record; Codex/opencode servers | Claude only without flags; the others need a launch flag |

## How input is sent

- **Keys (everyone).** Paste, pause, Enter as its own write, verify, retry a few times. Bracketed paste starts with
  ESC, which **cancels Claude's numbered pickers** (AgentAPI comment): never paste into a picker.
- **Known key failures** (agent-deck issue trail): Enter stranded in the composer; only the tail of a long paste
  arrives; a send clobbers an open question and the user's draft; an autosuggestion submitted by a retry Enter;
  "not delivered" reported for a queued message; Codex queued follow-ups mistaken for submits.
- **Protocols (only with launch flags):** Codex app-server, opencode server, pi RPC or bridge.
- **Claude inbox socket (no flags):** a receipt-free but reliable write; framed as a peer message; held behind an
  approval dialog in bypass mode unless `crossSessionInbound: "accept"`.

## Spike: Claude Code's own record and inbox

TUI in herdr pane, `status` polled every 100 ms, details in
[clients/claude-code-own-surfaces.md](../clients/claude-code-own-surfaces.md):

| Moment | Record | herdr |
|---|---|---|
| prompt sent | `busy` at once | working |
| permission prompt (auto-allowed by a company hook) | `waiting/permission prompt` 0.1 s | — |
| turn done | `idle` | idle |
| `/config` picker | `waiting/dialog open` | **idle** |
| `AskUserQuestion` | `waiting/input needed` | blocked |
| socket message "reply pong" | `busy` → `idle`, answered | working → idle |

The socket message landed in the transcript as `type:"user"`, `isMeta:true`, `origin.kind:"peer"`, so a transcript
reader can tell it from typed prompts (`origin.kind:"human"`).

## What Oriel takes

1. **Claude panes: read `~/.claude/sessions/<pid>.json`** (or `claude agents --json`) beside the transcript. Show
   the chat only while `status` is `idle` or `busy`; `waiting` with a `waitingFor` Oriel cannot answer → show the
   TUI. Over SSH this is one small file; Perl can poll it. Vet the record: `pid` in the pane's process tree,
   `procStart` equal, one match (agent-deck's checks).
2. **Send with `agent.prompt` only when the agent says idle or busy** (Claude: the record; others: herdr plus the
   side channel), never during `waiting`. After sending, confirm by the transcript (a new user entry), not the
   screen. No retry Enter unless the composer holds exactly Oriel's text.
3. **Per-agent "waiting" sources, all agent-published:** Claude record; Codex `--remote` requests; opencode SSE;
   pi bridge. If none is there, fall back to herdr's `blocked` and show the TUI.
4. **Claude inbox socket for Oriel's own automation** (for example a note after a file drop), never for what the
   user typed.

## What Oriel avoids

- Messages or idle from screen diffs (AgentAPI's design, now abandoned).
- Screen strings per agent version inside Oriel; leave screen detection to herdr.
- Bridges that own the process (ACP, SDK, happy): they need a second process and cannot show the user's TUI.
- Killing or resuming the TUI to switch views (happy).
- Channels and Remote Control: account and gateway limits; neither works under the company launcher.
- `codex queue` against a plain TUI: it targets an app-server, and with no daemon it would run through a separate
  embedded server (not tested).

## Notes

- Company launcher side effect: `/usr/local/bin/codex --version` (and `--help`) installed the `llm-rules` plugin
  into `~/.codex` (plugin folder, a `[plugins."llm-rules@claude-templates"]` block in `config.toml`, the
  marketplace list, `meta/preset/state.json`). I removed all four at once. Any codex launch may add it again.
- Not tested: the inbox socket in bypass mode, while busy, or with images; `codex queue`; channels.
