# Phase 39: Chat view for Codex, pi and opencode

Goal: the chat view from phase 38 for the other three agents, each through the same adapter interface,
with the TUI as the fallback for anything an adapter can't do reliably.

Design: [Chat view](../../docs/content/docs/future-work/chat-view.mdx) and
`resources/research/agents/{codex,pi,opencode}.md`.

## Track A: Codex (item 1)
1. Launch flags (`-c hooks.SessionStart=…`, `-c hooks.state` with the trusted hash), the rollout follower,
   the screen check for pickers, the adapter.

## Track B: pi and the pi-oriel extension (item 2)
2. **pi-oriel** ships inside Oriel (in this repo, not in pi-hkandala: the user may not have it): Oriel
   writes it to the pane's machine and starts pi with `-e <pi-oriel.ts> --oriel <state file>`. It reports
   session, tree, blocked and idle lines; the adapter follows them and the transcript.

## Track C: opencode (item 3)
3. Launch flags (`--port 0 --hostname 127.0.0.1`, the password file, `OPENCODE_TUI_CONFIG` with its small
   plugin), history and events from its server over the relay, permissions and questions answered in the
   chat.

## Findings
