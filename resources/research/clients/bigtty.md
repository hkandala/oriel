# bigtty (v1k45/bigtty): native macOS, AppKit and libghostty

**Stack.** Swift 6, SwiftPM, **AppKit** (not SwiftUI), macOS 14+. Targets: `HerdrKit` (pure socket/model lib, ~2.3k lines), `bigtty` (app), `btty` (CLI used by agents + placeholder process). ~21k Swift lines.
`Package.swift`: `.package(url: "https://github.com/Lakr233/libghostty-spm.git", exact: "1.6.20260929")`, product `GhosttyTerminal`. Bundles Ghostty theme collection as a resource.

**Terminal renderer.** libghostty via `GhosttyTerminal.AppTerminalView` with a **host-managed in-memory backend** (no PTY in the app):
```swift
// Sources/bigtty/HerdrTerminalView.swift
final class HerdrTerminalView: AppTerminalView, ... {
  session = InMemoryTerminalSession(
      write:  { data in DispatchQueue.main.async { box.value?.userInput(data) } },   // keys -> herdr
      resize: { vp   in DispatchQueue.main.async { box.value?.viewportChanged(vp) } }, // grid -> herdr resize
      suppressesPixelOnlyResizes: true)
  gate = FrameGate { surfaceSession.receive($0) }          // herdr frames -> ghostty
  configuration = TerminalSurfaceOptions(backend: .inMemory(session))
```
`FrameGate` holds frames during a resize so you see the redrawn result, not intermediate frames.

**herdr API socket (`HerdrKit/HerdrClient.swift`).** NDJSON, *one request per connection* (fresh unix socket per call): `{"id":uuid,"method":..,"params":{..}}` → `{"result":{..}}|{"error":{code,message}}`. Methods used:
`ping`, `session.snapshot` (→`result.snapshot`), `layout.export {tab_id}` (→`result.layout`), `pane.split {target_pane_id,direction:"right"|"down",ratio?,focus}` (→`result.pane`), `layout.set_split_ratio {tab_id,path:[Bool],ratio}`, `pane.focus`, `pane.focus_direction`, `pane.resize {pane_id?,direction,amount?}`, `pane.zoom`, `pane.swap {source_pane_id,target_pane_id}`, `pane.move {pane_id, destination:{type:"tab",tab_id,split,target_pane_id?,ratio?}|{type:"new_tab",workspace_id}|{type:"new_workspace",label?}, focus}` (→`move_result{changed,pane{pane_id,tab_id,workspace_id},closed_tab_id,closed_workspace_id}`; **moving into another workspace gives the pane a new id**), `pane.close`, `pane.process_info` (→`process_info.foreground_processes[{name,argv}]`), `pane.read {pane_id,source:"recent_unwrapped",lines}` (→`read.text`), `pane.send_text`, `pane.report_metadata {pane_id,source:"bigtty",title?,tokens:{k:v|null}}`, `tab.focus/create/close` (`tab.create`→`root_pane`), `workspace.focus/create{cwd?,label?,focus}/move{insert_index}/rename/close`.

**Push, not polling.** `HerdrKit/EventStream.swift`: long-lived `events.subscribe` connection:
```json
{"id":"subscribe","method":"events.subscribe","params":{"subscriptions":[{"type":"workspace.created"},…,{"type":"layout.updated"},
  {"type":"pane.agent_status_changed","pane_id":"…"}]}}
```
Global types: `workspace.{created,updated,metadata_updated,renamed,moved,reordered,closed,focused}`, `worktree.{created,opened,removed}`, `tab.{created,closed,focused,renamed,moved}`, `pane.{created,updated,closed,focused,moved,exited,agent_detected}`, `layout.updated`. `pane.agent_status_changed` must be subscribed **per pane**, so the stream is re-opened whenever the pane set changes. Server drops slow readers with `events_lost` → resnapshot+resubscribe. Event line shape: `{"event":"…","data":{…}}`.
`SessionStore.swift`: **events are only signals** — any event → coalesced (16 ms) `session.snapshot` + `layout.export` for every tab in parallel; diff-and-notify. Order: snapshot → subscribe (waits for `subscription_started`) → refresh, so nothing is missed. Backoff 0.5 s→5 s reconnect.

**Live terminal bytes.** `HerdrKit/TerminalChannel.swift` spawns the **herdr CLI** per visible pane: `herdr [--session X] terminal session control <terminal_id> [--takeover] --cols C --rows R` (or `observe`). Comment: *"The CLI is used instead of the binary client protocol because that protocol is private and changes between herdr releases."* stdout NDJSON: `{"type":"terminal.frame","bytes":"<b64 ANSI>","width":W,"height":H}`, `{"type":"terminal.closed","reason":…}`. stdin NDJSON: `terminal.input{bytes:b64}`, `terminal.resize{cols,rows,cell_width_px?,cell_height_px?}`, `terminal.mouse{action:down|up|drag|move,button,column,row,modifiers}`, `terminal.scroll{direction,lines,source:"wheel",column?,row?}`, `terminal.release`. herdr re-renders the pane **at the client's size** and owns scrollback (wheel goes to herdr). One client controls a pane, others observe; `ControlArbiter.swift` makes the last-focused window control and others `observe` so bigtty windows never fight; `--takeover` steals from the herdr TUI.

