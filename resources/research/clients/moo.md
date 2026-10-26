# moo-mac-terminal (ventz/moo-mac-terminal)

**Stack.**
- A standalone terminal emulator: AppKit+SwiftUI, macOS 15.5, Xcode project.
- Renderer: SwiftTerm fork `ventz/SwiftTerm@perf/moo`.

**herdr integration.**
- **Not a herdr front-end.** The user runs the herdr TUI in a Moo tab.
- Discovery: every 2 s Moo finds `herdr` processes in its own PTYs (`sysctl KERN_PROCARGS2` for argv and env) and resolves the socket the way herdr does.
- It then opens the socket **read-only** to show agent status in its sidebar. A type-level method whitelist (`ping`, `session.snapshot`, `events.subscribe`, `pane.focus`, `agent.focus`) enforces this.

**Useful herdr facts** (`Moo/Herdr/HerdrBridge.swift`, `MooTests/HerdrFixtures.swift` holds **real 0.9.3 JSON fixtures**, and `FakeHerdrServer.swift` is a fake server for tests):
- If one pane id in a `pane.agent_status_changed` subscription is unknown, **the whole subscribe fails** with `pane_not_found`.
  - Moo uses 1 lifecycle connection plus 1 connection per agent pane.
  - It caps these at 32 per session and 64 overall.
- Event names are mixed: the subscription types use dots, while pushed events such as `pane_created` use underscores. Normalize them.
- `done` becomes `idle` after a herdr client has shown it.
- An agent exit arrives as `pane_agent_detected` with `released:true`.
- Raw POSIX socket + `DispatchSourceRead` instead of NWConnection. The code comment says "NWConnection could report the hang-up first and drop a large reply".

**Other details.**
- Web pages are app-only **tabs** (a `WKWebView` plus an address bar, ad blocking with `WKContentRuleList`). They are **not restored** after relaunch.
- Its own split tree. Terminal and web objects live in `ProjectRuntime`, outside the SwiftUI tree, so they survive navigation.
- Notifications:
  - UN banners, a Dock badge and bounce, speech, and a menu-bar `NSStatusItem`.
  - Rate limits: 1 alert per pane per 30 s, and 10 per session per minute.
  - No alert while the user is viewing the pane.
  - "Finished" alerts are opt-in.
- No agent icons. No glass. No iOS.

---
