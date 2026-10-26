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

## Not researched

Menu bar monitors (herdrbar, herdr-menu-bar, herdry, herdr-topbar, corral), Moshi and SSHHIP (commercial),
ccgram (a Telegram bridge), zoetrope (a session as a live flow graph).
