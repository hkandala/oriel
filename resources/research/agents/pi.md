# pi: chat view research

> Two spikes in throwaway herdr panes for the [chat view](../ui/chat-view.md). The second one settled the reliable core below; spike scripts and samples lived in `/tmp/oriel-research/` and were not kept.

Agent: `/usr/local/bin/pi` (company launcher) → `pi_cli/pi.real`, upstream `@earendil-works/pi-coding-agent` 1.4.0.
Tests ran in herdr session `oriel-dev-research-pi2` (removed). Panes were started the way the chooser starts
them: `herdr pane run <pane> "<command>"` types the command and Return into the pane's shell.

## Summary

| Feature | Mechanism | Rating | Evidence |
|---|---|---|---|
| Launch flags | `pi -e <oriel-pi.ts> --oriel <state.jsonl>`. The extension file is written once by a relay run | **RELIABLE** | The launcher passed both flags through to `pi.real`. The user's 22–24 extensions, herdr integration and settings stayed active |
| Recognize an Oriel pane | `--oriel <path>` in the argv from `pane.process_info`. This works after an Oriel relaunch too | **RELIABLE** | Both `pi` and `pi.real` show the argv |
| Ready for input | The first `session` line in the state file (pi runs `session_start` in TUI mode) | **RELIABLE** | herdr already says `idle` about 1 s after launch, before the TUI is up. A prompt sent then was typed into the editor, and its Enter was lost |
| Transcript discovery | The last `session` line in the state file gives `path`. herdr's `agent_session` gives the same path when the herdr integration is installed | **RELIABLE** | startup, /new, /fork, /resume tested. Both sources agreed every time |
| Follow /tree | A `tree` line gives the new leaf, because pi writes nothing to the transcript on /tree | **RELIABLE** | `{"type":"tree","leaf":"07f07f41"}`, while the file's last entry was still `37364911` |
| Compaction | Same file. pi appends a `compaction` entry | **RELIABLE** | Tested with project-local `keepRecentTokens:1500` |
| File watching | `tail -F` on the path. Each entry is one whole line, written at `message_end` | **RELIABLE** | 40 ms from disk to watcher. Up to 1 s when the file is created late |
| Parser | Walk `parentId` back from the last entry (or from the `tree` leaf). Map a few types. Skip and count everything else | **RELIABLE** for the core, **FRAGILE** for the abort shape | See §3 |
| Send | `herdr agent prompt`. Enter while working = steer | **RELIABLE** | idle, working and multiline tested |
| Send confirmation | The user entry appears in the transcript | **RELIABLE**, but late for steer | A steered message lands only when pi delivers it, after the current tool ends |
| Refuse send in an extension dialog | `ui_prompt_start/end` → `herdr:blocked` and a `blocked` state line | **RELIABLE** | `agent prompt` → `{"code":"agent_blocked"}` |
| Refuse send in a built-in picker | none (`/model`, `/tree`, `/fork`, `/resume`, `/settings`) | **SKIP** → show the TUI | herdr says `idle` and the extension sees nothing. Screen checks are fragile |
| Interrupt | `herdr agent send-keys esc` | **RELIABLE** | `stopReason:"aborted"`, or `stopReason:"error"` + "The operation was aborted." |
| "Waits on something" | A `blocked` state line with `kind` and `title` | **RELIABLE** for extension dialogs | confirm, select, input, a tool gate and a timeout were all seen and cleared |
| In-chat answers | keys (`enter`, `down enter`, `esc`, text + `enter`) | **FRAGILE** → show the TUI | They work, but the options are unknown and an answer can race into the editor |
| Remote | All file + herdr one-shot + `tail -F` streams | **RELIABLE** (reasoned, no sshd test) | §7 |
| Model, thinking, slash commands, images | keys / typed commands | **SKIP** → show the TUI | §8 |

## Launch command

Before the first launch on a machine, Oriel does one relay run. The extension has no `'`, so it fits in single quotes:

