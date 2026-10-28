# Phase 38: Chat view, the core and Claude Code

Goal: an agent pane that Oriel started can switch between its terminal and a chat view of the same running
agent, with no process ended, on This Mac and remote machines. This phase builds the shared core and the
first adapter (Claude Code); phase 39 adds Codex, pi and opencode.

Design: [Chat view](../../docs/content/docs/future-work/chat-view.mdx) (it wins on details),
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
