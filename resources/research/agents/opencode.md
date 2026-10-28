# opencode: chat view research

> Two spikes in throwaway herdr panes for the [chat view](../ui/chat-view.md). The second one settled the reliable core below; spike scripts and samples lived in `/tmp/oriel-research/` and were not kept.

Tested: npm `opencode-ai@1.19.4` (round 1 install), `XDG_*` under `/tmp`, project `.opencode/opencode.json` with
`{env:…}` for the gateway, Haiku 4.5, `bash`/`edit` set to `ask`. herdr 0.9.5, throwaway session
`oriel-dev-research-opencode2`. Commands were typed into the pane's shell with `herdr pane run`, the way the chooser
would.

## Summary

| # | Feature | Mechanism | Rating | Evidence |
|---|---|---|---|---|
| 1 | Launch flags | `--port 0 --hostname 127.0.0.1` + `OPENCODE_SERVER_PASSWORD` (read from a 0600 file) + `OPENCODE_TUI_CONFIG` → Oriel's 20-line TUI plugin | RELIABLE (npm build) / SKIP (company launcher) | 1.1 |
| 1 | Recognize the pane | The plugin's state line `{pid,url,session,dialog}` in a file whose path Oriel chose; its `pid` = `pane.process_info` pid | RELIABLE | 1.2 |
| 2 | Find the transcript | `session` field in the state line (from `api.route.current`), and the server URL, so the chat reads `GET /session/<id>/message` | RELIABLE | 2 |
| 2 | Follow /new, /sessions, fork, compaction | State line changes within 200 ms. Compaction keeps the id and adds a `compaction` part. Subagents are child sessions. | RELIABLE | 2 |
| 3 | Watch | `curl -sN /event` (SSE, one JSON object per `data:` line) + `tail -F` of the state file | RELIABLE | 3 |
| 3 | Parser | Upsert messages and parts by id (`parse.py`). The same code reads history and SSE, and skips unknown types. | RELIABLE core, FRAGILE extras | 3.3 |
| 3 | SQLite polling (no port) | `sqlite3 -json` on `part.time_updated` | FRAGILE | 3.4 |
| 4 | Send | `herdr agent prompt`, only when the state line has `dialog:false` and herdr is not `blocked`. Confirmed by the user message on SSE (~0.4 s). | RELIABLE | 4 |
| 4 | `prompt_async` | Shows in the TUI, but ignores the TUI's agent (Plan) and model selection | FRAGILE | 4 |
| 5 | Interrupt | `esc` `esc` (herdr send-keys). On disk: `error.name=MessageAbortedError`. | RELIABLE | 5 |
| 6 | Permissions | SSE `permission.asked` / `GET /permission` → `POST /permission/:id/reply {once,always,reject}` | RELIABLE | 6 |
| 6 | Questions | SSE `question.asked` / `GET /question` → `POST /question/:id/reply {answers:[["Blue"]]}` | RELIABLE | 6 |
| 6 | Other waits | `dialog:true` (pickers), or herdr `blocked` with no known request → show the TUI | RELIABLE | 6 |
| 7 | Remote | All of the above as line streams and one-shot commands over one SSH connection (tested with a user-mode sshd) | RELIABLE | 7 |
| 8 | Model/mode change, pickers, images, `@file` | Show the TUI. `tab` cycles the agent. | SKIP | 8 |
| 8 | Show model/agent, todos, subagent rows | From the transcript (`agent`, `modelID`, `todowrite` input, `task` metadata `sessionId`) | RELIABLE | 3.3 |

## Launch command (what Oriel types)

One relay run per host, once. It writes three files into `D=${XDG_CACHE_HOME:-$HOME/.cache}/oriel/opencode`, a 0700
folder:
- `oriel-tui.js`: copy of `oriel/oriel-tui.js`.
- `tui.json`: `{"plugin":["<D>/oriel-tui.js"]}`.

One relay run per pane:
- `umask 077; printf %s <random> > <D>/<terminal_id>.pw`.

Then Oriel types this into the pane (`T` = herdr `terminal_id`; `<opencode>` = the resolved binary):

```sh
 env ORIEL_OC_STATE=<D>/<T>.jsonl OPENCODE_TUI_CONFIG=<D>/tui.json sh -c 'OPENCODE_SERVER_PASSWORD=$(cat <D>/<T>.pw) exec <opencode> --port 0 --hostname 127.0.0.1'
```

Tested as typed. `process_info` argv is `opencode --port 0 --hostname 127.0.0.1`. The password is not in the
scrollback, the argv or the shell history (`grep` on `pane read recent`: 0). The server answered 401 without auth
and 200 with it.

## 1. Launch flags and recognition