```sh
d="${XDG_CACHE_HOME:-$HOME/.cache}/oriel"; mkdir -p "$d/state" && chmod 700 "$d" &&
f="$d/pi-<sha8>.ts"; [ -f "$f" ] || { printf '%s' '<file text>' > "$f.tmp" && mv "$f.tmp" "$f"; }
```

Then Oriel types this into the pane's shell (it keeps the user's alias for `pi`, if any):

```sh
pi -e ~/.cache/oriel/pi-<sha8>.ts --oriel ~/.cache/oriel/state/<uuid>.jsonl
```

- Use a per-user 0700 folder, not a shared `/tmp/oriel`: anyone who can write the folder can run code in pi.
  Name the file by content hash, so two Oriel versions don't fight and the write is idempotent.
- **The file must exist.** If `-e` names a missing file, pi exits at once with `Failed to load extension … Extension
  path does not exist` and `Unknown option: --oriel` (tested). The chooser's failure rule then shows the terminal.
- No `-ne`, no `--session-dir`, no `--session-id`. pi still loads the user's settings, packages and extensions, and
  herdr's integration (`agent_session` and states were still reported). Sessions stay in the user's normal folder, so
  `/resume` works as usual.
- `--session-id <uuid>` would fix only the first file name (`<ts>_<uuid>.jsonl`), not /new or /fork. It is not needed.
- `--session <path>` with a path that does not exist uses that exact path (pi source `_setSessionFile`). It is not needed either.
- Not inline: pi needs a real `.ts` path, and `/reload` reads the file again. A pipe (`<(…)`) cannot be read twice.
- Lost on resume: herdr's resume and pi's exit hint (`pi --session-dir … --session <id>`) start pi without Oriel's
  flags. That pane then has no `--oriel` in its argv, so it is shown as a terminal only. That is the intended rule.

**Recognize the pane after an Oriel relaunch:** `pane.process_info` returns `foreground_processes[].argv`. It held
`["/usr/local/bin/pi","-e",".../oriel-pi.ts","--oriel",".../state/e5ae….jsonl",…]`, and `pi.real` showed the
same args after the launcher's own `--extension …`. Find `--oriel`, take the next arg, and read the state file. Oriel
keeps no other state. The `pid` in each `session` line matches `pi.real`'s pid in `process_info`. Delete the state
file when the pane closes.

## The extension (`oriel-pi.ts`)

It appends to `--oriel`, only in TUI mode:
`session {reason,path,pid}`, `blocked {kind,title}`, `unblocked`, `tree {leaf}`, `working`, `idle`, `shutdown`.
On `ui_prompt_start` and `ui_prompt_end` it emits `pi.events "herdr:blocked"` `{active}`.

Why it is robust:
- It uses public events only: `session_start` with `reason`, `session_tree`, `ui_prompt_start/end`, `agent_start`,
  `agent_settled`, `session_shutdown`, and `registerFlag`/`getFlag`. There is no monkeypatch. Round 1 wrapped `ctx.ui`;
  that is no longer needed.
- pi's runner wraps the shared `ctx.ui` itself (`wrapUIPromptContext`). So `ui_prompt_*` fires for **every**
  extension's `select/confirm/input/editor/custom`. Nested prompts give one start/end pair.
- Version floor: `ui_prompt_*` is in pi **0.84.4+**, `agent_settled` 0.80.4+, `ctx.mode` about 0.7x, and
  `session_start.reason` long before that. On an older pi, unknown `pi.on` names simply never fire: the `session`
  lines still work, and `blocked` lines are just missing. Oriel can check `pi --version` (the last line; the launcher
  prints a banner first) in the same relay run.
- It writes to herdr only through `herdr:blocked`, so herdr's own integration (installed on this Mac) does the
  reporting. Without that integration (for example on a remote machine), the state file alone still drives the chat.

## Details

