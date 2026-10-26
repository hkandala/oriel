# Phase 8: design refresh

Goal: the design in `docs/content/docs/` and the interactive overview
(`docs/public/overview/index.html`) describe Oriel with the decisions below. Docs and
mock-ups only, except where marked. Evidence: `resources/research/plugins/plugin-panes.md`
and `resources/research/plugins/remote-plugins.md`.

Follow the ponytail skill for every change: change what the decisions require, delete what
they remove, no new pages unless listed. Write in plain English (short sentences, define
jargon at first use), as the existing pages do. Keep decision numbers stable: changed
decisions get "Changed by Dxx", new ones get new numbers.

## Decisions (from the user)

1. **Intro** (`index.mdx`): a native Apple client for terminal multiplexers, herdr first and
   the only backend for now. Keep the problem and "What we build". Do not add a "who it is
   for" or "how it differs from other apps" section. Update the principles to match the
   decisions below (e.g. "the multiplexer is the source of truth"; "Everything is a plugin"
   stays true for terminal, agent, web and plugin panes).
2. **Multiplexer interface**: a `Multiplexer` interface (Swift protocol) that every
   multiplexer implements. herdr is the first and only implementation; Rex
   (superlogical.com) and tmux are named candidates. A new decision records this as a
   deliberate exception to "no abstraction with one implementation". Describe what the
   interface covers (machine connection, snapshot of workspaces/tabs/panes/layout, events,
   terminal streams, actions, agent status) at the level the design already describes herdr.
   Design now. The code gets the protocol too (see Later decisions).
3. **Plugins: HTML/JS in a web view.** A plugin is a small web page (HTML/JS) drawn in a
   native web view in its card, with a bridge to `run(argv)` and `dial(host, port)` on the
   pane's machine (permissions as today). It works on iOS from day one. The built-in
   git history, diff and Markdown plugins are rebuilt on this model. The TypeScript + React
   kit drawn as native SwiftUI (today's plugin UI, API, packages pages) moves to Future work
   as option (a), kept briefly with a link to `resources/research/plugins/plugin-ui-options.md`.
4. **Placeholder panes stay, created with `layout.apply` + `pane.move`.** A pane node
   `{label, cwd, command:[argv]}` creates the pane with its inert placeholder command and
   label in one call (in a temporary tab), then `pane.move` puts it in place; the temporary
   tab closes itself. The app never types into a shell: delete the typed-command path, the
   process_info gate, the base64 envelope for placeholders, the extra rename and "Restore
   placeholder". Warn: `layout.apply` with `tab_id` replaces the whole tab and kills its
   panes, so the app never passes it. Note the cold-restart gap (the pane returns as a
   shell with its label; the card still works) and the upstream ask (opt-in restore of
   `launch_argv` panes on cold restart, herdr discussion #1367) under Future work / risks.
5. **Remote content: `run` + `dial`**, one standard way for every pane kind and plugin:
   `run(argv)` (exists) and `dial(host, port)`: a TCP stream as seen from the machine
   (macOS: `ssh -O forward -L` / `ssh -W` on the ControlMaster; iOS: a Citadel
   `direct-tcpip` channel). Same port on the Mac when it is free, so the origin is exactly
   `localhost:<P>` (revises D27's L≠P rule). iOS: an in-app listener on `127.0.0.1:<P>` that
   pipes each connection into a `direct-tcpip` channel (add to spike S7). An "Open :<port>"
   chip when a terminal prints a localhost URL (`pane.output_matched`), and an on-demand
   port list (`ss`/`lsof`). Tailscale addresses load directly. Document the five triggers
   for a future small server helper behind the same two calls (session budget, latency,
   file watching, `AllowTcpForwarding no`, Windows servers) under Future work.
6. **OSC 7501** (program status protocol, superlogical.com/rex/docs/build/program-status):
   mention it where relevant: status comes from herdr's API; herdr does not support 7501
   yet (draft PR herdr#5172); under herdr the app never sees the raw sequence; another
   multiplexer's implementation may use it where the app owns the terminal bytes. No new
   UI.
7. **Chat view stays.** **Floating panes move to Future work** (pages, decisions, features,
   mock-ups, data rows such as the `oriel:float` tab). **Arc-style sideways machine swipe
   stays.**
8. **D16 dropped**: the app keeps its own machine list on macOS too (one code path with
   iOS). When herdr is installed on the Mac, its `herdr machine list` entries are imported.
   herdr on the Mac is needed only for This Mac's sessions, not for remote machines. Update
   Add a machine, machines.mdx, data.mdx and related decisions.
9. **Notifications**: no push in v1 (iPhone shows status while open; the Mac keeps local
   notifications). A tiny stateless relay that forwards encrypted payloads to Apple's push
   service goes under Future work.
10. **Image paste** into an agent or terminal pane: a new feature. Design the simplest
    approach that works over SSH (e.g. upload the image to the machine with `run` and stdin,
    then paste its path into the pane); check how existing clients do it.
11. **Where things live** (add to `data.mdx`): anything that takes space in the layout is a
    multiplexer pane with a label; transient UI (palette, popovers, hover) is app memory
    only; per-device settings are app storage.
12. **Overview HTML**: keep `docs/public/overview/index.html`, delete
    `resources/design.html`. Update the mock-ups to these decisions and to the look v0
    actually has (see the Rex reference shots and the current app: frosted pane
    cards, flat sidebar, title-bar pills, session button with the name only). Remove the
    floating-pane mock-ups; plugin cards are web-based.
13. **Status and build order** (`status.mdx`, `build-order.mdx`): v0 is built (This Mac,
    strip, splits, terminals, actions, palette); the next steps follow these decisions.
14. **Future work page**: one page listing everything deferred above (TS + React native
    plugin kit, floating panes, push relay, server helper, launch_argv upstream ask, more
    multiplexer implementations, OSC 7501 use) with links.
15. **Code, outside docs**: CI on herdr 0.9.5 (done in phase 7).

## Later decisions (from the user)

- **iOS plugins:** iOS v1 ships only the core plugins; your own plugins on iOS are Future
  work. This replaces item 3's "works on iOS from day one" for user plugins.
- **Machine name:** a small machine-name line at the top of each sidebar machine page. The
  session button still shows the session name only.
- **Web cards keep their viewing state on the machine (D58):** the label
  `oriel:web#<iid> <url>` keeps the typed address; the current address and scroll position
  go in the instance state file `web/<iid>.json`, as for plugins.
- **No live cross-device follow for any card (D59):** a card, web included, reads its state
  file only when it is built (fresh start, new device, reopened; on iOS only cards the system
  discarded). Every plugin and web card gets a header **Refresh** (it replaces the web card's
  Reload) that rebuilds the card from the machine. State writes no longer change `oriel_rev`;
  it follows only renames. `oriel.state` is for view state; live shared data goes in files
  read with `run`.
- **The `Multiplexer` protocol is also in code** (item 2's scope): `HerdrKit` has the
  protocol, `HerdrClient` conforms, and the app talks to it.