**1.1 Why each part.**
- `--port 0` turns on the HTTP listener inside the TUI process. Without it, v1 has no side door. Port 0 tries 4096
  first, then picks a random port; the second pane got `127.0.0.1:59843`.
- `--hostname 127.0.0.1` beats a user config `server.hostname`, such as `0.0.0.0` or `mdns`.
- `OPENCODE_SERVER_PASSWORD` turns on Basic auth (user `opencode`). In `--port` mode the TUI itself uses
  `ServerAuth.headers()`, so it keeps working.
- `OPENCODE_TUI_CONFIG` is **merged** between the global and the project `tui.json`, so plugins are concatenated.
  Test: the user's herdr plugin (copied into the `/tmp` global config) and Oriel's plugin both ran. herdr
  `agent_session` and Oriel's `session` showed the same id.
- No user file is touched. The user's `opencode.json`, permission rules and plugins apply unchanged.
- The env vars are inherited by the agent's tools (same user, so this is acceptable).
- Not caused by Oriel: on every start, opencode itself writes `.gitignore`, `package.json` and `node_modules` into the
  global config folder and into every `.opencode` folder (its `@opencode-ai/plugin` install). This happens with or
  without plugins.

**1.2 Recognition, also after an Oriel relaunch.** The plugin appends a line to `$ORIEL_OC_STATE` at start and
whenever a value changes (it polls every 200 ms):
`{"t":…,"pid":58763,"url":"http://127.0.0.1:62532","route":"home","session":null,"dialog":false}`.
- Oriel knows the path, because it built it from the `terminal_id`.
- A pane gets the chat switch only when the last line's `pid` equals the pid in `herdr pane process-info`.
- If the user quits and starts opencode by hand, the pid differs, so there is no chat.
- After an Oriel relaunch, `tail -n1` of the file restores `url` and `session`. curl reads the password file on the
  host, so Oriel stores no secret.
- No `lsof` is needed: the plugin reports the real URL.
- Startup: herdr said `idle` at +4.1 s and the first state line came at +6.7 s. opencode waits for its plugin npm
  install before it loads plugins. **Risk:** on a host with no npm registry, this may delay or block the plugin until
  npm fails. Then there is no state line and no chat (a safe failure).

**Security of the port.** Without a password, any local process can drive the agent (prompt → bash → code runs as
the user). Other users on shared Linux hosts can do it too, and maybe web pages through DNS rebinding. **So the
password is required.** With Basic auth over loopback, the risk is the same as the user's own files. On Linux,
`/proc/<pid>/environ` is owner-only and argv does not hold the password. curl gets the password from stdin
(`curl -K -` with `user = "opencode:…"`), never from argv.

## 2. Transcript discovery

The transcript is `GET <url>/session/<session>/message`, which returns `[{info, parts}]`. History is read once, then
SSE takes over. **There is no file to guess. The id comes from this TUI's own route.** Tested, from the state file:

| Action | State line | Notes |
|---|---|---|
| First prompt | `route:"session", session:ses_…ab36` | SSE `session.created` |
| `/new` | `route:"home", session:null` right away | SSE has **nothing** until the first prompt. This is why the plugin exists. |
| `/sessions`, pick an old one | `session:ses_…fc83` | SSE has **nothing** at all. Without the plugin the chat would be stale. |
| `/fork`, then pick a message | `dialog:true` (picker), then the new `ses_…a671` | Copies the history |
| `/compact` | Same id | `compaction` part + assistant message with `agent:"compaction"`; SSE `session.compacted` |
| Subagent (`task`) | Root id kept | Child `ses_…` with `parentID`. The tool metadata `sessionId` links to it. |

Without Oriel's plugin, the fallback is herdr `agent_session`, which works only if herdr's opencode integration is
installed. The SSE-only fallback follows only on activity: FRAGILE.

## 3. Watching

**3.1 Streams.**
- `curl -sN -K - <url>/event`: one `data: {json}` line per event, a blank line, and a heartbeat every 10 s.
- Only this TUI process's events arrive, because each `--port` TUI has its own server and bus. Filter by
  `sessionID`; child sessions use their own id.
- `tail -n1 -F <state>.jsonl` waits for a file that is created late (tested with BSD tail).
- Partial lines: every event is one line. curl line-buffers, so a broken last line only happens when the stream
  dies. Then reconnect and re-read `GET …/message`. Upserts make the replay harmless.

**3.2 Latency (This Mac).** For a 100-word reply ending in `XQ7END`:
- SSE final `message.part.updated` at .585.
- The SQLite row at .600 (polled every 20 ms).
- The TUI screen showed it at .619 (polled every 30 ms).

The **complete** text part arrives when the text block ends, together with the last token on screen. While it
streams, only `message.part.delta` events arrive (ignored by design). So the chat shows each block when it is done.
Tool parts update at pending, running and completed. The user message arrives 0.4 s after `herdr agent prompt`.

