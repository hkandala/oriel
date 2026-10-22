# Execution plan: UI polish phases 10–21

How the UI polish is built, phase by phase, by agents. The orchestrator (the main agent) follows this file.
It does not write app code. It starts one phase agent at a time, checks its result, and only then starts the
next phase.

## Roles

| Role | Who | Does | Never |
|---|---|---|---|
| Orchestrator | the main agent | starts each phase agent with the brief below, answers its questions from the design, runs the sanity check, starts the next phase, keeps the progress log at the end of this file | writes app code; skips the sanity check |
| Phase agent | one per phase | reads the plan, builds the phase with small commits, self-reviews, starts the reviewers and the verifier, fixes every finding, pushes, reports | starts the next phase; pushes red builds; writes slop tests |
| Reviewers | 3 in round 1, started by the phase agent, read only; later rounds only the ones still needed | spec review, ponytail review, e2e and GUI review (see below) | edit files or commit |
| Verifier | once, after a clean round, started by the phase agent, read only | checks every Build item and every e2e item of the phase file is done and works, item by item, with evidence | edit files or commit |

## GUI budget (the user works on this Mac)

GUI runs are slow and take over the user's mouse and keyboard. Phase 11 used about 80 minutes of GUI lock
for a small phase. The budget per phase:

| Who | GUI allowed | Not allowed |
|---|---|---|
| Phase agent, while building | single XCUITest runs of the tests it writes or changes (`-only-testing:`), about 2 min each | full `make e2e`; manual app driving |
| Phase agent, at the end | ONE full `make e2e` after the last code change; one screenshot run when the phase changes how things look (XCTAttachments in that run are enough) | a second full run unless the first failed |
| E2E reviewer | round 1 only, at most 15 min of lock: drive the new UI through XCUITest (or by hand with screenshots) and read the tests; no full `make e2e` | later rounds, unless its own blocker was fixed (then single tests only) |
| Spec and ponytail reviewers, verifier | none: read the code, the tests, the phase agent's final run and CI | any GUI run |

- **Now:** the user is away; local GUI runs are allowed under the GUI budget until the user pauses again.
  CI ad-hoc runs stay available.
- **Ad-hoc UI tests on CI** (when the GUI is paused; about 2.5 min for two tests). Push the commit to main
  (`[skip ci]` in the subject for a WIP step), then:
  `gh workflow run ci.yml --ref main -f only_testing=OrielUITests/OrielUITests/testA,OrielUITests/OrielUITests/testB`,
  `gh run list --workflow ci.yml --event workflow_dispatch --limit 1` for the id, `gh run watch <id>`. Such a run
  skips lint, build and HerdrKit tests, and never cancels a push run or another dispatch. On failure:
  `gh run download <id> -n e2e-xcresult-0`, then `xcrun xcresulttool` and ffmpeg on the recording (plan/ci.md).
  Locally the same is `make e2e ONLY=…`. The full suite still runs on the phase's last code push.
- When the user pauses GUI work, the orchestrator holds `/tmp/oriel-gui.lock` with owner "user". Nobody
  removes or works around it; agents keep building, testing without GUI and pushing (CI runs e2e).
- Never send keys with `osascript` / System Events or similar: when Oriel loses focus, the keys land in the
  user's apps (phase 11 typed into the user's browser). Keys go through XCUITest only.
- A small phase (a few files, no new view) gets one review round unless a blocker comes up.
- CI runs the full suite on every push; a failure only on CI is investigated from CI logs, not with more
  local runs. The user may step in for a moment; then wait and go on.
- The screenshots a phase file lists are `XCTAttachment`s (keepAlways) in the phase's e2e tests, taken in
  the final full run: no separate screenshot sessions. Items "checked by hand" fit in the E2E reviewer's
  15 minutes.

## Speed rules (lessons from phases 10 and 11)

Phase 10 took 2h12m and phase 11 over 3 hours for a few files. Where the time went, and the rule:

1. **Chasing a CI-only failure.** Phase 11 spent ~2 hours and ~10 CI runs on one ⌘= key that XCUITest on
   CI does not deliver. Rule: a failure that shows only on CI gets 20 minutes from its logs. Then
   simplify the test (or the feature) and record it in Findings, or hand it to the orchestrator. No
   debug branches or draft PRs.
2. **Too many GUI runs.** ~80 minutes of GUI lock in phase 11, two full suites by reviewers and one more
   by the agent. Rule: the GUI budget above.
3. **Waiting for CI.** A CI run takes ~10 minutes. Rule: never sit waiting on CI between steps; push and
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
16. **A helper agent may write the docs** from a list of facts while the phase agent runs tests.
17. **No branches or PRs.** Phases run one at a time: commit and push straight to `main` (pull --rebase
   first). CI runs on every push to main; docs-only pushes already skip it (`paths-ignore`).

## The phase loop (inside each phase agent)

1. Pull `origin/main`. Read `AGENTS.md`, `plan/README.md`, `plan/rules.md`, `plan/standards.md`,
   `plan/ui-polish.md`, `plan/ui-layout.md`, the phase file and every page it lists under "Read first",
   then the ponytail skill (`/Users/hkandala/code/pi-hkandala/extensions/pi-ponytail/skills/ponytail/SKILL.md`).
