# CI

Findings from the `ci` runs of 2026-10-21 and 22 (40 runs: 17 green, 12 red, 11 cancelled), read from
`gh run view --log-failed` and the `e2e-xcresult` artifacts.

## Causes

- **Cancelled runs are fine.** All 11 were pushes to main that the next push superseded within minutes
  (`concurrency: cancel-in-progress`). Docs-only pushes do not run CI (`paths-ignore`); the docs pushes that
  ran also carried code commits.
- **Every red run was `test-e2e`.** lint and build never failed.
- **8 of 12: `testFontSizeKeys`, a wrong test assumption.** It asked both sides of the grid to shrink on
  each 1 pt step. CI's display is 1x, where 14 and 15 pt have the same column count, so the ⌘= step never
  passed (phase 11 chased key delivery first; a debug run showed ⌘= arrives fine). Fixed in e2465e1: the
  test checks ⌘+, ⌘0, ⌘-, and accepts one side staying.
- **1 of 12, and 2 more tests in font runs: fixed in the next commits.** 9369d83: the window.look
  element covered the window, so hit tests failed in 18 tests (6d698f1). 6916f5b: Option sent Alt on CI's
  keyboard layout (8925395). b5a3631: the Settings window's font test, gone with the window (e5be74f).
- **2 of 12: tests fixed the same hour.** 4d8b1d7 and c73161c: the close-tab dialog's count and the
  teardown of a closed tab (d106493).
- **1 flake, a real app bug: two tabs lit after the sidebar hid.** 9eb0b22,
  `testTabRowOfAnotherWorkspaceShowsThatTab`: the video shows the strip at rest on t1 with both title-bar
  capsules lit, so the strip's page was a fraction past 0 (the thousandth rounding kept it). The strip now
  rests on a page when its offset is within a point of it; the assertion prints both values if it comes
  back.
- **Timeouts were not the problem.** e2e takes 8–12 min of its 20; no test hit the 120 s allowance except
  after a real failure, and those hung in teardown until the allowance (fixed, see Speed).

## Keeping CI green

- A test that fails only on CI: read the xcresult first (`gh run download <id> -p 'e2e-xcresult-*'`, one per shard,
  `xcrun xcresulttool get test-results tests|activities --path …`, `xcresulttool export attachments` for
  the screen recording; `ffmpeg -ss <s> -frames:v 1` gets a frame). The activity times and the video
  say which step and what the window showed; guessing costs runs.
- CI is a 1x, 1024 × 674 pt window on a VM, US layout. Grid and pixel checks must
  hold at 1x.
- CI's Mac has Reduce Motion on, so no motion that honors it runs there. A test of motion
  launches with `-forceMotion YES` (layout motion and the sidebar slide). While a test takes screenshots in a loop,
  the screen recording gets a frame only every 0.3–0.6 s: look at motion frame by frame in a step without them.
  On a Mac with Reduce Motion off, every test sees the motion: a frame read right after a split can be mid-way.
- Wait on conditions (`exists(within:)`, `has(_:_:within:)`, `until`, `poll`), never a bare sleep; a sleep is
  only the pause inside a poll.
- Check a fix with `gh run rerun <id>` on the same commit, not only one green run.

## Speed

Measured 2026-10-22 from the xcresults of green run 39843820616 (before) and the runs after the change.

### Where the time went (before)

| Part | Time |
|---|---|
| CI run, push to done | 18 min 43 s (one e2e job: lint and build ran beside it) |
| HerdrKit tests (`make test`) | 39 s |
| Build for testing | ~70 s |
| 72 UI tests | 966 s (16 min): 167 s setUp, 782 s bodies, 17 s tearDown |
| One app launch (terminate the last one, launch, idle) | ~2.3 s, 79 per run (~3 min) |

- **XCTest's waits cost a second each.** `waitForExistence`, `waitForNonExistence`, `wait(for:toEqual:)` and
  `XCTNSPredicateExpectation` check about once a second, and take 1.2 s even when the condition already
  holds (a probe test: 1.24 s for an element on screen; `.exists` is 0.2 s). The suite had about 380 of them,
  plus `hasKeyboard` on a predicate expectation: roughly a third of the test time.
- **One job ran everything in a row.** The tests are independent (each launches the app, the e2e script
  makes fresh herdr sessions), so they split across machines with no change.
- **A failure in an async test cost 2 more minutes and its recording.** With `continueAfterFailure = false`
  XCTest stops the test inside the main actor's job and runs teardown there; anything in teardown that awaits
  the main actor (an `async` tearDown, a `@MainActor` teardown block with `await`) then waits until the 120 s
  allowance (spindump in run 39863167622; two such failures in 39868989432). A probe test failed in 5.9 s after
  the fix.
- Not worth it: per-test setUp is ~2.5 s of each test (terminate ~1.4 s), so merging tests to share a launch
  saves little and costs isolation. Build and setup take 65–105 s per job; a package cache did not shorten
  them (see below), a full DerivedData cache was not tried. `-parallel-testing-enabled` runs clones on one
  Mac, which UI tests cannot share (one mouse, one app bundle id).

### What changed

- **100 ms waits** (3bf94a4): `exists(within:)`, `vanishes(within:)`, `has(_:_:within:)` on `XCUIElement` and
  `until(_:_:)` replace XCTest's waits; a SwiftLint rule (`fast_waits`) rejects the old ones in the UI tests.