**Remote hosts.** `Machines/SSHTunnel.swift`: probe via `ssh target sh -s` (script prints sock/bin/running/version/home), then a dedicated long-lived process:
```
/usr/bin/ssh -o ConnectTimeout=10 -o ControlMaster=no -o ControlPath=none -N -o ExitOnForwardFailure=yes
  -o ServerAliveInterval=15 -o ServerAliveCountMax=3 -o StreamLocalBindUnlink=yes
  -L <dir>/herdr.sock:<remote>/herdr.sock -L <dir>/herdr-client.sock:<remote>/herdr-client.sock
  -D 127.0.0.1:<free port> -- <target>
```
Local herdr CLI is then pointed at the forwarded socket with `HERDR_SOCKET_PATH` (it derives `herdr-client.sock` beside it) — "the rest of the app doesn't know the difference". Small probes (git branch, ports, file reads) via `ssh` with a ControlMaster=auto shared connection; exit status smuggled in stdout (`RemoteStatus`) because Tailscale SSH always exits 0. `SSHAskpass` handles prompts. Saved machines in UserDefaults (`MachineManager`).

**Browser/file panes — modeled IN herdr** (`Sources/bigtty/HostPanes.swift`, `Sources/btty/main.swift`). Flow: `pane.split` → `pane.report_metadata` with `tokens {btty_kind: browser|files|diff, btty_id, btty_url…}` → `pane.send_text "exec btty pane-host browser <id> <title>\r"`. The placeholder prints a banner ("🌐 bigtty browser pane — open this workspace in bigtty to see it"), disables echo/ICANON, ignores SIGINT and swallows stdin forever. Remote panes (no btty there) use `sh -c "printf '<banner incl. URL>'; stty -echo -icanon; exec cat >/dev/null"`.
Gotchas they hit and solved:
- **herdr keeps only 80 chars per token value** → long URLs are chunked into `btty_url`, `btty_url_2`, … (max 32 parts), next key set to `null` as terminator.
- **herdr drops pane tokens on server restart / live handoff** while the placeholder keeps running → `restoreTags()` inspects `pane.process_info` argv for `pane-host <kind> <id>`, or `pane.read`s the banner text and parses the URL back out, then re-tags.
- They *also* keep `~/Library/Application Support/bigtty/panes.json` (`HostPaneStore`, id→`{kind,url,title,path,selection,mode,paneID,machine}`), pruned against live panes. So tokens are the cross-device truth, the JSON is a cache/extra state.
- `BrowserRegistry` owns WKWebViews independently of windows (agents can drive an off-screen browser via `btty browser …` over the app's own unix socket `ControlServer`, mode 0600). Remote-machine browser panes use a per-machine `WKWebsiteDataStore(forIdentifier:)` with `ProxyConfiguration(socksv5Proxy:)` → the ssh `-D` port, so `localhost` means the remote machine. uBlock Origin Lite web extension supported.

**Layout.** Mirrors herdr's split tree exactly: `layout.export` → `LayoutNode = .pane(id) | .split(direction, ratio, first, second)` (JSON `{type:"split",direction,ratio,first,second}` / `{type:"pane",pane_id}`), `TabLayout{tab_id,zoomed,focused_pane_id,root}`. `SplitTreeView.swift` renders it; divider drags → `layout.set_split_ratio` with a `[Bool]` path; drag-to-rearrange → `pane.swap`/`pane.move`. Only app-local layout extra: a "pin column" (`PinLayout.swift`, width in UserDefaults).

**Stored locally.** UserDefaults: UI prefs (sidebar width/visibility, opacity, sound, notify mode, links, windowPerSpace…), active session, remote machines. `panes.json` (host-pane cache). Nothing about workspaces/tabs.

**Notifications.** `HerdrKit/Attention.swift` + `AttentionCenter.swift`: client-side "seen" model (herdr tracks seen per client): transition to `blocked` or witnessed `done` while pane not visible+focused in key window → `UNUserNotification` + Dock badge + ring on pane; "Needs You" list sorted by urgency. `AgentTitles.swift` reads the agent's own session files (claude/codex jsonl, keyed by herdr's `agent_session`) for nice tab titles (remote via ssh shell snippet).

**Agent icons.** None bundled (status dots/text; `display_agent`). **Liquid glass:** none (`NSVisualEffectView` only; a macOS 26 Network-framework crash workaround in `NetworkWarmup.swift`). **iOS:** none, but HerdrKit is Foundation-only and portable.
