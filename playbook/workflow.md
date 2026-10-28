# How we work

The one way of working for Oriel, for every agent. Read it with [lessons.md](lessons.md) before you start.
The design in `docs/content/docs/` wins on any conflict about what the app does.

## Pick the size of the job

| Job | How |
|---|---|
| Tiny (a color, a wording, a one-liner) | One agent in a worktree. Change it, and its line in the design pages if it has one, in the same commit. `make lint build test`, push to main, report. No new test, no review. The user tests it by hand. |
| Small fix (a bug) | As Tiny, pushed straight to main, plus a test that fails on the old code when one is cheap to write, and the root cause in the commit message. A review only when the change is risky (concurrency, data loss, more than one area). |
| Feature (one track) | One agent on its local branch, committing locally. One code review, then fixes, then the merge. No push before the review. |
| Project (several tracks) | [The whole run](#a-project): a plan, tracks in parallel, a review per track, merges one by one, a docs pass, one final review, fixes, the full UI suite, the report. |

A track is one agent's part of a phase: a set of items and the files they touch.

## Roles

| Role | Does | Never |
|---|---|---|
| Orchestrator (the main agent) | plans with the user, writes the phase files, starts and briefs agents, answers their questions from the design, says when each track merges, watches CI, reports | writes app code; asks the user what the design or the rules already answer |
| Track agent | builds its items in its own worktree and files, self-reviews, starts its code reviewer, fixes, merges when told, writes Findings | edits another track's files; asks the user; starts the next phase |
| Reviewer | read only; reports a numbered list: file:line, severity (blocker / should / nit), the concrete fix; says what is clean; ends with a verdict | edits, commits |
| Helper | read only, does a piece of reading for an agent and writes a report file | edits the repo |

## A project

1. **Plan (orchestrator, with the user).** Write down the target behavior once (the design pages). Write one
   phase file `playbook/phases/NN-name.md` (template below) with a row in [README.md](README.md). Cut the
   work into tracks of 1–3 hours each, so no two tracks edit the same files. Name the owner of any shared
   file in both briefs. A track that others depend on (a removal, a rename) goes first and merges early.
2. **Tracks, in parallel.** One agent each, on its own branch ([the track loop](#the-track-loop)). Tracks do
   not edit the design pages.
3. **A code review per track** ([Reviews](#reviews)), then the track's fixes.
4. **Merge one track at a time**, when the orchestrator says so ([Branches](#worktrees-branches-and-merging)).
5. **Docs pass.** One agent updates the design pages from the merged code and the Findings.
6. **Final review** ([Reviews](#the-final-review)). One fixer, or the owning track agents, apply it.
7. **Full CI.** The orchestrator dispatches the full UI suite once ([CI](#ci)).
8. **Report** to the user: what was built, what to check by hand, what is left to decide.

### Feedback rounds

The user tries the app and sends a list, screenshots or a Scrawl capture (screen, voice and red marks). Read
a capture fully, every frame, before acting. The orchestrator numbers the items, passes each track the
user's exact words and repro, decides the open points itself, and groups the items into tracks in one phase
file. Items that come in during the round become new tracks in the same file, above `## Findings`. Each
track writes only under its own heading. On a merge conflict in the phase file, keep both sides. Before the
report, the orchestrator checks that each numbered item landed: the user must never ask twice. When the user
asks "why", explain and change nothing.

A change to how something looks goes to the agent as the user's exact words, quoted, plus the orchestrator's
reading of them as a before/after sketch (for example `logo / [spinner] Starting Claude Code…`). If the
words allow two readings, ask the user or show a quick mock-up before the agent builds; never pass on a
paraphrase.

## Mechanics

### Worktrees, branches and merging

- **One worktree per agent:** `git fetch origin && git worktree add ../oriel-NN<track> origin/main -b
  wt-NN<track>`. Work and commit there. When done, `git worktree remove ../oriel-NN<track>` and
  `git branch -D wt-NN<track>`. Never run git in a checkout another agent uses.
- **Tracks and features commit on their local branch.** No remote branches, no PRs, no push before the
  review.
- **Merge when the orchestrator says so,** one track at a time. Rebase the branch on the latest main
  (`git pull --rebase origin main`), run `make lint build test`, fast-forward main
  (`git push origin HEAD:main`), and report. The track's agent solves conflicts on its branch. After the
  rebase, check that your commits did not revert another track's work.
- **Tiny and small fixes push straight to main:** commit, `git pull --rebase origin main`,
  `make lint build test` on the rebased tree (and `cd docs && pnpm build` for a docs change),
  `git push origin HEAD:main`.
- **Never `git stash`** (worktrees share one stash list: a pop in one can take another's), and never
  `git checkout <file>` to drop debug lines in a dirty tree (it reverts your other work in that file).
- **Code that moves between two owners' files** is one atomic commit by one agent. Tracks can agree on a
  shared API directly with each other (`agent_send`). One owner writes it.
- **Own DerivedData per worktree:** `DERIVED_DATA=/tmp/oriel-dd-NN<track>` (the Makefile honors it).
  Never build into the DerivedData a running test suite uses.
- **Commits:** small and atomic, one logical change with its tests. `type(scope): summary`, imperative,
  ≤ 72 characters (`feat`, `fix`, `chore`, `test`, `docs`, `refactor`, `perf`, `ci`, `build`). The hooks in
  `.githooks/` must pass. Never `--no-verify`. Never commit build output, DerivedData, `.xcresult`,
  screenshots or secrets.
- **Commands:** use the Makefile targets (`make lint`, `format`, `build`, `test`, `e2e`, `strip-check`,
  `run`). A new command gets a target. A rule a tool can check gets a lint rule or a script, not a line in
  a doc.

### The GUI lock

XCUITest and manual runs take over the real mouse and keyboard of the Mac the user works on. One agent
drives the GUI at a time ([more slots in VMs](ci.md#more-gui-slots-not-set-up)):

```sh
( mkdir /tmp/oriel-gui.lock || exit 1; trap 'rm -rf /tmp/oriel-gui.lock' EXIT
  echo "<your agent name> $(date +%H:%M)" > /tmp/oriel-gui.lock/owner
  make e2e DERIVED_DATA=/tmp/oriel-dd-NN<track> ONLY=… )
```

- Run UI tests locally only when the run is quick: one test, under about 2 minutes, and the lock is free.
  Otherwise use a [chosen-tests CI run](ci.md#running-part-of-it): dispatch it, give the run id in your
  report, and go on. The orchestrator watches it and sends back failures. Never run the same tests again
  without a code change.
- Take the lock only if it is free. If it is not, work on and try later (no waiting loop). One run per hold,
  released by the trap, also on failure. Never hold it while you read results, edit, build or wait for CI.
  Never remove someone else's lock. A lock older than 10 minutes whose owner is not `user` and whose agent is
  gone (`agent_list` with `scope: "all"`) is stale: the orchestrator removes it.
- When the user tests on the Mac, the orchestrator holds the lock for them
  (`mkdir /tmp/oriel-gui.lock && echo user > /tmp/oriel-gui.lock/owner`; `rm -rf /tmp/oriel-gui.lock` to
  release). Then all UI tests run on CI.
- RemoteTests skip on a local run (they need CI's sshd): run them in a chosen-tests CI run.
- Never send keys with `osascript` or System Events: when Oriel loses focus, the keys land in the user's
  apps. Keys go through XCUITest only.
- Screenshots: `screencapture -x -l <windowid>`, the xcresult's attachments, or frames of a CI recording.
  Put the ones you report in `/tmp/oriel-shots/`.

### herdr safety

- The user's sessions (`default` and any other in `herdr session list`) are read only: no writes, no
  `control` streams, no `--takeover`, no running the app against them. Look with
  `herdr --session <s> terminal session observe …` or `herdr --session <s> pane read …`.
- Writes go only to throwaway sessions `oriel-e2e-*` (tests) and `oriel-dev-*` (by hand), made with
  `scripts/herdr-session.sh up|down oriel-dev-<name>` and deleted when done. Run the app by hand with
  `make run SESSION=oriel-dev-<name>`.
- Every herdr argv carries `--session`. Never call focus methods (`*.focus`). Creates pass `focus:false`.
- Remote machines: tests use CI's sshd on localhost (`scripts/ci-sshd.sh`). Never connect to the user's
  hosts.

### CI

- A push to main runs only the checks (about 3 minutes). Nobody waits on it. The orchestrator watches it
  and sends a red one to the agent of the commit that broke it.
- The full UI suite runs only when the orchestrator dispatches it: once after a feature merges, or once
  after the final review's fixes merge. The orchestrator sends each failing test to the track that owns it.
  That agent fixes it and runs only those tests in a chosen-tests run. Then the orchestrator dispatches one
  last full run.
- At the end of a big project, or when a track touches what they guard: two full runs in a row green on the
  first try, and the on-demand suite once. Then refresh `scripts/test-times.tsv`.
- Judge a run by which tests failed, not by its color. How to run, watch and read CI: [ci.md](ci.md).

### Agents

- **Start** an agent with `agent_start`, a brief with everything it needs (below) and a name: track agents
  `tNN-<track>`, feature agents `pNN-<name>`, their reviewers and helpers `<agent>-<role>`
  (`t33-docs-review`). A track agent starts its own reviewer and helpers.
- **Ask** with `needsReply: true` when you want an answer. You are woken when it replies or stops. FYIs go
  with `needsReply: false`. Never send acknowledgements.
- **Wait** without polling: watch every agent you start (`agent_watch` with no timeout for one already
  working). No sleep loops. Never end a turn on "waiting for run X": wait in a background command and
  report the result.
- **Stop** agents when their work is done, together in one `agent_stop`. Read a stuck one with
  `agent_read` (with `screen: true`).
- An agent asks the orchestrator only when the design and these rules do not answer it. The orchestrator
  decides open points itself and does not ask the user.

## The track loop

A feature runs the same loop.

1. Pull. Read `AGENTS.md`, this file, [lessons.md](lessons.md), the phase file, the Findings of earlier
   phases it touches, the design pages it names, and the ponytail skill (path under Code).
2. Spike herdr (and any API) for five minutes in a throwaway session: the exact calls the code will send,
   their results and side effects ([lessons.md](lessons.md#herdr)).
3. Build the parts that cannot change first (menus, keys, herdr calls), then the look. A new window or
   panel: send the orchestrator one rough screenshot before you polish it. The orchestrator checks it
   against the design bar and settles order and wording then.
4. Small commits on your branch, `make lint build test` green on each.
5. Run only the UI tests you add or change ([the GUI lock](#the-gui-lock)).
6. Self-review the diff against the phase file and the ponytail rules. Write your Findings.
7. Start your code reviewer on the branch's head ([Reviews](#reviews)). Fix every blocker and should in one
   commit. Answer each nit with a fix or a one-line reason.
8. A feature updates its design pages on its branch. A track leaves them to the docs pass.
9. Report when the branch is reviewed and fixed: what was built, the commits, the tests, screenshot paths
   (a new window or panel only), anything open, and the id of any CI run still going. Never wait on CI, chosen-tests runs included. At 2 hours, report progress anyway.
10. Merge when the orchestrator says so, and report the push.

### The orchestrator's check after each track

Read the diff with the ponytail eye: no new protocol, manager, option or file the track did not need; no dead
code. Each new test checks behavior through herdr or accessibility values and would fail if the feature
broke. Look at the screenshot of a new window or panel. After the merge, check that main has every commit
and that no rebase reverted another track's work. Anything wrong goes back to the same agent as a numbered
list.

## Reviews

No plan review. Every review is read only, in a clean copy of the commit it reviews.

- **Code review (one per track or feature).** One reviewer covers every side: bugs, races, edge cases, does
  it do what the user asked, ponytail simplicity, herdr safety, and tests that can fail. Its fixes go in one
  commit. A second round only if it found a blocker: the brief maps each finding to its fix and asks what the
  fixes touched.
- **Small fixes** get a review only when they are risky.

### The final review

A project gets one final reviewer after every track merged and the docs pass landed. It reads the whole
change at once: bugs between tracks, duplicated code, consistency, comments that say why (not what or
when), and docs that match the code. One fixer, or the owning track agents, apply it. A security or
accessibility auditor joins only when the project touches those. For a cleanup of the whole repository
([phase 32](phases/32-final-review.md)), use one agent per code area instead. Anything big (a redesign, a
removal that changes behavior) goes on a list for the user with the reason, the cost and a recommendation.

## Phase file template

```markdown
# Phase NN: <name>

Goal: <what the user gets, in two or three sentences>.

## Track A: <area> (items n–m)
1. **<item>.** <what, where, the design page that rules it, the test that proves it>.

## Findings
```

Each track writes its Findings under `### Track X` at the end.

**Findings:** at most about 8 bullets per track, each with a bold lead: **Cause**, **Fix**, **Decisions**
(choices the design did not make), **Runs** (a red run on the old code and a green one, when there are any),
**For the user** (what to check by hand). No test-name, file or run-id inventories. A lesson that will come
back goes to [lessons.md](lessons.md), not into the phase.

## Briefs

**Track agent.** "You are the agent for track ‹X, items› of phase NN of Oriel. Read `AGENTS.md` and
`playbook/workflow.md` and follow the track loop. Build everything in your section of
`playbook/phases/NN-*.md`. The design pages win. Worktree `../oriel-NN<track>`, branch `wt-NN<track>`,
`DERIVED_DATA=/tmp/oriel-dd-NN<track>`. Your files: ‹list›; ‹owner of shared files›. Commit on your branch
and do not push until I say merge. Start your code reviewer yourself. Decide open points yourself. Write
Findings under `### Track X`. Reply when the branch is reviewed and fixed, with what you fixed, the causes,
the tests, and anything the user must decide or check by hand."

**Code reviewer.** "Read-only code review of ‹track› at ‹sha›, in a clean copy
(`git worktree add --detach /tmp/oriel-rev-<name> <sha>`, `DERIVED_DATA=/tmp/oriel-dd-rev-<name>`, removed
after), against the phase file, the design pages and `playbook/workflow.md`. Cover every side: bugs, races,
leaks, error paths, edge cases; does it do what the user asked; what can be deleted or made simpler (the
ponytail-review skill); herdr safety; accessibility identifiers; tests that assert nothing real, sleep,
duplicate others, mock herdr where it is cheap, or would pass without the feature. Run UI tests only as
[the GUI lock](#the-gui-lock) allows. Write a numbered list to ‹path›: file:line, severity, the concrete fix.
Say what is clean. End with a verdict."

**Final reviewer.** "Read-only final review of phase NN at ‹sha› (main after every track and the docs pass),
in a clean copy as above. Read the whole change since ‹base sha›: bugs between tracks, duplicated code,
consistency, comments, and design pages that match the code. Write a numbered list to ‹path› with the owner
track of each finding. End with a verdict."

## Code

Tools enforce what they can (SwiftFormat, SwiftLint, the compiler in Swift 6 mode with strict
concurrency). The rest:

- **Ponytail.** Read `/Users/hkandala/code/pi-hkandala/extensions/pi-ponytail/skills/ponytail/SKILL.md`
  before writing code. Does it need to exist? Is it already here? Does the stdlib, SwiftUI, AppKit or an
  installed package do it? Only then the minimum. No protocol with one conformer except `Exec` and
  `Multiplexer` (D49). No factories, managers, coordinators or service layers; no scaffolding for later. A
  deliberate shortcut gets a `// ponytail:` comment with its ceiling and upgrade path. A type gets its own
  file when more than one file uses it or it passes about 200 lines.
- **Swift.** No `@unchecked Sendable` or `nonisolated(unsafe)` without a one-line reason. UI state is
  `@Observable` classes on the main actor; no Combine or `ObservableObject` (except where libghostty-spm
  needs it). `async`/`await`, `AsyncStream`, structured tasks; cancel what you start. Errors: `throws` with
  a small enum per module, shown in the UI as text; never crash on bad input from herdr; no `try!` or force
  unwraps outside tests. Decoding: hand-written lenient `Decodable` models with only the fields the app uses.
  Names follow the design's words (machine, session, page, window, workspace, tab, pane, card, strip).
  Comments say why, not what or when; no commented-out code.
- **Design bar.** Every new or changed surface (window, panel, dialog, sheet, popover, About, a menu we
  draw) looks modern and native to macOS 26: Liquid Glass through the app's shared glass style where it
  fits, generous padding, the app's fonts and sizes. No stock-looking AppKit panels, no dumps of text. A new
  window or panel is done only when its screenshot sits well next to the existing glass surfaces (Open
  Session, the remote machine dialogs).
- **Look.** Views draw only with the `Look` tokens in `Style.swift`, read from the environment; no color
  literal outside it. Glass is one behind-window `NSVisualEffectView` under a tint plus the system glass APIs;
  Classic is opaque; pane cards are never glass. No hardcoded sizes where layout can decide; the fixed sizes
  are written down in the design pages. Every control and region a test touches has an
  `accessibilityIdentifier`. No hint text in the UI, and never send the user to herdr: the app shows the
  button that does it.
- **herdr in code.** Never patch local state after a write: read the snapshot again (the one exception is
  `Ahead`, which shows a new tab, split or close before herdr answers). Every long-running child ends when
  its stdin closes; the one fallback kill signals by pid, never by process group.
- **Tests.** UI tests first: XCUITest in `OrielUITests` against a throwaway herdr session with a known
  layout, asserting through accessibility identifiers and herdr (`pane.read`, `session.snapshot`), not
  pixels. Unit tests (`swift test` in `Packages/HerdrKit`) only for logic with branches, with recorded herdr
  JSON next to them. App logic no UI test can drive gets a small check script that `make test` runs. No
  mocks of herdr where the real one is cheap; one `Exec` fake for pacing tests is fine.
- **Docs.** Plain English, following `/Users/hkandala/code/pi-hkandala/skills/simple-english/SKILL.md`:
  short sentences, active voice, every term defined at first use. Docs describe the app as it is now: no
  dates, no history.
