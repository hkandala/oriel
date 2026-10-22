# Execution plan: UI polish phases 10–21

How the UI polish is built, phase by phase, by agents. The orchestrator (the main agent) follows this file.
It does not write app code. It starts one phase agent at a time, checks its result, and only then starts the
next phase.

## Roles

| Role | Who | Does | Never |
|---|---|---|---|
| Orchestrator | the main agent | starts each phase agent with the brief below, answers its questions from the design, runs the sanity check, starts the next phase, keeps the progress log at the end of this file | writes app code; skips the sanity check |
| Phase agent | one per phase | reads the plan, builds the phase with small commits, self-reviews, starts the reviewers and the verifier, fixes every finding, pushes, reports | starts the next phase; pushes red builds; writes slop tests |
| Reviewers | 3 per round, started by the phase agent, read only | spec review, ponytail review, e2e and GUI review (see below) | edit files or commit |
| Verifier | 1 per round, started by the phase agent, read only | checks every Build item and every e2e item of the phase file is done and works, item by item, with evidence | edit files or commit |

## GUI runs while the user works

Local GUI runs (XCUITest, app launches, screenshots) are allowed under the GUI lock. The user may step in
for a moment; then wait and go on. CI stays the final check.

## The phase loop (inside each phase agent)

1. Pull `origin/main`. Read `AGENTS.md`, `plan/README.md`, `plan/rules.md`, `plan/standards.md`,
   `plan/ui-polish.md`, `plan/ui-layout.md`, the phase file and every page it lists under "Read first",
   then the ponytail skill (`/Users/hkandala/code/pi-hkandala/extensions/pi-ponytail/skills/ponytail/SKILL.md`).
2. Build the phase in small steps. Each step: code + its tests, `make lint build test` green, a commit with a
   conventional subject (≤ 72 characters), and a push when it builds. Several commits per phase, never one
   big commit at the end.
3. Run the e2e tests the phase adds (with the GUI lock), and keep screenshots of the new UI in
   `/tmp/oriel-shots/<phase>/`. The whole suite (`make e2e`) runs once per review round, by the E2E reviewer.
4. Self-review the diff against the phase file and the ponytail rules; fix what you find.
5. Start the three reviewers and the verifier in parallel (briefs below). Merge their findings. Fix every
   blocker and should; answer each nit with a fix or a one-line reason.
6. Later rounds (fresh agents) re-run only the reviewers whose last round had a blocker or a should, plus
   the E2E reviewer when code changed. The verifier runs once, after a round with no blocker and no should
   (phase 10: four verifier runs found nothing; ponytail after round 1 found only nits). Done when that
   round is clean and the verifier passes every item. At most 4 rounds; if it does not converge, report
   to the orchestrator what is stuck.
7. Write the implementation notes in the phase file's `## Findings` section, as phases 01–09 did (see
   `plan/phases/05-strip-and-glass.md`): short bullets with a bold lead, saying why, not only what. Cover:
   - **Deviations**: where the code differs from the phase file, `plan/ui-layout.md` or a design page, and why.
   - **Decisions**: choices the design did not make (names, numbers, APIs picked, spike results).
   - **Assumptions**: what you took as true without proof (herdr behavior, macOS behavior, user intent).
   - **Learned**: bugs found, measurements, API quirks, test tricks the next phase needs.
   Update the design pages the phase changed so they match the code. Commit and push.
8. Confirm CI is green on the last push (`gh run list --limit 3`).
9. Write `plan/metrics/NN.json` (format below), commit it with the phase, and report to the orchestrator:
   what was built, the commits, how it was tested, screenshot paths, the review rounds and their final
   verdicts, how valuable each reviewer was, anything left open.

## Metrics (for the dashboard after phase 21)

The user wants to learn which reviews are a must and which add little, and how long each part takes. Each
phase agent records, in `plan/metrics/NN.json`:

```json
{
  "phase": 10, "agent": "phase10-appearance",
  "started": "2026-10-21T19:20:00-07:00", "finished": "…",
  "base": "<sha before the phase>", "head": "<last sha>",
  "commits": 9, "files_changed": 14, "insertions": 420, "deletions": 180,
  "review_rounds": 2,
  "reviews": [
    {"name": "phase10-spec-review", "role": "spec", "round": 1,
     "started": "…", "finished": "…", "minutes": 12,
     "findings": {"blocker": 0, "should": 3, "nit": 4},
     "genuine": 5, "rejected": 2,
     "value": 4, "note": "one sentence: what it caught that nothing else would have"}
  ],
  "self_review_findings": 3,
  "e2e_runs": 3, "ci_green": true,
  "notes": "anything that slowed the phase down"
}
```

- `genuine`: findings that led to a real change; `rejected`: wrong, duplicate or not worth it.
- `value`: 1 (nothing new) to 5 (caught a real bug nothing else caught). Be honest; low scores are useful.
- Times come from when you started each agent and when it replied.

After phase 21 the orchestrator builds a dashboard from these files (time per phase, changes, review
agents, rounds, time and value per reviewer role).

## Briefs the phase agent sends

All reviewers and the verifier are read only: they never edit files, commit, push, or run writes against
herdr sessions other than throwaway `oriel-e2e-*` / `oriel-dev-*` ones.

