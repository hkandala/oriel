# allward (joshuaswarren/allward): a terminal for agents across machines

**Stack.**
- SwiftPM 6.2, **macOS 26 only**, AppKit-first, with SwiftUI in `NSHostingView`.
- Its own VT engine (`Sources/AllwardTerminal`) and Metal renderer (`Sources/AllwardRenderer`), with a `forkpty` C shim.
- Config is a single file, `~/.config/allward/allward.toml`.

**herdr integration.** Shallow, and pinned to herdr **0.7.5 / protocol 17**:
- All calls are CLI subprocesses: `["herdr"] + args`, or `["ssh", host, "herdr"] + args`.
- Calls used: `herdr api snapshot`, `herdr agent list`, `herdr agent focus <pane>`.
- No socket or event source is wired up in production. Snapshots refresh only on demand.
- To show herdr content it runs the herdr TUI (`herdr --remote host`) inside its own pane. "Teleport" means `herdr agent focus`.
- `docs/evidence/HERDR.md` is a good capability table: `pane.read` returns a rendered snapshot, not a byte stream, and `pane_output_changed` cannot be subscribed to.

**Other details.**
- Remote: plain ssh.
- No web panes, no notifications through UN, no agent icons (SF Symbols show state).
- The layout is its own split tree.
- **Glass rejected on purpose** (`docs/DESIGN-LANGUAGE.md:452`): "permanent glass … outside the language. The opaque grid is the baseline."
- It also ships an MCP server, `allward-mcp`.
