# Browser pane: engine, foundation and remote

Facts and measurements for the browser pane (`docs/content/docs/future-work/web-page.mdx`), the first pane kind
on the plugin foundation (`future-work/plugins/`). Spikes ran on an Apple Silicon Mac with macOS 27.0.1, Xcode
27.1, Swift 6.4, CEF 156.0.14 (Chromium 156.0.8078.48), herdr 0.9.5 and OpenSSH 10.3.

## Engines compared

| Option | DevTools | Cost | Verdict |
|---|---|---|---|
| CEF, a child `NSView` per card (Alloy style) | Chrome DevTools; undocked native, docked through a bridge | +330 MB app (arm64), 190–280 MB for the first page | chosen |
| CEF, off-screen rendering | DevTools only in a CEF window | the app redoes input, IME, accessibility; open macOS bugs | no |
| CefSwift (pure Swift over CEF's C API) | as CEF | ~8,000 lines from one author, a CEF version behind | watch; borrow its pump and bundling |
| WKWebView + Safari Web Inspector | Safari's, docked only through private `_inspector` (cmux does this) | ~50 MB per view; same engine on iOS | plugin cards; fallback |
| Real Chrome over the DevTools protocol, screencast frames | Chrome's frontend | JPEG frames (~5 fps reported), input re-sent, no IME | agents only |
| Real Chrome `--app` window | full | not a pane | no |
| Own Chromium build (Arc and Dia's ADK, Atlas's OWL) | full | ~150 GB checkout, a team (The Browser Company ~65 people) | no |
| Electron, Tauri | Electron's | not a Swift app; Tauri is WKWebView | no |

Others: VS Code's integrated browser is Electron with a scoped DevTools-protocol proxy for agents (the design to
copy for agent access). JetBrains ships JCEF. Spotify, Steam and OBS ship CEF and pin a version for months
(Spotify on 146, OBS jumped 127 → 150). Atlas ran Chromium out of process and drew it with private
`CALayerHost`. Zed, Warp and Ghostty have no browser.

## CEF facts

- **Versions:** CEF follows Chrome's even milestones, a branch about every 4 weeks; security builds trail Chrome by
  2–3 days; branch 150 is the long-term one. Docs: https://chromiumembedded.github.io/cef/branches_and_building.
- **Style:** since CEF 128 every browser picks Alloy or Chrome style. On macOS a child view (`SetAsChild`) is
  always Alloy style (no `chrome://` pages, no extensions). DevTools are always Chrome style
  (`chrome_browser_delegate.cc`: `CHECK(IsChromeStyle())`).
- **DevTools:** `ShowDevTools` with an empty `CefWindowInfo` opens Chromium's DevTools window, no port: works.
  `ShowDevTools` with `SetAsChild` (docked) crashes on that check. Docked worked by loading
  `http://127.0.0.1:<port>/devtools/inspector.html?ws=…/devtools/page/<targetId>` in a second child view, but that
  needs the remote debugging port (no authentication: any local process can drive every page) and shows a
  screencast pane. `SendDevToolsMessage`, `ExecuteDevToolsMethod` and `AddDevToolsMessageObserver` speak the
  protocol in process without a port. Unchecked: whether a child view can load `devtools://devtools/bundled/`.
- **SwiftUI:** SwiftUI ignores `NSPrincipalClass` and makes its own `SwiftUI.AppKitApplication`. Creating CEF's
  `NSApplication` subclass in `App.init()` (while `NSApp` is nil) makes SwiftUI adopt it; windows, menus and glass
  worked. SwiftUI `.overlay` views draw over the CEF view.
- **Run loop:** `external_message_pump`; `OnScheduleMessagePumpWork` schedules one-shot `NSTimer`s in common modes
  that call `CefDoMessageLoopWork`, plus a 1/30 s safety timer. No stalls with 3 views or DevTools.
- **Loading:** `CefScopedLibraryLoader`; `browser_subprocess_path` to one helper. Without `root_cache_path` CEF
  shares `~/Library/Application Support/CEF/User Data` with other CEF apps.
