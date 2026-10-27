# Phase 26: Remote hosts, first prototype

Goal: connect to a machine over SSH and use its herdr like This Mac's: a first prototype, improved later.
The design is in `docs/content/docs/machines.mdx` and D43, D54.

## Build

1. **Add a remote host**: an SSH target as the user types it in a terminal (`host`, `user@host`, a
   `~/.ssh/config` alias).
2. **Connect without asking when SSH needs nothing** (keys, agent, config): a BatchMode ControlMaster first.
3. **Ask when SSH asks** (a password, a one-time passcode, a host key) in an Oriel dialog, through
   `SSH_ASKPASS`; never store an answer.
4. **Run herdr there**: find it, list its sessions in Open Session, open one as a page; say when herdr is
   missing.
5. **Reconnect by itself** while no prompt is needed; when a retry would need an answer, stop and show
   Disconnected with a Connect button.

Rules: the system `ssh` only, never write to `~/.ssh`; tests use CI's sshd on localhost; only throwaway herdr
sessions on the remote side.

### Round 2

On a server with one-time passcodes every card failed with "Session open refused by peer": Oriel opened an
SSH session per herdr call and per stream, more than the server's `MaxSessions`, and a second connection
would need a second passcode. Carry a host's traffic over one SSH session through the one master; test
under `MaxSessions 2`.

## Findings

- **Decisions.** `SSHExec` is an actor: one master start in flight per host, joined by every run. Its socket
  lives under `~/Library/Caches/oriel/`, named by a hash of the target. ssh's keepalive ends a dead master and
  the next run starts a new one in BatchMode. Automatic starts time out after 30 s. A master that outlived a
  crashed app is not reused. New tabs pass cwd `~`, so This Mac's home never reaches a remote machine.
- **Decisions.** ssh's questions are an Oriel dialog, not `osascript`: it belongs to the window that asked,
  follows the app's look, and a test can answer it. `Exec.herdr()` throws, so "cannot reach the machine" is
  never "herdr is not installed".
- **Cause, round 2.** One SSH session per call and per stream. herdr's own `--remote` pipes its private client
  protocol over one session, which Oriel cannot drive; `--machine` opens one session per request, as Oriel did.
- **Fix, round 2.** The relay: one SSH session per host runs a Perl script sent in the envelope (never
  installed), and every run is a line-framed channel inside it ([The SSH
  connection](../../docs/content/docs/machines.mdx)). `Exec` and everything above it stayed the same. A machine
  without Perl says so; the per-run fallback went. CI's sshd allows 2 sessions per connection, and every remote
  test runs under it.
- **Cause, on the way.** The relay's kill (`k`) ended only `sh`, so the observe wrapper's herdr kept streaming;
  it now kills by pid and closes stdin. Runs got their own write buffers, so a run that reads nothing never
  stalls the host.
