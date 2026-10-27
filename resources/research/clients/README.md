# herdr clients

One file per client of herdr (and two near relatives), with how it talks to herdr, draws terminals, lays out
panes and handles remote machines. How herdr itself works is in [../multiplexers/herdr.md](../multiplexers/herdr.md);
the client files say only what each one uses.

## Native macOS

| File | What it is |
|---|---|
| [bigtty.md](bigtty.md) | AppKit and libghostty, spaces sidebar, browser and file panes |
| [uherdr.md](uherdr.md) | local and remote over SSH, image paste, ⌘1…0 |
| [herdrm.md](herdrm.md) | SwiftUI console with rows for spaces and agents |
| [paca.md](paca.md) | Slack-style window and a menu bar panel |
| [rai.md](rai.md) | who is working, stuck or needs approval |
| [allward.md](allward.md) | a terminal for agents across machines |
| [moo.md](moo.md) | terminal, agents sidebar, browser tabs, ⌘K |
| [herdr-gpui.md](herdr-gpui.md) | Rust and GPUI desktop client (macOS, Linux, Windows) |
| [rex.md](rex.md) | Rex.app, the macOS client of the Rex multiplexer: the look Oriel follows |
| [gorex.md](gorex.md) | a Rex-like app in Go (and MyGo, its framework) |
| [kero.md](kero.md) | terminal panes beside a browser and a changes panel |

## Mobile

| File | What it is |
|---|---|
| [heeler.md](heeler.md) | iOS, libghostty, SSH, QR pairing, push |
| [kelpie.md](kelpie.md) | a Heeler fork for iPad and iPhone |
| [herdr-connect.md](herdr-connect.md) | iPhone companion over LAN or Tailscale |
| [herdrup.md](herdrup.md) | iOS client on a herdr fork |
| [whip.md](whip.md) | React Native and Rust, Android first |
| [multiplex.md](multiplex.md) | tmux first, herdr per host; Vision Pro, iPad, iPhone |
| [anyssh.md](anyssh.md) | an SSH client for iOS with herdr support |
| [pairfob.md](pairfob.md) | the computer dials out to a relay; PWA |
| [pdx.md](pdx.md) | Android launcher for remote herdr agents |

## Web and bridges

| File | What it is |
|---|---|
| [herdr-web-ui.md](herdr-web-ui.md) | browser and phone PWA with a chat view, remote PCs over SSH, web push |
| [collie.md](collie.md) | self-hosted PWA with push alerts |
| [roamgate.md](roamgate.md) | web client for desktop and mobile, files and diffs (was herdr-studio) |
| [herdr-world.md](herdr-world.md) | a roamgate fork with visual "world" views, local and SSH hosts |
| [herdr-webui-alecuba16.md](herdr-webui-alecuba16.md) | local browser UI: worktrees, git, files |
| [termote.md](termote.md) | Go binary that streams sessions to xterm.js |
| [herdr-remote.md](herdr-remote.md) | menu bar, phone and Telegram, a free tunnel |
| [herdr-browser.md](herdr-browser.md) | a Chromium view inside a herdr pane (plugin; deprecated) |
| [agentaps.md](agentaps.md) | GPUI and WASM over iroh; runs its own agents over ACP, not herdr |

## Compared

One row per client that talks to herdr. "Terminal" is how live pane output reaches the screen; "Remote" is how
the client reaches a herdr on another machine. Details and sources are in each client's file.

