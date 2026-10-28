# super.engineering (closed source): a native Rust ADE with chat and terminal tabs and an idle-only switch

Site: https://super.engineering (formerly Superconductor). Closed source, free alpha, macOS only. Rust, rendered on
Metal; WebKit only for browser tabs. No repo to read, so everything here comes from its docs
(`super.engineering/docs/…`). Not a herdr client. Read it because it is the one native app that offers both
surfaces per agent and an explicit switch between them.

## Surfaces

- Each tab is a **Chat UI** or a **Terminal** (`super.engineering/docs/terminal-and-chat`). Chat UI exists for Claude Code, Codex,
  Cursor, OpenCode, Pi, Oh My Pi, Grok, Kimi, Prime, fx; Copilot, Droid, Kiro, Qwen, Hermes, Antigravity and Gemini are
  terminal-only (`super.engineering/docs/providers-and-models`).
- Docs: "A provider's terminal UI may expose controls that its Chat UI integration does not."
- **Claude's chat transport:** `claude -p` (structured, non-interactive) by default. A beta **Compliant Claude view**
  runs local Claude chats "through Claude Code's interactive mode" to keep usage on the subscription plan; SSH
  workspaces always use `claude -p` (`super.engineering/docs/settings-privacy-local-data`). How it reads the interactive session is not
  documented.
- Mid-turn steering works on "Claude's noninteractive chat path"; for a busy terminal agent the docs warn: "Never
  assume that text typed into a busy terminal provider was accepted merely because it appears on screen."

## Switching

- **Switch to Chat View / Switch to Terminal View** in the tab menu, for Claude Code, Codex, Cursor, Grok, OpenCode,
  Pi, Oh My Pi and Kimi.
- Only for an **idle** session with a usable resume target. "A busy session cannot switch. If the app cannot validate
  the provider session, it disables the action instead of opening a fresh process that only looks related."
- So the switch is a new process resuming the same provider session, not two views of one process.
- The same idea restores tabs after a restart: resume only what it can validate, else open a fresh session
  (`super.engineering/docs/session-history-and-restore`). Session ids come from a flag at launch, hooks, or the agent's history files.

## Approvals and attention

- Chat UI shows structured approval and question forms.
- One inbox (Running, Queue, Timeline) is fed by "provider hooks, managed session events, and Chat UI events". The app
  "does not treat arbitrary terminal output as authoritative approval or completion protocol"
  (`super.engineering/docs/notifications-and-approvals`).

## Remote

SSH workspaces: the app installs a managed `sc` CLI on the host (Linux or macOS) and runs git, terminals and agents
there; passwordless keys are required because background work never prompts (`super.engineering/docs/remote-workspaces`). Claude chats
there use `claude -p`.

## For Oriel

- Copy: disable the switch when the app cannot prove which session it would land on, rather than guess.
- Copy: never treat screen text as approval or completion truth; hooks and structured events only.
- Note: the "Compliant Claude view" shows ADEs moving Claude chats onto the interactive TUI for billing reasons.
  Anthropic announced a separate meter for `claude -p` and the Agent SDK, then paused it (its help center says nothing
  has changed "for now"). Oriel's TUI-first design is already on the safe side.
- Avoid: an idle-only, restart-to-switch toggle. Oriel keeps one process and switches views at any time.
