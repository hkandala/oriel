# Phase 26: Remote hosts, first prototype

The user (2026-10-25): connect to a machine over SSH and use its herdr like This Mac's. Explore and build a
first prototype; we improve from there. The design is in `docs/content/docs/machines.mdx` (machines, the
app's machine list, ControlMaster per host, checks on connect) and D43/D54 in `decisions.mdx`; it wins
unless the prototype proves a part wrong (then fix the page and say why).

## What the prototype must do

1. **Add a remote host** (the machine button's Add Remote Host sheet, per machines.mdx): an SSH target as the
   user types it in a terminal (`host`, `user@host`, a `~/.ssh/config` alias).
2. **Connect without asking when SSH needs nothing:** keys, agent, config. Start the host's ControlMaster
   with no prompt possible first (BatchMode); when that works, connect at once.
3. **Ask when SSH asks:** when the host needs a password, an OTP or a host-key confirmation, show the
   prompt's text in an Oriel sheet and pass the answer to ssh (for example through `SSH_ASKPASS` with
   `SSH_ASKPASS_REQUIRE=force` pointing at a small helper that asks the app). Never store a password in a
   file or in defaults. A new host key shows its fingerprint and asks.
4. **Run herdr there:** check herdr on the host (`herdr --version` through the master), list its sessions
   (`herdr session list --json`) in Open Session, and open one as a page: snapshot, events, terminal streams
   all through the ControlMaster. herdr missing on the host: say so in the machine's state (the bundling plan
   in `resources/research/multiplexers/README.md` is later).
5. **Reconnect by itself** when the connection drops (network change, sleep, server restart): back off and
   retry while the host needs no prompt; the pages show their reconnecting state (states.mdx) and come back
   on their own. When a retry would need a password or any answer, stop retrying and show the page as
   disconnected with a Connect button that asks again.

## Rules

- The system `ssh` only; the user's `~/.ssh/config`, agent and keys work unchanged. Never write to `~/.ssh`
  (known_hosts is ssh's own business when the user accepts a key).
- Tests: no real remote machine of the user's. CI can run sshd on the runner (passwordless sudo) and connect
  to localhost with a generated key and with a password user, which covers no-prompt, password prompt and
  reconnect (kill the master or sshd). Locally only read-only probes; never launch Oriel or run XCUITest
  locally while the user works on this Mac.
- herdr on the remote side: only throwaway `oriel-dev-26-*` / `oriel-e2e-*` sessions, deleted after.

## Checks

- `make lint build test`; UI tests on CI for: add host, no-prompt connect, password prompt, open a remote
  session and type in it, reconnect after the master dies, no retry loop on a password host.
- One review round (spec and ponytail). Findings at the end of this file.

## Findings
