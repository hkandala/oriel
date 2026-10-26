# Execution: inside a phase

How one phase runs: the GUI budget, the speed rules, the phase loop, the review briefs, metrics and the
progress log. [workflow.md](workflow.md) is the whole run around it (roles, plan, final review, report).
Written for the UI polish (phases 10–23). Phases 24–32 ran the same way in parallel lanes, each lane a
phase agent with its own files.

## GUI budget (the user works on this Mac)

GUI runs are slow and take over the user's mouse and keyboard. Phase 11 used about 80 minutes of GUI lock
for a small phase. The lock itself is in [rules.md](rules.md#building-and-running). The budget per phase:

| Who | GUI allowed | Not allowed |
|---|---|---|
| Phase agent, while building | single XCUITest runs of the tests it writes or changes (`make e2e ONLY=…`), about 2 min each | full `make e2e`; manual app driving |
| Phase agent, at the end | the full suite on CI on the last code push; one local screenshot run when the phase changes how things look (XCTAttachments in that run are enough) | a local full `make e2e` (about 40 minutes of GUI for 171 tests) unless the orchestrator asks |
| E2E reviewer | round 1 only, at most 15 min of lock: drive the new UI through XCUITest and read the tests | later rounds, unless its own blocker was fixed (then single tests only) |
| Spec and ponytail reviewers | none: read the code, the tests, the phase agent's runs and CI | any GUI run |

- **Who may use the GUI** changes with the user's work. The phase brief says it. When the user holds the
  lock (owner "user"), nobody removes or works around it: agents build, test without GUI and push, and the
  UI tests run on CI.
- **Ad-hoc UI tests on CI** (about 2.5 min for two tests). Push the commit to main, then
  `gh workflow run ci.yml --ref main -f only_testing=OrielUITests/OrielUITests/testA,OrielUITests/OrielUITests/testB`,
  `gh run list --workflow ci.yml --event workflow_dispatch --limit 1` for the id, and poll it at most once a
  minute. Such a run uses one machine, skips lint, build and HerdrKit tests, and never cancels a push run or
  another dispatch. On failure: `gh run download <id> -n e2e-xcresult-0`, then `xcrun xcresulttool` and ffmpeg
  on the recording ([ci.md](ci.md)). The on-demand tests run with `-f on_demand=true`.
- **Hold the lock for one run only** (several agents share it): take it for one XCUITest run or one launch
  for screenshots and release it in the same shell command, also on failure (`trap`). Never hold it while
  reading results, editing, building or waiting for CI or reviewers. At most 10 minutes per hold. If you
  wait more than 20 minutes for it, tell the orchestrator. Never remove someone else's lock.
- Never send keys with `osascript` / System Events or similar: when Oriel loses focus, the keys land in the
  user's apps (phase 11 typed into the user's browser). Keys go through XCUITest only.
- A small phase (a few files, no new view) gets one review round unless a blocker comes up.
- A failure only on CI is investigated from CI logs, not with more local runs. If the user steps in for a
  moment, wait and go on.
- The screenshots a phase file lists are `XCTAttachment`s (keepAlways) in the phase's e2e tests. Green CI
  runs keep their screen recordings, and frames from them are screenshots too.

## Speed rules (lessons from phases 10 and 11)

Phase 10 took 2h12m and phase 11 over 3 hours for a few files. Where the time went, and the rule:

1. **Chasing a CI-only failure.** Phase 11 spent ~2 hours and ~10 CI runs on one ⌘= key that XCUITest on
   CI does not deliver. Rule: a failure that shows only on CI gets 20 minutes from its logs. Then
   simplify the test (or the feature) and record it in Findings, or hand it to the orchestrator. No
   debug branches or draft PRs.
2. **Too many GUI runs.** ~80 minutes of GUI lock in phase 11, two full suites by reviewers and one more
   by the agent. Rule: the GUI budget above.
3. **Waiting for CI.** A full CI run takes 10–14 minutes ([ci.md](ci.md)). Rule: never sit waiting on CI between steps; push and
   keep working. Check CI once at the end; one red run on a late commit is fixed, not re-run.
