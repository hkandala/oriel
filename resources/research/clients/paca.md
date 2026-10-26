# paca (adarshzpatel/paca): Slack-style window and menu bar panel

**Stack.**
- Pure SwiftPM (tools 6.0), SwiftUI app, macOS 14. `scripts/install.sh` builds the `.app` and ad-hoc signs it, because notifications need a signed app.
- Also has a `MenuBarExtra`, a global ⌥Space Carbon hotkey, and a floating `NSPanel`.
- Renderer: SwiftTerm `from: "1.2.0"` with the Metal renderer, fed by `feed(byteArray:)`.

**Socket.**
- Short-lived connection per call.
- Methods:
  - `ping`, `session.snapshot`, `server.agent_manifests`
  - `workspace.create/rename/move/close`, `tab.create`
  - `pane.split/rename/close/focus`, `pane.read {source:"recent_unwrapped",strip_ansi:true}`
  - `agent.focus/start/rename/prompt`; `agent.start` replies `launch_pending:true` and is retried on `agent_pane_busy` for up to 10 s
  - `worktree.*`
- Sessions and machines go through the **herdr CLI**: `herdr session list --json`, `herdr --session N server`, `herdr machine list --json`, `herdr machine add/remove`. The machine list belongs to herdr and is shared with the TUI.
- Events: lifecycle types plus a per-pane `pane.agent_status_changed`. Each event triggers a full re-snapshot. `pane.updated` is skipped on purpose because it fires on every title change.

**Live bytes.** `HerdrKit/TerminalSession.swift` runs `herdr terminal session control <pane_id> --cols N --rows N [--takeover]` as a `Process` with pipes (no PTY). Wire format:
```
stdout: {"type":"terminal.frame","seq":1,"full":true,"width":80,"height":12,"encoding":"ansi","bytes":"<b64>"}
        {"type":"terminal.closed","reason":"..."}
stdin:  {"type":"terminal.input","bytes":"<b64>"} | terminal.resize{cols,rows} | terminal.scroll{direction,lines} | terminal.release
```
- The first frame is a full repaint. After that, frames are diffs.
- A second controller that connects without `--takeover` receives `terminal.closed` with "already has an attached client", and the UI then shows a **Take over** button.
- If no TUI is attached, the controller's size becomes the pane's real size. Headless panes default to 120x40.
- herdr owns scrollback.
- Hidden tabs stay attached, but their frames are dropped before decoding. To show a tab again, paca sends a resize to the same size, which forces a full repaint without SIGWINCH.
- A FramePacer caps redraws at 30 fps (15 fps for the unfocused split). Resizes are debounced because each resize makes Claude Code redraw.
- `herdr terminal session observe` is the read-only variant.

**Remote.**
- `ssh -N -o BatchMode=yes -L <dir>/herdr.sock:<remote>/herdr.sock -L <dir>/herdr-client.sock:<remote>/herdr-client.sock`.
- `docs/PLAN.md`: "Forwarding only the API socket fails with 'failed to connect to server' from the terminal."
- Only one machine is active at a time.

**Other details.**
- No web panes.
- Layout: its own tab strip, holding the pane ids the user opened, plus one app-side split.
- Stored locally:
  - UserDefaults: `paca.*`
  - `activity.jsonl` and `rules.json` (automation rules: "when agent X becomes done → `agent.prompt` Y")
- Notifications: from snapshot diffs.
- Agent icons: `scripts/sync-agent-icons.sh` downloads LobeHub `@lobehub/icons-static-svg` and fixes the SVGs so NSImage can parse them (`currentColor`→`#000`, `1em`→`24`, arc flags). Files are `agent-<kind>.svg`, drawn as templates.
- Testing trick: `pane.report_agent {source,agent,state}` fakes a status change.
- **Glass: tried, then removed.** `docs/PLAN.md`:
  - The window background was `NSGlassEffectView` on macOS 26, then went back to a solid window.
  - `scripts/snapshot.sh` rendered the glass as white.
  - The app icon is an Icon Composer `.icon` file.
