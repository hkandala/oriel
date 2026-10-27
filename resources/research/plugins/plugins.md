# Plugins: what a future plugin system could use

Oriel has no plugins (see `docs/content/docs/future-work/index.mdx`). These are the facts and options found for
one, so a later design starts from evidence.

## What herdr offers

- **herdr plugins** (`herdr-plugin.toml`): actions, event hooks, startup commands and terminal panes. Their
  panes are terminals only; there is no browser or graphics pane (`pane.graphics.*` was removed in 0.9).
  Details: [../multiplexers/herdr.md](../multiplexers/herdr.md).
- **A placeholder pane** can hold a plugin's place in herdr's layout: `layout.apply` starts a pane with a
  label and an inert command in one call (then `pane.move` places it). The label is the one durable
  free-form field on a pane: it survives moves and a cold restart; a metadata token does not. After a cold
  restart the pane comes back as a plain shell with its label.
- One idle placeholder costs about 110 KB in the server plus one `cat` (a shell pane costs about 166 KB in the
  server; a `cat` about 1.2 MB RSS).
- `pane.split` and `tab.create` take no command; only `layout.apply` does.
- Workspace, tab and pane ids are kept across a cold restart and never reused. A tab never changes workspace,
  so `tab_id` is the one good anchor for a slot that only the app draws.
- Rejected: a placeholder that reports itself as an agent (`resume_argv`). It survives a cold restart, but the
  pane then counts as an agent in herdr's agent list and in the tab's `agent_status`. Also rejected: a TUI
  fallback program (tig, glow) as the placeholder, because quitting it closes the pane on every device.
- Upstream watch list: issue #244 (virtual panes; the maintainer called them "too large for core" and promised
  "custom rows/surfaces"), discussions #4445 and #5421 (sidebar surfaces), #1367 (plugin panes after a
  restart).

## How to draw plugin UI

