# Chat view: options for Oriel

How to show an agent pane as messages with a reply box, switch back to its terminal without ending the agent, and
do it on remote machines. Read from three apps that have both views ([orca.md](../clients/orca.md),
[paseo.md](../clients/paseo.md), [paradev.md](../clients/paradev.md)), the herdr clients
([../clients/README.md](../clients/README.md)), herdr's source, and spikes on this Mac (codex 0.163, Claude Code 2.1,
herdr 0.9.5), then one spike per agent for Claude Code, Codex, pi and opencode ([../agents/](../agents/claude-code.md)). The design is [chat-view.mdx](../../../docs/content/docs/future-work/chat-view.mdx).

## Answer in one screen

1. **Keep the agent running in its pane and read what it writes anyway** (Base). Tail the transcript over the relay
   (opencode: poll its SQLite), send with `agent.prompt`, answer prompts with keys. Switching is a view change on the
   same process, so nothing ends, and remote machines work the same. This is Orca's "terminal-backed chat".
2. **Each of the four agents also has a side channel beside its TUI** that adds per-token text and real
   Approve/Deny buttons without ending the TUI. Claude Code: hooks and a statusline from `--settings`. Codex: the TUI
   started as `codex --remote` against an app-server, joined as a second client. pi: a one-file extension with a
   unix socket. opencode: its HTTP server (1.x with `--port`, 2.x always) with SSE. Only pi's attaches to a running
   TUI (`/reload`); the others must be chosen when the agent starts.
3. **No other app shows one process both as a terminal and as a structured chat.** Orca, Paseo and Paradev run the
   structured chat as a second, headless process on a copy or resume of the conversation. That costs 30k to 170k
   lines of code.
4. **The trap:** pickers and pi's extension dialogs leave herdr at `idle`, so `agent.prompt` can type into them
   (proven on pi, Claude Code and opencode).
5. **First slice:** Base for all four agents, the transcript-tree look, the Needs-you drawer with each agent's answer
   keys, model and mode read back with a one-key mode toggle. Side channels next: pi, then opencode, then Claude Code
   and Codex through a launch path.

## Per agent

The full research, the capability matrix (agent × interaction), the adapter interface, the approval and model
designs and five Liquid Glass mock-ups are in [chat-view.html](chat-view.html) (open it in a browser). The evidence
per agent, from throwaway runs: [Claude Code](../agents/claude-code.md), [Codex](../agents/codex.md),
[pi](../agents/pi.md) (with the [bridge spike](../agents/pi-bridge.ts)), [opencode](../agents/opencode.md).

| | Base: history | Side channel | Joins a running TUI | In-chat approvals |
|---|---|---|---|---|
| Claude Code 2.1 | `agent_session` id → `~/.claude/projects/<slug>/<id>.jsonl` | `--settings` hooks + statusline, through files | no | PermissionRequest hook waits on a decision file; company `allow` hooks beat a deny |
| Codex 0.163 | the rollout its process holds open (`lsof`, `source=="cli"`, newest) | `codex --remote` to an app-server; WebSocket | no | `requestApproval` goes to every client; first answer wins |
| pi 1.4 | `agent_session` path; a tree | bridge extension, unix socket | yes, `/reload` | the bridge races extension dialogs; pi has no built-in prompts |
| opencode 1.19 / 2.2-dev | SQLite rows, polled | HTTP + SSE (`curl -N` is lines) | 2.x yes, 1.x only with `--port` | `/permission/:id/reply`, `/question/:id/reply` |

## How the three apps do it

| | Orca | Paseo | Paradev |
|---|---|---|---|
| Chat data | transcript tail over the live TUI; or a structured child (Agent SDK, app-server, pi RPC, ACP) | structured child only (Agent SDK, app-server, pi RPC, `opencode serve`, ACP) | ACP child only (translators for Claude, Codex, pi) |
| Send | keys into the PTY; or protocol calls | protocol calls | protocol calls |
| Same process as the terminal | yes for the transcript chat; no for structured | no | no |
| Switch | in place (transcript chat); a fork (structured) | copy a resume command, or import | resume by id; the chat notices after the fact |
| Approvals | `1`/Esc keys from a hook report; or protocol requests | protocol requests | ACP `request_permission` |
| Remote | transcripts over SSH; structured only with an Orca runtime there | its daemon on the machine | its daemon on the machine, a Cloudflare relay |
| Chat code | 150–170k lines | about 58k adapters + 30k UI | about 30k (38k with the shared composer) |

## The options