**3.3 Parser** (`parse.py`, about 140 lines, with an `assert` self-check in `demo()`).
- Messages and parts go into dicts keyed by id. Ids sort by time.
- Output: `user`, `assistant`, `thinking` (from `reasoning`), `tool` (call and result are **one part**:
  `state.status` / `input` / `output` / `error`), `subagent` (`task`, with `child_session`), `todos` (`todowrite`
  input), `attachment`, `compacted`, `compaction_summary`, `interrupted`, `error`, `turn_end`, `permission_pending`
  and `question_pending`.
- It skips and counts unknown part and event types. sse4 skipped `plugin.added`, `session.diff`, `todo.updated`,
  `tui.*` and others.
- Runs: `python3 parse.py <ses> runs/hist-….json`, `… runs/sse4.log`, `… runs/reasoning-messages.json`.

Robust:
- id-keyed upserts.
- `type` / `role` / `text` / `tool` / `state.status`.
- Ignoring anything unknown.
- History and live data share one shape.

Fragile:
- Per-tool shapes (`todowrite` input, `task` metadata `sessionId`, `question` input).
- Turn end: `finish:"tool-calls"` after a rejected permission has no `stop`. Use SSE `session.idle` /
  `session.status idle` live, and the next user message in history.
- `synthetic` text parts.
- Pending cards: an API `abort` does not publish `permission.replied` (see 6). Rebuild them from `GET /permission`
  and `GET /question` on `session.idle` and on reconnect.

**3.4 No port.** You can poll `opencode.db` (WAL) with `sqlite3 -json`. Rows land as fast as SSE (above). But the
schema is internal, it changes in 2.x, `sqlite3` may not exist on the host, and pending requests are never on disk.
FRAGILE. Only useful for panes not started by Oriel, which get no chat anyway.

## 4. Send

- Idle: `herdr agent prompt` works. Multiline keeps its newlines (`"Multi A\n\nMulti B…"`; herdr adds one trailing
  space).
- Working: the TUI shows the message as `QUEUED`. The user message is **saved at once** and runs after the turn.
  This is a queue, not a steer.
- Confirmation: the user `message.updated` + text part on SSE, about 0.4 s later. No event within ~3 s means the
  send failed, so show the TUI.

Failure cases:
- **A picker is open** (`/models`, `/sessions`, `/fork`): herdr still says `idle`, and the typed text goes into the
  search box (round 1). The plugin says `dialog:true` (tested with `/models` and `/fork`). **Refuse to send while
  `dialog` is true.**
- **Permission or question:** herdr says `blocked` and `agent prompt` returns `agent_blocked`.
- **Starting:** no state line yet. Refuse.

Alternatives:
- `POST /session/:id/prompt_async` → 204, and the TUI showed it. But with no `agent` it uses the **default agent**
  (Build) even when the TUI is in Plan mode. The model comes from the session. FRAGILE.
- `POST /tui/append-prompt` + `/tui/submit-prompt` with a picker open: both returned `true`, but nothing was
  submitted, and the text stayed in the input box. No confirmation. FRAGILE.

## 5. Interrupt

- `esc` shows "esc again to interrupt"; a second `esc` cancels. The TUI shows `· interrupted` and herdr goes `idle`.
- On SSE: `session.error {name:"MessageAbortedError"}`. Saved: the assistant message `error.name` and the partial
  text.
- `POST /session/:id/abort` → `true` also works, but see 6. Prefer the keys.

## 6. Approvals and questions (in-chat, through the port)

- **Seen:** SSE `permission.asked {id, permission:"bash", patterns, metadata.command, always, tool.callID}`; the same
  from `GET /permission`. Pair it with the tool row by `tool.callID`.
- **Answered from outside:** `POST /permission/per_…/reply {"reply":"once"}` → 200 `true`. The TUI dialog closed,
  herdr went `blocked`→`working`, and the command ran. Then SSE `permission.replied {requestID, reply}`.
- **Questions:** `POST /question/que_…/reply {"answers":[["Blue"]]}` → 200. The TUI showed "Blue" and the model
  said "You picked Blue." Then SSE `question.replied`. There is also `/question/:id/reject`. Custom-text answers were
  not tested.
- **Race:** after the user answered in the TUI (`esc` = reject), Oriel's reply got **404
  `PermissionNotFoundError`**: clean. The chat drops the card on `*.replied` or on a 404.
- **Timeouts:** none. A request waits forever (in-memory `Deferred`).
- **Abort while pending:** `POST /abort` ended the turn, but the permission **stayed** in `GET /permission`, in the
  TUI dialog and as herdr `blocked`. A later `reject` cleared it. Keep the card while `GET /permission` lists it.
