# agentaps (domenkozar): GPUI and WASM, ACP instead of herdr

Repo: https://github.com/domenkozar/agentaps (crate version 0.5.1). About 29k lines, almost all Rust.

## 1. Architecture

| Part | Path | Notes |
|---|---|---|
| Desktop app | `src/` (bin `agentaps`) | Rust 2024, UI with **GPUI via `gpui-kit = 0.7.0`** (Zed's GPUI plus the longbridge component kit) |
| Shared wire types | `crates/control-protocol/src/lib.rs` | about 100 lines, serde only. Used by the desktop and by WASM |
| Web Connect | `web/` (cdylib, wasm32) | Same GPUI kit running in the browser (`gpui_kit::platform::single_threaded_web()`), `iroh` 1.1, `rqrr` QR decoder, JS glue in `web/src/browser.js` |
| ACP transport | `src/acp.rs` | Spawns a child process (local or `ssh`) and moves JSON lines over stdin/stdout |
| Session logic | `src/session.rs`, `src/session/protocol.rs`, `src/session/prompt.rs` | ACP v1/v2 handling, normalised to one `SessionUpdate` enum |
| Pane layout | `src/panes.rs` (model), `src/app/panes.rs`, `src/app/render/panes.rs` | Own binary split tree |
| Terminal drawer | `src/app/terminal.rs` | `gpui-libghostty = 0.3.1` (feature `ghostty-terminal`, macOS + Linux Wayland) |
| Mobile server | `src/mobile.rs` (iroh endpoint, credentials), `src/app/mobile.rs` (snapshot + command apply) | |
| Notifications | `src/app/notifications.rs` | Local OS notifications only |
| Persistence | `src/config.rs`, `src/persistence.rs` | `~/.config/agentaps/config.json`, written by a single background writer |
| Other | `git_diff.rs`/`diff_watch.rs` (gix + notify), `git_clone.rs`, `file_search.rs` (nucleo), `theming.rs` (GTK/Qt/native-theme) | |

Key dependencies (`Cargo.toml`): `iroh = "1.1"` (tls-ring), `agent-client-protocol-schema = 1.9.1`
(`unstable_protocol_v2`), `secretspec 0.21` (keyring), `qrcode`, `subtle` (constant-time token
compare), `tokio`, `gix`, `notify`, `gpui-libghostty` (optional).

Threading model. The GPUI main thread runs a **polling tick**: 25 ms while the visible session is
connecting, otherwise 100 ms (`src/app.rs:1361-1398`). Each tick drains `std::sync::mpsc` channels:
agent events, mobile commands, persistence results. The agent I/O threads are plain
`std::thread`s. The iroh server runs its own tokio runtime on a dedicated thread.

## 2. "Backend" protocol (ACP instead of the herdr socket)

### 2.1 Process transport (`src/acp.rs`)
```rust
let mut ssh = Command::new("ssh");
ssh.args(["-T","-o","BatchMode=yes","-o","StrictHostKeyChecking=yes","-o","ConnectTimeout=10", host])
   .arg(remote_command);           // "cd '/path' && exec 'agent' 'args'"  (remote.rs::agent_command)
...
for line in BufReader::new(stdout).lines() { serde_json::from_str(&line) → Event::Message{agent_id,value} }
```
- Newline-delimited JSON-RPC 2.0. Requests are built by hand with `serde_json::json!`.
- `Drop for Connection` kills the child, so **agents live only as long as the app**. The README
  says: "Closing the app can interrupt an active turn."
- Reconnect: on launch, sessions with a saved `session_id` restore through `session/resume` (v2, or v1
  with `sessionCapabilities.resume`) or `session/load` (v1 `loadSession: true`). Connections to
  hidden sessions are *deferred* until the visible one is ready (`poll_events`,
  `deferred_connections`). This is staggered startup.

### 2.2 Methods used (client to agent)
| Method | Params (exact) |
|---|---|
| `initialize` (id 1) | `v2::InitializeRequest{protocolVersion:2, clientInfo:{name:"agentaps",…}, capabilities:{elicitation:{form:{}}}}` plus a duplicate `clientCapabilities:{elicitation:{form:{}}}` so v1 agents can read it (`session/protocol.rs:25`) |
| `session/new` (id 2) | `{"cwd":path,"mcpServers":[]}` |
| `session/resume` / `session/load` (id 2) | `{"sessionId","cwd","mcpServers":[]}`, plus `"replayFrom":{"type":"start"}` on v2 |
| `session/prompt` (id ≥3) | `{"sessionId","prompt":[{"type":"text",…},{"type":"image",…},{"type":"resource",…}/{"type":"resource_link",…}]}` |
| `session/cancel` (notification) | `{"sessionId"}` |
| `session/set_config_option` / `session/set_mode` | model, effort, mode, "collaboration" (the Codex Plan toggle) |

### 2.3 Agent to client
- `session/update`, decoded into `SessionUpdate` (`session/protocol.rs:96-214`):
  `session_info_update`(title), `usage_update`(used/size → context meter), `config_option_update`,
  `current_mode_update`, `available_commands_update` (slash commands), v2 `state_update`
  (`running|requires_action|idle` + `stopReason`), `user_/agent_message[_chunk]`,
  `agent_thought[_chunk]` (v2 keyed by `messageId`), `tool_call`, `tool_call_update`,
  `tool_call_content_chunk`.
- `session/request_permission` is stored as `Permission{request_id, title, description, options:[(optionId,name)]}`.
  The answer is `{"id":req,"result":{"outcome":{"outcome":"selected","optionId":…}}}`.
  If there are no options, the client auto-replies `{"outcome":"cancelled"}`.
- `elicitation/create` (form only) and `$/cancel_request` are handled.
- Any other request gets `-32601 "Method not supported by this client"`. This covers **ACP `fs/*` and
  `terminal/*` client methods, which are NOT implemented**.

### 2.4 Status model
`Status = Connecting | Idle | Working | Done | Error` (`session.rs:27`). The mobile snapshot sends
these as lowercase strings. "Needs attention" is derived as `elicitations.len() + permissions.len() > 0`.

## 3. Live terminal bytes / rendering

- **No agent terminal streaming exists.** Agents are headless ACP processes, so there are no TUI bytes.
- The terminal drawer (`src/app/terminal.rs`) works like this:
  ```rust
  let mut options = TerminalOptions::new(shell_words::quote(&shell).into_owned(), &project.path);
  options.configuration = TerminalConfiguration::UserDefaultWithOverride(theme);
  match Terminal::spawn(options, window, cx) { … }     // gpui_libghostty spawns PTY + renders
  ```
  libghostty owns the PTY, VT parsing, keys, and resize. The app only sets height and visibility and
  pushes a 16-colour `TerminalTheme` derived from the app palette (live light/dark). The comment
  "Native surfaces need explicit visibility" suggests it embeds a native Ghostty surface (a guess:
  an NSView/Metal child on macOS). It is local only, not restored on restart, and not on Web Connect.
- Built with Zig 0.16 (`.github/actions/setup-terminal/install-zig.py`). The first build downloads
  Ghostty's dependencies.

## 4. UI state model and pane layout

- Hierarchy: **Project (path + optional ssh_host) → Agents (sessions)**. Sidebar sessions can be
  nested under projects or flat (`nested_sidebar`, `sidebar_order`). Archive is a flag on `AgentConfig`.
- **Panes are a view layer, not process containers** (`src/panes.rs`):
  ```rust
  #[serde(tag = "kind", rename_all = "snake_case")]
  enum Node { Pane { id: u64, session: Option<u64> },
              Split { id: u64, direction: Direction /*Right|Down*/, ratio: f32, first: Box<Node>, second: Box<Node> } }
  struct Layout { root: Node, focused: u64 }
  ```
  Constants: `MIN_WIDTH 320`, `MIN_HEIGHT 280`, `DIVIDER 1px`. `sizes()` clamps the ratio against
  the subtree minimum sizes. A session shows in at most one pane: "sessions already visible receive
  focus". Closing a pane does not stop its agent. The layout is saved in `config.pane_layout` and
  restored on restart. The diff panel follows the active pane.
- Web Connect has **one session at a time** (a list of projects/agents, then a conversation).

## 5. Local storage vs fetched

`config.json` (`AgentConfig`, `src/config.rs:135`) stores: `id`, `command`, `archived`, names/titles,
**`session_id`** (the harness reference), `model`, `context`, `available_commands`,
**`pending_prompts`** (the queue survives restart), `active_prompt`, `was_working`, fork info. It also
stores the pane layout, theme, key bindings, and sidebar prefs.
`messages` has `#[serde(skip)]`, with the comment *"Conversation text belongs to the harness. These
fields are transient UI state."* The conversation comes back from ACP replay on reconnect. This
matches our "store as little as possible" goal.

Secrets (iroh identity and linked browser tokens) live in **SecretSpec** (system keyring, 1Password,
…). They are never written to `config.json`.

## 6. Multi-host

- **Agent hosts**: SSH only, per project, as `ssh://user@host/abs/path` (`src/remote.rs::parse_project`
  rejects hosts that start with `-`, which blocks `-oProxyCommand` injection). It uses
  `BatchMode=yes` and `StrictHostKeyChecking=yes`, so the user's existing keys and `known_hosts`
  must already work. Diff and terminal are local only. Nothing runs remotely except the agent itself.
  There is no remote daemon, so a remote agent dies when the SSH session ends.
- **Client devices**: iroh (next section). The desktop is the only "server". There is no
  desktop-to-desktop link.

## 7. Mobile / Web Connect transport (iroh)

### 7.1 Wire protocol (`crates/control-protocol/src/lib.rs`)
```rust
pub const ALPN: &[u8] = b"agentaps/control/0";
pub const MAX_REQUEST_BYTES: usize = 64 * 1024;   pub const MAX_RESPONSE_BYTES: usize = 16 * 1024 * 1024;
struct Request { token: String, command: Command, client_name: Option<String> }
#[serde(tag="type", rename_all="snake_case")]
enum Command  { Pair, Snapshot, Prompt{agent_id,text}, Cancel{agent_id},
                Permission{agent_id,request_id,option_id}, NewSession{project,command:Vec<String>,name} }
enum Response { Paired{token}, Snapshot{projects:Vec<Project>, agent_options}, SessionCreated{agent_id},
                Accepted, Error{message} }
struct Agent { id:u64, name, status:String, active:bool, has_older_messages:bool,
               messages:Vec<Message{role,text}>, permissions:Vec<Permission{request_id,title,description,options:[{id,label}]}> }
```
Example `Snapshot` request on the wire: `{"token":"<64hex>","command":{"type":"snapshot"}}`.

### 7.2 Framing
**One QUIC connection per request.** `endpoint.connect(remote, ALPN)`, then `open_bi`, then write the
JSON, then `finish`, then `read_to_end(16MB)`, then `connection.close`. See `web/src/connection.rs::request`.
The server does `accept_bi`, then `read_to_end(64KB)`, then dispatches, then `write_all` + `finish`,
then waits up to 30 s for the client to close (`src/mobile.rs::send_response`). This is plain
request/response with no streaming and no subscriptions.

### 7.3 Endpoints
- Desktop: `Endpoint::builder(presets::N0).secret_key(secret).alpns(vec![ALPN]).bind()`. This uses n0's
  production relays and pkarr/DNS discovery. The EndpointId (the public key) is the stable address.
- Browser: `presets::Minimal` + `PkarrPublisher::n0_dns()` + a custom `DotlessRelays` wrapper around
  `PkarrResolver::n0_dns()` + `RelayMode::Custom(default prod relays without trailing dot)`. A
  comment explains why: *"Safari cannot connect to hostnames with a trailing dot, and n0's default
  relay URLs all end in one."* In a browser, iroh can only use the relay (WebSocket). There is no
  UDP hole punching from WASM, so all browser traffic goes through n0 relays. The relay only sees
  QUIC-encrypted bytes.

### 7.4 Sync model
- Desktop: `poll_mobile` runs on each UI tick and rebuilds `Response::Snapshot` into a shared
  `Arc<Mutex<Response>>` at most every 500 ms (or right after a command or status change). A
  `Snapshot` request is served straight from that mutex, without a round trip to the UI thread.
  Other commands go to the UI thread through `mpsc`, and the reply comes back through a
  `tokio::oneshot`.
- The snapshot holds **every project and agent with its last 100 messages**. Each message is cut to
  4000 characters (`mobile_text`). There are no deltas. Tool calls are flattened to text lines
  (`"Title · status\n details"`).
- Browser: a loop drains queued commands, sends a `Snapshot` request, and then waits
  `pollDelay()` = **800 ms**. It stops when `document.hidden`. The page "locks when hidden or
  reloaded", so the user must unlock again.

### 7.5 Pairing and auth
1. The desktop has a persistent iroh `SecretKey` and a rotating **pairing token** (random 32 bytes hex).
2. Link/QR: `{web_url}#{endpoint_id}:{pairing_token}`. The default base is `https://agentaps.dev/`,
   which can be overridden with `AGENTAPS_WEB_URL` or a setting. The secret is in the **fragment**,
   so the static host never receives it. The page calls `history.replaceState` to remove it. The
   in-page QR scanner (`rqrr` over camera frames) checks `url.origin() == location.origin`.
3. The browser sends `Request{token: pairing_token, command: Pair, client_name}`. The desktop
   compares in constant time (`subtle::ct_eq`), creates a per-client `{id, name, token, paired_at}`,
   saves it to SecretSpec (and reads it back to verify), **rotates the pairing token** (one use only),
   and returns `Paired{token}`.
4. Every later request carries this client token. `authorizes()` checks it in constant time against
   all linked clients. Revoking a client deletes it. The UI lists linked clients.
5. Browser at rest: `{endpoint, token}` is encrypted with AES-GCM in `localStorage`. The AAD is the
   storage key. The key comes from a **WebAuthn PRF passkey** (HKDF, info `"Agentaps phone unlock v2"`)
   or from a **PBKDF2 passphrase of 15 or more characters**.
6. To rotate everything, delete the `MOBILE_CREDENTIALS` secret. This gives a new iroh ID and drops
   all clients.

Transport security comes from iroh/QUIC TLS bound to the desktop's public key, so the client
authenticates the server by EndpointId. The server authenticates the client only by the bearer token
in the JSON body, not by the client's iroh key. (A fact: the server never checks
`connection.remote_id()`.)

