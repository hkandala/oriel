# Workflow: building a multi-phase change with agents

How a large change (many phases) is planned, built, reviewed and finished in this repo. It is the
playbook from the UI polish (phases 10–23, see `plan/execution.md` and `resources/metrics/dashboard.html`),
the user's feedback rounds (phases 24–31) and the final review (phase 32), with the lessons folded in. Point the main agent at this file at the start of a session: "follow
plan/workflow.md for <goal>".

## Roles

| Role | Who | Does | Never |
|---|---|---|---|
| Orchestrator | the main agent | plans, starts agents, answers their questions from the design, checks each phase, merges, keeps `plan/execution.md` current, reports | writes app code; skips a check |
| Phase agent | one per phase | builds the phase, self-reviews, starts its reviewers, fixes, pushes, writes Findings and metrics | starts the next phase; pushes red builds |
| Reviewer | started by a phase agent, read only | one focus each (below); a numbered list with file:line, severity, fix | edits, commits, GUI runs beyond its budget |
| Fixer | one per area, after the final review | fixes a report's findings in its own files | touches another fixer's files |
| Lane | one per area in a feedback round (below) | a phase agent for its items, in its own worktree and files | edits another lane's files; asks the user |

## The whole run

```
1. Plan         → 2. Plan review → 3. Phases (one or more lanes) → 4. Comment pass
→ 5. Final review → 6. Fixers (parallel) → 7. Metrics and report
```

### 1. Plan (orchestrator, with the user)

- Write the target layout or behavior as one source-of-truth file (like `plan/ui-layout.md`) and, for UI
  work, HTML mock-ups (`resources/mockups/`). Agree them with the user before any code.
- Cut the work into phase files `plan/phases/NN-*.md`: Goal, Read first, Build (numbered items), e2e,
  Done when, and an empty `## Findings`. Each phase is buildable by one agent in 1–3 hours.
- Write the run file (`plan/execution.md` style): progress log, "for the user to check at the end",
  open tasks.

### 2. Plan review (read only, in parallel)

Three reviewers: **consistency** (docs, plan and phases agree; nothing built twice or missing),
**ponytail** (simpler mechanisms, fewer settings, native APIs), **feasibility** (real APIs, herdr schema,
test harness limits, phase order). One fixer applies the findings; one verifier checks the fixes. Then
push and start building.

### 3. Phases

- **One phase agent per phase.** Start it with the brief below. Phases that touch different parts run in
  parallel, each in its own git worktree (`git worktree add ../oriel-<name> origin/main -b <name>`); name
  who owns shared files (for example tokens) in both briefs. Everyone pushes straight to `main` after
  `git pull --rebase`; no branches or PRs on the remote.
- **The phase loop** (inside the phase agent):
  1. Pull, read the plan, the phase file, the Findings of earlier phases, the ponytail skill.
  2. Spike herdr (and any API) for five minutes: the exact calls, their side effects (focus), defaults.
  3. Build in small commits, `make lint build test` green, push as you go (batch pushes while a full CI
     run is in flight).
  4. New window, panel or screen: send the orchestrator one rough screenshot before polishing. Settle
     ordering and wording questions then.
  5. Run only the e2e tests the phase adds or changes (single local runs, or ad-hoc CI runs).
  6. Self-review the diff.
  7. **Review round 1** (parallel): spec, ponytail, e2e/visual. Fix every blocker and should; answer
     each nit.
  8. **Later rounds** (only after fixes): the **spec** reviewer alone, plus the e2e reviewer only if its
     own blocker was fixed. Stop when a round is clean. Small phases: round 1 only.
  9. CI's full run green on the last code commit (a local full `make e2e` takes about 40 minutes of GUI).
  10. Findings (Deviations, Decisions, Assumptions, Learned) and `plan/metrics/NN.json`; report.
- **Orchestrator check after each phase:** commits are small and on `main`; CI green; read the diff with
  the ponytail eye; the new tests would fail if the feature broke; look at the screenshots; fold Findings
  into the design pages and later phase files; send back a numbered list if anything is wrong. In
  parallel lanes, check every commit landed and no later rebase reverted another lane's work.

### 4. Comment pass

One agent (helpers on disjoint files allowed): every comment says what the code cannot (why,
assumptions, quirks, measured numbers, decision links, safety rules); delete what-comments and dead
code; fix wrong ones. A script proves the diff is comments only. One reviewer, one round.

### 5. Final review (read only, in parallel)

**Ponytail** over the whole repo (duplication across phases, dead code, files near the 400-line limit),
**bugs and edge cases** (races, leaks, error paths, multi-window, safety rules), **spec** (code vs the
design pages; docs vs code; e2e gaps; slop tests). No separate verifier.