| Option | Verdict |
|---|---|
| A small web page in a `WKWebView` per card | Simplest; any web library; looks native only with care (`system-ui`, `ui-monospace`, `color-scheme`, CSS variables). A WebContent process costs 120–200 MB. |
| React in JavaScriptCore, a JSON tree drawn as SwiftUI (Raycast 1.x's model) | Fully native look; needs our own component kit, a reconciler and a build tool. Measured below. |
| A hybrid of the two (native kit with a web view escape hatch) | Both costs. |
| React Native embedded | A large dependency (react-native-macos), still needs a kit. |
| Native Swift plugins loaded at runtime | Needs the library-validation entitlement; runs in-process. |
| ExtensionKit | Needs a sandboxed extension in a notarized container app and user approval. |
| WASM components (Zed's model) | No UI; a capability model worth copying for finer permissions. |
| herdr's own TUI plugin panes | Work today as terminals; no native UI. |

Evidence behind the verdicts:

- ExtensionKit: `EXHostViewController` needs macOS 13 or iOS 26. On iOS 26 "an app can only host extensions
  that it contains". On macOS an extension must be sandboxed, shipped inside a notarized app and approved by
  the user in System Settings.
- Native plugins as dynamic libraries need `disable-library-validation` (Gatekeeper then runs extra checks) and
  module stability (`BUILD_LIBRARY_FOR_DISTRIBUTION`). Xcode 8 dropped in-process plugins for the same reasons.
- Web plugin precedents: VS Code webviews (theme CSS variables; `retainContextWhenHidden` costs much memory) and
  Figma (an iframe plus messages). VS Code deprecated its Webview UI Toolkit (2025-01-01): ship CSS variables
  and a base stylesheet, not a component library.
- Zed's capability model (`process:exec` with command and argument patterns, `granted_extension_capabilities`)
  is the one to copy if plugins ever get finer permissions.
- WebAssembly in a page needs `'wasm-unsafe-eval'` in `script-src`; a plugin can then bundle a diff engine or a
  syntax highlighter.

Raycast, the model for the native kit:

- v1 first tried one JavaScriptCore per extension in XPC, then moved to Node worker threads. The app talks to
  Node with JSON-RPC on stdio; each render tree is diffed as JSON Patch, gzipped, and drawn by AppKit.
  Sandboxing was "considered but rejected"; safety comes from open-source review.
- Raycast 2.0 draws in WKWebView with a Node backend. Memory went from 200–300 MB (v1) to 350–450 MB (v2), and
  Node costs 150–200 MB of it. Native feel took deliberate work: no `cursor: pointer`, native popovers,
  workarounds for WebKit throttling and flicker.
- Lesson: a fixed component vocabulary outlived a full renderer rewrite.

JavaScriptCore facts for the native kit:

- A `JSContext` inside an iOS app has no JIT (a measured 7.5× CPU slowdown; UI-sized work still takes about
  2 ms). Unchecked: whether the Hardened Runtime needs `com.apple.security.cs.allow-jit` on macOS.
- One `JSVirtualMachine` and one serial queue per card; suspending the queue pauses the card.
  `JSContext.isInspectable` (macOS 13.3, iOS 16.4) enables Safari's inspector.
- There is no public execution time limit or heap limit: `JSContextGroupSetExecutionTimeLimit` is private API,
  which the Developer Program License Agreement §3.3.1(A) forbids. So the kit needs a watchdog (about 3 s) that
  abandons a hung VM. Fallback: QuickJS-ng, which has `JS_SetInterruptHandler` and `JS_SetMemoryLimit`.
- Text fields must be owned by the native side, with no round trip per key.
- Prior art: react-watchos (React 19 in QuickJS drawn as SwiftUI, full-tree commits).

**Measured** (React 19 and react-reconciler in plain system JavaScriptCore, a 500-row list and a detail,
the full 80 KB JSON tree per commit, Apple Silicon): bundle 143 KB minified, 45 KB gzip; a row select 2–3 ms
with the JIT, about 2 ms without; 20 updates in a row 12–16 ms with the JIT, 41–47 ms without; about 3 MB
per JavaScriptCore context. The host config is about 60 lines; the only polyfills are `setTimeout`,
`queueMicrotask` and `console`. Full-tree commits are fine at this size; heavy work belongs on the machine.
One context made an 8.6 MB process on a 2.0 MB base; 10 contexts made 31.7 MB. The spike (react 19.3.0,
react-reconciler 0.34.0, the system `jsc` with and without `--useJIT=false`, and a Swift memory probe) is in git
at `55e4665:resources/research/plugins/plugin-system-v2-spike/`.

## Plugins on iOS

- App Store guideline 2.5.2 forbids downloaded code that "introduces or changes features".
- Guideline 4.7 allows HTML5 and JavaScript mini apps and plug-ins: no native APIs without permission (4.7.2),
  user consent (4.7.3), an index with universal links of the software offered (4.7.4; it does not apply
  without a catalog) and age gating (4.7.5).
- The Developer Program License Agreement §3.3.1(B) allows downloaded interpreted code that does not change
  the app's primary purpose, bypass OS security, or create a store.
- Enforcement: Apple pulled Anything and blocked Replit and Vibecode updates under 2.5.2 (early 2026). The
  other way: Obsidian ships community JavaScript plugins on iOS.

## How plugins reach a remote machine

| Option | Verdict |
|---|---|
| Run plain CLIs over the existing SSH connection (the relay) | Enough for git history, diffs, file views and port lists; nothing installed on the server. |
| A web page reaching the machine's `localhost` through an SSH port forward | Works without an agent; needs `AllowTcpForwarding`. |
| A bigger agent of our own over SSH stdio (cmux, Zed, VS Code style), beyond the relay | Only when latency, file watching or a server without forwarding make it necessary. |
| Plugin backends on the server, UI local | An install per machine; no gain over the agent. |
| herdr as the transport | herdr has no generic file or port API. |
| An overlay network (Tailscale) | The user's choice, not ours to require. |

Others: cmux, Zed and VS Code ship a server agent mostly to keep terminals alive or run language servers;
herdr already keeps the terminals alive, and `sshd` already reads files, runs git and forwards ports.

| Product | How it reaches remote content |
|---|---|
| VS Code | a server it uploads; ports forwarded automatically by mode: `process` (polls `/proc`), `output` (scans terminal output for URLs) or `hybrid` |
| Zed | `remote_server` in `~/.zed_server`, version-matched, uploaded over SSH |
| cmux | `cmuxd-remote`, a Go binary (~15k lines, mostly PTY persistence) uploaded with a SHA-256 check; its browser goes through SOCKS5 over the daemon's stdio, with the loopback alias `cmux-loopback.localtest.me` because WebKit bypasses proxies for loopback; ports found with a shell script over exec |
| Orca | port forwards; fails when the server refuses them |
| t3code | streams a headless Chrome from the server (~120 MB) |
| Superset | its own cloud relay |
| Coder Desktop | a WireGuard VPN |

- **A server agent, if ever needed:** generic `exec`, `spawn`, `fs.watch`, `tcp.open`, `ports.list` and
  `hello` as JSON lines over one stdio channel. Binaries for linux-x64/arm64 and darwin-x64/arm64, uploaded to
  `~/.local/share/oriel/agent/<ver>/` and SHA-256 checked, falling back to `$XDG_RUNTIME_DIR` or `/tmp` when the
  home is `noexec`. About 800–1,500 lines plus ~500 lines of Swift client. Shipping it as a herdr plugin was
  rejected: that install is interactive and global per user, so two app versions would fight over it.
- **SOCKS instead of forwards** loses the secure context (`crypto.subtle`, service workers);
  `WKWebsiteDataStore.proxyConfigurations` needs macOS 14 or iOS 17; WebKit has known proxy leaks.
- **Finding ports:** `pane.process_info`'s tty can tell which pane owns a port; `ports.list` in herdr would be a
  friendly upstream ask.
- **Open checks:** whether `ssh -W` and `-O forward` work on a ControlMaster started with
  `ClearAllForwardings=yes` (Oriel's master is); Citadel's `DirectTCPIP` API and its throughput.

## Sources

- Raycast: [How the Raycast API and extensions work](https://www.raycast.com/blog/how-raycast-api-extensions-work),
  [A Technical Deep Dive Into the New Raycast](https://www.raycast.com/blog/a-technical-deep-dive-into-the-new-raycast).
- herdr: `herdr api schema --json`, its `docs/plugins.mdx`, discussion
  [#1367](https://github.com/herdrdev/herdr/discussions/1367) (plugin panes after a restart).
- cmux: https://cmux.com/docs/ssh.
