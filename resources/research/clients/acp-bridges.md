# ACP bridges and wrappers that own the agent process

Question: does any of them attach to a TUI that is already running? **No.** Each starts its own headless agent.
Read from shallow clones.

| Bridge | Runs | Session reuse | Attaches to a live TUI |
|---|---|---|---|
| claude-agent-acp (zed-industries, v0.98, was claude-code-acp) | Claude Agent SDK `query()`, which spawns `claude` in stream-json mode | `session/load`, `session/resume`, `unstable_forkSession`, `listSessions` over Claude's transcripts | no |
| codex-acp (zed-industries, v0.16) | links `codex-core` (tag rust-v0.137) in process | Codex's own threads | no |
| pi-acp (svkozak, v0.0.34) | `pi --mode rpc --no-themes [--session <file>]` | a map file `~/.pi/pi-acp/session-map.json`; sessions open in both pi and the ACP client | no |
| agentapi `--experimental-acp` | any ACP agent | none (no state persistence in ACP mode) | no |
| happy-cli (slopus) | "local" mode: the real `claude` TUI in your terminal, transcript tailed (`sessionScanner`), session id from a SessionStart hook in a temp `--settings`; "remote" mode: SDK `--resume` | same transcript | **switching kills the TUI**: a phone message aborts the local process and restarts in remote mode |

Resuming a transcript that a live TUI still writes means two writers. Claude refuses for background sessions
("Two processes can't write to the same transcript"); the others do not check. Orca forks instead.

## For Oriel

Nothing to take for the chat over a running TUI. If Oriel ever adds a headless mode: fork, never resume, the
live conversation (Orca's rule); happy's kill-and-resume switch is what Oriel avoids.
