# Remodex (Emanuele-web04/remodex): iPhone chat for Codex, with a rollout tail for runs started elsewhere

Repo: https://github.com/Emanuele-web04/remodex (Apache-2.0, about 3.3k stars, active). A Node bridge
(`phodex-bridge/`, npm `remodex`, a `launchd` service on macOS) plus a native SwiftUI iOS app (`CodexMobile/`), joined
by an end-to-end encrypted relay paired with a QR code. Codex and OpenCode. Read for how it shows Codex runs it does
not own: it **tails the rollout JSONL** and turns it into app-server-shaped events.

## Chat data, two paths

| Run started by | Source | Live? |
|---|---|---|
| the phone | the bridge's own `codex app-server` over stdio, or an existing one at `REMODEX_CODEX_ENDPOINT=ws://…` (`phodex-bridge/src/codex-transport.js:2-24`, `README.md:348`) | yes, item deltas |
| Codex.app, VS Code or the CLI | the thread's rollout file under `~/.codex/sessions`, polled every 250 ms (`rollout-live-mirror.js:33`, `:157-200`) | turn by turn, as lines land |

`rollout-live-mirror.js` emits "synthetic app-server-like notifications" so the phone has one event model for both.
It handles the cases a tail must handle:

- Big files: read a 256 KB head for metadata and a 4 MB tail at bootstrap, never the whole file (`:45-50`).
- Dead runs: a killed run never writes `task_complete`; growth older than 10 min is not shown as running, and a
  heartbeat never refreshes the growth clock (`:42`, `:186-190`).
- Turn end: a synthetic "turn completed" after a 1 s grace when the end marker is missing (`:43`, `:330-333`).
- Partial lines are kept until their newline (`partialLine`, `:185`).

It also pushes phone-made changes into Codex.app by opening `codex://threads/<id>` (`codex-desktop-refresher.js:908`)
and talks to Codex Desktop's private IPC socket to share live state (`desktop-ipc-live-owner.js`, about 10k lines
across the `desktop-ipc-*` files).

## Input, approvals, waiting

- Input: app-server `turn/start` and `turn/steer`; follow-ups queue while a turn runs. No PTY keys anywhere.
- Approvals: app-server `…/requestApproval` server requests go to the phone (`bridge.js:3574`). Runs that came from
  a rollout tail cannot be answered from the phone; the file has no pending-approval record.
- Waiting: app-server turn state; for tailed runs, "no growth" plus the end marker.

## Terminal view, TUI alive?

No terminal view. A Codex CLI TUI running on the Mac keeps running; the phone only watches its rollout. A phone
message to that thread goes through the bridge's own app-server, a second writer on the same thread.

## Size

Bridge `src/` about 40k lines (`bridge.js` 5.5k, rollout mirror 2.3k, rollout watch 1k). The SwiftUI app is separate.

## For Oriel

- Copy: the rollout tail rules: bounded bootstrap read, keep partial lines, treat a stalled file as stopped, close a
  turn after a short grace when the end marker never comes.
- Copy: one internal event model, whether events come from a protocol or from a tailed file.
- Note: a Codex TUI started as `codex --remote ws://…` against a shared `codex app-server --listen` gives live events and approvals with
  the TUI still alive; Remodex supports connecting to such an endpoint.
- Avoid: Codex Desktop's private IPC; it is undocumented and large.
