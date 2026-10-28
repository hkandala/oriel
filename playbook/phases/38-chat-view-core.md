# Phase 38: Chat view, the core and Claude Code

Goal: an agent pane that Oriel started can switch between its terminal and a chat view of the same running
agent, with no process ended, on This Mac and remote machines. This phase builds the shared core and the
first adapter (Claude Code); phase 39 adds Codex, pi and opencode.

Design: [Chat view](../../docs/content/docs/ui/chat-view.mdx) (it wins on details),
`resources/research/ui/chat-view.md` and `resources/research/agents/claude-code.md`. The user approved
(2026-10-28): the transcript file followed by a watcher (no live text); a small reliable core with the TUI
as the fallback; launch flags with hooks where they make it reliable; chat only for agents Oriel started
with its flags; design C without the status island (iMessage-like), detail levels Replies / Steps / All,
stacked tool cards, the pill card version (E). Mock-up: `~/Downloads/oriel-research/chat-view.html`.

## Track A: core and Claude Code (items 1–6)

1. **Launch flags.** The chooser and Start Agent Here start Claude Code with Oriel's flags
   (`--session-id`, `--settings` with the inline hooks), local and remote, and the marker is read back from
   `pane.process_info` after a relaunch.
2. **The adapter interface.** One small protocol every agent fits (recognize, follow the transcript,
   ready/busy/waiting, send, stop; optional extras), and the transcript follower that runs locally or over
   the relay (`tail -F` style, offset and inode checks).
3. **The chat view.** Design C without the island in SwiftUI (no web views), Liquid Glass, the three detail
   levels, stacked tool cards, the composer, and the chat|term switch in the card header; the pill card
   version.
4. **Sending and stopping.** Send through herdr only when the agent is ready, confirmed by the user entry in
   the transcript (5 s, then "Not sent" with Show Terminal); stop with the interrupt key; text that starts
   with `/` goes to the terminal.
5. **Waiting and fallbacks.** When the agent waits on something the chat can't answer, the live terminal
   takes the bottom of the card until it is busy or idle again; Claude's questions answered in the chat
   through its hook; an unreadable transcript shows Show Terminal.
6. **Tests.** e2e with a stand-in agent on CI (a script that writes a Claude-format transcript and reacts
   to input), local and on the remote test host.

## Findings

### Track A

- **The adapter interface (for phase 39):** `ChatAdapter` in `Oriel/Chat/ChatAdapter.swift`: `static command`,
  `static flags(token)` (what the chooser types after the command), `init?(foreground)` (the marker in
  `pane.process_info`'s argv, now `Program.foreground`), `token`, `stopKeys`, `follow(chat, on: exec)` (follows the
  agent on its machine and writes `chat.history`, `chat.recorded` (its own phase, nil for herdr's), `chat.question`,
  `chat.problem`; it goes on from `chat.marks`), and the optional `answer(question, answers, on:)`. Register it in
  `ChatAdapters.all`. The core does sending (`agent.prompt`, confirmed by the history), stopping, slash text, the
  drawer and the views. HerdrKit gives `Exec.follow` (tail -F with inode and offset, last 256 KiB) and `Exec.watch` (a
  rewritten file printed on change), and `ChatHistory` (entries, rows per level) that each parser fills.
- **Decisions:** the hooks hold no quote and no backslash (`set -f`, one `ask`/`answer` file pair that the waiting
  hook marks with its pid instead of per-request ids), so the inline `--settings` reads the same in sh, bash, zsh and
  fish: no settings file, even for fish. The side files live in `~/.cache/oriel/chat/T/` (0700, the user's own on a
  shared machine; folders untouched for 30 days go), not `/tmp/oriel-chat/T`. Chats live on the session's store, one
  per pane for every window. Multi-answer questions go to the terminal. A card of a marked pane opens on the chat; the switch is kept in
  memory. The adapter follows only while a card shows the chat (marks keep the place); off screen the header's state
  is herdr's.
- **Decisions (the orchestrator's polish, for the docs pass):** the messages, the reply box and the question card sit
  in a 760 pt column centered on any card (not only zoomed); the detail level moved from the header into the reply
  row (Replies · Steps · All left of the reply box); thinking rows show at All only; the reply box says "Reply to
  Claude Code" (the chooser's name); the header has the state capsule and Chat · Terminal in the app's own pill
  segments. A clicked stack keeps its open or closed state at every level.
- **Not built (deviations):** the terminal stream stays open while the chat shows (the registry keeps This Mac's
  streams of cards out of view anyway); floating windows show the terminal only; the pill card has no host until the
  pills land (it is `ChatView` at 360 pt with the level fixed, a few lines then); no `/resume` with the flags.
- **Cause (spike):** herdr's `agent.prompt` refuses ("no longer the pane foreground process") unless a foreground
  process has the agent's name, so the stand-in runs itself again through a link named `claude`. The marker check
  first required `/tmp/oriel-chat/T/`; the hooks write `/tmp/oriel-chat/T;`, so no pane was recognized until fixed.
- **Cause (keyboard):** the terminal that had the keyboard leaves the window when the chat or the drawer replaces it,
  so nothing had the keyboard; the reply box now takes it when the chat appears and when the drawer goes, and
  `PaneViewRegistry.focus` sends a chat card's keyboard to its reply box.
- **For the user:** a real Claude Code started from the chooser (the company launcher rewrites
  `~/.claude/settings.json` on each start, as it always does); a question (AskUserQuestion) answered in the chat and
  one answered in the terminal; a tool approval (the drawer) with permission prompts on; `/clear` in the terminal
  (the chat starts the new session); a remote machine; light mode and Classic.