- **Policies:** config rules are checked before asking. `deny` and `allow` never emit `asked`. The `permission.ask`
  plugin hook exists in the types but is not wired in v1. "Always" adds in-memory rules and auto-replies with
  matching pending requests (`reply:"always"` events).
- **Knowing that it waits:**
  1. A pending request from SSE or GET means a known card.
  2. `dialog:true` from the plugin means a picker. Show the TUI.
  3. herdr `blocked` (screen-based; it worked without herdr's plugin) with no pending request means something
     unknown. Show the TUI.

## 7. Remote (one SSH connection, line streams and one-shot commands)

Tested through a user-mode `sshd` on `127.0.0.1:22999` (temp keys under `/tmp`, `-F /dev/null`; killed after):
- `sh -c "tail -n 1 -F <state>"` streamed the route change to `home`.
- `sh -c 'printf "user = …%s" "$(cat .pw)" | curl -sN -K - <url>/event'` streamed `SSH-OK` and `session.idle`. The
  password stays on the host.
- One-shot `herdr --session … agent prompt` (use the full path: it was not on the non-login `PATH`), and
  `send-keys`.

Everything else is also a one-shot `curl`: history GET, permission and question replies. The plugin files are one
relay write. Needs `curl` on the host; Perl's `IO::Socket` could stand in (not tested). No port forward, no daemon.

## 8. Everything else

| Item | Rating | Note |
|---|---|---|
| Model / variant change | SKIP | A picker chain. Show the TUI. |
| Agent (Build/Plan) | SKIP for setting, RELIABLE for display | `tab` cycles, but the result is only on screen. Show the last message's `agent` and `modelID`. |
| Slash commands | Partly | `/compact` and `/new` sent as text run directly. Picker commands set `dialog:true`, so show the TUI. |
| Images, `@file` | SKIP | A pasted `@file` stays plain text. |
| Subagent detail | RELIABLE (read-only) | `GET /session/<child>/message`, same parser |
| Todos | RELIABLE | `todowrite` input in the transcript; `GET /session/:id/todo` |

## 2.x (unreleased dev)

- **Launch:** the TUI has no `--port`. Every TUI attaches to a shared background service with Basic auth from
  `$XDG_STATE_HOME/opencode/service.json` (0600). So the side door always exists and no password flag is needed.
- **Plugin:** `OPENCODE_TUI_CONFIG` is gone (`tui.json` is migrated). Route reporting needs the v2 plugin path, the
  way herdr's plugin has a v2 `setup()`.
- **API:** routes move under `/api/*`. Questions become forms (`/form/:fid/reply`). The permission reply is
  `/api/session/:id/permission/:rid/reply`. A prompt can use `delivery:"steer"`.
- **Storage:** `session_message` instead of `message`/`part`. The parser needs a second mapping.
- **Shared service:** it serves many TUIs, so filter strictly by `sessionID`.

## Source

The TUI plugin as tested (20 lines), named in Oriel's `tui.json` (`{"plugin":["<D>/oriel-tui.js"]}`). Reading the server URL goes through the SDK client's private `_client`: check it on each opencode release.

```js
// Oriel TUI plugin: appends one JSON line to $ORIEL_OC_STATE whenever the TUI's session, dialog state or server URL changes.
import { appendFileSync } from "node:fs"
export default {
  id: "oriel.state",
  tui: async (api) => {
    const file = process.env.ORIEL_OC_STATE
    if (!file) return
    let last = ""
    const tick = () => {
      const r = api.route.current
      const cfg = api.client?._client?.getConfig?.() ?? api.client?.client?.getConfig?.()
      const s = { pid: process.pid, url: cfg?.baseUrl ?? null, route: r?.name ?? null,
        session: r?.name === "session" ? r.params?.sessionID ?? null : null, dialog: api.ui.dialog.open }
      const k = JSON.stringify(s)
      if (k !== last) { last = k; appendFileSync(file, JSON.stringify({ t: Date.now(), ...s }) + "\n") }
    }
    tick()
    const iv = setInterval(tick, 200)
    api.lifecycle.onDispose(() => clearInterval(iv))
  },
}
```

## From the first spike

- A plain 1.x TUI runs its server in a worker thread with no HTTP listener; only `--port`, `--hostname` or `--mdns` open one. 2.x always attaches to a shared local service (`service.json`, Basic auth).
- Storage is SQLite (`opencode.db`): `session`, `message`, `part` (text, reasoning, tool, step-start/finish with cost and tokens, file, agent, subtask, patch, compaction). Pending permissions and questions are never on disk.
- Keys: Return allows once, Esc rejects, ←/→ move, a digit answers a question; Esc twice interrupts; tab cycles build and plan.
- 1.x `/tui/append-prompt`, `/tui/submit-prompt` and `/tui/publish` drive the TUI's own input and commands. Model and variant pickers report `idle`.