4. **Too many review rounds for a small phase.** Rule: a small phase (a few files, no new view) gets one
   round; later rounds only for the reviewer whose blocker or should was fixed. A round's nits are fixed
   or answered without another round.
5. **Design changes mid-phase.** The Settings window was redesigned and then dropped after it was built.
   Rule: a phase that adds a new window, panel or screen shows the orchestrator one screenshot of its
   first rough version before it polishes or tests it. Phases 13, 14, 15 and 19 do this.
6. **Time box.** A phase reports to the orchestrator when it passes 2 hours, with what is left.
7. **Read the CI result first.** Before guessing at a CI-only failure, open the failing step and its values
   in the CI result bundle (`gh run download <id> -p 'e2e-xcresult-*'`, one per shard). CI's display is 1x: tests on grid
   sizes allow rounding. Avoid ⌥⇧ chords in tests (global hotkeys of other apps take them).
8. **Build the parts that cannot change first.** Menus, keys, defaults and herdr calls before the look of a
   new view; the look is the part most likely to change after the screenshot.
9. **Spike herdr first** (phase 12): five minutes with one throwaway session to see what the snapshot,
   events and the calls the phase needs really send. It settles questions before they cost test runs.
10. **Fast waits, no reruns to look.** Poll accessibility values every 100 ms (the `poll` helper in the UI
   tests), not `XCTNSPredicateExpectation` (about once a second). When a single test fails, look at the
   last frames of its screen recording in the xcresult (ffmpeg on the mp4) before running it again.
11. **Log before blaming the view** (phase 14): one line written to a file from the app shows in one run
   whether an event arrives. XCUITest drags on macOS need `click(forDuration:thenDragTo:)`;
   `press(forDuration:thenDragTo:)` sends no mouse down. Dump `debugDescription` before guessing an
   element's label or value.
12. **Assert every scripted edit** (phase 15): a replace that matches nothing must fail loudly.
   **Write the screenshot's e2e test first**, so the rough screenshot (rule 5) is also its first run.
