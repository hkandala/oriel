# CI

How CI runs, how to run part of it, and how to keep it green and fast.

## Layout

- **Workflows.** `.github/workflows/ci.yml` runs the checks on every push to main and on pull requests,
  except docs-only changes (`playbook/**`, `docs/**`, `resources/**`, `**/*.md`): those start no run. The
  UI tests run only on a dispatch.
- **Docs site.** `.github/workflows/docs-deploy.yml` builds the docs and deploys them to the Vercel project
  `oriel` when `docs/` changes; Vercel's own git deploys are off. Run the `vercel` CLI only from the repo
  root: in another folder `vercel pull --yes` creates and links a new project.
- **Machines.** `runs-on: xcode-27`: a VM with a 1x display (a 1024 × 674 pt screen), the US keyboard layout
  and Reduce Motion on. The account has 5 macOS runners. herdr is downloaded and checked by its SHA-256
  (`HERDR_VERSION` in `ci.yml`). At 1x, cell sizes round: `stty size` can be one column narrower than the
  card's grid, and a 1 pt font step can leave the column count the same, so grid tests allow one column. A
  second ⌃⌘F during the full-screen animation is lost.
- **Checks** (a push or a pull request): one job, `checks`, runs `make lint`, `make build`,
  `make build-tests` (the UI tests compile), `make test` (HerdrKit, the three-finger check, the
  acknowledgements check) and `make strip-check`. It takes about 3 minutes.
- **Full run** (a dispatch): five jobs (`test (0)` to `test (4)`), each a shard of the UI tests. Every job
  starts CI's sshd on localhost for the remote-host tests (`scripts/ci-sshd.sh`).
- **Shards by time.** `make e2e SHARD=i/5` runs the tests that `scripts/shard.py` gives shard i: the slowest
  test first, each to the shard with the least time so far, from `scripts/test-times.tsv` (a test not
  listed counts 15 s).
- **On-demand tests.** The Makefile's `ON_DEMAND` list (stress tests, cost and memory measurements,
  frame-record tests, the look scenes) is left out of `make e2e` and of full runs. Run them before a release
  and after a change to what they measure.
- **Results.** Each test job uploads `e2e-xcresult-<shard>`: the xcresult with screen recordings, also of
  green runs. The checks job uploads the strip check's captures (`strip-check`).
- **Time.** A full run takes 10–14 minutes: about 2 minutes of setup and build per job plus a fifth of about
  2130 s of UI tests.

## Running part of it

| What | Command | Machines |
|---|---|---|
| Checks | push to main | 1 |
| Full run | `gh workflow run ci.yml --ref main` | 5 |
| Chosen UI tests | `gh workflow run ci.yml --ref main -f only_testing=OrielUITests/OrielUITests/testA,OrielUITests/OrielUITests/testB` | 1 |
| On-demand tests | `gh workflow run ci.yml --ref main -f on_demand=true` | 4 |
| Same locally | `make e2e ONLY=…`, `make e2e ON_DEMAND_ONLY=1` (under the GUI lock) | this Mac |

- **Find your run:** `gh run list --workflow ci.yml --limit 5 --json databaseId,headSha,event,createdAt`,
  the one on your commit (or created after your dispatch).
- **Watch it** in a background command, not a polling loop: `gh run watch <id> >/dev/null; gh run view <id>
  --json conclusion,jobs`. Trust the `conclusion`: `gh run watch --exit-status` has exited 0 on a failed
  run. A chosen-tests run takes about 2.5 minutes for two tests.
