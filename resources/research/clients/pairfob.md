# pairfob (arronKler/pairfob): outbound relay, PWA

- Topology (README): `phone --HTTPS/WSS--> pairfob.com (Cloudflare Worker + Durable Object) <--outbound WSS-- pairfob daemon --loopback--> herdr`.
  The host opens no inbound ports and needs no VPN. After authenticated setup, the session **upgrades to a WebRTC
  DataChannel** (`proto/direct-transport.md`; STUN `stun.cloudflare.com`, no TURN, so the relay stays as fallback).
- Crypto: SPAKE2+ pairing with a code both sides confirm (PGP word list), Argon2id, AEAD envelopes (`proto/envelope-v2.md`).
  The relay sees only ciphertext `FWD` frames. Pairing runs from `pairfob pair` or the herdr plugin action
  (`[[panes]] placement = "overlay"`).
- herdr access (`internal/runtime/`): **the daemon dials the unix socket directly** (`net.DialContext("unix", socket)`) for
  `session.snapshot`, `events.subscribe`, `agent.prompt`, `agent.start`, `pane.split/swap/zoom/resize/close/rename`,
  `pane.send_keys`, `pane.send_text`, `pane.read`, `pane.process_info`, `tab.*`, `workspace.*`, `agent.explain`.
- **Terminal = `herdr terminal session control <pane> [--takeover] --cols N --rows M`** as a child process
  (`herdr_terminal.go`). It speaks NDJSON on stdio:
  - out: `{"type":"terminal.frame","sequence":n,"width":w,"height":h,"full":bool,"encoding":"ansi","bytes":"<b64>"}`,
    `{"type":"terminal.closed","reason":…}`
  - in: `{"type":"terminal.input","bytes":"<b64>"}`, `{"type":"terminal.resize","cols","rows","cell_width_px","cell_height_px"}`,
    `terminal.scroll {direction,lines,source:"wheel"|"page_key",modifiers}`, `terminal.mouse`, `terminal.release`.
  - This is a **public, JSON, versioned-by-CLI** form of herdr's client protocol. Verified locally:
    `herdr terminal session {control,observe} <TARGET> [--takeover] [--cols] [--rows]` exists in 0.9.3.
- Phone renders **xterm.js 6 + WebGL addon**. Modes: Control (terminal + system keyboard + keypad), Terminal (raw PTY),
  Chat.
- Chat: the daemon reads agent journals (`internal/journal/`: claude `agent-transcripts/<id>/<id>.jsonl`, codex, pi,
  opencode, hermes) and serves an `agentTrace` RPC. It sends with `agent.prompt`. The UI keeps sending, accepted, processing,
  and transcript-received as separate states and **never replays** a send.
- Push (`internal/daemon/push.go`): **standard Web Push (RFC 8291 aes128gcm + VAPID) sent straight from the daemon** to the
  browser's push endpoint (Apple Web Push for an installed PWA). It debounces for 30 s and refuses private or loopback
  endpoint IPs. The project runs no APNs server. This only works because the client is a PWA. A native app cannot use it.