**Spec reviewer.** "Review phase NN of Oriel (`/Users/hkandala/code/oriel`) against `plan/phases/NN-*.md`,
`plan/ui-layout.md`, the design pages it lists and `plan/standards.md`. Diff: `git diff <base>..HEAD`.
Find: missing or wrong behavior, bugs, races, leaks, error paths, herdr safety rules (`--session` on every
argv, `focus:false`, no focus calls, read the snapshot after writes), accessibility identifiers. Report a
numbered list: file:line, severity (blocker / should / nit), the concrete fix."

**Ponytail reviewer.** "Ponytail review of phase NN (`git diff <base>..HEAD`). Follow
`/Users/hkandala/code/pi-hkandala/extensions/pi-ponytail/skills/ponytail-review/SKILL.md`. What can be deleted or made
simpler: types, files, protocols with one conformer (only `Exec` and `Multiplexer` may exist), managers,
options nobody asked for, code for later phases, duplicated logic, needless state, comments that explain what
instead of why. Report a numbered list: file:line, severity, the smaller version."

**E2E and GUI reviewer.** "Take the GUI lock (`plan/rules.md`), build and run Oriel against a throwaway
session (`scripts/herdr-session.sh up oriel-dev-<name>`, `make run SESSION=…`), drive the new UI of phase
NN, try to break it, take screenshots (`screencapture -x -l <window id>`), run `make e2e`, release the lock,
delete the session. Then read the phase's tests. Flag slop tests: tests that assert nothing real, assert
only that an element exists when the phase promises behavior, sleep instead of waiting for a condition,
duplicate another test, mock herdr where the real one is cheap, or check pixels where herdr or an
accessibility value can say it. Report a numbered list with severity and the fix."

**Verifier.** "Verify phase NN is complete. For every numbered Build item and every e2e item in
`plan/phases/NN-*.md`, say done / partly / missing, with evidence: the file:line that implements it and the
test (or the manual step plus screenshot) that shows it works. Run `make lint build test`, and the phase's e2e
tests only if the E2E reviewer's `make e2e` run of this round is older than the last commit; otherwise cite
that run. Pass only when every item is done and every check is green."

## The orchestrator's sanity check (after each phase)

1. `git log` of the phase: several small commits, conventional subjects, no build output or screenshots in
   the repo.
2. CI green on the last commit.
3. Read the diff once with the ponytail eye: no new protocol, manager, option or file that the phase did not
   need; no dead code; no `// TODO` without a `ponytail:` reason.
4. Read the new tests: each one checks behavior through herdr or accessibility values, waits on conditions,
   and would fail if the feature broke.
5. Build and run the app once against a throwaway session (GUI lock), look at the new UI next to
   `resources/mockups/layout.html` and the Rex references, keep 2–3 screenshots.
6. Read the phase's Findings (implementation notes). Fold each deviation and decision into the design
   pages, `plan/ui-layout.md` and later phase files where they matter. Send the phase agent a numbered
   list of any assumption or note that looks wrong or that the user should decide, and settle it before
   the next phase.
7. If anything fails: send it back to the same phase agent with a numbered list. Otherwise log the phase as
   done below and start the next one.

## Phase agent brief (the orchestrator sends this)

> You are the phase agent for phase NN of Oriel (`/Users/hkandala/code/oriel`). Follow
> `plan/execution.md` ("The phase loop" and "Briefs the phase agent sends") exactly. Build everything in
> `plan/phases/NN-*.md`; `plan/ui-layout.md` is the layout source of truth and `resources/mockups/layout.html`
> shows it. Small commits, pushed as you go. Use `DERIVED_DATA=/tmp/oriel-dd-phaseNN`, the GUI lock for any
> GUI work, and only throwaway `oriel-dev-*` / `oriel-e2e-*` herdr sessions (delete them after). Never touch
> existing herdr sessions or the user's Rex app. The user works on this Mac: take the GUI lock only for the
> minutes you need it, use `screencapture -x`. Start the reviewers and the verifier yourself as separate
> agents and loop until a clean pass. When done, reply with the report described in step 9. Ask the
> orchestrator only when the design does not answer a question.

## Decisions without the user

The user is not asked during phases 10–21. The orchestrator decides open questions from the design and the
ponytail rules, records each choice in the design pages, keeps going until phase 21 is done, and lists
here what the user should check at the end.

### For the user to check at the end

- Phase 10: the four looks next to Rex (`/tmp/oriel-shots/10/final-*.png`). Known gaps kept on purpose:
  the Classic dark pill is a little brighter than Rex (`#303030` vs `#292929`); Glass dark cards are
  lighter than the window until phase 17's fade.
- The UI tests share the app's defaults with your own Oriel (same bundle id): an e2e run leaves the look
  at Glass Dark.

## Progress log

| Phase | Agent | Status | Notes |
|---|---|---|---|
| 10 | phase10-appearance | done | 25 commits, 4 rounds, 2h12m; verifier never found anything |
| 11 | | not started | |
| 12 | | not started | |
| 13 | | not started | |
| 14 | | not started | |
| 15 | | not started | |
| 16 | | not started | |
| 17 | | not started | |
| 18 | | not started | |
| 19 | | not started | |
| 20 | | not started | |
| 21 | | not started | |
