# How we work

The one way of working for Oriel, for every agent. Read it with [lessons.md](lessons.md) before you start.
The design in `docs/content/docs/` wins on any conflict about what the app does.

## Pick the size of the job

| Job | How |
|---|---|
| A small fix (a bug, a wording, one file or a few) | Fix it in the main checkout or one worktree: the fix and its test, `make lint build test`, the UI tests it touches, push. One reviewer only if the change is risky. |
| One feature or a short list | One phase file, one phase agent, the phase loop below. |
| A project (several features, a redesign, a round of the user's feedback) | The whole run below: plan, plan review, phases or lanes in parallel, final pass. |

## Roles

| Role | Does | Never |
|---|---|---|
| Orchestrator (the main agent) | plans with the user, writes the phase files, starts and briefs agents, answers their questions from the design, checks each phase, reports | writes app code; asks the user what the design or the rules already answer |
| Phase or lane agent | builds its items in its own worktree and files, self-reviews, starts its reviewers, fixes, pushes, writes Findings | edits another lane's files; asks the user; starts the next phase |
| Reviewer | read only, one focus; reports a numbered list: file:line, severity (blocker / should / nit), the concrete fix; says when an area is clean; ends with a verdict | edits, commits, GUI runs beyond its budget |
| Helper | read only, does a piece of reading for an agent and writes a report file | edits the repo |

## The whole run

1. **Plan (orchestrator, with the user).** Write down the target behavior once (the design pages). Cut the
   work into phase files `plan/phases/NN-name.md` (template below), each one agent's work for 1–3 hours.
   For a feedback round, one phase file with one lane per area, so no two lanes edit the same files; name
   the owner of any shared file in both briefs.
2. **Plan review (read only, in parallel).** Consistency (docs, plan and phases agree; nothing built twice
   or missing), ponytail (simpler mechanisms, fewer settings, native APIs), feasibility (real APIs, herdr's
   schema, what the test harness can do, phase order). One fixer applies the findings.
3. **Phases or lanes.** One agent each, in parallel where the files are disjoint (the phase loop below). A
   lane that others depend on (a removal, a rename) goes first and pushes early.
4. **Comment pass** (after a big build). Every comment says what the code cannot (why, assumptions, quirks,
   measured numbers, safety rules); what-comments and dead code go. A script proves the diff is comments
   only. One reviewer.
5. **Final review.** For a large repo, by area: one agent per code area reads every file and fixes bugs,
   comments and needless code with small, safe changes; read-only auditors (ponytail, security,
   accessibility) send findings to the area owners. Anything big (a redesign, a removal that changes
   behavior) goes on a list for the user with the reason, the cost and a recommendation.
6. **Integration (last).** Fix the flakes at their cause; two full CI runs in a row green on the last code
   commit with no reruns; refresh `scripts/test-times.tsv` ([ci.md](ci.md)).
7. **Report** to the user: what was built, what to check by hand, what is left to decide.

### Feedback rounds

The user tries the app and sends a list, screenshots or a Scrawl capture (screen, voice and red marks). Read
a capture fully, every frame, before acting. The orchestrator numbers the items, passes each lane the user's
exact words and repro, settles the open points itself, and groups the items into lanes in one phase file.
Items that come in during the round become new lanes in the same file. Each lane writes only under its own
heading (on a merge conflict in the phase file, keep both sides) and updates the design pages it changes.
Before reporting, the orchestrator checks that every item landed: the user should never have to ask twice.

- Every fix of a user-reported bug gets a test that is red on the old code, and its root cause goes in
  Findings, so later lanes and reviewers check it. Fixes came back broken when either was missing.
- Decide once, then send one message. When the user asks "why", answer and change nothing.

## Mechanics

### Worktrees and pushing

- **One worktree per phase or lane:** `git worktree add ../oriel-NN<lane> origin/main -b wt-NN<lane>`. Work
  and commit there. When done, `git worktree remove ../oriel-NN<lane>` and `git branch -D wt-NN<lane>`.
- **Push straight to main.** No remote branches, no PRs: `git pull --rebase --autostash origin main`, then
  `make lint build test` on the rebased tree, then `git push origin HEAD:main`. After a rebase over another
  lane's work, check your commits did not revert theirs, and that no file passed the 400-line limit.
- **Code that moves between two owners' files** is one atomic commit by one agent. Lanes may agree on a
  shared API directly with each other (`agent_send`); one owner writes it.
- **Never `git stash`.** Worktrees share one stash list: a pop in one worktree can take another's stash.
  Commit first, or let `--autostash` do it.
- **Own DerivedData per worktree:** `DERIVED_DATA=/tmp/oriel-dd-NN<lane>` (the Makefile honors it).
  Never build into the DerivedData a running test suite uses.
- **Commits:** small and atomic, one logical change with its tests, pushed when it builds.
  `type(scope): summary`, imperative, ≤ 72 characters (`feat`, `fix`, `chore`, `test`, `docs`, `refactor`,
  `perf`, `ci`, `build`). The hooks in `.githooks/` must pass; never `--no-verify`. Never commit build
  output, DerivedData, `.xcresult`, screenshots or secrets.
- **Commands:** use the Makefile targets (`make lint`, `format`, `build`, `test`, `e2e`, `strip-check`,
  `run`). A new command gets a target. A rule a tool can check gets a lint rule or a script, not a line in
  a doc.

### The GUI lock

XCUITest and manual runs take over the real mouse and keyboard of the Mac the user works on. One agent
drives the GUI at a time:

```sh
( mkdir /tmp/oriel-gui.lock || exit 1; trap 'rm -rf /tmp/oriel-gui.lock' EXIT
  echo "$NAME $(date +%H:%M)" > /tmp/oriel-gui.lock/owner; make e2e ONLY=… )
```

- Take it only if it is free; if it is not, work on and try later (no waiting loop). One run per hold, at
  most 10 minutes, released by the trap, also on failure. Never hold it while you read results, edit,
  build or wait for CI. Never remove someone else's lock.
- When the user tests on the Mac, the orchestrator holds the lock with owner `user`. Then everyone runs
  UI tests on CI only ([chosen-tests runs](ci.md#running-part-of-it)), and the CI recordings are the
  visual check.
- Never send keys with `osascript` or System Events: when Oriel loses focus, the keys land in the user's
  apps. Keys go through XCUITest only.
- Screenshots: `screencapture -x -l <windowid>`, the xcresult's attachments, or frames of a CI recording.
  Put the ones you report in `/tmp/oriel-shots/`.

### herdr safety

- The user's sessions (`default` and any other in `herdr session list`) are read only: no writes, no
  `control` streams, no `--takeover`, no running the app against them. Look with `observe` or `pane.read`.
- Writes go only to throwaway sessions `oriel-e2e-*` (tests) and `oriel-dev-*` (by hand), made with
  `scripts/herdr-session.sh up|down` and deleted when done. Run the app by hand with `make run SESSION=…`.
- Every herdr argv carries `--session`. Never call focus methods (`*.focus`); creates pass `focus:false`.
- Remote machines: tests use CI's sshd on localhost (`scripts/ci-sshd.sh`). Never connect to the user's
  hosts.

### CI

A push to main runs the full suite (10–14 minutes, 5 machines). Don't sit waiting on it between steps: push
and keep working, check it at the end. While a full run matters, batch pushes (a push cancels the run in
flight). For one or two tests, use a chosen-tests run instead of a full run or a local run. Every red test in a
full run gets an owner: a lane reports its own tests green and lists the other reds; the orchestrator finds
the commit that broke them and tells its lane. Details: [ci.md](ci.md).

### Agents

- **Start** an agent with `agent_start`, a kebab-case name that says what it works on (`l33-docs`,
  `phase14-spec-review`), and a brief with everything it needs (below): its files, its worktree, where to
  write. Agents that a phase agent needs (reviewers, helpers) are started by that agent, not the
  orchestrator.
- **Ask** with `needsReply: true` when you want an answer; you are woken when it replies or stops. FYIs go
  with `needsReply: false`. Never send acknowledgements.
- **Wait** without polling: watch every agent you start (`agent_watch` with no timeout for one already
  working); no sleep loops. Never end a turn on "waiting for run X": wait in a background command and
  report the result.
- **Stop** agents when their work is done, together in one `agent_stop`. Read a stuck one with
  `agent_read` (with `screen: true`).
- An agent asks the orchestrator only when the design and these rules don't answer it; the orchestrator
  decides open points itself rather than asking the user.

### Docs site

The docs deploy only through `.github/workflows/docs-deploy.yml` to the Vercel project `oriel` (Vercel's own
git deploys are off: they deployed every push and hit the free plan's 100 deploys a day). Run the `vercel`
CLI only from the repo root; in another folder `vercel pull --yes` creates and links a new project.

## The phase loop

1. Pull. Read `AGENTS.md`, this file, [lessons.md](lessons.md), the phase file, the Findings of earlier
   phases it touches, the design pages it names, and the ponytail skill.
2. Spike herdr (and any API) for five minutes in a throwaway session: the exact calls the code will send,
   their results and side effects (focus, defaults).
3. Build the parts that cannot change first (menus, keys, herdr calls), then the look. A new window, panel
   or screen: send the orchestrator one rough screenshot before polishing, and settle order and wording
   then.
4. Small commits, `make lint build test` green, push as you go.
5. Run only the UI tests you add or change (one local run under the lock, or a chosen-tests CI run).
6. Self-review the diff against the phase file and the ponytail rules.
7. Commit and push (Findings too) before starting reviewers, and name the SHA. Reviewers review that SHA
   in a clean copy (`git worktree add /tmp/… <sha>`, their own DerivedData), never your working tree.
   **Review round 1** in parallel: spec, ponytail, e2e (table below). Fix every blocker and should;
   answer each nit with a fix or a one-line reason. **Later rounds** only after fixes: the spec reviewer
   alone, plus the e2e reviewer if its own blocker was fixed; their brief maps each finding to its fix
   commit and asks what the fixes touched. Stop when a round is clean; at most 4 rounds.
   A small phase (a few files, no new view) gets round 1 only.
8. Update the design pages you changed, in plain English.
9. CI's full run green on the last code commit.
10. Done is a checklist: design pages match the final code; Findings with the root cause, numbers before and
    after, and the red (old code) and green run ids; CI green on the last code commit. Report what was
    built, the commits, the tests and run ids, screenshot paths, anything open. At 2 hours, report progress
    anyway.

### The orchestrator's check after each phase or lane

Every commit is small and on `main`, and no later rebase reverted another lane's work. CI is green on the
last code commit. Read the diff with the ponytail eye (no new protocol, manager, option or file the phase did
not need; no dead code). Each new test checks behavior through herdr or accessibility values and would
fail if the feature broke. Look at the screenshots. Fold the Findings into the design pages and later phase
files. Anything wrong goes back to the same agent as a numbered list.

### Reviews: who and when

| Reviewer | Round 1 | Later rounds | Why |
|---|---|---|---|
| Spec (and bugs) | yes | yes, alone | finds the most real bugs in every round |
| E2E / visual | yes | only if its own blocker was fixed | catches suite-wide breaks and rendering bugs; slow (about 10 min) |
| Ponytail | yes | no | cheap, most findings stick, little after round 1 |
| Verifier | no | no | adds little; the last spec round checks every Build and e2e item instead |

GUI budget: the e2e reviewer gets at most 15 minutes of lock in round 1; spec and ponytail reviewers get
none. A phase agent runs single tests while building; the full suite runs on CI, not locally (a local full
`make e2e` is about 40 minutes of the user's screen).

## Phase file template

```markdown
# Phase NN: <name>

Goal: <what the user gets, in two or three sentences>.

## Build
1. **<item>.** <what, where, the design page that rules it>.

## e2e
- <the UI tests that prove each item, through herdr or accessibility values>

## Done when
- <checks>

## Findings
```

A feedback round puts the items under `## Lane X: <area> (items n–m)` headings instead, and each lane writes
its Findings under `### Lane X` at the end.

**Findings** are short bullets with a bold lead that say why, not only what: **Deviations** (where the code
differs from the plan or the design, and why), **Decisions** (choices the design did not make), and anything
the user must check by hand. A lesson that will come back goes to [lessons.md](lessons.md), not into the
phase.

## Briefs

**Phase or lane agent.** "You are the agent for phase NN ‹lane, items› of Oriel. Read `AGENTS.md` and
`plan/workflow.md` and follow the phase loop. Build everything in `plan/phases/NN-*.md` ‹your section›; the
design pages win. Worktree `../oriel-NN<lane>`, branch `wt-NN<lane>`, `DERIVED_DATA=/tmp/oriel-dd-NN<lane>`.
Your files: ‹list›; ‹owner of shared files›. Push straight to main after a rebase and a build. Start your
reviewers yourself (NN<lane>-spec-review, …). Decide open points yourself. Write Findings under ‹heading›.
Reply when done with what you fixed, the causes, the tests and CI run ids, and anything the user must
decide or check by hand."

**Reviewer.** "Read-only ‹focus› review of ‹phase/lane› (`git diff <base>..HEAD`), against the phase file,
the design pages and `plan/workflow.md`. ‹Spec: missing or wrong behavior, bugs, races, leaks, error paths,
herdr safety, accessibility identifiers. Ponytail: follow the ponytail-review skill; what can be deleted
or made simpler. E2E: drive the new UI through XCUITest under the lock (at most 15 minutes, a throwaway
session), then read the tests and flag slop: asserting nothing real, only that an element exists, sleeping,
duplicates, mocks where herdr is cheap, pixels where herdr or an accessibility value can say it.› Report a
numbered list: file:line, severity, the concrete fix. Say what is clean. End with a verdict."

## Code

Tools enforce what they can (SwiftFormat, SwiftLint, the compiler in Swift 6 mode with strict
concurrency). The rest:

- **Ponytail.** Read `/Users/hkandala/code/pi-hkandala/extensions/pi-ponytail/skills/ponytail/SKILL.md`
  before writing code. Does it need to exist? Is it already here? Does the stdlib, SwiftUI, AppKit or an
  installed package do it? Only then the minimum. No protocol with one conformer except `Exec` (local and
  remote machines) and `Multiplexer` (`HerdrClient` is its only conformer; it grows a method only when the
  app uses a new feature). No factories, managers, coordinators or service layers; no scaffolding for
  later. A deliberate shortcut gets a `// ponytail:` comment with its ceiling and upgrade path. A type gets
  its own file when more than one file uses it or it passes about 200 lines.
- **Swift.** No `@unchecked Sendable` or `nonisolated(unsafe)` without a one-line reason. UI state is
  `@Observable` classes on the main actor; no Combine or `ObservableObject` (except where libghostty-spm
  needs it). `async`/`await`, `AsyncStream`, structured tasks; cancel what you start. Errors: `throws` with
  a small enum per module, shown in the UI as text; never crash on bad input from herdr; no `try!` or force
  unwraps outside tests. Decoding: hand-written lenient `Decodable` models with only the fields the app uses.
  Names follow the design's words (machine, session, page, window, workspace, tab, pane, card, strip). Comments
  say why, not what; no commented-out code.
- **Look.** Views draw only with the `Look` tokens in `Style.swift`, read from the environment; no color
  literal outside it. Glass is one behind-window `NSVisualEffectView` under a tint plus the system glass APIs;
  Classic is opaque; pane cards are never glass. No hardcoded sizes where layout can decide; the fixed sizes
  are written down in the design pages. Every control and region a test touches has an
  `accessibilityIdentifier`. No hint text in the UI, and never send the user to herdr: the app shows the
  button that does it.
- **herdr in code.** Every argv carries `--session`; no focus methods; never patch local state after a write
  (read the snapshot again; the one exception is `Ahead`, which shows a new tab, split or close before herdr
  answers). Every long-running child ends when its stdin closes; the one fallback kill signals by pid, never
  by process group.
- **Tests.** UI tests first: XCUITest in `OrielUITests` against a throwaway herdr session with a known
  layout, asserting through accessibility identifiers and herdr (`pane.read`, `session.snapshot`), not
  pixels. Unit tests (`swift test` in `Packages/HerdrKit`) only for logic with branches, with recorded herdr
  JSON next to them. App logic no UI test can drive gets a small check script that `make test` runs. No
  mocks of herdr where the real one is cheap; one `Exec` fake for pacing tests is fine.
- **Docs.** Plain English: short sentences, active voice, every term defined at first use. Docs describe the
  app as it is now: no dates, no history.