- A push cancels the checks run in flight (`cancel-in-progress`). A dispatch never cancels a run and is
  never cancelled. Only the orchestrator dispatches full runs ([workflow.md](workflow.md#ci)). Use
  chosen-tests runs for single checks.
- **Judge a run by which tests failed**, not by its color, and give each failing test to the track that owns
  it.
- **Old code or work in progress on CI** (a remote probe while the GUI is busy, or to prove a test is red
  on the old code): commit on a detached HEAD, push a tag, `gh workflow run ci.yml --ref <tag> -f
  only_testing=…`, read the result, delete the tag. The hooks still run on that commit (no `--no-verify`):
  the old code builds, so revert only the fix and keep the new test.

## A test fails only on CI

1. Check which commit the red run was on: often a later commit already fixed it.
2. Read the result before guessing: `gh run download <id> -p 'e2e-xcresult-*'` (one per shard), then
   `xcrun xcresulttool get test-results tests|activities --path …` for the failing step and its values, and
   `xcresulttool export attachments` for the screen recording (`ffmpeg -ss <s> -frames:v 1` gets a frame).
   A recording gets a frame only when the screen changes (about 17 fps on CI, one every 0.3–0.6 s while a
   test takes screenshots in a loop), so a one-frame jump shows only by luck: use `FrameProbe` for that.
3. Think of CI's machine ([Layout](#layout)); Option sends Alt there.
4. Give it 20 minutes from the logs. Then simplify the test or the feature and write it down, or hand it on.
   No debug branches.
5. Never rerun to green: run again only after a code change. A flake fix is proven by two full runs in a
   row green on the first try.

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

When tests are added or get slower, rewrite `scripts/test-times.tsv` from two or three green full runs (dispatches): the
mean of the passed tests, from each shard's artifact:

```sh
xcrun xcresulttool get test-results tests --path <e2e.xcresult> | jq -r '.. | objects |
  select(.nodeType == "Test Case" and .result == "Passed") | "\(.durationInSeconds)\t\(.name | rtrimstr("()"))"'
```

Round the means to whole seconds: `scripts/shard.py` reads integers.

## Tried and dropped

- `-parallel-testing-enabled`: it runs copies of the app on one Mac, and UI tests cannot share one mouse
  and one bundle id.
- Merging tests to share a launch: setUp is about 2.5 s of each test, so it saves little and costs
  isolation.
- Caching Swift packages: libghostty's 190 MB xcframework restored in 2 s, but build and setup stayed
  65–105 s per job.

## More GUI slots (not set up)

Local UI runs take the GUI lock because XCUITest drives the real pointer. Nothing on the host isolates it:
the runner asks `testmanagerd` to post HID events into the login session, so the pointer moves on every
display, virtual ones (`CGVirtualDisplay`, BetterDisplay, DeskPad) too. A second macOS user has no display
and no known XCUITest support. Only another session isolates it: a VM or another Mac.

If one slot is not enough, run each extra slot in a headless Tart VM. Set it up once:

```sh
brew install openai/tools/tart
tart clone ghcr.io/cirruslabs/macos-golden-gate-base:latest oriel-vm   # 34 GB download, ~41 GB on disk
tart set oriel-vm --cpu 4 --memory 8192 --display 1024x768             # CI's 1x screen
tart run oriel-vm --no-graphics --no-audio --no-clipboard              # a background command
VM=$(tart ip oriel-vm)                                                 # user and password: admin
ssh-keygen -t ed25519 -N '' -f ~/.ssh/oriel_vm && ssh-copy-id -i ~/.ssh/oriel_vm admin@$VM
# ~/.ssh/config: Host 192.168.64.*  User admin  IdentityFile ~/.ssh/oriel_vm  StrictHostKeyChecking no
rsync -a /Applications/Xcode.app admin@$VM:/Applications/
ssh admin@$VM 'sudo xcode-select -s /Applications/Xcode.app && sudo xcodebuild -license accept &&
  sudo xcodebuild -runFirstLaunch && automationmodetool'   # must say "DOES NOT REQUIRE user authentication"
ssh admin@$VM 'mkdir -p .local/bin && echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.zshrc'
scp ~/.local/bin/herdr admin@$VM:.local/bin/herdr      # CI's herdr version
```

Then do one run (below): if a privacy (TCC) prompt shows, allow it over VNC (`open vnc://$VM`). Save the
guest to reset from: `tart stop oriel-vm && tart clone oriel-vm oriel-vm-clean`, and `tart run` it again.

One run: build on the host, test in the guest.

```sh
NAME=<agent>; DD=/tmp/oriel-dd-$NAME
xcodebuild -scheme Oriel -derivedDataPath $DD -destination platform=macOS build-for-testing
rsync -a --delete $DD/Build/Products/ admin@$VM:runs/$NAME/Products/
rsync -a --delete scripts/ admin@$VM:runs/$NAME/scripts/
ssh admin@$VM "cd runs/$NAME && scripts/e2e.sh xcodebuild test-without-building \
  -xctestrun Products/Oriel_*.xctestrun -destination platform=macOS -only-testing:… \
  -resultBundlePath e2e.xcresult"
rsync -a admin@$VM:runs/$NAME/e2e.xcresult /tmp/oriel-e2e-$NAME.xcresult
```

- **Rules.** One lock per VM (`/tmp/oriel-vm-1.lock`, `-2`), as the GUI lock. The guest runs its own herdr,
  so the user's sessions are out of reach, and `osascript` is safe there. Reset a dirty guest from
  `oriel-vm-clean`.
- **Limits.** Apple allows 2 macOS VMs per host. After a few start and stop cycles the limit error can stay
  until the host reboots (Tart #1217), so keep VMs running. Two 8 GB guests plus host builds make a laptop
  swap: run one. The guest's macOS must not be newer than the host's.
- **Risks.** `screencapture` over ssh asks again every 30 days. The guest's GPU reports an old Metal family:
  it renders, but timing is slower, as on CI. Some host and guest pairs draw no windows: check the first
  screenshot. The guest's password is `admin`, on the host's private network only.
- **More slots.** A Mac mini on the network (about $800–1,000) with the same setup adds two (`ssh -J`);
  rented Macs (Scaleway, EC2 Mac) cost more over time.