| Client | Stack | Terminal | herdr access | Remote | Chat | Push | Web panes |
|---|---|---|---|---|---|---|---|
| bigtty | AppKit, libghostty | `terminal session control` (NDJSON frames) | API socket, events then snapshot | `ssh -N -L` both sockets, `-D` SOCKS | no | no | herdr placeholder pane + pane tokens |
| uHerdr | SwiftUI + AppKit, libghostty | binary client socket (protocol 22), falls back to `session control` | snapshot polled every 1.25 s | `ssh -N -L` both sockets | no | no | no |
| herdrm | SwiftUI, libghostty; iOS 18 too | PTY running `agent attach` / `terminal attach --takeover` | events then snapshot | `ssh -L` API socket + `ssh -tt`; libssh2 on iOS | no | no | no |
| rai | SwiftUI + AppKit, SwiftTerm fork | PTY running `terminal attach --takeover` | events then snapshot | `ssh -N -L` both sockets; `herdr machine list` | no | no | no |
| paca | SwiftUI, SwiftTerm | `terminal session control` (pipes) | events then snapshot | `ssh -N -L` both sockets | no | no | no |
| allward | AppKit, own VT + Metal | the herdr TUI in its own PTY | `herdr api snapshot` on demand | plain ssh | no | no | no |
| moo | AppKit + SwiftUI, SwiftTerm fork | the herdr TUI in a Moo tab | events (status only) | none | no | no | app-only tabs, not restored |
| herdr-gpui | Rust GPUI desktop | server-rendered cell grids on the client socket (focused tab) | binary client socket | `remote-client-bridge` over ssh stdio | no | OS notifications | app-only WKWebView tabs per workspace |
| herdrup | SwiftUI iOS, SwiftTerm | fork-only `pane.stream` | fork-only `api-bridge` over SSH exec | Citadel SSH; fork daemon federation | no | APNs through a Worker relay | no |
| Heeler | SwiftUI iOS 18, libghostty | PTY running `agent attach --takeover` | direct-streamlocal to the API socket | own libssh2 SSH, jump host | no (composer sends `agent.prompt`) | APNs through a stateless Worker relay, end-to-end encrypted | no |
| Kelpie | Heeler fork | the herdr TUI over the SSH PTY | as Heeler | as Heeler | Claude Code transcript (`tail -c +N`) | as Heeler | no |
| herdr-connect | Expo iPhone | none (`agent read` text) | daemon on the host runs the CLI, polls 1 s | LAN or Tailscale HTTPS to the daemon | `agent read` history | local only | no |
| whip | Expo + Rust (russh) | binary client socket over streamlocal, xterm.js | API socket over streamlocal | russh, nested jump hosts | agent transcripts over SSH | local only | no |
| Multiplex | SwiftUI visionOS/iPad/iPhone, SwiftTerm | `session attach` in a PTY | CLI over SSH exec | Citadel SSH, optional mosh | composer types into the PTY | local only | no |
| anyssh | SwiftUI iOS 26, SwiftTerm | `session attach` in a PTY | CLI over SSH exec, polled 1 s / 5 s | libssh2 SSH | no | local + Live Activity | no |
| pairfob | Go daemon + React PWA | `terminal session control` child, xterm.js | daemon on the API socket | the machine dials out to a relay; WebRTC | agent journals | Web Push from the daemon | no |
| pdx | Kotlin Android | `terminal session control\|observe`, xterm.js | CLI over SSH exec | sshj SSH | Codex only (`codex app-server`) | none | no |
| herdr-web-ui | Bun + React PWA | `terminal attach` in a node-pty sidecar, xterm.js | API socket + `pane.agent_status_changed` | SSH forward to a bridge on each PC | transcript via `agent.get` + screen-parsed prompts | Web Push | no |
| collie | Bun + React PWA | `pane.read recent` snapshots, own renderer | API socket | a Collie on every host ("crew") | transcripts | Web Push | no |
| roamgate | Bun + React PWA | client socket cell surfaces, xterm.js | API + client socket | `ssh -L` both sockets | transcripts (read only) | Web Push | no |
| herdr-world | roamgate fork + pixi | as roamgate | as roamgate | as roamgate | as roamgate | as roamgate | no |
| herdr-webui (alecuba16) | Rust Axum + JS | direct attach frames, wterm/Ghostty | API + client socket | none | jcode store only | browser only | no |
| termote | Go + React PWA | `terminal session observe/control`, xterm.js | API socket + CLI | none | claude/codex JSONL | Web Push | tab URLs in localStorage |
| herdr-remote | Python relay + PWA + SwiftUI | `pane read --format ansi` every ~3 s | CLI only | SSH per call (ControlMaster) | claude/pi/kimi JSONL | Web Push, Telegram, Live Activity | no |

