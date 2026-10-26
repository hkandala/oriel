# herdrm (missuo/herdrm): SwiftUI console

**Stack.**
- SwiftUI, with AppKit bridges.
- XcodeGen `project.yml` defines two targets: `HerdrM` (macOS 14) and `HerdrMobile` (iOS/iPadOS 18). The app is not sandboxed because it spawns `ssh` and `herdr`.
- Local packages:
  - `Packages/HerdrKit`: RPC, models, SSH tunnel, devices.
  - `Packages/HerdrSSH`: libssh2 + OpenSSL xcframeworks for iOS, vendored.
  - `Packages/HerdrTailcat`: a gomobile WireGuard/DERP client xcframework.
- The README says the app uses SwiftTerm. That is out of date: the code uses libghostty.

**Renderer.**
```yaml
## project.yml
GhosttyTerminal:
  url: https://github.com/Lakr233/libghostty-spm
  exactVersion: "1.6.20260909"   # binary xcframework: pin exactly, review checksum diff
```
- One process-wide `TerminalController(configSource: .none, theme:)`, in `Sources/HerdrM/TerminalView.swift` (`enum GhosttyRuntime`).
- Font, cursor and `copy-on-select` are set through `TerminalConfiguration { builder.withFontSize(..); builder.withCustom("copy-on-select","clipboard") }`.
- Each terminal is an `AppTerminalView` subclass with `TerminalSurfaceOptions(backend: .inMemory(session))`.
- **The same `GhosttyTerminal` API runs in `Sources/HerdrMobile/MobileTerminalView.swift` on iOS.**
- Build notes: Xcode 27 needs `xcodebuild -downloadComponent MetalToolchain`, and `-skipPackagePluginValidation` is required.

**Socket.** `HerdrKit/SocketRPC.swift`:
- NDJSON, one connection per request. `params` must always be present (send `{}` when empty).
- Methods:
  - `session.snapshot`, `agent.list`, `workspace.list`, `server.agent_manifests`
  - `agent.prompt {target,text}`, `agent.start {name,kind,pane_id,args}` (retried while the pane is busy), `agent.rename`
  - `workspace.create/rename/move/move_block/close`, `tab.create/rename/move`
  - `pane.get`, `pane.read {source:"visible",format:"ansi"}`, `pane.send_input {pane_id,text}` or `{pane_id,keys:["enter","ctrl+c"]}`, `pane.scroll`, `pane.close`
  - `plugin.action.list/invoke`
- Push: one long-lived `events.subscribe` with the same global types as bigtty, plus a per-pane `pane.agent_status_changed`. If the subscribe fails with `pane_not_found`, it retries without the per-pane subscriptions.
- Every event triggers a debounced `session.snapshot` (200 ms leading edge, plus a trailing run). Status changes are patched in place.
- Event names arrive with underscores (`pane_created`), so they are normalized.

**Live bytes.**
- `TerminalProcess.swift` calls `forkpty` to run the herdr CLI client: `agent attach <pane> --takeover` or `terminal attach <terminal_id> --takeover`, with `HERDR_ATTACH_GRAPHICS=1`. The PTY output goes into `session.receive`.
- The attach protocol needs the **CLI and server versions to match exactly**, so the app searches `$PATH` for a herdr binary whose `--version` equals the server's.
- Rebuilding the view kills the attach process, and it then re-takes the pane with `--takeover`. Because of this, the layout must stay structurally stable.

**Remote.** Three transports:
1. macOS: `ssh -N -L $TMPDIR/herdrm-tunnels/<hash>.sock:$HOME/.config/herdr/herdr.sock` forwards the API socket only. The terminal runs as a separate `ssh -tt target "exec herdr agent attach … --takeover"`.
2. iOS: libssh2 opens one `direct-streamlocal` channel per RPC and one long-lived channel for events. The terminal is an SSH PTY channel that runs `herdr agent attach`.
   - The app prints an APC marker `ESC _ herdrm-attach ESC \` before `exec` and renders only the bytes after it, which skips shell rc noise.
   - An Ed25519 device key is stored in the Keychain. Host keys use TOFU (trust on first use).
3. Tailcat: a gomobile bridge to a `herdr.tailcat` plugin. It re-serves the API socket and the `-client` socket locally.

**Other details.**
- No web panes.
- Layout is the app's own (one pane, or a ⌘D two-pane split). It does not mirror herdr.
- Stored locally:
  - `~/Library/Application Support/HerdrM/devices.json`
  - Keychain: passwords, tokens, keys
  - `@AppStorage`: UI prefs
- Notifications: `UNUserNotificationCenter` when an agent becomes `done` (sound "Glass") or `blocked` (sound "Funk"). No notification for the pane being watched.
- Agent icons: bundled LobeHub SVGs in `Resources/AgentIcons/*.svg`, mono and `-color` variants.
  - `BrandIconLoader.agentIcon(for:)` maps herdr `kind` to a file name (`claude-code`→`claude`, `github-copilot`→`githubcopilot`), falls back to the longest prefix match, and prefers the `-color` file.
  - Mono icons load as template `NSImage`.
- Glass: none. It uses `NSVisualEffectView(.sidebar)`, and works around an NSPopover crash on macOS 26.
- iOS: shares HerdrKit models and events, GhosttyTerminal and Tailcat. The UI is separate (`NavigationSplitView`), with its own `MobileTransport` protocol.