### 7.6 What mobile can do
Read conversations, send prompts (queued if the agent is busy), stop turns, answer permissions,
start a new session (local path or `ssh://`, with any ACP command). It cannot do diff,
elicitation forms, or terminal.

## 8. Push notifications

**There are none.** There is no APNs and no web push. `src/app/notifications.rs` raises desktop OS
notifications (`cx.show_system_notification`, tagged with agent_id) when:
- the attention request count goes up ("Needs your input": a permission or elicitation arrived), or
- the status changes to `Done` ("Finished"),

and only when the session is **not on screen** (window inactive, or another session displayed).
Clicking a notification opens that session. The phone learns about changes only while the page is
open and polling.

## 9. Chat view details

- Source: **ACP only**. There are no JSONL readers and no hooks. History is replayed by the harness
  (`replayFrom:{type:"start"}` on v2).
- Entries: `ChatEntry{role: User|Agent|Thought|Tool|System|ContextReset, key, text, images}`. Tool
  calls upsert by key `tool:{toolCallId}`, with the headline `"{title} · {status}"` (status one of
  `pending|in_progress|completed|failed`) and details after the first `\n`. The renderer groups
  consecutive Tool entries (`render/tool_group.rs`) and has special cases: "Guardian Review" is the
  Codex approval reviewer, and "Terminal"/"Using tool" are treated as generic titles.
  `shell_steps()` splits shell scripts into steps for display.
- Permissions are shown as cards with one button per option (desktop and `web/src/ui/render.rs:439`).
- Composer: `/` for agent slash commands (from `available_commands_update`), `@` for file search
  (nucleo), and `!cmd` asks the agent to run a shell command. Prompts sent while busy go to a
  persisted queue. Up/Down recalls history. Image paste is allowed if `promptCapabilities.image`.
  Text files are embedded as `resource` if `embeddedContext`, otherwise sent as `resource_link`.
- Per-agent adapters are minimal: discovery lists in `src/discovery.rs`, an env tweak for Claude
  (`CLAUDE_CODE_EXECUTABLE`, removes `ANTHROPIC_API_KEY`), and heuristics for config options
  (`model`/`thought_level`/`mode`/Codex "collaboration" Plan toggle). The rest is generic ACP.
- Fork: a new session seeded with the visible conversation as context. Reset context: `session/new`
  on the same process, with settings re-applied.

## 10. Web page / other non-terminal panes

None. The only pane content is a chat session or empty. The diff is a shared side panel. The
terminal is a drawer inside a chat pane.