### 1. Launch: tests
- Pane `w1:p1`, launched with Oriel's flags plus `--session-dir`/`--model`/`--thinking low` and the stand-ins (the
  extra flags only keep the test out of the user's session folder and cheap). The state file got
  `{"type":"session","reason":"startup","path":".../2026-10-28T07-35-46-023Z_e5aefd15-….jsonl","pid":74269}`.
  `pane get` showed the same path as `agent_session {kind:"path",source:"herdr:pi"}`.
- `~/.pi/agent` top-level files, compared before and after: only `meta-muse-model-catalog.json` changed (00:35, at
  the first pi start). That is the company build refreshing its model catalog cache, as on every pi start. It is
  not from Oriel's flags. No `trust.json` was written. I did not use `/reload`, which writes it.

### 2. Transcript discovery: tests

| Action | State file | herdr `agent_session` | Transcript |
|---|---|---|---|
| startup | `session reason:startup` | same path | written at the first message (header + buffered entries at once) |
| /new | `shutdown`, then 1.4 s later `session reason:new` | updated | new file, not on disk until the first message |
| /fork (picker) | `session reason:fork` | updated | new file. Forking at the first message put its text in the editor, and the file came later |
| /resume (picker) | `session reason:resume`, old path | updated | the existing file, appended to |
| /tree (picker) | `tree leaf:<id>` | no change | **nothing written** until the next entry |
| /compact | nothing | no change | `compaction` entry appended to the same file |
| /quit | `shutdown` | — | — |
| /clear | does not exist in pi | | |

The chat always tails the path from the newest `session` line. "Path known, file missing" is normal: keep `tail -F`
running. pi rewrites a file in place (`open "w"`) only when it migrates an old-version file on load, or when the
file is empty. So on truncation, re-read from offset 0 (`tail -F` prints "file truncated" and starts over).

### 3. File watching and the parser
- `tail -n +1 -F` on This Mac, started before the file existed. The first flush arrived 0.75 s after pi wrote it
  (`tail` checks for a missing file once per second). After that, the disk timestamp to the watcher line was
  41 ms, 39 ms and 226 ms (`tail.log`). pi writes one whole line per entry with `appendFileSync`. I saw no partial
  line, but the parser keeps a trailing fragment anyway.
- Write timing: user entry at submit. Assistant entry at its `message_end`: a tool-call message is written before
  the tool runs (and before any approval gate). Tool result when the tool ends. There is no live text (by design).
- `parse.py` emits: `user` (text, image count), `assistant`, `thinking`, `tool` (call paired with its result by
  `toolCallId`), `bash` (user `!cmd`), `error`, `aborted`, `turn_end` (any `stopReason` other than `toolUse`),
  `divider` (compaction, branch_summary), `note` (`custom_message` with `display:true`). It skips and counts
  everything else. For my sample: `{'model_change':1,'thinking_level_change':1,'role:system':1,'custom_message':1,'custom':1}`.
  `--follow` ran on a not-yet-existing path through 2 turns and a compaction (`follow.log`).
- **Robust:** the tree walk (`id`/`parentId`), `message.role`, the content block types `text/thinking/toolCall`,
  `toolResult.toolCallId`, and skipping unknown types, blocks and roles.
- **Fragile:**
  - The abort shape. Esc while streaming gave `stopReason:"aborted"`, "Operation aborted". Esc during a tool gave a
    `toolResult` (isError, "Killed: 9"), then an empty assistant with `stopReason:"error"`, "The operation was
    aborted." The parser matches "abort" in the error text.
  - Subagents, todos and plan mode are not built in. They are plain tools (the user's `agent_start`, the company
    `codemode`), so they show as generic tool rows.
  - The user's extensions add entry types: `pi-time-sense` `custom_message` (display:false), `pi-retry`
    `context_edit`. Both are skipped.
- Show the raw branch. Don't apply `context_edit` or the compaction window; those only change what the model sees.