## Patterns across clients

- **Nobody shows a strip of live panes across tabs.** herdr-gpui gets one surface (the focused tab) per
  connection; herdr-web-ui and herdrup show one pane at a time. herdrup's cache of hidden live terminals comes
  closest to Oriel's strip.
- **Chat always comes from the agent's own transcript**, found through herdr's `agent_session` (or
  `pane.process_info` pid and cwd) and read by byte offset. Prompts and approvals come from the screen.
  Sending is `agent.prompt` (or paste + Enter), answers are `agent.send_keys`. No client builds chat from herdr
  alone.
- **Five ways to reach a machine:** SSH with a streamlocal channel to the API socket (nothing installed; LAN,
  Tailscale or a jump host); SSH exec of the herdr CLI (simplest, but polls and has no events); a daemon on
  the machine over LAN HTTPS (needs a pinned self-signed certificate); an outbound relay with WebRTC (works
  anywhere, needs a daemon and a hosted relay); iroh (used only by agentaps, which does not use herdr).
- **Three ways to get terminal bytes:** `agent attach` or `session attach` in an SSH PTY (raw bytes to a local
  emulator); `terminal session control` (NDJSON frames, public, explicit resize, scroll and mouse); the binary
  client socket (fastest, breaks every few protocol versions).
- **Push needs a relay for a native app**, because Apple's push service needs the developer's `.p8` key.
  Heeler's design is the best: a stateless Worker relay, a herdr plugin `[[events]]` hook as the trigger, and
  end-to-end encryption with a key the app writes to the machine over SSH. Web clients use Web Push from their
  own server. iOS gives a backgrounded app about 26–30 s (`beginBackgroundTask`); faking the `audio` or `voip`
  background modes risks App Store rejection.
- **Pairing:** a QR code printed on the machine with its addresses, the host key fingerprint and a one-time
  secret. The SSH form uses a one-time `restrict,command=` bootstrap key that enrolls the device's own public
  key; Kelpie and Multiplex sync it through iCloud Keychain.
- **Keyboards:** every iOS client has a key row (Esc, Tab, Shift-Tab, a Ctrl latch, arrows, Enter) and most a
  native composer. Heeler moved the row out of `inputAccessoryView`, because keyboard mode switches tore it
  down.
- **No client puts glass behind terminals:** paca removed `NSGlassEffectView` after two days, allward's design
  forbids it, and no client uses `.glassEffect`.
- **Pitfalls seen in the web clients:**
  - `pane.read` with `source:"recent"` and more lines than the viewport, in a background path, visibly scrolls
    the user's terminal and takes seconds.
  - Agent panes are alt-screen, so they have no scrollback; history comes from the transcript.
  - herdr's `revision` is a stub, and an RPC answer does not prove the TUI acted.
  - Chunking a long send can submit half a message at a `\n`; use `agent.prompt` or bracketed paste.
  - `send_keys` rejects names such as `PageUp`, `Home`, `End`, `Delete`, `C-c`.
  - `control` with takeover, or a resize without the user acting, moves the shared PTY size to the last client.

## Not researched

Menu bar monitors (InsaneArts/herdrbar, hmu332233/herdr-menu-bar, pavel-snyk/herdry, bigbug16/herdr-topbar,
jirathip-dev/corral), Moshi and SSHHIP (commercial), alexei-led/ccgram (a Telegram bridge),
furkankly/zoetrope (a session as a live flow graph).

To refresh the list, search GitHub topics `herdr` and `herdr-plugin`, awesome-herdr and r/herdr.
