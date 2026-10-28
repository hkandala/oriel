# Phase 37: The browser pane on remote machines

Goal: a browser pane on a remote machine shows pages from that machine (its localhost dev servers and its
private names) through the existing SSH connection, with its own profile per machine, and a ports chip to
open a listening port in one click.

Design: the Remote section of [Browser](../../docs/content/docs/ui/browser.mdx) and
`resources/research/plugins/browser.md`.

## Track A: remote browser (items 1–3)

1. **SOCKS per machine.** One `ssh -S <ctl> -O forward -D 127.0.0.1:<P>` per machine on its ControlMaster,
   a free local port each, started on the first browser pane of that machine and stopped when the machine
   disconnects. One `WKWebsiteDataStore(forIdentifier:)` per machine id with its `proxyConfigurations` set
   before the first load. Removing a machine removes its store.
2. **Machine-local addresses.** WebKit never proxies `localhost`, so a remote card rewrites
   `localhost:<port>` to `<machine>.localhost:<port>` (shown as typed in the address field if that reads
   better), which the machine resolves to its own loopback; private names go through the proxy as typed.
3. **Ports chip.** The toolbar shows the machine's listening TCP ports (one run over the relay when the
   chip opens) and opens one in the card. Group them by herdr workspace through `HERDR_WORKSPACE_ID` in
   each listener's environment where the machine allows reading it (herdr-gpui does this), else one list.

e2e on CI's sshd: a tiny HTTP server on the "remote" side, a browser pane on Key Host loads it through the
proxy, two machines with the same port don't collide, and the ports chip lists the server.

## Findings

### Track A

- **Spike:** `-O forward -D 127.0.0.1:<P>` works on Oriel's master (`ClearAllForwardings=yes`); `-D …:0` is
  refused, a taken port exits 255, a second identical forward is a silent no-op, and `-O cancel` of a missing one
  exits 0. `proxyConfigurations` can change between loads of a store (checked). curl resolves `*.localhost` itself
  and never asks the proxy, so check a proxy with WebKit, not curl.
- **Cause:** ssh's `-D` closes a connection it cannot open (a refused port, an unknown name, a server with
  `AllowTcpForwarding no`) without a SOCKS reply, and WebKit then retries and waits 60 s ("The request timed out").
  **Fix:** a SOCKS front of the app's own (HerdrKit `SOCKSFront`, Network.framework) on a loopback port before ssh's
  `-D`: it answers "refused" at once, and it asks the machine for `localhost` where a page asked for
  `<anything>.localhost`, so a machine need not resolve `*.localhost` (no check of Linux hosts needed; on one by
  hand: `getent hosts x.localhost`). WebKit reports the refusal as `-1004` or `-1000` "bad URL" at random; a remote
  card reads both as refused.
- **Decisions:** the front and the `-D` start with a machine's first card and end with its last (`-O cancel`); the
  `-D` dies with its master and the next page connection forwards again on the new one (checked by killing the
  master). Connections the front already carries (an HMR websocket) live on after the last card until WebKit drops
  them. Two machines of one target share the exec, so one proxy; after a target edit, old cards share the store
  with the new target's proxy (rare, accepted). `<machine>` is the name in lowercase words joined by dashes, not
  made unique: each machine has its own store and proxy, so a clash mixes nothing; any `*.localhost` shows as
  `localhost`, so a rename keeps working, but its pages get a new origin (their logins go).
- **Decisions (This Mac's loopback):** a remote card never reaches it. Its loads and restored back and forward
  list wait for the proxy; a main-frame link, redirect or `form_post` to `localhost` is sent as
  `<machine>.localhost`; a content rule blocks every other loopback request (images, fetches, websockets, frames,
  popups, and `127.1`, `localhost.`, `[::ffff:7f…]`, which WebKit never proxies). So a remote page that calls
  `http://localhost:8000` from script is blocked, not sent to the machine: serve the API on the page's origin. For
  `127.1` WebKit still opens an empty preconnect to This Mac (no bytes). Removing a machine also removes its
  approvals; its store stays on disk if a window still uses it (`remove(forIdentifier:)` fails then, no retry).
- **Decisions (errors):** "Nothing answers on localhost:3001 on ‹machine›" for a loopback port, "‹machine› cannot
  reach ‹host:port›" for another name, "‹machine› is not connected" while its session is not live. Not built: "does
  not allow port forwarding" (WebKit sees the same refusal; a `ssh -W` probe on failure could tell it).
- **Decisions (ports chip):** on This Mac too; `ss -ltnp` else `lsof`, listeners on any address or loopback, one
  per port, with the process name (empty for another user's). `HERDR_SESSION` and `HERDR_WORKSPACE_ID` come from
  `/proc/<pid>/environ`, else one `ps -E` (perl hides its environment from `ps -E`; node and Python do not). Groups
  are the session's workspaces by label, then "Other"; one plain list when none matched. The last answer shows
  until the new one comes. SwiftUI calls `onAppear` for each menu item as it appears, also on an update, so one run
  per opening needs a 1 s guard (without it the menu looped).
- **For the user:** on the devserver, a dev server on `localhost:<port>` in a browser pane (page, HMR websocket,
  login that persists across relaunches); a port with nothing on it (the error comes at once); the ports chip's
  groups; a private name (`http://<host>.<corp domain>`) typed in a remote card; close the last browser card and
  check `lsof -nP -iTCP -sTCP:LISTEN | grep ssh` shows no SOCKS port; after the OTP Connect, a card reloads.
- **Runs:** CI's sshd is this Mac, so "two machines, one port" is one pane shown in a This Mac window and a Key
  Host window at once: WebKit connects to one, sshd to the other. A CI window recording draws web pages blank on
  both machines (the accessibility values are right); locally they draw.
