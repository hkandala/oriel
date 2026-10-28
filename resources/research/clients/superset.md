# Superset (superset-sh/superset): now the Paradev repo; terminal agents tracked by hooks

`github.com/superset-sh/superset` now redirects to `ParadevAI/Paradev` (HEAD 84f9a904, Elastic License 2.0, about
15.7k stars, many commits a day). Same code, same `@superset/*` packages, the README says "Paradev". The chat side is
described in [paradev.md](paradev.md)
(written one day earlier, at 2c586e1c). This file covers what changed since then and the terminal-agent layer that
paradev.md skips.

## What changed since paradev.md

- The ACP chat is still the experimental `acp-chat` flag (`apps/desktop/src/renderer/stores/acp-chat.ts:5,28`).
- New: `packages/host-service/src/chat-v3/agentLogin.ts` (agent sign-in from the chat), `runtime/agent-jobs/`
  (background jobs a chat can follow), `packages/agent-harness/` (a pi-to-ACP bridge and tools for the cloud
  `agent-worker`). Chat runtime and UI grew about 1.7k lines. The terminal and chat are still separate processes.

## Terminal agents (the TUI side)

- Agents typed into a terminal report through **hooks** to an unauthenticated loopback endpoint. Each report upserts a
  row per terminal: agent id, `agentSessionId`, `transcriptPath`, start and end (`packages/host-service/src/terminal-agents/types.ts`,
  `store.ts:25-37`).
- A reported transcript path is kept only if it is absolute, ends in `.jsonl` and lies under `$HOME`, because anyone
  can POST to the endpoint (`terminal-agents/transcript-path.ts:1-19`).
- Uses of the transcript: the subagent list (Claude Task, Codex `spawn_agent`, keyed by the hook's `agent_id`,
  `subagent-transcript.ts`) and "hand off to another agent", read in a worker thread because a file can be hundreds of
  MB (`workers/tasks/harness.ts:1-3`, `harness-sessions/transcript.ts:11-22`). **No chat view of a terminal agent.**
- **Auto-resume:** an end reason (`detached` the agent said goodbye, `terminal-exited` the PTY died under it,
  `resumed`, `disposed`) decides whether the session is relaunched with the agent's resume flag after a daemon loss
  (`types.ts:9-27`, `daemon-loss-sweep.ts`, `TerminalAgentAutoResume.tsx:31-35`).
- **Config writes:** Claude hooks are merged into the global `~/.claude/settings.json`, tagged by the notify script's
  path and removed on teardown (`packages/agent-setup/src/agent-wrappers-claude-codex-opencode.ts:143-160`). Other
  agents get binary wrappers on `PATH` (`agent-wrappers-*.ts`).

## For Oriel

- Copy: trust a hook-reported transcript path only after checking it (absolute, `.jsonl`, under home, and the session
  id near the head of the file: `harness-sessions/transcript.ts:33-36`).
- Copy: tell "agent exited on its own" from "PTY died under it"; only the second is a resume candidate.
- Avoid: merging hooks into `~/.claude/settings.json`; Oriel's rule forbids it, and `--settings` per launch does the
  same job.
