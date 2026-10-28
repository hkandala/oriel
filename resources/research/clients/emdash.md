# Emdash (generalaction/emdash): an ADE where each conversation is either a chat or a TUI

Repo: https://github.com/generalaction/emdash (HEAD 85dfa91, Apache-2.0, about 6k stars, YC W26, daily commits).
Electron and React desktop, xterm.js, node-pty, SQLite, an Nx monorepo; a Node `workspace-server` daemon for remote
hosts. 20+ CLI agents through plugins. Not a herdr client. Every conversation has a type, `acp` or `pty`, picked when
it is created. There is no live switch between them.

## Choosing the surface

- The create dialog has a toggle "Chat UI" / "TUI" that sets the conversation type
  (`apps/emdash-desktop/src/core/features/conversations/contributions/browser/conversation-transport-toggle.tsx:14-22`,
  used in `create-conversation-modal.tsx:133` and `initial-conversation-section.tsx:423`). Nothing calls it later.
- Each agent plugin declares both paths. Claude (`packages/plugins/src/agents/impl/claude/index.ts:146-176`):
  - ACP: Zed's `claude-agent-acp` adapter bundled in the app, run as Node inside Electron, with
    `CLAUDE_CODE_EXECUTABLE=<user's claude>`.
  - TUI: `claude [--session-id|--resume] [--model] [--dangerously-skip-permissions]` in a PTY.

## Chat (ACP) mode

- One ACP runtime per host (`packages/core/src/runtimes/acp/`, 10.4k lines; design in
  `agents/architecture/acp-runtime.md`). A pure session state machine, a transcript reducer, a permission broker and a
  prompt queue per live session; history comes from `session/load`.
- `initialize` advertises `fs` read and write and `terminal` (`node/connection/acp-agent-connection.ts:157-167`), so
  the agent's file and shell tools run through Emdash.
- **Approvals:** `session/request_permission` becomes a card with the agent's options (`node/session/cell.ts:357-374`).
- **Send:** `sendPrompt` acknowledges once the session accepts or queues the prompt, not when the turn ends. A lost
  ack is "uncertain"; the draft is restored only when the failure is known to be before posting.
- Claude's Task subagents are rebuilt from `_meta.claudeCode.parentToolUseId` (`impl/claude/acp-transform.ts:1-16`).

## TUI mode

- `packages/core/src/runtimes/tui-agents/` (2.3k lines). The PTY can run inside tmux, so the TUI survives an app
  restart (`api/schemas.ts:32`). An unexpected exit respawns with `--resume <last session id>`
  (`node/runtime/runtime.ts:1036-1070`).
- **Input:** raw `pty.write(data)` (`runtime.ts:436-445`). The first prompt goes as an argv; one longer than 16k
  characters is written to a temp file and replaced by "read the file at …" (`node/runtime/prompt-spill.ts`).
- **Status and waiting:** hooks. Claude's are `SessionStart`, `UserPromptSubmit`, `Notification`, `Stop`, each
  running a stdin-to-HTTP command (`impl/claude/hooks.ts:50-62`). A `Notification` is classed by its text:
  `/permission|approval/i` means a permission prompt, anything else means idle (`hooks.ts:36-48`). Hookless agents
  go "working" on Enter and stay there until exit (`agent-state.ts:115-180`). The hook payload's `session_id` is kept,
  so a `/resume` inside the TUI is followed.
- **Approvals:** in the TUI only; the hook marks the tab as needing attention.
- **Config writes:** Claude hooks have `scope: 'global'` (`impl/claude/index.ts:80-84`), so the installer writes them
  into `~/.claude/settings.json` (`packages/core/src/services/agent-plugins/node/hook-installer.ts:105-124`), with
  `EMDASH_HOOK_PORT` and a token in the PTY's env (`runtime.ts:885-893`).

## Remote

`apps/workspace-server` runs on the SSH host and serves git, files, ACP and TUI runtimes over Emdash's wire protocol
on an SSH-forwarded Unix socket (`agents/architecture/workspace-server.md`). The desktop provisions and updates it.
Both conversation types run on the host.

## Known problems (issues)

#3260: a conversation suspended before Claude ACP saved it looped on "Could not restore". #3309, #3196: one bad
ACP call crashed the shared ACP worker and every conversation in it. #3166: streamed text split mid-word into rows.
#3074: a recursive `$HOME` watcher saturated the watch worker.

## Size

ACP runtime 10.4k, chat UI package 20.8k, desktop conversation feature 10.4k, TUI runtime 2.3k (no tests).

## For Oriel

- Copy: the hook-to-state mapping (`UserPromptSubmit` working, `Stop` done, `Notification` waiting) and keeping the
  hook's `session_id` current. Pass hooks with `--settings` per launch, not by editing `~/.claude/settings.json`.
- Copy: a per-agent "Enter means working" fallback that clears on the next real signal.
- Avoid: making the user pick chat or TUI up front; Oriel's switch stays live on one process.
- Avoid: one shared ACP worker whose crash takes every chat down.
