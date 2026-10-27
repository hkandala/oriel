# Chat view: options for Oriel

How to show an agent pane as messages with a reply box, switch back to its terminal without ending the agent, and
do it on remote machines. Read from three apps that have both views ([orca.md](../clients/orca.md),
[paseo.md](../clients/paseo.md), [paradev.md](../clients/paradev.md)), the herdr clients
([../clients/README.md](../clients/README.md)), herdr's source, and spikes on this Mac (codex 0.163, Claude Code 2.1,
herdr 0.9.5). The design is [chat-view.mdx](../../../docs/content/docs/future-work/chat-view.mdx).

## Answer in one screen

1. **Keep the agent running in its pane and read its transcript.** Tail the transcript file the agent writes
   anyway, over the relay, and send with `agent.prompt`. Switching is a view change on the same process, so
   nothing ends, and the tail is one more line stream on the relay, so remote machines work the same. This is
   Orca's "terminal-backed chat" and what every herdr client with a chat does. It is already the design.
2. **No app shows one process both as a terminal and as a structured chat.** Orca, Paseo and Paradev run a
   structured chat as a second, headless process on a copy (Orca's fork) or a resume (Paseo, Paradev) of the
   conversation, never the TUI's process. That costs 30k to 170k lines of code.
3. **One exception, found here: Codex.** codex's app-server sends a loaded thread's events to every client that
   resumed it, and a turn started by one client shows live in the other (spiked). Since codex 0.157 the TUI attaches
   to a shared daemon by default, so a chat could join the same running Codex thread as its TUI, with live text.
   Missing: a reliable way from a pane to its thread, and a WebSocket-to-lines adapter for the relay. A later
   option, Codex only.
4. **First slice:** the chat|term switch, the transcript tail and parser for pi and Claude Code, Markdown messages,
   and the reply box with `agent.prompt`, locally and remotely; screen text for every other pane.

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
| 5a | Attach to Codex's daemon (`codex app-server proxy`, `thread/resume`) | no | needs a line adapter: the socket speaks WebSocket frames, the relay carries lines | Codex on the daemon | medium | no pane-to-thread map yet; app-server is "experimental" |
| 5b | Hooks that stream previews and approvals to the app (Orca, Paseo) | no | needs a way back from the machine | per agent | medium, plus installing hooks | Oriel installs nothing on machines |
| 5c | Screen scrape into fake turns (Orca's last resort) | no | yes | any | small | wrong turns; rejected already |

Not options: Claude Code's `--remote-control` goes through Anthropic's cloud; a second structured client cannot join
a running interactive `claude` or `pi`.

## Facts checked here

- **Codex fan-out.** A throwaway `codex app-server --listen unix://…` with two WebSocket clients: A starts a thread
  and a turn; B's `thread/resume` then answers with the thread's turns; B's `turn/start` streams `item/*`,
  `turn/*` and `thread/status/changed` to both. Before the first turn, `thread/resume` fails with "no rollout found
  for thread id" (the rollout is written lazily). Who gets an approval request with two clients was not checked.
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

Option 1, as designed, with these refinements now on the design page:
- Prefer a transcript path from `agent_session` whenever herdr gives one (pi today; Claude Code once herdr keeps
  its path, option 3, filed under Waiting on herdr). Fall back to the id search, then to screen text.
- A "Working" row from `agent_status` while the agent works, since the transcript lags.
- Codex on the daemon (the upstream default) falls back to screen text; Codex with `--no-daemon` gets its rollout
  through `lsof`.

**First slice** (one phase): the chat|term switch; the finder and tail for pi (path) and Claude Code (id); their
parsers; Markdown messages with tool calls collapsed; the reply box with `agent.prompt` and its refusals; screen text
for every other agent and terminal pane; local and remote (RemoteTests on CI's sshd). **Next:** the blocked panel
and key guard; Codex off the daemon (rollout through `lsof`); the pill card reusing the view. **Later, if asked:** 5a,
which would cover Codex on the daemon once a pane can be mapped to its thread. Never: options 2 and 4 while herdr
owns the agents.
