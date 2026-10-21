# Remote content for plugins: how plugins show what lives on a remote machine

Date: 2026-10-21. Scope: research only. No repo changes.

## The short answer

- **Our design already has the right shape.** Plugins run *in the app*. Their
  data comes from the pane's machine through one primitive: run a command over
  SSH (`exec`). The web page reaches remote `localhost` through an SSH port
  forward. Nothing of ours is installed on the server (D2, D20, D24, D27).
- **Add one primitive, not a daemon.** "The one standard way" should be two
  calls on a machine, used by every plugin and pane kind:
  1. `run(argv)`: run a command, get its stdio (we have it).
  2. `dial(host, port)`: open a TCP byte stream *as seen from the machine*
     (new). SSH gives this for free: a `direct-tcpip` channel. On macOS that is
     `ssh -O forward -L` or `ssh -W`; on iOS it is one Citadel/NIOSSH call.
- With these two, the browser, git view, diff view, file view and port list all
  work on any machine, with zero install on the server.
- **Why we don't need a server agent like cmux, Orca, t3code or Zed have:** they
  ship an agent mostly to keep terminals alive (PTY persistence) or to run
  language servers. herdr already keeps our terminals alive. What is left
  (read files, run git, reach ports) is exactly what `sshd` already does.
- **Keep the agent (option B) as the planned upgrade, behind the same two
  calls.** Switch only when one of five triggers shows up (see
  [When to move to an agent](#when-to-move-to-an-agent)). The plugin API does
  not change when we switch.

Jargon used below:
- **sshd**: the SSH server program on the remote machine.
- **Channel**: one stream inside one SSH connection. A command run is a
  *session* channel. A port forward is a *direct-tcpip* channel.
- **ControlMaster**: one long-lived `ssh` process per host that other `ssh`
  runs reuse, so there is one login and one TCP connection.
- **Daemon / agent**: a small program of ours that runs on the server.
- **SOCKS proxy**: a proxy protocol where the client says "connect me to
  host:port" and the proxy does it. `ssh -D` is one.
- **Secure context**: a browser rule. Some web features (crypto.subtle,
  service workers, camera) work only on `https` or on `localhost`/`127.0.0.1`.

---

## 1. What our design says today

| Topic | What it says | Where |
|---|---|---|
| One primitive | "run a command and use its stdio" per machine; a daemon, relay or bridge of our own on the machine is *rejected* | `decisions.mdx:14` (D2), `talking-to-herdr.mdx:6-45` |
| Plugin data | `exec(argv)` runs on the card's machine only, through the base64 envelope; 30 s timeout, 4 MiB per stream, 2 at a time per machine | `plugins/api.mdx:19-23,61` |
| Plugins live where | in the app, not on machines; installed once per device | `decisions.mdx:77` (D20), `plugins/packages.mdx:49-56` |
| Core plugins | git-history, diff, markdown use only `exec` (`git diff`, `git log`, `git show`, `cat`) | `plugins/api.mdx:77-87` |
| Web page remote localhost | macOS: `ssh -S <ctl> -O forward -L 127.0.0.1:<L>:localhost:<P>` with L ≠ P; a navigation decider adds forwards for other loopback ports; content rule blocks other loopback; iOS "later" | `plugins/web-page.mdx:63-82`, `decisions.mdx:84` (D27) |
| Why not SOCKS | "WebKit never proxies loopback" | `decisions.mdx:84` |
| SSH on macOS | system `ssh`, one ControlMaster per host, forwarding off but `-O forward` still works | `machines.mdx:30-55` (D15) |
| SSH on iOS | Citadel, exec channels, Secure Enclave key | `machines.mdx:67-87` (D17) |
| Channel budget | `MaxSessions` 10 per connection; terminals, chat tails and plugin `exec` share it | `machines.mdx:96-113` |
| State | plugin instance state is a JSON file on the pane's machine | `plugins/state.mdx:25-48` (D22) |

So today the design is option A below, plus option D1 for the browser on the
Mac. The gaps are: browser on iOS, port discovery, file watching, and what to
do when the channel budget or latency hurts.

---

## 2. How others solve remote content

| Tool | What runs on the server | How the UI gets data | Browser / ports | Source |
|---|---|---|---|---|
| **VS Code Remote-SSH** | `vscode-server` (Node), per app commit, in `~/.vscode-server` | everything (fs, terminals, extensions) runs remote; UI local | Auto-forward. `remote.autoForwardPortsSource`: `process` polls `/proc` for listeners; `output` scans terminal output for URLs; `hybrid` = output to start, `/proc` to stop. Tries the same local port | code.visualstudio.com/docs/remote/ssh; github.com/microsoft/vscode/issues/180696 |
| **Zed** | headless `remote_server` binary in `~/.zed_server`, version-matched; downloaded on the server, or uploaded over SSH (`upload_binary_over_ssh`) | binary protocol over SSH stdio; ControlMaster via system `ssh` | manual `port_forwards` in settings, done with `ssh -L` | zed.dev/docs/remote-development (sections "Initializing the remote server", "Port forwarding") |
| **JetBrains Gateway** | the full IDE backend | thin client renders the backend's UI model over an SSH tunnel | IDE port forwarding | jetbrains.com/remote-development/gateway; blog.jetbrains.com/blog/2021/12/03/dive-into-jetbrains-gateway |
| **code-server / Coder** | whole web IDE (code-server) or the Coder agent | browser UI served from the server | Coder Desktop: a WireGuard VPN, every port at `<workspace>.coder:PORT`; or `coder port-forward`; or dashboard proxy | coder.com/docs/user-guides/workspace-access/port-forwarding |
| **cmux** (closest to us: native macOS, Ghostty, browser panes) | `cmuxd-remote` Go binary, uploaded on first connect to `~/.cmux/bin/cmuxd-remote/<ver>/<os>-<arch>/`, SHA-256 checked | newline JSON-RPC over SSH stdio: `proxy.*`, `session.*`, `pty.*` | Browser panes use SOCKS5 + HTTP CONNECT *through the daemon's stdio*; loopback URLs are rewritten to the alias host `cmux-loopback.localtest.me` because WebKit bypasses proxies for loopback; port list by an `ss -ltnp`/`lsof` shell script over SSH exec. iOS: an in-app SOCKS or `-L` listener whose connections are SSH `direct-tcpip` channels, no daemon | cmux.com/docs/ssh ("Browser panes", "Relay daemon"); repo `daemon/remote/README.md:1-60`; `Packages/macOS/CmuxCore/Sources/CmuxCore/Remote/RemoteLoopbackProxyAlias.swift:3-19`; `Sources/Panels/BrowserPanel.swift:4313-4338`; `Packages/macOS/CmuxRemoteSession/Sources/CmuxRemoteSession/Session/RemoteSessionCoordinator+PortScanScripts.swift:79`; `Packages/iOS/CmuxMobileSSH/Sources/CmuxMobileSSH/SSHLocalPortForward.swift:5-9` (146 lines), `SSHSocksProxy.swift:5-12` |
| **Orca** | "managed Orca server" (pinned Node runtime) on the host | its own protocol over SSH | Ports tab: scans the host for listeners, one click forwards; **fails if the SSH server refuses port forwarding** | onorca.dev/docs/ssh ("Managed Orca server", "Port forwarding") |
| **t3code** | T3 server downloaded to `~/.t3/runtime` | server API through an SSH port forward | Browser tabs are a **headless Chrome on the host, streamed** (~120 MB download) | github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md ("Desktop-managed SSH", "Browser on a remote environment") |
| **Superset** | `superset start --daemon` (HTTP server) | through **Superset Relay** (their cloud) | via the host | docs.superset.sh/remote-access |
| **Rex** (Superlogical) | sessions live on a server; clients web, macOS, iOS | own protocol | no public detail found | resources/inspirations/INSPIRATIONS.md:13 |
| **mosh / Eternal Terminal** | `mosh-server` / `etserver` | terminal only | none. cmux keeps SSH as the "management lane" even with mosh | cmux.com/docs/ssh ("Mosh terminal transport") |
| **Tailscale Serve** | `tailscaled` | — | `tailscale serve 3000` publishes `localhost:3000` on the tailnet with HTTPS | tailscale.com/docs/features/tailscale-serve |

**The pattern.** Almost everyone ships a server agent. But look at *why*:
- cmux: about 15,000 lines of Go, mostly PTY persistence and tmux emulation
  (`daemon/remote/README.md:44-70`). The proxy part is small.
- Orca, t3code, Superset: the agent *is* their session host (terminals, agents,
  chat).
- Zed, VS Code, JetBrains: the agent runs language servers, extensions and the
  file system for an editor.

We have none of those needs: herdr is the session host on every machine, and we
are not an editor. Our remaining needs are "run git/cat/ls" and "reach a port".
`sshd` already does both. Note that even cmux scans ports with a plain shell
script over SSH exec, not through its daemon.

---

## 3. What herdr 0.9.5 already gives us

Checked with `herdr --help`, `herdr api schema --json` (protocol 22, 112
methods/events) and the herdr repo docs.

Helps:
- **herdr is installed on every machine we show.** `herdr machine add`
  installs and updates herdr remotely and starts the server
  (`connecting-machines.mdx:32-56` in herdr's docs). We already rely on it
  (D16).
- **`remote-api-bridge`**: herdr's own JSON-over-stdio bridge. herdr's TUI
  remote attach does the same as option B: it forwards a local socket to the
  bridge over SSH stdio (`src/remote/attach.rs:56,3632`).
- **`pane.process_info`** returns the pane's `tty`, `shell_pid` and processes.
  That lets us scope a port scan to one pane ("ports opened by this
  terminal"), the way cmux scopes by TTY.
- **`pane.output_matched` subscription** with a regex (`OutputMatch` =
  substring or regex). That is VS Code's `output` port detection for free:
  match `https?://(localhost|127\.0\.0\.1|0\.0\.0\.0):\d+`.
- **`worktree.list`**: git worktrees for a git view without parsing.
- **Managed ControlMaster** with `ControlPersist 600` and auth recovery
  (`herdr machine status|reconnect`).
- **herdr plugins** (`herdr plugin install|link|action|pane`, manifest
  `herdr-plugin.toml` with `[[startup]]` hooks, any language). They run *on
  the server that hosts the session*: "Custom commands and plugins advertised
  by the selected server still run there" (`connecting-machines.mdx:114`).
  So a herdr plugin is a possible install vehicle for a server helper (option
  C/E).

Does not exist in herdr 0.9.5:
- no file system, exec, HTTP or TCP proxy methods in the API;
- no port detection or port forwarding;
- herdr plugins have no structured request/reply (actions are fire-and-log),
  and "native non-terminal plugin UI" is out of herdr plugin v1
  (`plugins.mdx:31-33`).

---

## 4. What plain SSH already gives us

| SSH feature | What it does | Useful for |
|---|---|---|
| exec (session channel) | run one command, stdio | `run(argv)` (today) |
| `direct-tcpip` channel | "connect to host:port from the server" | `dial(host, port)` |
| `ssh -S ctl -O forward -L 127.0.0.1:L:localhost:P` | ask the master to listen on the Mac and forward each connection | browser, macOS |
| `ssh -S ctl -O forward -D 127.0.0.1:L` | a SOCKS5 server on the Mac served by the master | browser via proxy, macOS |
| `ssh -S ctl -W host:port` | one process = one TCP stream on stdio, over the master | `dial()` on macOS without a listener |
| `-L /local.sock:/remote.sock` | Unix socket forwarding | reaching herdr's socket directly (rejected by D4) |
| Citadel / SwiftNIO SSH `DirectTCPIP` | same as `direct-tcpip` in Swift | `dial()` on iOS (cmux `SSHConnection.swift:214-220`) |

Two facts that matter:
- **Forwards do not use the session budget.** `MaxSessions` counts "shell,
  login or subsystem sessions". Debian's man page: setting it to 0 "will
  prevent all shell, login and subsystem sessions while still permitting
  forwarding" (manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html).
  So browser traffic never starves terminals.
- **Forwards need `AllowTcpForwarding yes` on the server.** That is the default,
  but some company hosts turn it off. Orca simply fails there. cmux survives,
  because its proxy runs inside the daemon's stdio. This is a real reason for
  option B later.

---

## 5. The options

Each option says how these four work: **browser** (remote `localhost:3000`),
**git view**, **diff view**, **file view**.

### Option A: per-call SSH exec of plain CLIs (today's design)

The app runs `git`, `cat`, `ls`, `herdr`, `ss` on the machine, one SSH session
channel per call, and parses the output.

- **Browser:** not covered by exec. Needs option D.
- **Git view:** `git log --format=…`, `git show`, `git status --porcelain=v2`,
  `worktree.list` from herdr.
- **Diff view:** `git diff --no-color <base>`; refresh on the herdr snapshot
  (agent finished) plus a Refresh action. Already designed.
- **File view:** `ls -la`/`find -maxdepth 1` for a tree level, `cat` or
  `head -c` for text, `base64 <file>` for images. Large trees need many calls.
- **Port list:** Linux `ss -ltnpH`, macOS `lsof -nP -iTCP -sTCP:LISTEN`,
  optionally scoped to the pane's `tty` from `pane.process_info`.
- **Install/upgrade:** nothing. Needs `sh`, `base64` and the tools themselves.
- **Security:** no listener anywhere; nothing new on the server; exec is
  already the one honest permission (D25).
- **Offline/reconnect:** stateless. Each call fails or succeeds on its own;
  after reconnect the next call just works.
- **iOS:** Citadel exec channels; Spike S7 already covers it.
- **Effort:** done in the design. Port scan about 100 lines.
- **Weak spots:** about one extra round trip per call plus a local `ssh`
  process on macOS (fine for diff refresh, slow for a file tree on a 150 ms
  link); every call takes a session from the budget of 10; no push file
  watching (you can run `inotifywait`/`fswatch` as a long exec, but they are not
  installed everywhere); POSIX `sh` only (herdr supports Windows servers; our
  envelope does not).
- **Ponytail:** best. It already exists.

*Variant A+: one long-lived shell runner.* Send a 30-line `sh` loop on connect
that reads `id base64-command` lines and prints `id base64-output` lines. One
session for all plugin calls, no install. But it is serial, base64 doubles
output size, and framing bugs are easy. Only worth it if the budget hurts before
we want option B. I would skip it.

### Option B: our own small agent over SSH stdio (cmux, Zed, VS Code style)

A static binary `oriel-agent` (Go or Rust, about 3–5 MB) runs as
`oriel-agent serve --stdio` on one SSH exec channel. It speaks JSON lines (like
herdr's bridge) and multiplexes many requests and streams on that one channel.

Keep it generic. No git logic inside, so plugins stay in the app:
- `exec {argv, cwd, stdin}` → `{code, stdout, stderr}` (same contract as today)
- `spawn` + `stream.data/eof` for long-lived processes
- `fs.watch {paths}` → change events (inotify / FSEvents)
- `tcp.open {host, port}` + `stream.*` → the browser proxy (works even with
  `AllowTcpForwarding no`)
- `ports.list` → listeners with pid and tty
- `hello` → version and capabilities

- **Browser:** the app runs a local SOCKS5/CONNECT broker (or a per-port
  listener) and pushes bytes through `tcp.open`, like cmux.
- **Git / diff / file view:** same `git`/`cat` commands, now through
  `exec` on the agent: no new channel, no local process per call. File view
  and diff view get live refresh from `fs.watch`.
- **Install/upgrade:** the app carries binaries for linux-x64, linux-arm64,
  darwin-arm64, darwin-x64. On connect: `uname -sm`, check
  `~/.local/share/oriel/agent/<version>/oriel-agent`, else upload it through
  `exec` stdin (`cat > tmp && mv`), check SHA-256, `chmod +x`. One version
  per app build; old versions deleted later. Fallbacks for `noexec` home
  directories: `$XDG_RUNTIME_DIR` or `/tmp`. Zed also offers "download on the
  server" from a URL; we need not.
- **Security:** no network listener (stdio only, unlike code-server). Lives
  only as long as its SSH channel. No persistence, no token files, because
  herdr already holds the sessions. That makes it far smaller than cmux's
  daemon (no PTY, no Unix socket, no auth lease).
- **Offline/reconnect:** the agent dies with the channel. On reconnect: start
  it again, send `hello`, re-subscribe watches, reopen proxies. In-flight calls
  fail and plugins retry (they already handle a failed `exec`).
- **iOS:** one Citadel exec channel with stdio, same as the herdr bridge. The
  iOS bundle would carry ~15–20 MB of Linux/macOS binaries as plain data. They
  never run on the phone, so guideline 2.5.2 should not apply, but it is extra
  size and a review question. Alternative on iOS: the Mac or a GitHub release
  URL, fetched by `curl` on the server.
- **Effort:** agent 800–1,500 lines + Swift multiplexing client ~500 lines +
  cross-builds, signing (a macOS binary uploaded to a Mac needs notarization or
  `xattr` care; uploaded via `cat`, it gets no quarantine flag) and an upload
  path. About 2–4 weeks, then ongoing upkeep across OS and arch.
- **Ponytail:** not yet. It is the right v2, and the API stays the same.

### Option C: plugin backends run on the server (plugin UI local)

A plugin may ship a `backend/` (any language) that the app uploads and runs on
the machine as a long-lived process; the plugin UI talks to it by JSON lines.
JetBrains Gateway is the extreme form (whole IDE backend remote).

- **Browser:** unchanged (D or B).
- **Git / diff / file view:** a plugin could keep an index, watch files or
  run a language tool near the data, and send only results.
- **Install/upgrade:** per plugin, per machine, per version. Needs the runtime
  (Node, Python) on the server unless the backend is a static binary. herdr
  plugins could be the vehicle (`herdr plugin install`, `[[startup]]` hooks),
  but herdr's install asks interactively, runs builds on the server and
  installs per user, not per Oriel plugin version.
- **Security:** plugin code runs on the server as the user. Same power as
  `exec`, but now it also *persists* there and outlives consent changes.
- **Offline/reconnect:** each backend reconnects on its own; version skew
  between the plugin UI and its backend.
- **iOS:** the phone would have to upload code it does not run. Fine
  technically, awkward for review.
- **Effort:** a `spawn` API (cheap) plus upload, versioning and cleanup
  (not cheap). Ongoing support burden per plugin.
- **Ponytail:** no for v1. It reverses D20 ("no setup on any machine"). The
  cheap piece worth keeping in mind: a streaming `spawn(argv)` in the plugin
  API lets a plugin run its own remote helper later *if it ships one*, without
  any new machinery from us.

### Option D: the browser through SSH forwarding (no agent)

Four ways to show remote `localhost:3000` in the web card:

| | How | Origin the page sees | Secure context | Remote internal hosts (`staging.internal`) | iOS | Work |
|---|---|---|---|---|---|---|
| **D1. `-L` per port** (today, macOS) | `ssh -O forward -L 127.0.0.1:L:localhost:P`; load `127.0.0.1:L` | `127.0.0.1:L` (port changes unless L = P) | yes (loopback) | no | in-app `NWListener` on `127.0.0.1:P` + one `direct-tcpip` channel per accepted connection (cmux: 146 lines) | small |
| **D2. SOCKS + alias host** (cmux) | `ssh -O forward -D` or an in-app SOCKS front; set `WKWebsiteDataStore.proxyConfigurations` (macOS 14 / iOS 17); rewrite `localhost` to an alias host so WebKit does not bypass the proxy | `alias:3000` (port kept, host changes) | **no** (plain http on a non-loopback name) | **yes**, the whole remote network | in-app SOCKS server → `direct-tcpip` (cmux: 85 lines + shared SOCKS code) | medium; URL rewriting is the hard part |
| **D3. Remote headless browser, streamed** (t3code) | Chrome on the server, frames to the app | real `localhost:3000` | yes | yes | yes | large; 120 MB Chrome per server; no native feel |
| **D4. Overlay network** (option F) | load `http://devbox:3000` or a `tailscale serve` URL directly | `devbox:3000` | only with `tailscale serve` HTTPS | yes | yes, natively | none in the app |

My view on each:
- **D1 is the right v1.** It is one command on macOS, it keeps a secure context,
  and it does not touch the session budget. One change worth reconsidering in
  D27: **use L = P when the Mac's port P is free** (VS Code does this). Then
  the page's origin is exactly `localhost:3000`: OAuth callbacks registered
  for `localhost:3000`, CORS allow lists and hard-coded absolute URLs keep
  working. Fall back to another port only when P is taken. The cost: a Mac dev
  server started later on P fails to bind, so the app must list its forwards
  and let the user stop one. On iOS, L = P is always free, so the phone gets
  the exact origin.
- **D2** is worth it only when users need the remote's *network* (internal
  hosts only the server can reach, or many ports with cross-port links).
  Loss of secure context breaks `crypto.subtle` and service workers on http dev
  servers, which modern frameworks use. Also, the alias host
  `cmux-loopback.localtest.me` depends on DNS on the server unless our own
  SOCKS front maps it, and WebKit has known proxy leaks
  (mysk.blog/2026/08/04/webkit-proxy-icloud-private-relay-ip-leak). Later, not
  v1.
- **D3**: no. Heavy, and the opposite of a native app.
- The design's claim "WebKit never proxies loopback" is confirmed by cmux: it
  had to invent the alias host (`RemoteLoopbackProxyAlias.swift:3-11`).

**Port discovery for any D option** (from VS Code and cmux):
- *Output:* subscribe to `pane.output_matched` with a URL regex on terminal
  panes of the selected tab, or scan the screen text we already read for the
  chat view. Show an "Open localhost:3000" chip on the terminal card.
- *Process:* run `ss -ltnpH` / `lsof -nP -iTCP -sTCP:LISTEN` via exec when the
  pane picker or a web card opens, and after snapshot events, never on a timer
  while nothing is visible. Use `pane.process_info.tty` to say which pane owns
  the port.
- Close a forward when its last web card closes (already in the design).

### Option E: piggyback on herdr

Three forms:
1. **herdr's socket over SSH** (`-L` Unix socket forward, or the bridge we
   already use). Gives only herdr's API, which has no fs/exec/proxy. Rejected
   in D4, and it would not help plugins anyway.
2. **Ask herdr upstream** for generic methods (`fs.read`, `exec`, `tcp.open`,
   `ports.list`). Then `remote-api-bridge` would be our agent, already
   installed and updated by `herdr machine add`. Best install story of all. But
   herdr's stated direction is a lean core with plugins for workflows
   (`plugins.mdx:13-16`), the bridge answers one request per connection, and we
   would depend on another project's roadmap. Worth one friendly issue for
   `ports.list` (useful for herdr's own TUI too), not worth waiting for.
3. **Ship our agent (option B) as a herdr plugin.** `herdr plugin install`
   handles download, versions, enable/disable and cleanup; a `[[startup]]` hook
   could even start it. But install asks interactively, runs builds on the
   server, and plugins are global per user, so two Oriel versions on two
   devices would fight over one installed version. Uploading our own binary is
   simpler and is what cmux, Zed and VS Code do.

- **Ponytail:** use what herdr already gives (process info, output match,
  worktrees, ControlMaster). Do not build on herdr plugins.

### Option F: an overlay network (Tailscale and friends)

If the Mac or phone and the server share a tailnet, the web card can load
`http://devbox:3000` directly. `tailscale serve --bg 3000` (run by the user,
or by us through exec) publishes a loopback-only dev server with HTTPS on the
tailnet name. Coder Desktop does the same with its own WireGuard VPN
(`<workspace>.coder:PORT`).

- **Browser:** works on Mac and iOS with no app code, no SSH in the path, and
  it survives app backgrounding on iOS. But most dev servers bind only to
  `localhost` (Vite does by default), so without `serve` you see nothing.
- **Git / diff / file view:** not covered. Still exec over SSH.
- **Install:** the user's choice; we cannot require it.
- **Security:** tailnet ACLs; Serve stays inside the tailnet (Funnel is the
  public one, never use it here).
- **Ponytail:** zero code. Support it by accepting any `http(s)` address in the
  web card (already true) and maybe a "Share on tailnet" action later. Not the
  standard way.

---

## 6. Side by side

| | A: exec CLIs | B: agent over stdio | C: remote plugin backends | D1: `-L` forwards | E: herdr | F: overlay |
|---|---|---|---|---|---|---|
| Browser remote localhost | no (needs D) | yes (proxy in agent) | no | **yes** | no | yes if bound or served |
| Git / diff view | **yes** | yes, faster | yes | no | partly (`worktree.list`) | no |
| File view | yes (many calls) | **yes, with watch** | yes | no | no | no |
| Port list | yes (`ss`/`lsof`) | yes | — | — | output match + process info | — |
| Server install | **none** | upload binary per version | per plugin | **none** | none (already there) | user's VPN |
| Works with `AllowTcpForwarding no` | yes | **yes** | yes | no | yes | yes |
| Session budget use | 1 per call | **1 total** | 1 per backend | **0** | 1 per call | 0 |
| Reconnect | **trivial** | restart and resubscribe | per backend | re-add forwards | trivial | n/a |
| iOS | Citadel exec | Citadel exec + bundled binaries | awkward | in-app listener + `direct-tcpip` | Citadel exec | native |
| Windows servers | no (needs `sh`) | yes if we build it | maybe | yes | yes | yes |
| Effort | done | 2–4 weeks + upkeep | large + upkeep | days | issue upstream | none |
| Ponytail | ★★★ | ★ (v2) | ✗ | ★★★ | ★★ (use what exists) | ★★ (free) |

---

## 7. Recommendation

### The one standard way

Every pane kind and plugin reaches its machine through one Swift type with two
calls. This is the "common socket API" the user asked for, but it lives in the
app, and the server side is plain `sshd` + POSIX tools + herdr:

```swift
protocol Exec {                       // exists today
    func run(_ argv: [String]) async throws -> Channel
    func dial(host: String, port: Int) async throws -> Channel   // new
}
```

- `run`: macOS `Process` + `ssh -S ctl`; iOS Citadel exec channel. Already
  designed.
- `dial`: macOS `ssh -S ctl -O forward -L` for the browser (one command), or
  `ssh -S ctl -W host:port` when a stream is needed in Swift; iOS Citadel/NIOSSH
  `DirectTCPIP` channel. A shared helper turns `dial` into a local listener
  for the web view (`127.0.0.1:P` on iOS; on macOS `-O forward` already is
  one).
- The plugin JavaScript API does **not** change: plugins keep `exec`. They do
  not get `dial` or raw network in v1 (D24, D25 stay true). Only the native web
  plugin uses `dial`.

### What v1 should do (minimal)

1. **Keep option A for git, diff, markdown and file data.** No server install.
2. **Web page on macOS: D1 as designed, plus "same port when free"** (revisit
   D27's L ≠ P rule). List active forwards in the web card menu with Stop.
3. **Web page on iOS: D1 through `dial`.** An in-app `NWListener` on
   `127.0.0.1:P` whose accepted connections each open a `direct-tcpip`
   channel. This closes the "iOS later" gap in `web-page.mdx:81-82`. Add it
   to Spike S7 (test Citadel's `DirectTCPIP` next to its exec channels). Note
   the iOS background rule: listeners stop with the app, like terminal streams.
4. **Port discovery, cheap:** `pane.output_matched` on the selected tab's
   terminal panes for `localhost:\d+` URLs → an "Open :3000" chip that creates a
   web pane on the same machine. A `ss`/`lsof` exec only when the user opens
   the picker's "Ports" list.
5. **Tell users F works**: any tailnet address loads directly; nothing to build.
6. **Do not build** an agent, remote plugin backends, a SOCKS proxy or a
   streamed browser in v1.

### When to move to an agent

Build option B (generic `exec`, `spawn`, `fs.watch`, `tcp.open`, `ports.list`
over one stdio channel, uploaded binary, no persistence) when one of these is
real, not before:

1. **Budget:** cards show "no session · Retry" because terminals, chat tails
   and plugin calls exceed `MaxSessions` on busy tabs.
2. **Latency:** a plugin needs many small calls (file tree, search) and users
   on slow links feel it.
3. **Watching:** a plugin needs push file changes, not snapshot-driven refresh.
4. **Locked-down hosts:** users hit `AllowTcpForwarding no`.
5. **Windows servers:** herdr supports them; our `sh` envelope does not.

Because `Exec` hides the transport, the switch is an implementation change in
`ProcessExec`/`CitadelExec`. Plugins, labels, state files and the web card stay
the same. Keep the agent small by refusing what herdr already does (PTYs,
sessions, persistence); that is what made cmux's daemon 15,000 lines.

### Open questions for spikes

- Citadel's `DirectTCPIP` API and throughput on iOS 26 (cmux uses raw
  swift-nio-ssh: `SSHConnection.swift:214-220`).
- `ssh -O forward -L` with `ClearAllForwardings=yes` on the master: the design
  says app-requested forwards still work; confirm on OpenSSH 10.3 (local
  version).
- Cost of `pane.output_matched` subscriptions per pane in herdr (D5 notes that
  per-pane status subscriptions cost a 100 ms poll each).
- How often real dev servers hard-code `localhost:<port>` absolute URLs or
  OAuth callbacks (decides whether "same port when free" is enough).

---

## Sources

Our repo:
- `docs/content/docs/decisions.mdx:14,16,29,31,77,81,82,84`
- `docs/content/docs/plugins/api.mdx:19-23,61,73-87`
- `docs/content/docs/plugins/web-page.mdx:63-82`
- `docs/content/docs/plugins/security.mdx:6-13`
- `docs/content/docs/plugins/state.mdx:25-48`
- `docs/content/docs/plugins/packages.mdx:49-56`
- `docs/content/docs/machines.mdx:30-55,67-87,96-113`
- `docs/content/docs/talking-to-herdr.mdx:6-45`
- `resources/research/plugins/plugin-architecture.md:360-370` (remote host data row)

herdr 0.9.5 (local CLI) and github.com/herdrdev/herdr (cloned to
`/tmp/oriel-brainstorm/repos/herdr`):
- `herdr --help`, `herdr machine --help`, `herdr plugin --help`,
  `herdr api schema --json` (protocol 22; `pane.process_info` with `tty` and
  `shell_pid`; `pane.output_matched` with `OutputMatch` regex; `worktree.list`)
- `docs/next/website/src/content/docs/plugins.mdx:6-33`
- `docs/next/website/src/content/docs/connecting-machines.mdx:14-16,32-56,114`
- `src/remote/attach.rs:56,3632`

cmux (github.com/manaflow-ai/cmux, cloned to `/tmp/oriel-brainstorm/repos/cmux`):
- https://cmux.com/docs/ssh, https://cmux.com/blog/cmux-ssh
- `daemon/remote/README.md:1-70`
- `Packages/macOS/CmuxCore/Sources/CmuxCore/Remote/RemoteLoopbackProxyAlias.swift:1-30`
- `Sources/Panels/BrowserPanel.swift:4313-4338`
- `Packages/macOS/CmuxRemoteSession/Sources/CmuxRemoteSession/Session/RemoteSessionCoordinator+PortScanScripts.swift:1-80`
- `Packages/iOS/CmuxMobileSSH/Sources/CmuxMobileSSH/SSHLocalPortForward.swift:1-36`
- `Packages/iOS/CmuxMobileSSH/Sources/CmuxMobileSSH/SSHSocksProxy.swift:1-30`
- `Packages/iOS/CmuxMobileSSH/Sources/CmuxMobileSSH/SSHConnection.swift:214-220`

Others:
- VS Code: https://code.visualstudio.com/docs/remote/ssh,
  https://code.visualstudio.com/docs/debugtest/port-forwarding,
  https://github.com/microsoft/vscode/issues/180696
- Zed: https://zed.dev/docs/remote-development
- JetBrains: https://www.jetbrains.com/remote-development/gateway/,
  https://blog.jetbrains.com/blog/2021/12/03/dive-into-jetbrains-gateway/
- Coder: https://coder.com/docs/user-guides/workspace-access/port-forwarding
- Orca: https://www.onorca.dev/docs/ssh
- t3code: https://github.com/pingdotgg/t3code/blob/main/docs/user/remote-access.md
- Superset: https://docs.superset.sh/remote-access
- Tailscale: https://tailscale.com/docs/features/tailscale-serve
- OpenSSH: `man ssh` (`-O forward`, `-W`), https://man7.org/linux/man-pages/man5/sshd_config.5.html,
  https://manpages.debian.org/trixie/openssh-server/sshd_config.5.en.html
- SwiftNIO SSH channel types: https://swift.org/blog/swiftnio-ssh/
- WebKit proxy leaks: https://mysk.blog/2026/08/04/webkit-proxy-icloud-private-relay-ip-leak/
