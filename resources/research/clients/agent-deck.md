# agent-deck (asheshgoplani/agent-deck): the send layer, read for its failure modes

Repo: https://github.com/asheshgoplani/agent-deck (Go, tmux-based session manager for many agents). The client
itself is covered elsewhere; here only how it **sends into** and **reads state from** agent TUIs. Clone:
a shallow clone.

## State

- Hooks first (`internal/sessionstatus`): Claude hooks and statusline, Codex `notify`; a tmux pane-title and
  screen fallback (`internal/tmux/detector.go`, per-agent prompt detectors for claude, codex, cursor, gemini, omp,
  deepseek). The package header lists the bugs from three copies of that mapping drifting apart.
- Reads `~/.claude/sessions/<pid>.json` for titles, and since the socket transport also for `status`.

## Send (`internal/send`, about 7.6k lines without tests)

Keys through tmux, with a verify loop. Each rule in the code names the issue that forced it:

| Rule | Why |
|---|---|
| Multi-line text goes as one framed paste (`tmux paste-buffer -p -r`) | line-by-line typing submitted early (#2079) |
| Check `[Pasted text #N +M lines]`: M must equal the hard line breaks | a composer remount swallowed the tail of a paste and still drew a valid marker (#2079) |
| Count markers, never test presence | an old marker stays on screen forever (#1855) |
| Every automated bare Enter passes an "attribution" gate: only press if the composer is empty, a placeholder, or holds exactly our text | a Claude autosuggestion can appear as real text and an Enter would submit what nobody wrote (#1777, #1409) |
| Refuse to send while a picker or the user's draft is open | a send clobbered an open `AskUserQuestion` and the draft (#1981) |
| Codex: "taken" = a new `›` transcript cell with our text and the composer no longer holds it; text in "Queued follow-up inputs (↳)" is not taken | Codex 0.15x queues while busy (#2424, #2536) |
| `--defer-if-busy` reads the hook status, not the screen | interrupt recovery read the pane and guessed wrong (#2033) |

The maintainer discussion #2089 sums it up: the pane "is a shared surface, it carries the user's own draft, and it
gives no delivery receipt."

## Claude inbox socket transport (`send/claudesocket.go`, opt-in `send_transport = "auto"`)

- Vets the target before any byte: `peerProtocol == 1`, socket path present, pid alive, `procStart` equal (macOS:
  `LC_ALL=C TZ=UTC ps -o lstart= -p <pid>`, the exact string Claude writes), same uid, exactly one live record in
  the pane's process tree.
- Any failure before the write → fall back to tmux. A failure **after** the write started → hard error, never
  retried on tmux (double delivery).
- Writes `{"type":"auth",…}` (if a key is readable) and the `user` frame in one write, then closes after 150 ms.
- Only for Claude; every other agent stays on tmux.

## For Oriel

- Take: the "no foreign Enter" rule. Never press Enter unless the composer holds exactly what Oriel typed (or is
  empty). Fall back to the TUI instead.
- Take: vet a pid record (`procStart`, uid, pane tree) before trusting `~/.claude/sessions/<pid>.json`.
- Avoid: growing a screen-verify layer. 7.6k lines and a long issue trail for one action is the cost of keys
  without a receipt.
