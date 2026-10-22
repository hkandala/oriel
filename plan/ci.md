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
  after a real failure (a poll that never passes runs out its tries).

## Keeping CI green

- A test that fails only on CI: read the xcresult first (`gh run download <id> -p 'e2e-xcresult-*'`, one per shard,
  `xcrun xcresulttool get test-results tests|activities --path …`, `xcresulttool export attachments` for
  the screen recording; `ffmpeg -ss <s> -frames:v 1` gets a frame). The activity times and the video
  say which step and what the window showed; guessing costs runs.
- CI is a 1x, 1024 × 674 pt window on a VM, US layout. Grid and pixel checks must
  hold at 1x.
- Wait on conditions (`waitForExistence`, `wait(for:toEqual:)`, `poll`), never a bare sleep; a sleep is
  only the pause inside a poll.
- Check a fix with `gh run rerun <id>` on the same commit, not only one green run.
