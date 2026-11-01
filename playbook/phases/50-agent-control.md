# Phase 50: Agent control

Goal: build the recommended agent-control design: the `oriel` command and its protocol, so agents on This Mac and on
remote machines open and drive Oriel cards, ask whether they are shown, and manage plugins. Then replace today's
workarounds and the `oriel-panes` skill with one `oriel` skill.

Design: the recommended design, `~/Downloads/oriel-research/agent-control-design.html` (it wins), and the proposed
pages `docs/content/docs/future-work/agent-control/*.mdx`, which this phase moves out of future work and rewrites as
built. The user: "in parallel in a separate branch let's work on the agent control impl as well, go with your
recommended design, and once all the fixes i asked for above are done and agent control impl is also done, let's
merge the agent control impl on top of the main".

Branch `agent-control`, a Project: tracks from the report's build plan, a review per track, a docs pass, a final
review, then (after phase 49 is on main) a rebase onto main, two full CI runs green in a row plus the on-demand
suite on the exact head, and a fast-forward of main.

## How the branch runs

- Base branch `agent-control` on origin (never main until the end). Each track: worktree `../oriel-50<t>` off
  `origin/agent-control`, branch `wt-50<t>`, `DERIVED_DATA=/tmp/oriel-dd-50<t>`. Merge when the orchestrator says:
  `git pull --rebase origin agent-control`, `make lint build test`, `git push origin HEAD:agent-control`.
- The orchestrator rebases `agent-control` onto `origin/main` only between merges, when no track is mid-merge,
  and says so; a track then runs `git pull --rebase origin agent-control` before its merge.
- UI tests on CI: `gh workflow run ci.yml --ref <tag or agent-control> -f only_testing=…`. One run in flight per
  track at most (two in all); never wait on one in a loop: report its id.
