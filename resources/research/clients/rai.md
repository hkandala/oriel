# rai (YogevKr/rai): who is working, stuck or needs approval

**Stack.**
- SwiftPM, `platforms: [.macOS(.v14), .iOS(.v17)]`.
- `RaiCore` (herdr client, wire types, bridge protocol) is shared with iOS.
- The macOS app uses SwiftUI `WindowGroup`s, with AppKit for terminals.
- The iOS project is defined with XcodeGen in `ios/project.yml` and compiles about 15 macOS view files directly, using `#if os(...)`.
- Renderer: a SwiftTerm fork pinned by revision `97d70b0`. The fork adds a selection API, `pinGridSize` for iOS, and Metal fixes.

**Terminal paths.**
1. **Main Mac window** (`Sources/RaiApp/TerminalPool.swift:354`): a SwiftTerm `LocalProcess` runs `herdr terminal attach <terminal_id> --takeover` in a PTY.
   - An LRU pool keeps 8 to 32 attached views. Hidden views are suspended: the attach process is killed and the buffer is kept.
   - The process is spawned only after the first layout, so the pane starts at its real size.
   - A comment at line 184 says that frequent `--takeover` attaches made **the displaced herdr client panic**.
2. **"Independent" windows**: rai speaks herdr's private binary endpoint protocol ("generation one", `endpoint.hello.v1`) directly on `herdr-client.sock` and renders cell grids composited by the server (`Sources/RaiCore/HerdrEndpoint*.swift`). This is reverse-engineered and fragile.
3. **iPhone**:
   - The phone never talks to herdr. The Mac runs a WebSocket bridge (`NWListener`, Bonjour `_rai._tcp`, reachable over LAN or through `tailscale serve --https`).
   - The Mac spawns `herdr terminal session observe <pane> --rows N` and forwards frames as `.paneFrame(paneID, b64, full, seq, cols, rows)`. Without `--rows`, observe defaults to 40 rows.
   - Phone input goes through `pane.send_input`. Pairing uses a QR code, and the token is kept in the Keychain.
   - **The Mac is the APNs provider**: it signs ES256 JWTs with a `.p8` key that the user pastes in.

**Socket.**
- Push through `events.subscribe` on its own thread.
- The subscription list depends on the protocol version, because **unknown event types make older servers close the whole stream**.
- `pane.output_changed` cannot be subscribed to. rai uses `pane.updated` plus a poll of the focused pane instead.
- Methods also include `pane.resize/zoom/move`, `agent.prompt`, `agent.explain`, `pane.selection.read`, `plugin.pane.open` and `agent.view.set/clear`.

**Remote.**
- `ssh -N -o BatchMode=yes -o StrictHostKeyChecking=yes -o StreamLocalBindUnlink=yes -o ExitOnForwardFailure=yes -L sock -L client.sock`, then `HERDR_SOCKET_PATH` is set to the local copy.
- The host list comes from `herdr machine list --json` and `herdr session list --json` (`MachineDirectory.swift:128`).

**Layout.** Mirrors herdr. `PaneLayoutTreeBuilder` (`Sources/RaiCore/PaneLayoutTree.swift`) turns the snapshot's flat `panes[]` + `splits[]` rects into a binary tree.

**Other details.**
- No web panes. No agent icons: status is a colored dot, and Claude spinner glyphs are stripped from titles.
- No glass.
- Claude Code hooks (`ClaudeHooksInstaller.swift`) send beacons to `~/Library/Application Support/Rai/hooks.sock`, which gives exact permission prompts. The phone can approve or deny them.