2. Build the phase in small steps. Each step: code + its tests, `make lint build test` green, a commit with a
   conventional subject (≤ 72 characters), and a push when it builds. Several commits per phase, never one
   big commit at the end.
3. Run only the e2e tests the phase adds or changes (single tests, GUI lock). The one full `make e2e`
   comes at the end, by the phase agent (see "GUI budget"). Keep screenshots in `/tmp/oriel-shots/<phase>/`.
4. Self-review the diff against the phase file and the ponytail rules; fix what you find.
5. Start the three reviewers in parallel (briefs below). Merge their findings. Fix every
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

**E2E and GUI reviewer.** "Round 1 only, at most 15 minutes of GUI lock (`plan/rules.md`; see the GUI
budget in `plan/execution.md`). Build and run Oriel against a throwaway session
(`scripts/herdr-session.sh up oriel-dev-<name>`, `make run SESSION=…`), drive the new UI of phase NN through
XCUITest only (a scripted mouse click landed in the user's Ghostty in phase 15), try to break it, take screenshots (`screencapture -x -l <window id>`), release the
lock, delete the session. Never send keys with osascript / System Events. No full `make e2e` (the phase
agent runs it once at the end; CI runs it on every push). Then read the phase's tests. Flag slop tests:
tests that assert nothing real, assert only that an element exists when the phase promises behavior, sleep
instead of waiting for a condition, duplicate another test, mock herdr where the real one is cheap, or
check pixels where herdr or an accessibility value can say it. Report a numbered list with severity and the
fix."

**Verifier.** "Verify phase NN is complete. No GUI runs. For every numbered Build item and every e2e item
in `plan/phases/NN-*.md`, say done / partly / missing, with evidence: the file:line that implements it and
the test that shows it works, citing the phase agent's final `make e2e` run and CI. Run `make lint build
test`. Pass only when every item is done and every check is green."

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
> phase agent sends" and "Metrics". Build everything in `plan/phases/NN-*.md`; `plan/ui-layout.md` is the
> layout source of truth and `resources/mockups/layout.html` shows it. Read the Findings of the phases
> before yours. Small commits, pushed straight to `main` as you go (no branches or PRs). Use
> `DERIVED_DATA=/tmp/oriel-dd-phaseNN`, the GUI lock for any GUI run, and only throwaway `oriel-dev-*` /
> `oriel-e2e-*` herdr sessions (delete them after). Never touch existing herdr sessions or the user's Rex
> app. Start the reviewers (phaseNN-spec-review, phaseNN-ponytail-review, phaseNN-e2e-review; -2, -3 for
> later rounds) and the verifier (phaseNN-verifier) yourself and stop them when done. No slop: no tests that
> assert nothing real, no code for later phases, no settings or abstractions the phase does not ask for.
> Do not ask the user anything; ask the orchestrator only when the design does not answer a question, and
> report to it at 2 hours. When done, reply with the step 9 report, including which reviewers were a must
> and which added little, and your top 3 lessons for speed.

## Decisions without the user

The user is not asked during phases 10–21. The orchestrator decides open questions from the design and the
ponytail rules, records each choice in the design pages, keeps going until phase 21 is done, and lists
here what the user should check at the end.

### Hand checks waiting for the GUI

- Phase 18: the 9 checks in `plan/phases/18-drag-and-drop.md` Findings, "To check by hand when the GUI is
  free" (Esc, forbidden pointer, window not moving, spring-load to an edge in another tab, full track or
  sidebar). The orchestrator runs them (or a short agent) when the user frees the GUI.

### For the user to check at the end

- Phase 10: the four looks next to Rex (`/tmp/oriel-shots/10/final-*.png`). Known gaps kept on purpose:
  the Classic dark pill is a little brighter than Rex (`#303030` vs `#292929`); Glass dark cards are
  lighter than the window until phase 17's fade.
- Phase 11: the Settings window is dropped for now (comes back after its mock-ups). ⌘= (second Bigger key)
  has no CI test; try it by hand. Phase 11's osascript keys may have landed in your browser or Raycast.
- Phase 13: the machine menu has no icons (macOS 27 draws no item images in app menus). A tab renamed
  to only digits shows the program title (herdr's default labels are digits). Tab status glyphs come back
  in phase 15.
- Phase 14: the Open Session sheet lists every herdr session on the Mac (your `default` and `pi-herd`
  too). Workspaces the app creates in a repo are not indented as worktrees (herdr fills the worktree
  fields only for `worktree.*` calls). The "herdr is too old" page still says to update herdr.
- Phase 15: notifications and the Dock badge need a signed build: the ad-hoc dev build gets no
  notification permission, so neither showed on this Mac. One reviewer's scripted mouse click landed in
  your Ghostty window (no keys sent).
- Phase 16: the app stays open with no window, as WindowGroup apps do. Window restore after quit is
  made independent of the macOS "close windows when quitting" setting in phase 21.
- Phase 17: herdr 0.9.5's `pane.swap` moves herdr's focus even with `focus:false`, so Split Left / Up
  and swaps change the focused pane a herdr TUI on the same session sees. ⌃⌘= (Balance Splits) is taken
  by a global hotkey on your Mac (BetterTouchTool or Raycast); the menu item works.
- The UI tests share the app's defaults with your own Oriel (same bundle id): an e2e run leaves the look
  at Glass Dark.

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
| 19 | | not started | |
| 20 | | not started | |
| 21 | | not started | |
