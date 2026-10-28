# Happy (slopus/happy): a phone app that takes over a terminal Claude by killing it

Repo: https://github.com/slopus/happy (MIT, very active). A pnpm monorepo: `happy-cli` (Node, TypeScript, Ink),
`happy-app` (Expo / React Native for iOS, Android and web), `happy-server` (relay with end-to-end encryption,
tweetnacl). The old `slopus/happy-cli` repo is archived and merged here. You run `happy` (or `happy codex`) instead
of `claude`; the wrapper owns the terminal and the agent. Read for its **local/remote mode switch**, the most-copied
design for "chat on the phone, TUI on the desk".

## The mode switch (Claude)

| | Local mode | Remote mode |
|---|---|---|
| Process | the real `claude` TUI, stdio inherited from `happy` | the Agent SDK (`query()`, stream-json) driving `claude` headless |
| Terminal shows | Claude's own TUI | Happy's Ink screen, a read-only log ("press space twice for terminal") |
| Chat data | transcript file `~/.claude/projects/<dir>/<id>.jsonl`, scanned | SDK messages, converted to transcript-shaped records |
| Input | the keyboard only | the phone (SDK user messages) |
| Approvals | in the TUI; the phone sees nothing to answer | SDK `canCallTool` → phone card (`claude/utils/permissionHandler.ts`) |

- **Local → remote:** a message from the phone, or the app's "switch" RPC, aborts the local child (SIGTERM through an
  `AbortController`) and the loop starts remote mode (`claude/claudeLocalLauncher.ts:75-90`, `claude/loop.ts:78-117`).
- **Remote → local:** double space or Ctrl-T on the Ink screen (`ui/ink/RemoteModeDisplay.tsx:32-41`) aborts the SDK
  run and spawns `claude --resume <id>` again (`claude/claudeLocal.ts:224-228`).
- So **the TUI does not stay alive.** Only one of the two processes runs at a time; they share one conversation by
  `--resume`. A PR once kept the local process alive and queued phone messages until the user quit Claude; phones
  looked hung for 29 minutes (issue #1388), and current `main` kills again.

## How it finds and reads the transcript

- `happy` passes `--settings <tmp file>` with one **SessionStart hook** that posts the hook JSON (session id) to a
  loopback HTTP server (`claude/utils/generateHookSettings.ts:20-45`, `happy/scripts/session_hook_forwarder.cjs`). The id
  comes from Claude, not from a guess; `--continue`/`--resume` change it, and the hook catches that.
- The scanner re-reads the whole file on each file-watch event plus every 3 s, and skips lines it has seen by `uuid`
  (`claude/utils/sessionScanner.ts:67-149`, keys at `:220-232`). It keeps watching old session files too, because
  Claude may still write to them after a resume (`:60-63`). Internal line types are dropped (`:15-19`).
- Known gaps: messages silently dropped while background subagents run (#1626); the scanner followed the wrong file
  after a handoff (#994); remote → local once started a new session (#932).

## "Is it thinking?" without screen scraping

Local Claude starts through `happy/scripts/claude_local_launcher.cjs`, which **monkey-patches `global.fetch`** and writes
`fetch-start`/`fetch-end` lines to fd 3 (`claude_local_launcher.cjs:16-63`). `claudeLocal.ts:316-370` reads fd 3 and
says "thinking" while any request is open, with a 500 ms grace. This only works when `claude` is the JS `cli.js`;
the native binary (≥ 2.1.113) loads no launcher (`scripts/claude_version_utils.cjs:40-60`). There is no "waits for
approval" signal in local mode.

## Codex, Gemini, others

Codex runs only in remote style: `codex app-server` over stdio (`codex/codexAppServerClient.ts`), with an Ink log in
the terminal (`ui/ink/CodexDisplay.tsx`). Open PRs try to bring back a native local Codex TUI (#780, #1222). Gemini
and others go through ACP (`agent/acp/`).

## Remote machines

A `happy daemon` on each machine registers with the relay; the app spawns sessions there (`daemon/run.ts`, optional
tmux). All content is encrypted end to end between CLI and phone (`api/encryption.ts`).

## Reliability tricks

- Force stdin back to blocking before spawning the local TUI; Node leaves `O_NONBLOCK` on and the child gets
  `EAGAIN`, seen as doubled cursors after a switch (`claude/claudeLocal.ts:191-207`, #1148, #647).
- Drain keys typed while Ink owned stdin, so extra spaces from the double-space do not land in Claude's prompt
  (`claude/claudeRemoteLauncher.ts:509-525`).
- On start, cancel approval cards left by a dead CLI, else the phone shows a prompt nothing can answer
  (`claudeRemoteLauncher.ts:105-116`).

## Size

`happy-cli/src` about 40k lines without tests (Claude part about 6k). `happy-app` about 130k lines; the chat list,
message and tool views are a few thousand of those.

## For Oriel

- Copy: get the session id from a **SessionStart hook** passed with `--settings`, not from a cwd guess.
- Copy: dedupe transcript lines by `uuid` and keep watching the old file after a resume.
- Avoid: the mode switch. Killing the TUI to chat breaks Oriel's rule that the TUI never restarts, and every bug
  above sits on that seam.
- Avoid: the `fetch` patch for status; it is dead on the native Claude binary.
