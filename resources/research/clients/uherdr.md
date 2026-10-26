# uHerdr (MrMySQL/uherdr): native macOS

**Stack.** SwiftPM, **SwiftUI + AppKit**, macOS 14 (built with Xcode 26 SDK). Targets `HerdrCore` (Foundation) + `HerdrMac`. ~6.6k lines of own code + vendored wrapper.

**Renderer / embedding.** libghostty, **vendored Swift wrapper** of `Lakr233/libghostty-spm` 1.5.20260906 in `Vendor/GhosttyTerminal` (only `Sources/GhosttyKit` + `Sources/GhosttyTerminal` copied; the native lib still a checksummed SPM binary target):
```swift
.binaryTarget(name: "libghostty",
  url: "https://github.com/Lakr233/libghostty-spm/releases/download/upstream.c4e16970a803/GhosttyKit.xcframework.zip",
  checksum: "bd9bba3b…385da")
// GhosttyKit target links c++ + Carbon; GhosttyTerminal depends on MSDisplayLink 2.2.0, ships Resources/Ghostty + terminfo
```
Local patches (Vendor/GhosttyTerminal/README.md): `InMemoryTerminalSession(suppressesTerminalResponses:)` → uses `ghostty_surface_write_buffer_replay` so **herdr's ANSI frames don't make Ghostty answer DA/DSR queries back into the shell** ("Herdr owns the authoritative terminal and answers its queries… a Swift callback gate around receive is insufficient"); resource-bundle lookup in `Contents/Resources`; `clipboardPasteHandler` hook for file/image paste. Note the wrapper already contains `Platform/UIKit/UITerminalView*` — the same wrapper works on iOS.

**API socket.** `HerdrCore/HerdrClient.swift`: same NDJSON, one socket per request, serialized on a queue, 8 s timeout. Methods seen: `session.snapshot`, `layout.export`, `layout.set_split_ratio`, `pane.focus/move/read/split/swap/zoom`, `tab.create/focus`, `workspace.create/focus`, `worktree.create`, `agent.start`.
**Polling, not push**: `SessionStore.start()` loops `refresh()` every **1.25 s** (no `events.subscribe`).

**Live bytes — two paths** (`HerdrMac/TerminalSurface.swift`):
1. If server protocol == 22: `HerdrCore/NativeTerminalConnection.swift` + `NativeTerminalWire.swift` speak **herdr's private binary client protocol directly on `herdr-client.sock`** (4-byte LE length-prefixed packets, varint ints; hello `[0,22,cols,rows,0,0,0]`, control `[8,pane,takeover]`, input `[1,blob]`, resize `[3,…]`, scroll `[6,…]`, SGR mouse reports re-encoded as tag 16; server frames tag 1, clipboard tag 5 (OSC52), mouse-capture tag 8…). A second "shell endpoint" lane (`endpoint.hello.v1` JSON) is opened only for focused panes to receive clipboard writes. Pinned to v22 — breaks on herdr upgrades (hence path 2).
2. Fallback: spawn `herdr terminal session control <pane> --cols --rows [--takeover]` with `HERDR_SOCKET_PATH` env, same NDJSON as bigtty.

**Remote.** `HerdrCore/SSHTunnel.swift`: discovery via `ssh host <cmd>`, then `ssh -N -o ExitOnForwardFailure=yes -o StreamLocalBindMask=0177 -L local.sock:remote/herdr.sock -L local-client.sock:remote/herdr-client.sock -- host`. Requires `AllowStreamLocalForwarding` on server; retries every 10 s. Remote file/image drops stream bytes over a separate ssh channel (`RemoteFileTransfer.swift`) — never typed into the pane — then paste the remote path. Local sessions auto-discovered via `herdr session list` every 15 s; can start/stop/delete sessions through the CLI (`SessionControl.swift`, strips inherited `HERDR_SESSION`/`HERDR_SOCKET_PATH`). Shows remote Mac battery (`pmset` via ssh).

**Browser panes:** none. **Layout:** mirrors herdr (`LayoutNode` in `HerdrCore/Models.swift`, `PaneLayoutView.swift` computes frames, drag → `pane.move/swap`). Tab order is app-local (`tabOrder:<device>` in UserDefaults).

**Stored locally.** UserDefaults keys: `appearance`, `fontSize`, `selectedDeviceID`, `selectedSpace:<id>`, `selectedTab:<id>`, `tabOrder:<id>`, device profiles.

**Notifications.** `AttentionNotifier.swift`: `UNUserNotificationCenter`, posts when an agent starts waiting; click reveals the pane (held until device connects); Dock badge = attention count.

**Agent icons — best of the set.** `Sources/HerdrMac/Resources/AgentIcons/<herdr agent id>.png` (≤64 px): agy, amp, claude, cline, codex, copilot, cursor, devin, droid, gemini, grok, hermes, kilo, kimi, kiro, letta, maki, opencode, pi, qodercli, qwen; `SOURCES.md` lists official asset URLs. `templateMarks = ["codex","copilot","pi"]` drawn in text color; fallback SF Symbol `sparkles`. Lookup is simply `agent.lowercased() + ".png"`.

**Liquid glass:** none; only `#available(macOS 26)` for `onDragSessionUpdated`. **iOS:** none.
