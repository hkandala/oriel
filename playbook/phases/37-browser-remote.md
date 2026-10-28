# Phase 37: The browser pane on remote machines

Goal: a browser pane on a remote machine shows pages from that machine (its localhost dev servers and its
private names) through the existing SSH connection, with its own profile per machine, and a ports chip to
open a listening port in one click.

Design: the Remote section of [Browser](../../docs/content/docs/future-work/web-page.mdx) and
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
   chip opens) and opens one in the card.

e2e on CI's sshd: a tiny HTTP server on the "remote" side, a browser pane on Key Host loads it through the
proxy, two machines with the same port don't collide, and the ports chip lists the server.

## Findings