- Track order: A first (it is the base of the others), then B and C in parallel, then D and E in parallel.
  The removal of `oriel-float` and `oriel-copy` (the report's track 6) is one release later, not in this phase.

## Track A: the bus (items 1–6)

Files: `Packages/HerdrKit` (the decode, the take and answer runs, the `oriel-open` marks), `Oriel/Store/HostStore.swift`
(split it first: it is at the 400-line limit), `Oriel/Store/Presence.swift`, a new `Oriel/Agent/` folder (the
parser and dispatcher, `info`, `help`, `float`, `unfloat`, `copy`), the script as an app resource, and a new
`OrielUITests/AgentControlTests.swift` plus one case in `RemoteTests.swift`. Track A owns the dispatcher file;
B, C and D each add their commands in their own file under `Oriel/Agent/` and one registration line in it.

1. **The script.** `oriel` as an app resource, from the design's script (cli.mdx, The script), `# oriel-cli 1` on
   line 2; `status` (with `--json`, `--watch`) answered by the script from herdr tokens alone.
2. **Written on connect.** When a store opens a session on a machine: one run makes `~/.cache/oriel/{bin,rpc}`
   (rpc mode 0700), removes mailbox files older than 60 minutes and reads line 2; a second run writes the script
   (temporary name, `mv`, 0755) when missing or older. Never an older one over a newer one (remote.mdx).
3. **The doorbell.** HerdrKit decodes `oriel-req` off `pane.updated` (UUID v4 pattern only, the last 256 ids per
   session, once per id) into `Update.request(id:pane:)`. The take (`mv .req .run; base64`) and the answer
   (`.out`, then `.exit`, each by temporary name and `mv`; remove `.run`, `.in`) are one run each (protocol.mdx).
   Size limits: 64 KiB, 64 fields, `.in` 1 MiB.
4. **Two Oriels.** An Oriel whose user is away (no key or click in the app for 60 s, the screen locked, or no
   visible window shows the session) waits 500 ms before its take.
5. **`oriel-open`.** `1` on each workspace of a followed session (`workspace.report_metadata`, source `oriel`,
   `ttl_ms` 30000), with the 10 s `oriel-shown` refresh and on a snapshot with a new workspace; cleared on Detach
   Session and on quit (the same 1 s wait as `oriel-shown`).
6. **The dispatcher and the first commands.** `AgentCommands.run(argv, cwd:, from:, store:)`: the one parser
   (global `--json`; errors as text or `{"error":{code,message}}`, exit codes per protocol.mdx), `help` generated
   from the commands, `info`, `float` (`--on-top`; `existing`), `unfloat` (`not_floating`), `copy` (stdin from
   `.in`, 1 MiB). Pane arguments: `w1:p3` or `‹session›/‹pane›` on the same machine only (`other_machine`).
   Tests: an e2e test that runs the command in a pane of an `oriel-e2e-*` session (float, copy, status, exit 3
   with no Oriel) and checks through accessibility values and herdr; a RemoteTests case over CI's sshd. Measure
   the round trip on This Mac and over the sshd and write it in the Findings.

## Track B: cards (items 7–10)

Files: `Oriel/Agent/` (its own file), `Oriel/Plugins/OpenPlugin.swift`, the notice in the window, tests in
`AgentControlTests.swift` (its own test methods, below track A's) or a new `AgentCardTests.swift`.

7. **`open`** in its four places (default split right of the asking pane, `--down`, `--beside <pane>`, `--tab`
   after the asking pane's tab and not selected, `--float`, `--replace <pane>` for a browser or plugin card only,
   a browser one adding a history entry), kind or path (`./name` for a path named like an id), relative paths
   from the request's cwd, a folder turned into its git root where the kind wants one, the default plugin from
   `Registry.openers`, the old words `file`, `preview`, `markdown`, `files`, `diff` as labels do; reuse of a card of
   the same kind and argument (`reused`), `--new`; the JSON answer of cli.mdx. Never selects a tab or moves focus.
8. **The notice** "‹agent› opened ‹Kind› ‹title› · Show" in each window that shows the session for `--tab` and a
   reused card out of view; Show selects the pane's workspace, tab and card in that window.
9. **`reveal`**: a 0.6 s accent flash of the card's border when in view, else the notice "‹agent› points to
   ‹title›" with Show.
10. **`card`** and **`shown`** with the fields of cli.mdx.

## Track C: plugins (items 11–14)

Files: `Oriel/Agent/` (its own file), `Oriel/Plugins/PluginInstalls.swift`, `PluginBuilds.swift`, `Registry.swift`,
`PluginTrust.swift` (the agent's name in the prompt), tests in a new `AgentPluginTests.swift`.

11. **`plugins`** from `Registry.all` and `Registry.problem` (cli.mdx and the design: `source` is the panel's row
    text; `log` only for a pane on This Mac), `--for <path or URL>` in `Registry.openers` order with `default`.
12. **`plugins new <name>`**: `PluginInstalls.create` with the name as a parameter in place of `askName`;
    trusted, as the panel does; answers `id`, `folder`, `log`.
13. **`plugins reload [<id>]`**: `PluginBuilds` reload of one or all; `dirty` (names the pane) in place of the edits
    prompt; the build result (`built`, `ms`, `cards`) or `build_failed` with the last 20 lines on stderr.
14. **`plugins install <source>`**: the trust prompt on the Mac with the agent's name; Cancel is `declined`;
    answers after install and build. `new`, `reload`, `install` from a remote pane are `other_machine`.

## Track D: agents and notices (items 15–17)

Files: `Oriel/Agent/` (its own file), the notification code and Settings (the switch), `Oriel/Chat/EnableChat.swift`
for the relaunch, tests in a new `AgentStartTests.swift`.

15. **`agent <name>`** with the places of `open` (track B's place parser, reused): the pane, then the agent's
    command line with the chat view's launch flags, as Start Agent Here does; answers when typed.
16. **`chat <pane>`**: Relaunch with Chat for an idle agent; `busy` while it works or needs you; `self` on the
    asking pane.
17. **`notify <title> [<body>]`**: a Mac notification whose click shows the pane; one per pane every 10 s
    (`rate_limited`); a third switch "From agents", on by default, next to "needs you" and "finished".

## Track E: pi-hkandala (items 18–20)

In `~/code/pi-hkandala` on the local branch `oriel-skill` (never pushed until Oriel's side is on main).

18. **The `oriel` skill** (below, The skill).
19. **pi-herd's float** (`orielFloat`) through `oriel --pane ‹pane› float ‹session›/‹pane›`; any exit but 0 opens the
    herdr popup as before; `orielShows` stays (migration.mdx).
20. **pi's copy** (`herdr/oriel-copy.ts`) through `oriel copy` on stdin under the same remote test; its test moves
    to a fake script; the 30 s cleanup goes. The `oriel-panes` skill and `placeholder.sh` go.

## Decisions (the orchestrator, from the design's open questions)

- One `oriel-shown` for all devices (no per-device tokens).
- Agent notifications get a third switch, "From agents", on by default.
- A stale `$HERDR_PANE_ID` fails at herdr before Oriel hears it: the script exits 5 and says to pass `--pane`.
  `pane_not_found` is for a pane argument Oriel cannot find.
- `plugins install` is This Mac only; `plugins new` trusts the plugin, as the panel does.
- `chat` on the asking pane is `self`.
- Oriel keeps reading `oriel-float` and `oriel-copy` in this phase.

## The skill

"also update the oriel-panes skill, also call it just oriel skill and it should be fully based on the agent control
impl, keep it concise, simple, let it refer to herdr skill for any herdr related stuff, also use progressive
disclosure and have may be different md files where agent can load what only needed, keep the skill very clear and
simple and brief."

- `~/code/pi-hkandala/skills/oriel/`: a short `SKILL.md` (what Oriel is, how to tell it is there, the five commands
  an agent uses most, and links), plus one file per topic loaded only when needed (for example `cards.md`,
  `plugins.md`, `remote.md`). Every herdr detail points to the herdr skill (`herdr --skill`).
- The `oriel-panes` skill and its `placeholder.sh` go; pi-herd's `orielFloat` and `oriel-copy.ts` move onto the
  command (the report's migration table). Push pi-hkandala to master when the Oriel side is on main.

## Findings

### Track A

- **Spike (herdr 0.9.5).** `pane report-metadata --token oriel-req=… --ttl-ms 3000` from a pane works and exits 1 for
  an unknown pane; `pane.updated` carries the whole pane (`pane_id`, `tokens` of every source merged) and comes again,
  without the token, when it expires. `workspace.report_metadata` takes `tokens` and `ttl_ms` like the pane call, a
  `null` clears, and `workspace.metadata_updated` carries the workspace's `tokens`. `pane get` and `workspace get` print
  compact JSON on one line, so the script's `sed` reads `workspace_id`, `oriel-shown` and `oriel-open`.
- **Round trip.** `oriel info`, typed in a pane, to its exit. This Mac, by hand: 0.34 s at best, 0.47 s median,
  0.69 s at worst (10 calls, load average 130–200 from other agents' builds); `oriel status` 0.18 s. CI's VM: 0.23 s
  at best, 0.5 s median, 1.55 s at worst. Over CI's sshd on localhost (Key Host): 0.18 s at best, 0.36 s median,
  0.48 s at worst, faster than This Mac because the relay is one long-lived process, while This Mac starts a
  `Process` for the take and another for the answer. With no Oriel, exit 3 after 2.4–3.0 s. The script's own forks
  (the ring, `date` and `sleep` in each 50 ms poll) cost the rest, so a busy Mac is above the design's 0.1 s.
- **Decisions.** A stale or unknown asking pane never reaches Oriel: the ring fails at herdr, so the script exits 5
  and says to pass `--pane`; `pane_not_found` is only for a pane argument. A pane argument is always read on the
  asking pane's machine (the syntax cannot name another), so no pane argument answers `other_machine`; a
  `‹session›/‹pane›` whose session herdr does not run there is `pane_not_found`. `--json` counts anywhere in the
  arguments. Without `--json`, a command that gives no text prints its JSON fields as `name: value` lines. `copy`
  answers `{"bytes": n}` and prints nothing. `oriel-open` marks every workspace of a session while any window has it
  open (a float-only page too), not only while its page is in view: requests are taken then. A request that is not
  one, or is over 64 KiB or 64 fields, answers `usage`; a newer protocol answers `protocol`.
- **The dispatcher.** A command is an `AgentCommand` (`name`, `usage`, `summary`, `help`, `run`) declared as a
  `static let` in its track's own file under `Oriel/Agent/`, and one line in `AgentCommands.all`. `run` reads its
  arguments off an `AgentCall` (`flag`, `value`, `argument`, `optionalArgument`, `done`, `target` for a pane), throws
  `AgentError(code:message:)` (any other error answers `failed`), and returns `AgentOutput(json, text:)`.
- **Two Oriels.** Away is no key press or click in the app for 60 s, the screen locked, or no visible window with the
  session's page in view; an away Oriel waits 500 ms before its take.
- **The script's version.** Line 2 is `# oriel-cli ‹protocol›.‹revision›` (`1.1` now). Oriel compares the
  machine's line 2 with its bundled script's, as numbers, and writes only over a lower one, so a fixed script
  replaces an older one without a new protocol. For the docs pass: protocol.mdx, cli.mdx and remote.mdx say
  `# oriel-cli 1`. No command is `help`; `help status` answers from a help-only `status` entry.
- **Tests.** The remote case sits in `AgentControlTests.swift`, not `RemoteTests.swift`, which is at the 400-line
  limit; it skips without CI's sshd as the others do. The e2e test writes the script and the mailbox in the real
  `~/.cache/oriel` (a cache, as the chat state is), never over a newer script.
- **For the user.** A float from `oriel float` (and its `existing` bring-to-front) should open without activating
  Oriel: check it with Oriel in the background.