### 4. Send
- Idle: `agent prompt` → `agent_prompted`. The user entry appeared in 0.75 s (first flush), later ones in about 40 ms.
- While working (`sleep 6` tool): `agent_prompted`, shown as a steer. The transcript order was toolResult → **user
  (steer)** → assistant. The user entry is written at delivery (48.459), not at submit (about 43.4). So the chat
  shows the message as "queued" until its entry appears. A follow-up (Alt+Enter) needs keys; `agent.prompt` always
  presses Enter.
- Multiline: one user entry, `"line one of steer\nline two: …"`.
- Failure cases:
  - **Starting:** herdr reported `idle` 1 s after launch. A prompt sent then was typed into the editor, but not
    submitted. Gate sending on the state file's `session` line: a prompt sent right after it worked (`READY`).
  - **Extension dialog:** `{"error":{"code":"agent_blocked",…}}`, and nothing was typed.
  - **Built-in picker:** herdr says `idle`, and `agent.prompt` would type into it (round 1 showed this; the `/fork`
    picker's Enter forks). The `/model` picker's Enter selects (Ctrl+S sets the default). Rule: the composer does
    not send `/…` text. It switches to the TUI and types it there.
  - **Session switch:** do not send between `shutdown` and the next `session` line.
- Ready = the last state line is `session`, `idle`, `unblocked` or `tree` (not `blocked` or `shutdown`) **and**
  herdr `agent_status` is `idle` or `working`.

### 5. Interrupt
`herdr agent send-keys <pane> esc`. In the transcript: an assistant entry with `stopReason:"aborted"` (streaming)
or `"error"` + "The operation was aborted." (during a tool, after a killed `toolResult`). The state file gets `idle`.
Esc in a dialog cancels the dialog only. Never send ctrl+c (it clears the editor, and twice exits).

### 6. Approvals and questions
pi has no built-in approvals. Questions come only from extensions, and every one of them goes through `ctx.ui`.
- **The chat knows pi waits:**
  - `/ask-me` gave `blocked confirm "Deploy?"`, then `select "Pick a color"`, then `input "Your name?"`, each about
    11 ms after the previous `unblocked`.
  - The tool gate gave `blocked select "⚠️ Dangerous command:\n\n  rm -rf ./nothing-here\n\nAllow?"` 33 ms after the
    tool-call entry. So the chat can label the pending tool row "waiting".
  - herdr went to `blocked` too.
- **Answered from outside with keys:** `enter` (Yes), then `down enter` (green), then `send-text Ada` + `enter` →
  `asker got ok=true color=green name=Ada`. Gate: `down enter` → toolResult `"Blocked by user"`, isError.
- **Timeout:** a `{timeout:2000}` confirm gave `blocked`, then `unblocked` after 2.4 s, and herdr went back to
  `idle` (`timed got false`).
- **Race:** after the TUI answered, a late `enter` from the chat landed on an empty editor and did nothing. With a
  draft in the editor, it would submit the draft. The options and the default are not in the event (only `kind` and
  `title`). So in-chat buttons need the round-1 `ctx.ui` wrap: **FRAGILE**.
- **Other extensions and policies:** they keep working. Another extension that emits `herdr:blocked` itself only
  raises herdr's counter, and each pair stays balanced. `meta/command-policy` blocks without asking, so no prompt
  is shown.
- **Rule:** on `blocked`, the chat shows a row "pi is asking: ‹title›" and a "Show terminal" button. Built-in
  pickers send no signal. They only open from typed `/` commands or keys in the TUI, so the user is already in the TUI.

### 7. Remote (one SSH relay: line streams and one-shot commands)
Reasoned out; I did not start a test sshd.
- **Write the extension:** one `sh -c` run (above). It needs only POSIX sh, `printf`, `mkdir` and `mv`.
- **Launch and recognize the pane:** herdr `pane run` and `pane.process_info` on the remote herdr, as on This Mac.
- **State:** `tail -n +1 -F <state>` as one long-lived stream. **Transcript:** `tail -c +<offset> -F <path>`. When a
  new `session` line arrives, restart that stream. GNU and BusyBox `tail -F` both retry missing files, and GNU
  uses inotify.
- **Send, keys, interrupt:** herdr one-shots.
- **Blocked:** the state file works even when the herdr pi integration is not installed on the remote. Then
  `agent.prompt` is not refused, so the chat must check the state line itself.
- The only file Oriel installs is `~/.cache/oriel/pi-<sha8>.ts`. No daemon, no socket, no port.

### 8. Everything else
| Item | Rating | Note |
|---|---|---|
| Model / thinking change | SKIP → TUI | `/model <exact scoped id>` and `/thinking <lvl>` work as typed text, but a non-exact name opens the picker. Read the current model from the last assistant entry's `provider/model/thinkingLevel` (RELIABLE, display only) |
| Slash commands | SKIP → TUI | Typed into the TUI. Headless ones (`/name x`, `/compact`, `/new`) show up in the state file or transcript |
| Images | SKIP | A pasted path stays text. A real image block needs an extension API (round-1 bridge) |
| Subagents, todos, plan | generic tool rows | Not built in |
| Cost / context | RELIABLE (display) | Sum `usage.cost.total` over the assistant entries |
| Steer vs follow-up | steer only | `agent.prompt` = Enter = steer |
| Live text | SKIP | By design (would need the round-1 socket) |

Option (a), with no extension, works for discovery only where the herdr integration is installed. It has no ready
signal (herdr says `idle` early) and no blocked signal (dialogs read as `idle`, and `agent.prompt` answers them).
Option (b) costs 31 lines and one cached file, and closes all three gaps. **Recommend (b).**

## Source

The extension as tested (31 lines). Oriel writes it to `~/.cache/oriel/pi-<sha8>.ts` before the first launch on a machine.

```ts
// Oriel chat helper for pi. Load per run: pi -e <this file> --oriel <state.jsonl>
// Appends one JSON line per change: the live transcript path, and whether a ctx.ui dialog is open.
// Also tells the herdr pi integration (if installed) that pi is blocked, so herdr agent.prompt refuses.
// @ts-nocheck
import { appendFileSync } from "node:fs";

export default function (pi) {
	pi.registerFlag("oriel", { type: "string", description: "Oriel: state file to append to" });
	let ui = false; // a TUI session is live
	const w = (o) => {
		const f = pi.getFlag("oriel");
		if (ui && f) try { appendFileSync(f, JSON.stringify({ ts: Date.now(), ...o }) + "\n"); } catch {}
	};
	pi.on("session_start", (e, ctx) => {
		ui = ctx.mode === "tui";
		w({ type: "session", reason: e.reason, path: ctx.sessionManager.getSessionFile(), pid: process.pid });
	});
	pi.on("ui_prompt_start", (e) => {
		pi.events.emit("herdr:blocked", { active: true, label: e.title ?? e.kind });
		w({ type: "blocked", kind: e.kind, title: e.title });
	});
	pi.on("ui_prompt_end", () => {
		pi.events.emit("herdr:blocked", { active: false });
		w({ type: "unblocked" });
	});
	pi.on("session_tree", (e) => w({ type: "tree", leaf: e.newLeafId })); // /tree moves the leaf without writing the transcript
	pi.on("agent_start", () => w({ type: "working" }));
	pi.on("agent_settled", (_e, ctx) => ctx.isIdle() && w({ type: "idle" }));
	pi.on("session_shutdown", () => w({ type: "shutdown" }));
}
```

## From the first spike

- A bridge extension with a unix socket inside the TUI gave live deltas, sends with steer or follow-up, images, abort, `setModel` and `setThinkingLevel`, and every extension dialog raced between the TUI and a client (first answer wins). Not needed without live text; the 31-line state extension covers the core.
- `pi --mode rpc` on the TUI's session file is a second process: it split the tree into two sibling branches. Never.
- `/reload` loads a new extension into a running TUI, but writes `~/.pi/agent/trust.json`.
- `/model <exact scoped id>` switches directly; any other argument opens the picker. ctrl+p cycles models, shift+tab cycles thinking.