- **4 parallel e2e jobs** (10cd9e1, 2e6ff98): `make e2e SHARD=i/4` runs every 4th test by name (by name, not
  file order: files hold similar tests). lint, both builds and the HerdrKit tests share one job, so a run
  needs 5 macOS runners, the account's limit; a second run at the same time queues.
- **No teardown waits for the main actor** (6c76c1a, 886a4a4): a timed-out `poll` throws instead of calling
  XCTFail, tearDown is sync, and async teardown blocks use the nonisolated `ids(_:in:)`. A failure now shows at
  once and keeps its screen recording.
- **Tried and dropped: caching Swift packages** (16081ad, 99af648). libghostty's 190 MB xcframework restored in
  2 s, but build plus session setup stayed 65–105 s per job with or without it.
- **Races the slow waits hid:** `newTab` now waits for the capsule to be hittable (it slides in; a click 0.2 s
  after it appears missed it). Expect a few more of these: a wait that passes at once can expose an animation.
- No test removed or merged.

### Before and after

| | Before (39843820616) | After (39870619668) | After (39871268934) |
|---|---|---|---|
| CI run, push to done | 18 min 43 s | 5 min 37 s | 6 min 25 s |
| Slowest e2e job | 18 min 38 s | 5 min 32 s | 6 min 20 s |
| UI test time, all tests | 966 s (72 tests) | 682 s (76 tests) | 770 s (76 tests) |
| The 71 tests in both | 950 s | 636 s | 716 s |

Other green runs after the change: 39863083184 (7 min 42 s), 39866497406 (8 min 22 s, its jobs shared the
5 runners with a second run), 39868394263 (5 min 2 s). The same tests vary by ±15 % between runs on CI's VMs,
and the 4 jobs end up to a minute apart (split by name, not by time).

Flakes seen in these runs: see [Flakes](#flakes).

### Writing fast tests

- Wait with `exists(within:)`, `vanishes(within:)`, `has(_:_:within:)`, `until` or `poll` (lint enforces it).
- Fail an async helper with a thrown error, never XCTFail; keep tearDown sync and async teardown blocks off the
  main actor (the 2-minute hang).
- A launch costs ~2.5 s: relaunch only when the launch is what the test checks.
- Each element query takes 0.1–0.2 s and each click about 1 s: check the outcome through one herdr call or one
  accessibility value, not a walk over many elements.
- Keep a test under ~30 s: one long test sets its shard's time. New tests join a shard by name on their own.

## Flakes

Three flakes seen around the speed work (2026-10-22), each traced to a cause in the app or the tests. The two
UI tests' recordings were lost (their failures hung in teardown before 6c76c1a), so the causes come from the
activity logs, the code and hand runs.

- **`testHoldingOverACapsuleSpringLoadsItsTabAndADropSplitsRight`: a late drop update re-ran the spring-load**
  (39863167622 on 3b57779; 39836126263 was the capsule-drop bug fixed in 0513a67, 39859559120 the selection wait
  fixed in da845aa). After the first drop (refused, `zoomed_tab`), SwiftUI can send a `dropUpdated` after
  `performDrop` with no `dropExited` after it. That set the capsule's `over` again and started a new 0.65 s
  spring-load, which selected the zoomed tab again just after the test clicked back to the first tab. The next
  drag then started on a card of the wrong tab, and its drop on its own tab's capsule moved nothing. Fixed in
  phase 18's follow-up (47017c9, aab15c8): targets clear their state when a drag starts or ends, ignore updates
  with no drag, and a spring-load fires only while a pane is dragged. Hand checks saw the same stale state.
- **`testDropOnACardsCenter…`: two ways the old card kept the keyboard after a re-place** (39868989432 on
  16081ad, after the first keyboard fix). (1) A write reads the snapshot without waiting for it; when the drop
  ended before the store showed the moved pane in its tab, `focusKeyboardCard` gave the keyboard to the tab's
  old card, and that card's `becomeFirstResponder` recorded it as the tab's keyboard card (`tookKeyboard`), so
  the snapshot that came next kept it. Now `Page` holds the moved terminal and gives the keyboard to nobody until
  a snapshot shows it in its tab (13bf138). (2) A terminal view that SwiftUI moves to a new host while it is the
  first responder claims the keyboard back when it is in the window again; that claim was made even after the
  app had asked for another card, so the two raced. Now a view re-claims only if it still holds the window's
  latest claim; any terminal that becomes first responder drops the others' claims (21b8ed2).
- **HerdrKit `reads at once, one at a time…`: blocked cooperative threads** (39866693109). The integration
  tests ran `herdr-session.sh up` and `down` in `Process.waitUntilExit`, which blocks a thread of Swift's
  cooperative pool (one thread per core) for up to seconds; with the tests in parallel on CI's small VM the
  pacing test's read waited for a free thread. Locally the read starts 0.1–0.2 ms after the event. The shell
  helper now awaits the exit (`terminationHandler`), so no test blocks a pool thread (81a4273); the 100 ms bound
  stays.
- **Proof:** the full run on 21b8ed2 (39876558654) and five ad-hoc runs of the two UI tests (39876582219,
  39876589569, 39876596834, 39876603997, 39876610911) all green; HerdrKit's suite 20 times in a row locally, green;
  the drag and keyboard tests (8) green in one local run.