13. **Test as on CI's small screen** (phase 16): CI's display is 1024 × 768, so windows overlap. Pick and
   raise windows by identifier (`firstMatch`, ⌘`), never by click position. Log the timing of a macOS
   lifecycle question (restore, full screen) before designing around it. Never `git checkout <file>` to
   drop debug lines in a dirty tree (it reverts the phase's work in that file); remove them with an edit.
14. **Spike side effects too** (phase 17): check what each herdr write does to herdr's focus, not only its
   result (`pane.swap` moves focus even with `focus:false`). When a key does nothing, log it in the menu
   action and in `keyDown` in the first run; test chords through their menu item (global hotkeys of
   other apps take some chords on this Mac). Check a ponytail change that moves *when* code runs against
   the tests it can break before taking it.
15. **CI recordings stand in for the GUI** (phase 18): green runs keep their screen recordings; frames
   from them are screenshots. XCUITest runs nothing during a drag: let the outcome after the drop prove
   the mid-drag behavior. Spike each herdr call in the exact shape the code and tests send (defaults
   such as a missing `target_pane_id` differ).
16. **One push per review round while CI runs** (phase 19): a push cancels the full run in flight
   (cancel-in-progress). Batch fixes; use ad-hoc `only_testing` runs for single checks. Don't spend CI
   time on what XCUITest cannot read (help-tag text): assert the same string another way. Give the e2e
   reviewer the CI recordings.
17. **Keep the full run's result** (phase 20): build-for-testing outside the lock, never into the
   DerivedData a running suite uses, and copy the full run's xcresult aside at once. Make failures say
   what they saw (put the pane's text in the error). Settle ranking and ordering rules at the rough
   screenshot, before tests exist. Run the tests a layout change can move before pushing it.
18. **A helper agent may write the docs** from a list of facts while the phase agent runs tests.
19. **No branches or PRs.** Commit and push straight to `main` (`git pull --rebase --autostash` first; parallel
   lanes rebase often). CI runs on every push to main; docs-only pushes skip it (`paths-ignore`).
20. **Fast tests** (e2e-speed): wait with `exists(within:)`, `vanishes(within:)`, `has(_:_:within:)`, `until`
   or `poll`; XCTest's own waits take over a second even when the condition holds (lint rejects them). Fail
   async helpers with a throw, not XCTFail, and keep tearDown sync (else a failure hangs for 2 minutes). Relaunch the app only when the
   launch is under test (~2.5 s each). Keep a test under ~30 s; CI splits the suite by measured time into 5 jobs ([ci.md](ci.md)).

## The phase loop (inside each phase agent)

1. Pull `origin/main`. Read `AGENTS.md`, `plan/README.md`, `plan/rules.md`, `plan/standards.md`,
   `plan/ui-layout.md`, the phase file and every page it lists under "Read first",
   then the ponytail skill (`/Users/hkandala/code/pi-hkandala/extensions/pi-ponytail/skills/ponytail/SKILL.md`).
2. Build the phase in small steps. Each step: code + its tests, `make lint build test` green, a commit with a
   conventional subject (≤ 72 characters), and a push when it builds. Several commits per phase, never one
   big commit at the end.
3. Run only the e2e tests the phase adds or changes (single local tests under the GUI lock, or ad-hoc CI
   runs). The full suite runs on CI on the last code push (see "GUI budget"). Keep screenshots in
   `/tmp/oriel-shots/<phase>/`.
4. Self-review the diff against the phase file and the ponytail rules; fix what you find.
5. Start the three reviewers in parallel (briefs below). Merge their findings. Fix every
   blocker and should; answer each nit with a fix or a one-line reason.
6. Later rounds (fresh agents) re-run only the spec reviewer, plus the E2E reviewer when its own blocker
   was fixed ([workflow.md](workflow.md#reviews-who-and-when)). The last spec round also checks every Build
   and e2e item of the phase file, item by item: there is no separate verifier (phase 10: four verifier runs
   found nothing). Done when a round is clean. At most 4 rounds; if it does not converge, report to the
   orchestrator what is stuck.
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

## Metrics

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

`python3 resources/metrics/build.py` builds the dashboard from these files, git and CI (time per phase,
changes, review agents, rounds, time and value per reviewer role). Phases 24–31 wrote no metrics files:
their lanes' Findings carry the numbers.

## Briefs the phase agent sends

All reviewers are read only: they never edit files, commit, push, or run writes against
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

**E2E and GUI reviewer.** "Round 1 only, at most 15 minutes of GUI lock (`plan/rules.md`; see the GUI
budget in `plan/execution.md`). Build and run Oriel against a throwaway session
(`scripts/herdr-session.sh up oriel-dev-<name>`, `make run SESSION=…`), drive the new UI of phase NN through
XCUITest only (a scripted mouse click landed in the user's Ghostty in phase 15), try to break it, take screenshots (`screencapture -x -l <window id>`), release the
lock, delete the session. Never send keys with osascript / System Events. No full `make e2e` (CI runs the full
suite on every code push). Then read the phase's tests. Flag slop tests:
tests that assert nothing real, assert only that an element exists when the phase promises behavior, sleep
instead of waiting for a condition, duplicate another test, mock herdr where the real one is cheap, or
check pixels where herdr or an accessibility value can say it. Report a numbered list with severity and the
fix."

## The orchestrator's sanity check (after each phase)

1. `git log` of the phase: several small commits, conventional subjects, no build output or screenshots in
   the repo.
2. CI green on the last commit.
3. Read the diff once with the ponytail eye: no new protocol, manager, option or file that the phase did not
   need; no dead code; no `// TODO` without a `ponytail:` reason.
4. Read the new tests: each one checks behavior through herdr or accessibility values, waits on conditions,
   and would fail if the feature broke.
5. Look at the phase's screenshots (no extra GUI run unless something looks wrong) next to
   `resources/mockups/layout.html` and the Rex references, keep 2–3 screenshots.
6. Read the phase's Findings (implementation notes). Fold each deviation and decision into the design
   pages, `plan/ui-layout.md` and later phase files where they matter. Send the phase agent a numbered
   list of any assumption or note that looks wrong or that the user should decide, and settle it before
   the next phase.
7. If anything fails: send it back to the same phase agent with a numbered list. Otherwise log the phase as
   done below and start the next one.

## Phase agent brief (the orchestrator sends this)

> You are the phase agent for phase NN (‹name›) of Oriel (`/Users/hkandala/code/oriel`). `git pull --rebase`
> first. Follow `plan/execution.md` exactly: "GUI budget", "Speed rules", "The phase loop", "Briefs the
> phase agent sends" and "Metrics". Build everything in `plan/phases/NN-*.md`; the design pages in
> `docs/content/docs/` are the source of truth and `plan/ui-layout.md` maps the window. Read the Findings of the phases
> before yours. Small commits, pushed straight to `main` as you go (no branches or PRs). Use
> `DERIVED_DATA=/tmp/oriel-dd-phaseNN`, the GUI lock for any GUI run, and only throwaway `oriel-dev-*` /
> `oriel-e2e-*` herdr sessions (delete them after). Never touch existing herdr sessions or the user's Rex
> app. Start the reviewers (phaseNN-spec-review, phaseNN-ponytail-review, phaseNN-e2e-review; -2, -3 for
> later rounds) yourself and stop them when done. No slop: no tests that
> assert nothing real, no code for later phases, no settings or abstractions the phase does not ask for.
> Do not ask the user anything; ask the orchestrator only when the design does not answer a question, and
> report to it at 2 hours. When done, reply with the step 9 report, including which reviewers were a must
> and which added little, and your top 3 lessons for speed.

## Progress log

| Phase | Agent | Status | Notes |
|---|---|---|---|
| 10 | phase10-appearance | done | 25 commits, 4 rounds, 2h12m; verifier never found anything |
| 11 | phase11-settings | done | 44 commits, 4 rounds, ~3h40m; Settings window dropped by the user; ~85 min GUI lock |
| 12 | phase12-program-icons | done | 16 commits, 3 rounds, 1h07m, ~20 min GUI lock |
| 13 | phase13-title-row | done | 15 commits, 3 rounds, 1h55m, ~35 min GUI lock |
| 14 | phase14-sidebar | done | 13 commits, 3 rounds, 1h28m, ~40 min GUI lock |
| 15 | phase15-agents | done | 13 commits, 4 rounds, 1h11m, ~30 min GUI lock |
| 16 | phase16-windows | done | 12 commits, 3 rounds, 1h47m, ~50 min GUI lock |
| 17 | phase17-panes | done | 18 commits, 4 rounds, 1h56m, ~55 min GUI lock |
| 18 | phase18-drag-drop | done | 14 commits, 2 rounds, 2h56m, CI only (GUI paused) |
| 19 | phase19-hover-card | done | 18 commits, 2 rounds, 2h08m, mostly CI |
| 20 | phase20-palette | done | 15 commits, 3 rounds, 2h08m |
| 21 | phase21-find-finish | done | 17 commits, 4 rounds, 2h22m, ~25 min GUI lock + 1 full run |
| 22 | phase22-visual-match | done | 34 commits, 4 rounds, ~4h (incl. user additions); parallel worktree |
| 23 | phase23-comments | done | 7 commits, comments only (checked), 39 deleted, 29 fixed |
| Final review | 3 reviewers + 3 fixers | done | 61 commits, 1h27m, CI green on a707a44 |
| 24 | lanes A–G | done | the user's first hands-on list; UI tests on CI only |
| 25 | lanes H–L, S, A2, F2, P, I2, O, B2, T | done | floating panes, Ahead (changes before herdr answers), memory and CPU |
| 26 | phase26-remote-hosts | done | remote hosts over SSH, CI's localhost sshd |
| 27 | lanes A3, G3, T3, F3, V | done | live surfaces stay; the overview replaces the tab preview |
| 28 | lanes E, V, F, R | done | empty sessions, a bounded overview, float requests, remote hosts |
| 29 | lanes D, R, V, M, K, F, C, S, T | done | tab drags to a workspace, the UI at scale, selection colors |
| 30 | lanes W, V, P, R, G, D, Q, N | done | many tabs in two windows, three-finger swipes |
| 31 | lanes S, G, F, M, K, O, integration | done | selection in view, CI in 5 shards by time, on-demand tests |
| 32 | final review: 11 area agents, 3 auditors, f-e2e | running | [32-final-review.md](phases/32-final-review.md) |