| # | Option | Ends the agent to switch | Remote over the relay | Agents | Cost for Oriel | Risk |
|---|---|---|---|---|---|---|
| 1 | Tail the transcript, send with `agent.prompt`, answer with keys | no | yes: `tail -F` is a line stream | pi, Claude Code, Codex off the daemon (one parser each); screen text for the rest | small: a finder, three lenient parsers, the view | formats change; text arrives per message, not per token; approvals only as screen keys |
| 2 | Restart in a structured mode (`claude -p --input-format stream-json --output-format stream-json --resume`, `codex app-server`, `pi --mode rpc`) and back | yes, and only when idle; back must fork | runs as a relay run, so it dies when the link drops (herdr panes survive) | one adapter each | large: 1–12k lines per agent elsewhere (Paradev's native adapters 1–2k, Paseo's 7–12k) | two writers on one session; adapters drift with each release |
| 3 | herdr-side: herdr reports the transcript path (or serves the transcript) | no | yes | every agent herdr integrates | none for Oriel; an upstream change | waits on herdr |
| 4 | Oriel as an ACP client (`claude-agent-acp`, `codex-acp`, `pi-acp`, `gemini --acp`, `opencode acp`) | yes, like 2 | as 2 | many, one protocol | medium: one client, but npm translators on every machine | installs things on machines; same two-writer problem |
| 5a | Join Codex's app-server as a second client (`thread/resume`); the TUI must run as `codex --remote` to a server Oriel starts, one per pane | no | needs a line↔WebSocket shim | Codex started that way | medium | app-server is "experimental"; a server restart puts the TUI on a new thread |
| 5b | Hooks that report and decide (Claude Code `--settings` statusline and PermissionRequest hooks, through files) | no | yes: files tailed and written over the relay | Claude Code started that way | medium | launch only; other hooks can override a deny |
| 5d | pi bridge extension with a unix socket | no | yes, with the file on the machine | pi, also already running (`/reload`) | small (~200 lines) | a monkeypatch of `ctx.ui` |
| 5e | opencode's HTTP server and SSE | no | yes: `curl -N` is lines | opencode 2.x, or 1.x with `--port` | small | 2.x changes the API |
| 5c | Screen scrape into fake turns (Orca's last resort) | no | yes | any | small | wrong turns; rejected already |

Not options: Claude Code's `--remote-control` goes through Anthropic's cloud; a second structured client cannot join
a running interactive `claude` or `pi`.

## Facts checked here

- **Codex fan-out.** A throwaway `codex app-server --listen unix://…` with two WebSocket clients: A starts a thread
  and a turn; B's `thread/resume` then answers with the thread's turns; B's `turn/start` streams `item/*`,
  `turn/*` and `thread/status/changed` to both. Before the first turn, `thread/resume` fails with "no rollout found
  for thread id" (the rollout is written lazily). With two clients both get an approval request; the first answer wins and every client gets `serverRequest/resolved` ([codex.md](../agents/codex.md)).
- **Codex's daemon.** Upstream codex turned `daemon_auto_start` on in 0.157: the TUI starts a shared app-server
  daemon and attaches. The daemon then runs the hooks (herdr's docs: it "can route hooks to the wrong pane, so use
  `--no-daemon`") and writes the rollouts. On this Mac's build the flag shows on, but a TUI in a throwaway pane
  started no daemon: it ran app-server in its own process, listened on no socket, and held its rollout open
  (`lsof -p <pid> -Fn`). That is the case the design's `lsof` step covers; a Codex on the daemon gets screen text.
- **`codex app-server proxy`** pipes raw bytes to the daemon's socket; JSON lines get no answer. The socket speaks
  WebSocket.
- **herdr already has Claude's transcript path and drops it.** Its Claude hook sends `transcript_path` as
  `agent_session_path`, but `session_ref_from_report` (`src/agent_resume.rs`) keeps a path only for pi and omp.
  Keeping it would remove the `~/.claude/projects/*/<id>.jsonl` search and the `CLAUDE_CONFIG_DIR` limit
  (option 3). Codex gains nothing from a path: off the daemon `lsof` gives it, on the daemon herdr's report may name
  the wrong pane.
- `agent.prompt` already pastes with bracketed paste and presses Enter after a delay: Orca's PTY send recipe (paste,
  then `\r` 500 ms later as a separate write) for free.

## Lessons not in the design

- A structured chat beside a TUI needs **fork, not resume**, or two processes write one conversation (Paseo and
  Paradev only notice after the fact).
- Structured children live and die with whoever spawned them; herdr panes outlive the app and the link. Moving the
  agent out of herdr loses that.

## Recommendation

Option 1 as the base for all four agents, plus a side channel per agent (option 5, widened):
- **Base:** pi by its path, Claude Code by its id, Codex by `lsof` (filtered: one process holds every rollout it
  opened), opencode by polling its SQLite. Send with `agent.prompt` behind a picker check. Blocked: the Needs-you
  drawer with a fixed key map per agent.
- **Side channels, in this order:** the pi bridge (attaches to a running TUI; can ship in pi-hkandala); opencode's
  server when the pane has one; Claude Code hooks and Codex `--remote` once Oriel starts agents itself.
- **Never:** options 2 and 4 while herdr owns the agents; `pi --mode rpc` on the TUI's file (it splits the tree).

The first slice and the order are on the design page.
