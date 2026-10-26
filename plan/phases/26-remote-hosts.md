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

## Findings

### What works (CI on localhost sshd, `scripts/ci-sshd.sh`)

- Add Remote Host (name, SSH target, icon) in the machine menu; the window switches to the machine's `default`
  session and connects. The list is JSON in `UserDefaults` (`machines`). A run with `-session` (the tests) never
  sees the user's machines.
- No-prompt connect: a BatchMode ControlMaster per host (`SSHExec` in HerdrKit), with the system `ssh` and the
  user's config, agent and keys. Every herdr call, the events stream and terminal streams go through it in the
  base64 envelope. Open Session lists the machine's sessions; a remote page types and streams like This Mac's.
- Prompts: Connect and Add start the master with `SSH_ASKPASS` pointing at a script the app writes beside the
  sockets. ssh runs it with its own stdin and stderr, which are the app's pipes: the question comes out on stderr,
  the answer goes in on stdin. Nothing is stored. Each question is a sheet (host key: ssh's facts with the
  fingerprint on its own line, and Connect; a password, passphrase or PIN: a hidden field; Return answers, Esc
  cancels). A wrong password gets ssh's next question.
- herdr missing on the host: "herdr is not installed on ‹machine›" with the install command (the password user has
  none).
- Reconnect: a dead master (killed, or ended by ssh's keepalive within about 15 s) is started again by the next run,
  without a prompt; the cards stream again. A host that needs an answer is blocked: Disconnected with ssh's text
  and Connect, and no ssh runs until the user clicks it (the test counts sshd's connections). Other failures back
  off from 2 s to 30 s and show Reconnecting.

### Deviations

- **ssh's questions are an Oriel sheet, not an `osascript` dialog** (machines.mdx said a dialog). The sheet belongs
  to the window that connects, follows the look, and an e2e test can answer it. The phase file asked for it.
- **No `-O exit` on a failed health check.** `ServerAliveInterval=5`, `ServerAliveCountMax=3` let ssh end a dead
  link's master by itself; the next run starts a new one. Less code than restarting from the health check.
- **The master's liveness is `kill(pid, 0)`, not `-O check` per run** (the pid comes from one `-O check` per start).
- **At most 10 channels per connection, and remote windows stream only the tabs in view.** The first CI run of a
  remote page asked for more at once and sshd refused them ("Session open refused by peer", `MaxSessions` 10).
  A run past 10 waits up to 10 s, then fails (Reconnecting, not a freeze). The design's "close the least recently
  shown stream and try again" comes later.
- **Disconnected/Connect instead of Reconnect**, per the phase file; states.mdx follows.
- **herdr's version check** is the snapshot's (as on This Mac), not a separate `herdr --version`: the login shell's
  `command -v herdr` finds the path, the first snapshot says the version.
- **cwd `~`** for new tabs and workspaces everywhere: herdr reads it as its machine's home, so This Mac's home never
  goes to a remote machine.

### Decisions

- `SSHExec` is an actor: one start in flight per host, joined by every run; state (pid, blocked, backoff, herdr's
  path) lives there. `Exec.herdr()` now throws, so "cannot reach the machine" is never "herdr is not installed".
- Execs are kept by target, as sockets are (`~/Library/Caches/oriel/<8 hex of the target's SHA-256>`).
- Automatic starts time out after 30 s (ConnectTimeout covers only TCP and the banner); `-O check` after 5 s.
- A master that outlived a crashed app is not used (it may hold that app's sessions); the socket is removed and a
  new master starts.
- Remote Start runs `nohup herdr --session S server` over SSH (`exec is SSHExec` in `startServer`).
- Notification ids are `‹machine id›|‹session›|‹terminal id›`; a remote session's notification and Dock row show
  the machine's name.

### Not yet (later phases)

- Local Network privacy (macOS 15+): a LAN target fails with "No route to host" and shows Reconnecting with no hint.
- herdr's machine list in the Add sheet; rename, icon change, reorder, remove of a machine.
- ⌥-click on a remote machine switches the window instead of opening a new one; a notification of a machine no
  window shows opens nothing.
- MaxSessions refusal handling (D46 eviction), a remote home shown as `~` in card headers, `dial` and web cards,
  file drops and image paste to a remote machine, git's availability checked per machine.
- No test sees Reconnecting (it needs sshd stopped and started by the helper); Connect has no busy state.
- A security key touch prompt (`SSH_ASKPASS_PROMPT=none`) shows nothing.

## Round 2 (user, 2026-10-25 05:20)

The user connected to a server with one-time passcodes. The sidebar
loaded, but every card shows "mux_client_request_session: session request failed: Session open refused by
peer" and Retry (a screenshot in the main checkout's `.build/fb/`). The server refuses more sessions (channels)
on the one connection: Oriel opens one ssh session per herdr call and per terminal stream, more than the
server's MaxSessions. A second connection would need a second passcode, so it is no way out.

The user's working setup is `~/.config/herdr/herdr-remote.sh`: one ControlMaster authenticated once (an
askpass for the OTP), and `herdr --remote <host>` running through ssh/scp wrappers that reuse it. herdr also
has `herdr --machine <label> <command>` and `herdr machine …`. Do this by default:

1. Find how `herdr --remote` and `herdr --machine` carry many requests and terminal streams to a remote
   herdr (one ssh session with a multiplexed bridge? `remote-api-bridge`?), and how many ssh sessions they
   open. Read herdr's docs and source if needed (herdr is Apache-2.0).
2. Carry all of a host's traffic (calls, events, every terminal stream) over one ssh session, or the fewest
   the server allows, through the one ControlMaster: either herdr's own remote transport (if Oriel can
   drive it) or one long-lived remote process that multiplexes, never one ssh session per call or stream.
3. One passcode per host: nothing may open a second authenticated connection; a dropped master asks once
   (the existing rules on prompts and no retry loop stay).
4. A CI test with sshd set to a low `MaxSessions` (for example 2) and many panes: everything streams.

### Round 2 findings

- **Root cause:** one SSH session per herdr call and per terminal stream. That server allows fewer sessions per
  connection than a page opens at once (MaxSessions; it refused the third), so cards failed with "Session open
  refused by peer". The round-1 cap of 10 matched OpenSSH's default, not that server.
- **herdr's transports:** `herdr --remote` opens one ssh session running `herdr remote-client-bridge`, a byte pipe
  to the remote `herdr-client.sock` in herdr's internal binary client protocol (the TUI's), so Oriel cannot drive it
  without reimplementing that protocol. `herdr --machine <label> <cmd>` runs one `remote-api-bridge` session per
  request (the API answers one request per connection), the same as Oriel's round 1. Terminal streams use the
  client socket too: the API schema has no terminal method.
