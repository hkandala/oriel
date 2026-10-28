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

### Track A

- **Decisions:** the hook writes to `~/.cache/oriel/chat/T/hooks.jsonl` (phase 38's folder, not the design's
  `/tmp/oriel-T`), and the marker is that folder inside a `hooks.SessionStart=` argument. Codex runs hooks with
  `$SHELL -lc`, so the hook is plain commands with no variable, quote or backslash: it works in fish too. The chooser
  types `codex …` like the other agents, so the user's own `codex` alias (the company's `--yolo` and friends) still
  applies; the trust hash, not a bypass flag, keeps the "Hooks need review" picker away.
- **Decisions (the screen check):** while herdr says idle or working, the adapter reads the pane's last 8 lines
  every 0.5 s; two reads in a row without Codex's input box (`› …`) directly above its status row (`… · …`) make the
  chat wait, so the live terminal takes the bottom of the card and nothing is sent into a picker. It reads `recent`,
  not the viewport, so a scrolled pane does not count as a picker.
- **Decisions (the parser):** `CodexRollout` reads only `item_completed` items (whole when written), `task_complete`,
  `turn_aborted` ("Interrupted"), `error` and `turn_context` (the model). A plan reads as a reply; reads show as the
  file they read; edits show the full path (an item has no session folder to shorten it against).
- **Not built (deviations):** forks show only their own lines (no parent history up to
  `forked_from_ordinal_exclusive`); subagent rows and images are skipped; Codex starts its session at the first
  prompt, so a new chat is empty until the first message; "Codex has not started a session" shows only when a message
  goes unconfirmed with no session (the hook did not run: a trust hash Codex no longer takes).
- **Shared changes:** the history follower moved from `ClaudeCode` to `Chat.follow(history:on:read:)`, and the UI
  tests' `startChat(agent:)` starts `scripts/<command>-stand-in.py` by its place in the chooser (both taken by the pi
  track too).
- **Runs:** with the screen check turned off, the local e2e failed at the picker's drawer; with it, green.
- **For the user:** a real Codex from the chooser: no "Hooks need review" picker, a message and its reply in the
  chat, Stop, `/model` typed in the chat (it flips to the terminal) and a picker left open when you flip back (the
  terminal shows at the bottom); `/new` then a message (the chat starts the new session); a remote machine. The
  company launcher still reinstalls its llm-rules plugin into `~/.codex` on each start, as it always does.