- **Signing:** ad hoc, inside out, hardened runtime. `allow-jit` is needed (renderers die without it);
  `disable-library-validation` is needed only without a Team ID; `allow-unsigned-executable-memory` was not
  needed. No Mac App Store path is known (https://magpcss.org/ceforum/viewtopic.php?f=6&t=16215).
- **Keychain:** stock CEF reads the shared "Chromium Safe Storage" item. macOS showed a password prompt, and every
  request waited behind it. `--use-mock-keychain` avoids it; a shipped app needs its own item.
- **Profiles and proxies:** a `CefRequestContext` per machine with its own `cache_path`, and
  `SetPreference("proxy", {mode:"fixed_servers", server:"socks5://127.0.0.1:<P>", bypass_list:"<-loopback>"})`
  at runtime, worked: the SOCKS log showed `CONNECT localhost:8765` for one machine, and the other went direct.
  Traps: the setting is saved in the profile and survives a relaunch; browsers in the global context followed
  another context's proxy; Chromium's background requests (component updates, autofill) went through the proxy.
- **The shim:** 279 lines of Objective-C++ plus a 35-line header (one `NSView` class, the `NSApplication`
  subclass, the runtime), Swift 6 mode clean with `NS_SWIFT_UI_ACTOR`.
- Not tested (no input may be sent on the user's Mac): typing, IME, trackpad, VoiceOver, popups, clean quit,
  sleep and wake, Developer ID notarization.

| Measured (`footprint`, all processes) | Processes | Memory |
|---|---|---|
| 1 view: `about:blank` / example.com / MDN | 6 | 195 / 224 / 281 MB |
| 3 views of MDN in 3 profiles | 8 | 426 MB |
| MDN with DevTools undocked / docked | 7 | 553 / 639 MB |

Bundle: framework 333 MB (binary 233 MB, 220 locale folders 50 MB, SwiftShader 16 MB), five helpers (Helper, GPU,
Renderer, Plugin, Alerts) at 636 KB each; 148 MB zipped. No universal build (about +230 MB for x86_64). Build:
37 s for the wrapper and sample with CMake and Ninja, 10 s for the Swift app and shim.

## The pane in herdr

- `layout.apply` with a label and a `sh -c` placeholder, then `pane.move` into a split: works on 0.9.5. After
  `session stop` and a start the label is back and the process is a plain shell.
- The placeholder (about 20 lines of `sh`): centers its text from `stty size`, redraws on `SIGWINCH`, runs
  `stty raw -echo` and a background `cat <&0 >/dev/null` (a non-interactive shell gives background jobs
  `/dev/null` as stdin unless redirected), and waits on it. Ctrl-C, Ctrl-D, Ctrl-Z, Ctrl-\ and Enter did not end it.
- A TUI client attached to the session (run inside a pane of a second throwaway session and read with
  `pane.read`) showed the label in the border, cut to fit, and the placeholder's text centered.
- `pane.report_metadata {title}` replaces the label in the TUI border until the server restarts.
- `pane.read` returns no OSC 8 hyperlinks, so an OSC 8 link in the placeholder cannot be checked; herdr's own
  URL detection covers a plain URL.

## Remote pages

- On a ControlMaster started with `ClearAllForwardings=yes`, `-O forward -D`, `-O forward -L` and `-W` all work
  (OpenSSH 10.3, an unprivileged sshd on a high port).
- Chrome 156 with `--proxy-server=socks5://… --proxy-bypass-list=<-loopback>` loaded `http://localhost:<port>`
  through `ssh -D` with `isSecureContext` true. With a dead proxy and `<-loopback>` the page failed; with a dead
  proxy and the default bypass it loaded directly. So loopback really goes through the proxy.
- Chromium's SOCKS5 client always sends the host name (`kEndPointDomain`), so the machine resolves `localhost`.
  `<-loopback>` works only with fixed proxy servers, not PAC scripts
  (https://chromium.googlesource.com/chromium/src/+/HEAD/net/docs/proxy.md).
- WebKit has no implicit loopback bypass, and its WebSockets do not always follow `proxyConfigurations` (cmux's
  notes), so the iOS app keeps per-port listeners.
- An agent-facing DevTools endpoint (chrome-devtools-mcp, Playwright MCP and Browser Use need only one): bind to
  `127.0.0.1`, require a token, share one page at a time; `ssh -R` exposes it to every user on the machine.

## Mock-up directions

- A: the card header is the toolbar (Back, Forward, Reload, the address with a machine chip, DevTools, the card
  buttons); DevTools docked under or beside the page. Recommended.
- B: a quiet header like a terminal card's (favicon, title, host); ⌘L opens a glass address field over the page
  with history and the machine's ports.
- C: the browser in a floating pane window, DevTools in Chromium's own window.
- The herdr TUI: "Browser", the address and "Shown in Oriel" centered, the label in the border.

## Open questions

- Docked DevTools without an open port: the bundled frontend in a child view, or ship the frontend files.
- Ship CEF in the app (+330 MB) or download the pinned engine on first use.
- CEF's browser process runs in the app; Atlas moved Chromium out of process with private `CALayerHost`.
- Public sites in a remote machine's card: all through the machine (chosen), or a PAC script with local egress.
- Chrome extensions (React DevTools) are not available in Alloy style.

## Sources

- CEF: https://chromiumembedded.github.io/cef/general_usage, issue
  [#3685](https://github.com/chromiumembedded/cef/issues/3685) (styles), builds at https://cef-builds.spotifycdn.com.
- CefSwift: https://github.com/Rajaniraiyn/CefSwift. Atlas: https://openai.com/index/building-chatgpt-atlas/.
- WebKit inspector private API: `_WKInspector.h`, `WKWebViewPrivate.h` in https://github.com/WebKit/WebKit.
- Chrome 136 debugging-port change: https://developer.chrome.com/blog/remote-debugging-port.
- VS Code integrated browser: https://code.visualstudio.com/docs/debugtest/integrated-browser.
