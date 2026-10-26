# herdr-connect (Tomyail/herdr-connect): iPhone companion

- Architecture: iPhone app (Expo RN) ⇄ **HTTPS** ⇄ **Go daemon** (`cmd/herdr-connect`, installed as a launchd/systemd service
  with `herdr-connect service install`) ⇄ `herdr` CLI. The phone does not use SSH.
- Discovery: mDNS `_herdr-connect._tcp` (on macOS through `dns-sd -R`), TXT `fp=<cert fp>`. Over Tailscale, a `--host`
  override is baked into the QR.
- Pairing (`docs/security/lan-tls-pairing.md`): `herdr-connect pair` prints a QR with a 32-byte one-time secret (5-minute
  TTL, stored hashed), the cert fingerprint, addresses and port. The phone calls `POST /v1/pair` and gets a per-device
  **bearer token**, stored hashed in SQLite on the host. The cert is self-signed ECDSA P-256 with no SANs and is pinned by
  SHA-256. **The iOS app has to set `NSAllowsArbitraryLoads: true`**, because ATS rejects SAN-less certs on non-"local"
  interfaces such as Tailscale before the delegate can pin. Devices are revoked with `herdr-connect devices revoke`.
- herdr access (`internal/herdrsource/herdr_cli.go`): `exec herdr agent list`, `workspace list`, `tab list`,
  `agent read <id> --source recent-unwrapped --lines N`, `agent get`, **`pane run <id> <text>`** (send),
  **`pane send-keys <id> C-c`** (interrupt), `agent focus`. `Changes()` returns "no trusted incremental subscription": the
  daemon never uses `events.subscribe`.
- API: `GET /v1/agents`, `/v1/agents/<id>/{history,messages,focus,interrupt}`, and SSE `/v1/agents/events`. The SSE stream
  comes from **polling the snapshot every 1 s** (1 s cache TTL).
- The phone renders history text as markdown (`HistoryMarkdown.tsx`). It has voice input and no terminal emulator.
- Notifications: foreground only, a sound plus a local notification (`DoneSoundProvider.tsx`). Push is "a future
  milestone" (planned HPKE E2EE relay). On background the app stops polling and SSE entirely.
