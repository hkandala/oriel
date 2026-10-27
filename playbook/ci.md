# CI

How CI runs, how to run part of it, and how to keep it green and fast.

## Layout

- **Workflows.** `.github/workflows/ci.yml` runs the app's checks on every push to main and on pull
  requests, except docs-only changes (`playbook/**`, `docs/**`, `resources/**`, `**/*.md`): those start
  no run, so they cancel nothing.
- **Docs site.** `.github/workflows/docs-deploy.yml` builds the docs and deploys them to the Vercel project
  `oriel` when `docs/` changes; Vercel's own git deploys are off. Run the `vercel` CLI only from the repo
  root: in another folder `vercel pull --yes` creates and links a new project.
- **Machines.** `runs-on: xcode-27`: a VM with a 1x display (a 1024 × 674 pt screen), the US keyboard layout
  and Reduce Motion on. The account has 5 macOS runners. herdr is downloaded and checked by its SHA-256
  (`HERDR_VERSION` in `ci.yml`).
- **Five jobs** (`test (0)` to `test (4)`), each a shard of the UI tests. `test (0)` also runs `make lint`,
  `make build`, `make test` (HerdrKit, the three-finger check, the acknowledgements check) and, after its UI tests,
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
  2300 s of UI tests.

## Running part of it

| What | Command | Machines |
|---|---|---|
| Full run | push to main | 5 |
| Chosen UI tests | `gh workflow run ci.yml --ref main -f only_testing=OrielUITests/OrielUITests/testA,OrielUITests/OrielUITests/testB` | 1, no lint or build |
| On-demand tests | `gh workflow run ci.yml --ref main -f on_demand=true` | 4 |
| Same locally | `make e2e ONLY=…`, `make e2e ON_DEMAND_ONLY=1` (under the GUI lock) | this Mac |

- **Find your run:** `gh run list --workflow ci.yml --limit 5 --json databaseId,headSha,event,createdAt`,
  the one on your commit (or created after your dispatch).
- **Watch it** in a background command, not a polling loop: `gh run watch <id> >/dev/null; gh run view <id>
  --json conclusion,jobs`. Trust the `conclusion`: `gh run watch --exit-status` has exited 0 on a failed
  run. A chosen-tests run takes about 2.5 minutes for two tests.
- A push cancels the push run in flight (`cancel-in-progress`). A dispatch never cancels a push run or
  another dispatch. Batch dispatches; use chosen-tests runs for single checks.
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
3. Think of CI's machine ([lessons.md](lessons.md#testing-the-ui)): a 1x display, a small window, the US
   layout (Option sends Alt), Reduce Motion on.
4. Give it 20 minutes from the logs. Then simplify the test or the feature and write it down, or hand it on.
   No debug branches.
5. Never rerun to green. A fix is proven by two full runs in a row green on the first try.

## Writing fast tests

- Wait with `exists(within:)`, `vanishes(within:)`, `has(_:_:within:)`, `until` or `poll` (100 ms polls).
  XCTest's own waits take over a second even when the condition already holds; lint (`fast_waits`) rejects
  them.
- Fail an async helper with a thrown error, never `XCTFail`, and keep tearDown sync: a failure that waits
  for the main actor in teardown hangs until the 120 s allowance and loses its recording. In tearDown, move
  the pointer off the chrome and restore state before the tabs it lives in close.
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

Round the means to whole seconds: `scripts/shard.py` reads integers.
