# CI

How CI runs, how to run part of it, and how to keep it green and fast.

## Layout

- **Workflows.** `.github/workflows/ci.yml` runs the app's checks on every push to main and on pull
  requests, except docs-only changes (`playbook/**`, `docs/**`, `resources/**`, `**/*.md`).
  `.github/workflows/docs-deploy.yml` builds the docs site and deploys it to Vercel when `docs/` changes.
- **Machines.** `runs-on: xcode-27`: a VM with a 1x display (a 1024 × 674 pt window), the US keyboard layout
  and Reduce Motion on. The account has 5 macOS runners. herdr is downloaded and checked by its SHA-256
  (`HERDR_VERSION` in `ci.yml`).
- **Five jobs** (`test (0)` to `test (4)`), each a shard of the UI tests. `test (0)` also runs `make lint`,
  `make build`, `make test` (HerdrKit and the three-finger check) and, after its UI tests,
  `make strip-check`. Every job starts CI's sshd on localhost for the remote-host tests
  (`scripts/ci-sshd.sh`).
- **Shards by time.** `make e2e SHARD=i/5 SHARD_HEAD=180` runs the tests that `scripts/shard.py` gives
  shard i: the slowest test first, each to the shard with the least time so far, from
  `scripts/test-times.tsv` (a test not listed counts 15 s). Shard 0 starts with 180 s for its checks.
- **On-demand tests.** The Makefile's `ON_DEMAND` list (stress tests, cost and memory measurements,
  frame-record tests, the look scenes) is left out of `make e2e` and of push runs. Run them before a release
  and after a change to what they measure.
- **Results.** Each job uploads `e2e-xcresult-<shard>`: the xcresult with screen recordings, also of green
  runs. Job 0 also uploads the strip check's captures.
- **Time.** A full run takes 10–14 minutes: about 2 minutes of setup and build per job plus a fifth of about
  2300 s of UI tests. Each runner more would save about a minute; shorter tests would not (the slowest ones
  click through many steps, and each test pays 3–4 s to launch the app).

## Running part of it

| What | Command | Machines |
|---|---|---|
| Full run | push to main | 5 |
| Chosen UI tests | `gh workflow run ci.yml --ref main -f only_testing=OrielUITests/<Class>/testA,…` | 1, no lint or build |
| On-demand tests | `gh workflow run ci.yml --ref main -f on_demand=true` | 4 |
| Same locally | `make e2e ONLY=…`, `make e2e ON_DEMAND_ONLY=1` (under the GUI lock) | this Mac |

- Get the id with `gh run list --workflow ci.yml --event workflow_dispatch --limit 1` and check it at most
  once a minute. Read the result with `gh run view <id> --json conclusion`: `gh run watch --exit-status` has
  exited 0 on a failed run. A chosen-tests run takes about 2.5 minutes for two tests.
- A push cancels the push run in flight (`cancel-in-progress`). A dispatch never cancels a push run or
  another dispatch. So batch pushes while a full run matters, and use chosen-tests runs for single checks.
- Docs-only pushes skip CI.
- **Sign off** with a full run on your own last commit: another lane's push can cancel yours, so dispatch
  one (`gh workflow run ci.yml --ref main`) if needed, and judge a run by which tests failed, not by its
  color.
- **Old code or work in progress on CI** (a remote probe while the GUI is busy, or to prove a test is red
  on the old code): commit on a detached HEAD, push a tag, `gh workflow run ci.yml --ref <tag> -f
  only_testing=…`, read the result, delete the tag.

## A test fails only on CI

1. Check which commit the red run was on: often a later commit already fixed it.
2. Read the result before guessing: `gh run download <id> -p 'e2e-xcresult-*'` (one per shard), then
   `xcrun xcresulttool get test-results tests|activities --path …` for the failing step and its values, and
   `xcresulttool export attachments` for the screen recording (`ffmpeg -ss <s> -frames:v 1` gets a frame).
3. Think of CI's machine: a 1x display (grid and pixel checks must hold at 1x), a small window (windows
   overlap: pick them by identifier, never by position), the US layout (Option sends Alt), Reduce Motion on
   (a test of motion launches with `-forceMotion YES`).
4. Give it 20 minutes from the logs. Then simplify the test or the feature and write it down, or hand it on.
   No debug branches.
5. Never rerun to green. A fix is proven by two full runs in a row green on the first try.

## Writing fast tests

- Wait with `exists(within:)`, `vanishes(within:)`, `has(_:_:within:)`, `until` or `poll` (100 ms polls).
  XCTest's own waits take over a second even when the condition already holds; lint (`fast_waits`) rejects
  them.
- Fail an async helper with a thrown error, never `XCTFail`, and keep tearDown sync: a failure that waits
  for the main actor in teardown hangs until the 120 s allowance and loses its recording.
- A launch costs about 2.5 s: relaunch only when the launch is what the test checks.
- An element query takes 0.1–0.2 s and a click about 1 s: check the outcome through one herdr call or one
  accessibility value, not a walk over many elements.
- Keep a test under about 30 s: one long test sets its shard's time.
- Make a failure say what it saw (put the pane's text or both values in the message).

## Refresh the test times

When tests are added or get slower, rewrite `scripts/test-times.tsv` from two or three green full runs: the
mean of the passed tests, from each shard's artifact:

```sh
xcrun xcresulttool get test-results tests --path <e2e.xcresult> | jq -r '.. | objects |
  select(.nodeType == "Test Case" and .result == "Passed") | "\(.durationInSeconds)\t\(.name | rtrimstr("()"))"'
```

## UI tests without the user's screen

XCUITest posts real mouse and key events into the login session, so a local run moves the user's pointer,
takes focus and can type into other apps. No trick on the host isolates it (a virtual display shares the
same pointer). Only another session does: CI (what we use), a macOS VM on this Mac (Tart with a Cirrus
image; Apple allows two macOS VMs at a time), or a second Mac. That is why agents prefer chosen-tests CI
runs and take the GUI lock for local runs.
