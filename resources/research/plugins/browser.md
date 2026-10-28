# Browser pane: WebKit, the foundation and remote

Facts behind the browser pane (`docs/content/docs/future-work/web-page.mdx`), the first pane kind on the plugin
foundation (`future-work/plugins/`). Spikes ran on an Apple Silicon Mac with macOS 27.0.1, Xcode 27.1, Swift 6.4,
herdr 0.9.5 and OpenSSH 10.3, in a small ad-hoc signed app (`WKWebView`, no sandbox).

## WKWebView

- **Stores:** `WKWebsiteDataStore(forIdentifier:)` (macOS 14) keeps a persistent store per UUID under
  `~/Library/WebKit/<bundle id>/WebsiteDataStore/<uuid>/` (Cookies, LocalStorage, IndexedDB, CacheStorage,
  NetworkCache, HSTS, service workers). Nine stores with cookies set and read showed no keychain prompt
  (no `SecurityAgent`): WebKit uses no keychain key for website data. Only credentials saved as
  `URLCredential` `.permanent` go to the keychain.
- **Proxy per store:** `proxyConfigurations = [ProxyConfiguration(socksv5Proxy: .hostPort(...))]` is a store
  property in memory; set it before the first load.
- **Inspector:** `isInspectable` (macOS 13.3) is public and makes the page show in Safari's Develop menu.
  Showing the inspector from the app has no public API. `-[WKWebView _inspector]` returns a `_WKInspector`
  (`show`, `hide`, `attach`, `detach`, `connect`); in a background spike app that was never activated, `show` (with
  `developerExtrasEnabled`) opened no window. cmux ships `_inspector` docking, so check it in the running app.
  Headers: `_WKInspector.h`, `WKWebViewPrivate.h` in https://github.com/WebKit/WebKit.

## Remote pages

| Address loaded through a SOCKS proxy (store setting) | Went through the proxy | `isSecureContext` |
|---|---|---|
| `http://localhost:8731` | no, also with a dead proxy and with `matchDomains = ["localhost"]` | true |
| `http://127.0.0.1:8731`, `http://[::1]:8731`, `http://localhost.:8731` | no | true, —, false |
| `http://app.localhost:8731` | yes (`CONNECT app.localhost:8731`; a dead proxy fails it) | true |
| `http://example.com` | yes | false |
| `http://devbox.localhost:8731` through `ssh -O forward -D` on a ControlMaster | yes, end to end | true |

- So WebKit never proxies loopback names, but proxies `<name>.localhost` and keeps it secure. SOCKS5 passes the
  name; the server resolves it: macOS resolves `*.localhost` to loopback (`dscacheutil`), and so does Linux with
  systemd (`nss-myhostname`, `systemd-resolved`). Without them a small SOCKS listener in the app could map
  `*.localhost` to `localhost` and dial through `ssh -W`.
- On a ControlMaster started with `ClearAllForwardings=yes`, `-O forward -D`, `-O forward -L` and `-W` all work.
- Two machines never clash: each has its own local SOCKS port, the page's port travels inside the request, and
  each machine's pages have their own name and store. A forward per port would clash when two machines (or the
  Mac) serve the same port.
- Vite allows `*.localhost` hosts by default; OAuth callbacks and CORS lists for `localhost:3000` need the name.

## The pane in herdr

- `layout.apply` with a label and a `sh -c` placeholder, then `pane.move` into a split: works. After
  `session stop` and a start the label is back, the terminal id is new and the process is a plain shell.
- The placeholder (about 20 lines of `sh`): centers its text from `stty size`, redraws on `SIGWINCH`, runs
  `stty raw -echo` and a background `cat <&0 >/dev/null` (a non-interactive shell gives background jobs
  `/dev/null` as stdin unless redirected), and waits on it. Ctrl-C, Ctrl-D, Ctrl-Z, Ctrl-\ and Enter did not end it.
- A TUI client attached to the session (run in a pane of a second throwaway session, read with `pane.read`)
  showed the label in the border, cut to fit, and the placeholder's text centered.
- `pane.report_metadata {title}` replaces the label in the TUI border until the server restarts.

## Agents and the browser

- WKWebView has no DevTools protocol. `safaridriver` drives Safari only (one session, "Allow Remote Automation"),
  not an app's web view. Playwright's WebKit is its own build, not the system view.
- Agents that need a browser run their own on their machine (Playwright MCP, chrome-devtools-mcp, Browser Use),
  next to the dev server; that needs nothing from Oriel.
- A later option: an agent asks the app through a pane metadata token (as pi-hkandala's copy requests do) to read,
  run script in or capture one card; the app answers with a file on the machine. Opt-in per card.

## Considered: Chromium through CEF

Built and measured (CEF 156.0.14, Chromium 156.0.8078.48, arm64), not chosen for its size.

- A SwiftUI app hosted a CEF child `NSView` (Alloy style) under a glass header, with SwiftUI overlays over it.
  The shim was 279 lines of Objective-C++ plus a 35-line header. SwiftUI ignores `NSPrincipalClass`; creating
  CEF's `NSApplication` subclass in `App.init()` worked. `external_message_pump` with timers in common modes.
- Cost: +330 MB app (framework 333 MB, five helpers), 148 MB zipped, no universal build; footprint 195–281 MB for
  the first page, +70–80 MB per view, 553–639 MB with DevTools open; a CEF branch about every 4 weeks.
- DevTools: undocked worked; docked crashed on a CEF check (DevTools are always Chrome style). A workaround needed
  the remote debugging port, which any local process can use.
- Stock CEF reads the shared "Chromium Safe Storage" keychain item: a password prompt held every request.
- A `CefRequestContext` per machine with `SetPreference("proxy", … "<-loopback>")` carried `localhost` through
  SOCKS. The setting persisted in the profile, and the global context followed another context's proxy.
- Others: CefSwift (pure Swift over CEF's C API, ~8,000 lines); Atlas ran Chromium out of process with private
  `CALayerHost`; VS Code's browser is Electron with a scoped DevTools-protocol proxy; Zed, Warp and Ghostty have no
  browser. Sources: https://chromiumembedded.github.io/cef/general_usage, CEF issue
  [#3685](https://github.com/chromiumembedded/cef/issues/3685), https://openai.com/index/building-chatgpt-atlas/.

## Open questions

- Whether `_WKInspector` `show` opens Web Inspector from the running app.
- Servers that cannot resolve `*.localhost`: how common, and whether the app's own SOCKS listener is worth it.
- Public sites in a remote machine's card: all through the machine (chosen), or direct.
