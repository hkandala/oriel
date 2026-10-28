# Chat view: research and decisions

How to show an agent pane as messages with a reply box, switch back to its terminal without ending the agent, and do
it on remote machines. Based on two spikes per agent in throwaway herdr panes (Claude Code 2.1.310, Codex 0.163, pi
1.4.0, opencode 1.19.4 and 2.2.0-dev, herdr 0.9.5) and about 30 other apps and tools, read at the source. The design
is [chat-view.mdx](../../../docs/content/docs/future-work/chat-view.mdx). Evidence per agent:
[Claude Code](../agents/claude-code.md), [Codex](../agents/codex.md), [pi](../agents/pi.md),
[opencode](../agents/opencode.md). Other apps: [../clients/README.md](../clients/README.md#agent-apps-with-a-chat-view).
Tools that drive agent TUIs: [controlling-agent-tuis.md](controlling-agent-tuis.md).

## Decisions

1. **The agent keeps running in its herdr pane.** The chat reads the transcript the agent writes anyway and follows
   it with `tail -F` (opencode: its own server's history and event stream, because it writes no transcript file).
   There is no live text: each message shows when it is on disk, 0.1–2 s after the TUI draws it.
2. **Only agents that Oriel starts get the chat.** The new pane chooser adds Oriel's flags to the launch line. Each
   line carries a marker that `pane.process_info` shows. Panes without it show only the terminal.
3. **A small core, the TUI for the rest.** Every adapter recognizes its pane, follows the transcript, tells ready,
   busy and waiting apart, sends with `agent.prompt` only when ready (confirmed by the user entry in the
   transcript), and stops with the interrupt key. When the agent waits on something the chat cannot answer, the live
   terminal takes the bottom of the card until it is busy or idle again.
4. **Answers in the chat only where a flag gives a clean channel:** Claude Code questions (a PermissionRequest hook
   for AskUserQuestion only), opencode permissions and questions (its server). Tool approvals for Claude Code and
   Codex stay in the TUI.
5. **The UI is design C without the island:** blue bubbles for the user, replies as text, three detail levels
   (Replies, Steps, All), tool runs as stacked cards, the live terminal as the fallback, and the pill card at 360 pt.
   The mock-ups are kept outside the repo.

## Per agent

| | Claude Code | Codex | pi | opencode |
|---|---|---|---|---|
| Launch flags | `--session-id T --settings '<inline hooks>'` | `-c hooks.SessionStart=…` and `-c hooks.state={…trusted hash…}` | `-e ~/.cache/oriel/pi-<sha8>.ts --oriel <state>` | `--port 0 --hostname 127.0.0.1`, a password from a 0600 file, `OPENCODE_TUI_CONFIG` with a 20-line plugin |
| Written first | nothing | nothing | the 31-line extension | the plugin, `tui.json`, the password file |
| Marker | `--session-id T` in the argv | `/tmp/oriel-T` in the argv | `--oriel` in the argv | the state line's `pid` |
| Transcript | SessionStart hook writes the path | SessionStart hook writes the path | the extension's `session` and `tree` lines | the plugin's `session`; `GET /session/:id/message`, then `curl -N /event` |
| Ready / waiting | `~/.claude/sessions/<pid>.json` status (fragile, undocumented; sees pickers); herdr as fallback | herdr state and a screen check for pickers (fragile) | `blocked` lines from `ui_prompt_*` | plugin `dialog`, herdr `blocked` |
| Stop | Esc | Esc | Esc | Esc Esc |
| In-chat answers | questions | none | none | permissions, questions |
| Remote | tested over SSH | tested over SSH | reasoned | tested over SSH (needs `curl`) |

Model, mode, slash commands and images go to the TUI. The model shows read only, from the transcript.

## Fallback rules

- No marker: no chat switch. This includes herdr's own restore (`claude --resume` without Oriel's flags) and an agent
  the user starts by hand.
- Waiting with no request the chat knows: the live terminal at the bottom of the card.
- Not confirmed within 5 s: "Not sent", with Show Terminal.
- No transcript, a parse failure, or many unknown entries in one turn: Show Terminal.
- Text that starts with `/`: the card flips to the terminal and the text is typed there.

## Why

- **No other app puts a chat over the live TUI the way Oriel needs.** cmux, Nimbalyst (opt-in, Claude only),
  pi-agent-dashboard, Orca and herdr-gpui (opt-in, Linux hosts) do. Superset/Paradev, Emdash, super.engineering, Agentastic,
  happy, claudecodeui, Sculptor and Paseo run a second, headless process or hand the session over (two writers; a
  switch only while idle). T3 Code, Conductor, vibe-kanban, Crystal, opcode and Terragon have no TUI. cmux is the
  pattern Oriel follows: hooks give the path, a tail gives the messages, "Answer in terminal" for the rest.
- **Screen reading fails.** AgentAPI built messages from screen diffs and is deprecated after Claude Code redraws broke
  it. Agent-published state works: transcripts, hooks, Claude Code's session record, opencode's server.
- **Why not in-chat tool approvals.** Claude Code: company PermissionRequest hooks return allow and beat Oriel's deny,
  and a waiting hook keeps open prompts that would close by themselves. Codex: a waiting hook runs before the
  launcher's reviewer and hides the TUI's prompt. pi: no built-in prompts, and an extension dialog's options are not
  known.
- **Why not a structured mode** (`codex --remote`, `pi --mode rpc`, ACP, the Agent SDK): without live text they add a
  second process or a server lifetime for nothing the hooks do not give. `pi --mode rpc` on the TUI's file split its
  tree.
- **Send rules from others:** paste, then Enter as its own write (herdr's `agent.prompt` does this); confirm by the
  transcript, never by the screen; never Enter again after the text was accepted (agent-deck's issue trail).

## Traps

- herdr reports `idle` in pickers, so a send can land in one (proven for all four). Each adapter's ready signal above
  closes this.
- Typing the launch line through nested shell quoting corrupted it, and a stray line reached the TUI as a prompt. The
  line goes to herdr as one argv string.
- Writes to user config seen in the spikes: Claude Code `/model <name>` and Return in its picker; Codex Return in
  `/model` and Esc on its startup promo; pi `/reload` (`trust.json`). Oriel's flags write none. The company launchers
  write their own state on every start (Codex reinstalls a plugin into `~/.codex`, opencode rewrites caches).
- The company `opencode` (MetaCode 1.18) ignores the plugin and password: no chat there.

## Open

- Codex's hook trust hash is internal. If it changes, Codex shows its "Hooks need review" picker, which the chat treats
  as waiting. The fallback flag, `--dangerously-bypass-hook-trust`, would also trust a cloned repository's hooks.
- Claude Code's session record is undocumented; without it, Claude falls back to herdr's state.
- opencode 2.x moves to a shared service, `/api/*` routes, forms and new storage: a second mapping when it ships.
- herdr asks: `blocked` for pickers and pi dialogs, Claude Code's transcript path, the new session after a fork.
