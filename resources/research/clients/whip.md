# whip (kosumic/whip): React Native and Rust

- SSH: Rust **russh 0.63** + russh-sftp inside a single Tokio runtime, bridged to RN through UniFFI
  (`packages/react-native-whip-ssh`). It supports nested jump hosts, agent forwarding, and a strict global known-hosts list.
- herdr access (`rust/src/herdr_connection.rs`, `herdr_api.rs`): `channel_open_direct_streamlocal(socket_path)` for both:
  - the **API socket** (JSON NDJSON): snapshot, events, `agent.prompt`, `pane.send_input`, `pane.send_text`, etc. It
    supports protocols 17–22 and ships schema files in `protocol/herdr-api-v17..v20.schema.json`;
  - the **client socket** `herdr-client.sock` (`client_socket_path()` strips `.sock` and adds `-client.sock`). Over it they
    speak **herdr's binary client protocol** (`herdr_codec.rs`: bincode, messages `Hello/Input/Resize/Detach/Attach/Scroll`;
    server `Welcome/Terminal{sequence,width,height,full,bytes}/Graphics/Closed/Notify/Clipboard/Title/MouseCapture/…`).
    This is the same protocol herdr's own thin client uses, version-tabled because it breaks between versions (p18, p20, p22
    changed tags). **Fragile.**
- Rendering: xterm.js inside a WebView. They keep a cache of recent ANSI output so a read-only "virtual backend" shows the
  last screen while offline. A per-terminal **outbox** queues composer messages and replays them on reconnect.
- Chat View: **reads native agent transcripts over SSH**. Codex rollout JSONL matched by herdr's `agent_session` id;
  OpenCode via `opencode export` + `opencode db`; Claude by searching `~/.claude/projects/**/<session-uuid>.jsonl`
  (`docs/claude-chat-view.md`). It follows with `tail -c +OFFSET -F` and idles after 5 s once the agent is done.
- Sending from the composer (`src/lib/terminalSubmission.ts`): paste events into xterm (bracketed paste), then `"\r"`,
  written to the terminal stream.
- Pairing: `whipair` (Rust; runs with `npx` / `uvx` / `nix run`). It adds a temporary Ed25519 key with `restrict` and a
  forced command, and puts the seed, endpoint, user and host-key pin in the QR. The phone submits its permanent pubkey and
  **the host user approves it with [Y/n]**.
- Extras: "Reverse Control" sets up an MCP server for the agent through **SSH reverse TCP forwarding**, so a remote agent can
  drive the phone's browser and device. Links that point at loopback or private addresses are opened through an SSH
  direct-tcpip tunnel in the in-app browser.
- Push: none. Local notifications while connected. Android uses `HerdrBackgroundModule.kt` (foreground service). iOS
  declares `UIBackgroundModes: audio` (used for the voice announcements).