For a large repo, review and fix by area instead (phase 32): one agent per code area reads every file in
it and fixes bugs, comments and needless code with small, safe changes. Read-only auditors (ponytail,
security and accessibility) send findings to the area owners. Two docs agents take the design pages, and
plan and resources. One e2e agent runs the full suite at the end. Anything big (a redesign, a large refactor, a
removal that changes behavior) goes on a list for the user, with the reason, the cost and a
recommendation.

### 6. Fixers (parallel, disjoint files)

App and kit code (main checkout) · UI tests (worktree) · docs (worktree). Each: self-review, one
reviewer, CI green, worktree removed. The orchestrator checks every commit is on `main`, CI is green
on the last commit, no worktree or throwaway session is left.

## Feedback rounds

After the build, the user tries the app and sends a list, screenshots or a Scrawl capture (a screen
recording with voice and red marks; phases 28, 30 and 31). One round is one phase file:

- The orchestrator numbers the items, settles the open points itself, and groups them into lanes, one per
  area, so no two lanes edit the same files. Each lane is a phase agent in its own worktree. Items that come
  in during a round become new lanes in the same file.
- Each lane writes its Findings under its own heading at the end of the phase file, and updates the design
  pages it changes.
- When the user tests on this Mac, the lock is held for "user": UI tests run on CI only, and their
  recordings are the visual check.
- The last lane (integration) fixes the flakes it finds at their cause and makes two full CI runs in a row
  green on its first try.

### 7. Metrics and report

`python3 resources/metrics/build.py` rebuilds `resources/metrics/dashboard.html` from
`plan/metrics/*.json`, git and CI. Report to the user: what was built, the dashboard, which reviews
mattered, the "for the user to check" list, open tasks.

## Reviews: who and when

Measured over 132 review agents in the UI polish (dashboard, "Which reviews are a must"):

| Reviewer | Round 1 | Later rounds | Why |
|---|---|---|---|
| Spec (and bugs) | yes | yes, alone | found the most real bugs in every round (value 4–5 in 93 % of round-1 runs, 57 % later) |
| E2E / visual | yes | only if its own blocker was fixed | caught suite-wide breaks and rendering bugs; slow (about 10 min) |
| Ponytail | yes | no | cheap (about 1 min), most findings stick, little after round 1 |
| Verifier | no | no | 10 real findings in about 3 hours; fold its item checklist into the last spec round |

The last spec round also checks every Build and e2e item of the phase file is done.

- Worktrees share one `git stash` list: a pop in one worktree can take another's stash. Never `git stash`;
  commit first, or use `git pull --rebase --autostash`.

## GUI and CI

- XCUITest drives the real mouse and keyboard. One GUI lock (`/tmp/oriel-gui.lock`, the recipe in
  [rules.md](rules.md#building-and-running)): take it for one run, release it in the same command, at most
  10 minutes per hold. Never send keys with osascript. When the
  user works on the Mac, the orchestrator holds the lock for the user and everything runs on CI.
- Ad-hoc CI runs: `gh workflow run ci.yml --ref main -f only_testing=OrielUITests/OrielUITests/testX`.
  A full run takes 10–14 minutes on 5 shards split by measured time; the on-demand tests (stress, costs,
  frame records, look scenes) run only when asked ([ci.md](ci.md#layout)). The account has 5 macOS runners.
- Fast tests: wait with `exists(within:)` / `until` (100 ms polls), never XCTest's waits; read the failing
  step in the xcresult and its screen recording before re-running; CI's display is 1x.
- A machine for parallel GUI runs (a Tart VM) is described in `resources/research/dev/parallel-gui-testing.md`.

## Briefs

**Phase agent.** "You are the phase agent for phase NN (‹name›) of Oriel. Follow `plan/workflow.md`
(the phase loop) and `plan/execution.md`. Build everything in `plan/phases/NN-*.md`; ‹source-of-truth
file› wins. Read the Findings of earlier phases. Work in ‹folder› (worktree if parallel; name the owner
of shared files). Small commits pushed straight to main after pull --rebase. DERIVED_DATA=/tmp/oriel-dd-
phaseNN, the GUI lock for one run at a time, throwaway oriel-dev-*/oriel-e2e-* herdr sessions only.
Start your reviewers (phaseNN-spec-review, phaseNN-ponytail-review, phaseNN-e2e-review) yourself. Send
one rough screenshot of any new view. Report at 2 hours. Reply with the report, which reviewers were a
must, and your top 3 lessons."

**Reviewer.** Read only; one focus; "file:line, severity (blocker / should / nit), the concrete fix";
say when an area is clean; end with a verdict.

## House rules that apply throughout

`AGENTS.md`, `plan/rules.md` and `plan/standards.md`: ponytail; herdr safety (every argv carries
`--session`, `focus:false`, no focus methods, read the snapshot after writes, never touch the user's
sessions); no hint text in the UI; never send the user to herdr; plain English in docs; commit subjects
`type(scope): summary` ≤ 72 characters; never `--no-verify`.
