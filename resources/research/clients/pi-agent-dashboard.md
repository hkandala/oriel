# PI Dashboard (BlackBeltTechnology/pi-agent-dashboard): a pi extension mirrors a live TUI to a web chat

Repo: https://github.com/BlackBeltTechnology/pi-agent-dashboard (MIT, about 335 stars, very active). pnpm monorepo:
a **bridge extension** loaded into every pi session (`packages/extension/`), a Node dashboard server
(`packages/server/`), a React client, an Electron shell. pi only. Read because it is the cleanest case of "the TUI
keeps running and a chat sits beside it": the agent itself pushes its events out and takes prompts in.

## How a session reaches the chat

| Spawn mode | Process | TUI alive? |
|---|---|---|
| pi you started yourself, with the extension installed | your pi TUI | yes, in your terminal |
| `spawnStrategy: "tmux"` | pi TUI in a window of tmux session `pi-dashboard` | yes |
| `spawnStrategy: "headless"` (default) | `pi --mode rpc` under a keeper sidecar (`server/src/spawn-process/process-manager.ts:566-570`) | no TUI |

In the first two rows the chat and the TUI are **one process**. The extension dials the server's pi gateway over a
WebSocket (port 9999; `PI_DASHBOARD_URL=ws://host:port` for a remote server, README "Configuration").

## Chat data

- Live: the extension subscribes to pi events (`agent_start`, `message_update`, `tool_call`, `tool_execution_end`,
  `turn_end`, `agent_settled`, …; `extension/src/bridge-handlers/forwarders.ts:24-46`, `bridge.ts:1151-1991`) and
  forwards them. `message_update` carries the full text so far, so forwarding each one was O(N²) and **stalled the
  TUI**; a single-slot coalescer now throttles it (`extension/src/message-update-coalescer.ts:1-12`).
- History: bounded reads of pi's session `.jsonl` (256 KB per read). The cursor stores the offset **plus a length and
  hash of the last line read**; on mismatch it restarts from zero, and a partial last line is never emitted
  (`extension/src/transcript-backfill.ts:1-30`).

## Input

`pi.sendUserMessage(text, {deliverAs})` from inside the extension. Idle → a new turn. Busy + "steer" → pi's steer.
Busy + "followUp" → held in the bridge's own buffer and sent as a fresh turn on `agent_settled`, because pi's own
follow-up queue raced (`bridge.ts:1532-1572`, `followup-drain.ts`). The send state is read **before** the call: an
idle send fires `agent_start` synchronously (`bridge.ts:1543-1548`). No PTY keys.

## Approvals and questions

The extension wraps `ctx.ui.select/input/confirm/editor` (`bridge-handlers/ui-prompt-patch.ts:26-60`). Each dialog
goes to a **PromptBus** with two adapters: the TUI (the original `ctx.ui` methods, `tui-prompt-adapter.ts`) and the
dashboard card. **First answer wins**; the bus tells every other adapter to dismiss its UI
(`prompt-bus.ts:203-225`). So a question shows in the terminal and in the chat at once, and either can answer.
`custom` UI is not mirrored (`ui-prompt-patch.ts:34-43`); those stay TUI-only.

## Waiting and remote

- Waiting: pi's own events (`agent_start` / `agent_settled`, an open PromptBus request). No screen reading.
- Remote: a pi on another machine points its extension at the dashboard; phones reach the dashboard through a zrok
  tunnel with OAuth.

## Size and cost

Huge: client about 170k lines, server 140k, shared 53k, extension 29k (no tests). The core of the mirror (event
forwarder, prompt send, PromptBus, backfill) is a few thousand. Installed with `pi install`, which writes pi's
settings; a per-run `-e <path>` load would not.

## For Oriel

- Copy: for pi, an extension passed with `-e` on the launch line is the robust path: events out, `sendUserMessage`
  in, the TUI untouched. Only Oriel-launched panes get it, as the brief wants.
- Copy: PromptBus semantics: show a dialog in both places, first answer wins, dismiss the other. Anything the bus
  does not know (`custom`) stays in the TUI.
- Copy: the tail cursor with a last-line hash, and never emit a partial line.
- Avoid: forwarding every `message_update` (live text); Oriel does not need it, and it slowed the TUI.
