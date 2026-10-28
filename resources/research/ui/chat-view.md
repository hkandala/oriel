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
5. **First slice:** Base for all four agents, then side channels ([Recommendation](#recommendation)).

## Per agent

The evidence per agent, from throwaway runs: [Claude Code](../agents/claude-code.md), [Codex](../agents/codex.md),
[pi](../agents/pi.md), [opencode](../agents/opencode.md). Versions: Claude Code 2.1.310, Codex 0.163, pi 1.4.0,
opencode 1.19.4 (npm) and 2.2.0-dev (source), herdr 0.9.5.

### Capability matrix

Base works on any running pane; "S:" needs the side channel. yes: works today. partly: works with caveats. no: not
possible.

| Interaction | Claude Code | Codex | pi | opencode |
|---|---|---|---|---|
| Find the history | yes: id → `projects/<slug>/<id>.jsonl`; stale after `/branch`. S: statusline `transcript_path` | partly: `lsof`, `source=="cli"`, newest; id stale after `/fork`. S: `thread.path` | yes: the path; the file appears at the first message | yes: id `ses_…`, `opencode.db` by `lsof` |
| Messages and tool calls | yes: tail; `tool_use` ↔ `tool_result` by id | yes: tail; `item_completed` | yes: tail; walk the tree | partly: poll SQLite parts. S: SSE `message.part.updated` |
| Live text (per token) | no: screen only; disk lags by seconds | S only: `item/agentMessage/delta` | S only: `message_update` | S only: `message.part.delta` |
| Thinking | partly: no text, "thought for Ns" | partly: encrypted, a row only | yes: full text | yes: reasoning parts |
| Subagents | yes: Agent tool, `subagents/agent-<id>.jsonl` | partly: `SubAgentActivity` items | no: none built in | yes: child sessions (`parent_id`) |
| Todos and plans | partly: TodoWrite; plan file and ExitPlanMode | yes: plan items | no | yes: `todo` table, `todo.updated` |
| Context, tokens, cost | yes: usage. S: statusline | partly: `token_count`; no cost | yes: `usage.cost`. S: `contextUsage` | yes: step-finish tokens and cost |
| Read the model | yes: `message.model` | yes: `turn_context` | yes: `model_change` | yes: `modelID` |
| Read the mode | partly: screen footer (`permissionMode` lags to turn end) | yes: `turn_context` | yes: thinking level (no modes) | yes: the message's agent (build, plan) |
| Send so the TUI shows it | yes: `agent.prompt` | yes. S: `turn/start` | yes. S: `sendUserMessage` | yes. S: `prompt_async` |
| Send while working | queued to the next tool boundary | steers the turn | Return steers; follow-up needs alt+Return or S | queued (2.x: steer or queue) |
| Images | yes: a pasted path becomes `[Image #1]` | partly: a path alone attaches; in text it stays text | partly: the path stays text. S: image block | partly: S: file part |
| `@file` | yes | partly: literal text | partly: literal text | partly: literal text. S: file part |
| Tool approval in chat | partly: S: PermissionRequest hook and a decision file | partly: S: `requestApproval` (accept, acceptForSession, decline) | partly: none built in. S: the bridge races extension dialogs | partly: S: `/permission/:id/reply` |
| Questions to the user | partly: S: the hook returns answers | partly: S: `requestUserInput` | partly: S: forwarded select, confirm, input | partly: S: `/question/:id/reply` |
| Plan approval | partly: S: PreToolUse on ExitPlanMode | partly: "Implement this plan?" is a picker (idle) | no: no plan mode | no: plan is an agent, no approval |
| Slash commands | direct ones as text; ~15 open pickers | known ones as text, no arguments; ~30 open pickers | direct ones as text; S runs only extension commands | direct ones as text; pickers need the TUI |
| New, fork, resume | `/clear`, `/branch` as text; `/resume` picker | `/new` as text; `/resume`, `/fork` pickers | `/new` as text. S: fork, tree, resume without pickers | `/new`, `/fork` as text; sessions picker |
| herdr says `blocked` | dialogs yes; pickers idle | approvals and questions yes; pickers idle | no: dialogs and pickers idle (S fixes dialogs) | permissions and questions yes; pickers idle |
| Remote over SSH | yes: tail. S: files, needs Oriel's launch | partly: S needs a WebSocket shim | partly: S needs the bridge file there, `nc -U` | yes: `sqlite3` poll. S: `curl -N` |
| S on a running TUI | no: `--settings` only at launch | no: only a TUI started with `--remote` | yes: `/reload` | partly: 2.x always; 1.x only with `--port` |

Without a side channel, approvals, questions and plans are answered with keys (pi: unsafe, since herdr reports idle).

### Key maps

Fixed per agent; no prompt parsing. Never ctrl+c.

| | Claude Code | Codex | pi | opencode |
|---|---|---|---|---|
| Answer a prompt | Return = first option, ↓, Esc = no and end the turn | `y`, digits, Esc = no and end the turn | ↑/↓, Return, Esc | Return = allow once, ←/→, digits, Esc = reject |
| Interrupt | Esc | Esc | Esc | Esc Esc |
| Mode step | shift+tab | shift+tab | shift+tab | tab |

## Adapter interface

One chat view, one model of a conversation, one small adapter per agent (`ClaudeChat`, `CodexChat`, `PiChat`,
`OpencodeChat`; screen text for every other pane). An adapter turns its sources (transcript lines, SQLite rows, hook
files, SSE, the bridge socket, app-server events) into `ChatEvent`s, and `ChatAction`s into herdr calls, keys or
side-channel calls. Ids are the agent's own.

```swift
enum ChatEvent {
    case session(id: String, cwd: String)                    // new id on /clear, /new, /fork: restart the source
    case user(id: String, text: String, images: [Image], queued: Bool)
    case text(id: String, markdown: String, final: Bool)     // final:false = a live delta (side channel only)
    case thinking(id: String, text: String?, seconds: Double?)
    case tool(ToolCall)                                      // sent again as it runs and ends
    case subagent(id: String, parentTool: String?, name: String, status: Status)
    case plan([PlanItem])
    case ask(Ask)                                            // tool, question or plan: side channel only
    case askEnded(id: String, answer: String, by: AnsweredBy) // chat, terminal, policy
    case turnEnded(status: Status, seconds: Double?)
    case settings(Settings)                                  // model, effort or thinking, mode, context, cost
    case notice(String)                                      // compaction, model switched by the agent, retry
}
enum ChatAction {
    case send(text: String, images: [URL]), interrupt, command(String)
    case answer(ask: String, option: String, text: String?)
    case keys([String])                                      // the Needs-you drawer, behind the key guard
    case setMode(String), setModel(String, effort: String?)
}
protocol ChatAdapter {
    func events(pane: Pane, machine: Machine) -> AsyncStream<ChatEvent>
    func perform(_ action: ChatAction, pane: Pane, machine: Machine) async throws
    var can: Capabilities { get }                            // live text, in-chat asks, model menu, mode values
}
```

- **Shared:** state from `agent_status`, the Needs-you drawer, the send guard, grouping tool calls between two
  replies into a summary line, the tail and poll runners over the relay.
- **Per agent, Base:** a finder, a lenient parser that skips unknown types, the key map, the slash commands that open
  pickers.
- **Per agent, side channel:** Claude Code's hook and statusline scripts in inline `--settings` with request and
  decision files; a JSON-RPC client for Codex's app-server; pi's bridge socket; opencode's SSE and a few `curl` calls.

## Approvals and questions

The TUI keeps its own dialog in both ways, so the user can answer in either place.

| Way | When | The chat shows | The answer goes |
|---|---|---|---|
| In-chat card | a side channel sent an `Ask` | the command, diff or plan, the agent's options as buttons, a field for "tell it what to do instead"; pinned above the composer while scrolled away | Claude Code: the decision file the hook waits on. Codex: the JSON-RPC reply. pi: the bridge. opencode: `POST …/reply`. The TUI dialog closes; a TUI answer shows "Answered in terminal" |
| Needs-you drawer | Base: `blocked`, or a picker the chat opened | the live bottom of the terminal, the key map as named buttons, Open Terminal | each key only if the screen is unchanged since it was read (the key guard) |

- **Esc is not "No".** In Claude Code and Codex it also ends the turn: on Base the button says "No, stop"; on the side
  channel deny with a message (Claude `{"behavior":"deny","message":…}`, Codex `decline`) so the agent goes on.
- **Policy wins.** Company PermissionRequest hooks return `allow` and beat Oriel's deny. Read the result
  (`permissionDecision.source`, the tool result) and show "Allowed by policy".
- **Races.** A Claude hook keeps waiting after a TUI answer: give each request an id and end the hook when the tool's
  result appears. PermissionRequest has no `tool_use_id`; pair it with the PreToolUse before it.
- **Few prompts in practice.** This user's aliases start Claude Code with `--dangerously-skip-permissions` and Codex
  with `--yolo`, and managed configs auto-review most commands. Questions and plan approval come up as often.
- **Picker trap.** Before each send, read the last screen lines; a picker footer is a fixed string ("Enter to
  select", "↑↓ navigate", "⇆ select").

## Model and mode

The composer shows model, effort or thinking, mode, context and cost as pills, read from the sources in the matrix.

| | Mode pill | Model pill, Base | Model pill, side channel |
|---|---|---|---|
| Claude Code | auto, manual, accept edits, plan: shift+tab until the footer shows it (at most 4) | `/model` in the drawer; Oriel presses `s` (session only) | the same; the statusline reads it back. No direct session-only call |
| Codex | plan: shift+tab. Permissions: `/permissions`, then 1 Ask, 2 Approve for me, 3 Full Access, 4 Read Only | `/model` in the drawer; `s` at the effort step | `turn/start {model, effort}` on the next turn |
| pi | `/thinking <level>` typed | a real menu: `/model <exact scoped id>` (from `pi --list-models`) | `set_model`, then `set_thinking` (a model change resets thinking) |
| opencode | build ↔ plan: tab | `/models` in the drawer (a variant picker may follow) | 2.x: session `/model` and `/agent`; 1.x: `/tui/publish` commands, or a model per prompt |

Never send a model name as text: Claude Code's `/model x` saves it to `~/.claude/settings.json`, Codex sends it to the
model. In both pickers Return saves a global default; `s` keeps it to the session.

## Mock-ups

Five directions were drawn (outside the repo) in Oriel's look, each with a different agent:

- **A, transcript tree** (Claude Code): pi-content-layout in the card; user boxes, replies after a dot, tool runs
  folded into one summary line, approvals inline. The densest. **Pane cards.**
- **B, chat with an inspector** (Codex): plan, subagents, context and changed files in a right column; the approval
  pinned above the composer. The inspector needs ~230 pt, too wide for split cards; take only the pinned approval and
  a "Plan 2 of 4" capsule over the composer.
- **C, focus column with a status island** (pi): a centered reading column, state, model, thinking and context in a
  glass capsule; the composer turns into the question. **Zoomed or floated cards.**
- **D, turn cards with a terminal drawer** (opencode 1.x): one card per turn with time, tokens and cost; the
  Needs-you drawer. **The drawer is the fallback inside all of them.**
- **E, the pill card** (Claude Code, Codex): A at 360 pt. **The pill card.**

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

**First slice:** Base for all four, local and remote (opencode's database polled once a second while shown); design
A behind the chat|term switch with the Working row from `agent_status`; the composer with `agent.prompt`, its
refusals and the picker guard; Stop sends the interrupt keys; the Needs-you drawer with the key guard; model, mode,
context and cost pills read only, a mode menu, and a model pill that opens the agent's picker (pi: a real menu).

## Risks and open questions

- **Format churn.** Codex replaced its event names within ten releases, Claude Code adds entry types often, opencode
  2.x changes storage and API. Parsers skip what they do not know and key on the version in the file's header.
- **Side channels need the launch.** Panes the user started stay on Base for Claude Code, Codex and opencode 1.x.
- **Writes to the user's config.** `/model x` and Return in pickers (Claude Code, Codex), Esc on Codex's startup
  promo, and pi's `/reload` (`trust.json`) all wrote global files in the spikes. Adapters use the session-only paths.

Open, for the user:
1. Should Oriel start agents? A New Agent menu (Claude Code with Oriel's `--settings`, Codex with `--remote` and an
   app-server pane, opencode with `--port`) is the only way to give those three live text and in-chat approvals. It
   changes how agents start and bypasses the user's shell aliases.
2. The pi bridge: ship it in pi-hkandala (remote machines that have it get it too), or have Oriel copy it to each
   machine (breaks "nothing installed on machines")?
3. Codex remote: a line↔WebSocket shim sent with each run (Perl is on every machine the relay works on), or the
   Codex side channel on This Mac only?
4. History: keep the 256 KiB start, or page back further on scroll?
5. Upstream asks for herdr: keep Claude Code's `transcript_path`; follow `/branch` and Codex `/fork`; report `blocked`
   for pickers and pi's dialogs; detect opencode 2.x.