- **Design:** the relay, one SSH session per host running a Perl script sent in the envelope. Every run (calls, the
  events stream, every terminal stream, git, the herdr lookup) is a line-framed channel inside it
  (machines.mdx, macOS). `Exec` and everything above it are unchanged: `SSHExec.run` returns the relay's channel.
  A machine without Perl shows "Oriel needs Perl on ‹machine›"; the next run tries again. The round-1 fallback of
  one session per run (capped at 10) is gone: it cannot serve a strict server either.
- One passcode per host stays: the relay runs on the master like any run (`ControlMaster=no`,
  `ProxyCommand=/usr/bin/false`), so nothing opens a second authenticated connection; a dropped master is started
  again in BatchMode, and a host that needs an answer asks only on Connect.
- Remote windows stream the recently shown tabs again (D46): the round-1 "tabs in view only" rule is gone.
- CI's sshd now allows 2 sessions per connection; every remote test runs under it, and
  `testAHostThatAllowsTwoSessionsStreamsEveryPane` streams six panes and types in one.
- Reviews (round 2, one round): ponytail 10 items, fixed 1–7 and 9–10 (the no-Perl fallback and its cap gone, a
  shorter relay, no 2 s grace, `pause()` folded into `hide()`, D2 and principle 2 name the relay); 8 (unhex) kept.
  Spec 8 items, one blocker: `k` killed only `sh`, so the observe wrapper's herdr kept streaming; `k` now closes
  stdin first (a unit case covers it). Also fixed: runs wait for a relay start in flight instead of each starting
  one, per-run write buffers (a run that reads nothing no longer stalls the host), SIGPIPE back to default in runs,
  `use IO::Handle` for old Perl, `exec` before each command, the stale streaming bullet in talking-to-herdr.mdx.
- CI (round 2): remote tests 40193637252 (73d4369) and 40194450710 (5564018, after the reviews) green, all four
  under `MaxSessions 2`. Full suite 40195025282 on ed89f5a (which includes 5564018): green except
  `testPaletteEnterTakesTheMovedRowAndKeysFollow` in shard 0, red twice (also on the rerun). Not this phase's:
  the overview lane's "Show Overview" (ef39e2a) now sits between Show Agents and Show Previous Tab, so ↓ after
  "show" selects it.
