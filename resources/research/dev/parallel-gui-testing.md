# Parallel GUI testing without the user's screen

Research date: 2026-10-22. Scope: how agents can run XCUITest, launch Oriel, take screenshots and drive
the UI while the user works on the same Mac.

## Answer

Run the GUI work in a headless macOS virtual machine (VM) on this Mac. A VM has its own screen, cursor and
keyboard, so XCUITest in the VM never touches the user's session. Tart with a Cirrus Labs Golden Gate
(macOS 27) image is the best fit. GitHub's own macOS runners are VMs on the same Apple framework, and
Oriel's e2e suite already passes there with libghostty's Metal renderer. Apple allows at most two macOS VMs
at a time, so this Mac gets two parallel GUI slots at most. For more slots, use CI on demand or a second
Mac.

No host-only trick isolates XCUITest. XCUITest posts real mouse events, so it moves the user's pointer on
any display of the user's session. Background computer-use drivers (cua-driver, Codex, Claude) avoid the
pointer, but they do not run XCUITest, and Oriel's windows still open on the user's desktop.

## This Mac

| Fact | Value | What it means |
|---|---|---|
| Hardware | MacBookPro18,1, Apple M1 Pro, 10 cores (8 performance, 2 efficiency), 32 GB | One VM at 4 cores and 8 GB is comfortable. Two VMs (16 GB) leave 16 GB for the user and agent builds. |
| macOS | 27.0.1 (26A434), Golden Gate | The host can create and run macOS 27 guests. The guest must not be newer than the host. |
| Xcode | 27.1 (27A9275), 3.7 GB on disk | Small enough to copy into a guest. |
| Free disk | about 135 GB of 460 GB | One VM from a base image (about 41 GB) fits. The Cirrus Xcode image (97 GB) is too large to keep. |
| Hypervisor | `kern.hv_support: 1` | Virtualization.framework works. |
| CI | GitHub-hosted `xcode-27` (image `xcode-27-arm64`), public repo | Standard macOS minutes are free. arm64 runners are Virtualization.framework VMs. |

## Why XCUITest takes over the screen

XCUITest on macOS runs a separate runner app (`OrielUITests-Runner`). The runner asks `testmanagerd` to
synthesize events. Clicks go into the global HID event stream, which is the stream the physical mouse uses.
WindowServer moves the pointer to each click point as a side effect. Typed keys go to the frontmost app.
`XCUIApplication.launch()` and `activate()` bring Oriel to the front. A test can therefore move the user's
cursor, steal focus, and type into the user's apps when Oriel loses focus.

Pointer and focus belong to one login session. All displays in that session share them. So a virtual
display does not help. Only a separate session (another user, a VM, or another Mac) isolates XCUITest.

## Comparison

Legend: "Yes" means verified by docs or by a public report. "Likely" means the parts are verified but no
one reports the exact combination. "No" means it does not work or does not isolate.

| Option | Isolates the user's GUI fully? | Works with XCUITest? | Metal / libghostty? | Setup effort | RAM / disk | Cost | Agent-friendliness |
|---|---|---|---|---|---|---|---|
| Tart VM on this Mac (Cirrus images) | Yes | Yes. Base images enable Automation Mode and TCC grants. GitHub runs UI tests in the same kind of VM. | Yes. Paravirtualized GPU, Metal runs on the host GPU. Oriel e2e passes on GitHub's VMs. | Low: 1 to 2 hours, mostly the download | 8 GB per VM, about 45 GB disk (base image plus Xcode) | Free (Tart is free under 100 CPU cores) | High: CLI, `tart ip`, ssh, `tart exec`, VNC, many agent write-ups |
| Lume / cua stack on this Mac | Yes | Likely. You set up Automation Mode and TCC yourself. | Yes, same GPU path. A known Lume bug hid app windows in Tahoe guests on a Sequoia host. | Low to medium | 8 GB per VM, 50 GB per guest | Free (MIT). Cua Spaces app free for individuals. | High: CLI, HTTP API, MCP server, cua-driver in the guest |
| UTM | Yes | Likely | Yes | Medium. The UTM app must stay open, even for headless VMs. | Same as Tart | Free | Medium: `utmctl` wraps AppleScript |
| VirtualBuddy | Yes | Likely | Yes | Medium. GUI only. | Same | Free | Low: no headless CLI |
| Parallels Desktop | Yes | Likely | Yes | Medium | Same | Pro edition, about $120 per year | Medium: `prlctl` |
| Orka Desktop (MacStadium) | Yes | Likely | Yes | Medium. GUI app, OCI images. | Images are 100 GB unpacked | Free | Medium |
| Anka (Veertu) | Yes | Yes. Built for iOS and macOS CI. | Yes | Medium to high | Same | Commercial license | Medium to high: CLI, registry |
| Second macOS user on this Mac (fast user switching, or Screen Sharing "log in as yourself") | Likely for the pointer. Not verified for XCUITest. | Not verified. A switched-out session has no display. Apple documents nothing. | Unknown in a background session | Medium | 2 to 4 GB for the second session | Free | Low: fragile, no public success reports |
| Virtual display (CGVirtualDisplay, BetterDisplay, DeskPad) | No. Same session, same pointer and focus. | Yes, but it still moves the user's pointer. | Yes | Low | Small | Free | Low |
| AX-only driver instead of XCUITest (AXPress, set AX values, `postToPid` keys) | Partly. No pointer move, but windows open on the user's desktop and need private APIs for key focus. | No. It replaces XCUITest. All 13 test files need rewrites. Drags and hover need pixel events. | Yes | High | Small | Free | Medium |
| Background computer-use drivers on the host (cua-driver, Codex, Claude Code, Peekaboo, background-computer-use) | Partly. No pointer move, no focus steal for AppKit and SwiftUI apps. Oriel's windows still live on the user's desktop. | No | Yes | Low | Small | Free (cua-driver MIT), Claude needs Pro or Max | High for exploratory looks, not for e2e |
| GitHub-hosted runner (today) | Yes | Yes | Yes | None. Already in use. | None local | Free (public repo) | Medium: about 10 minutes per run, no live driving |
| Self-hosted GitHub runner in a Tart VM on this Mac | Yes | Yes | Yes | Medium | Same as a Tart VM | Free (the per-minute fee for self-hosted runners was paused) | Medium. Adds nothing over a Tart VM with ssh. |
| Cirrus Runners / Cirrus CI | Yes | Yes | Yes | Low | None local | Runners $150 per month. Cirrus CI shut down on 2026-06-01. | Medium |
| Xcode Cloud | Yes | Yes | Yes | Medium | None local | 25 hours per month included, then $49.99 for 100 hours | Low: slow, no live driving |
| AWS EC2 Mac | Yes | Yes | Yes | High | None local | M1 $0.65 per hour, M4 $1.23 per hour, 24-hour minimum (about $475 to $900 per month) | Medium |
| Scaleway Mac mini M4 | Yes | Yes | Yes | Medium | None local | €0.22 per hour (24-hour minimum) or €149 per month | Medium: ssh over the internet |
| Dedicated Mac mini on the local network | Yes | Yes | Yes | Medium | None on the laptop | About $800 to $900 to buy (2026 prices) | High: same Tart setup, two more VM slots |
| Docker-OSX | Not an option | It needs KVM on Intel or Linux. It does not run on Apple silicon. | | | | | |
| Apple `container` | Not an option | Linux guests only | | | | | |

## Option details

### macOS VMs on Apple silicon

All the VM tools above use Apple's Virtualization.framework. Parallels, Anka and Orka also use it for macOS
guests. So they share these facts:

- Apple's license allows two macOS guests at a time on one Mac. The framework enforces it with the error
  "The number of VMs exceeds the system limit".
- A guest must be the same macOS version as the host or older. On macOS 26 hosts, a macOS 27 IPSW does not
  install (Apple confirmed a `VZMacOSInstaller` bug). This Mac runs macOS 27, so that bug does not apply.
- Golden Gate (macOS 27) adds automatic first-user setup for macOS 27 guests on macOS 27 hosts. It also
  adds layered ASIF disk images, so several VMs can share one read-only base layer.
- The guest gets a paravirtualized GPU. The guest submits Metal work, and the host GPU runs it. The guest
  reports an older GPU family (Apple 5) and 32 KB threadgroup memory. That slows compute work such as
  llama.cpp. It does not stop normal rendering. Oriel's e2e suite renders libghostty in GitHub's arm64 VMs
  today. Tart and Lume ship an optional Metal capability shim. Oriel does not need it.
- Nested virtualization is not supported. You cannot run a macOS VM inside a macOS VM.
- Guest memory counts against host RAM while the VM runs. Disks are sparse files, and clones use APFS
  copy-on-write, so a second clone of the same image costs little disk at first.

#### Tart

Tart is a CLI for macOS and Linux VMs. Cirrus Labs built it for CI. OpenAI acquired Cirrus Labs in April
2026 and develops Tart now (`github.com/openai/tart`). It is free for up to 100 CPU cores. Install it from
`openai/tools/tart`. The old `cirruslabs/cli` tap is stale.

- Images: `ghcr.io/cirruslabs/macos-golden-gate-{vanilla,base,xcode:N}`. The base image has Homebrew, ssh,
  auto-login, no sleep and no screen lock. The user is `admin`, the password is `admin`.
- The base image enables Automation Mode without authentication (`automationmodetool`). It also writes TCC
  grants (Accessibility, Screen Recording, Post Event, Apple Events) for `sshd-keygen-wrapper`,
  `osascript`, Python and the Tart guest agent. So screenshots, clicks and UI tests work over ssh.
- Sizes measured today from the registry: `macos-golden-gate-base:latest` is a 34 GB download and 41 GB on
  disk. `macos-golden-gate-xcode:27.1` (published 2026-10-21) is an 82 GB download and 97 GB on disk. With
  135 GB free, use the base image and copy the host's 3.7 GB Xcode into it.
- Headless: `tart run --no-graphics`. No window, no Dock icon. `tart ip <vm>` gives the guest IP on
  `192.168.64.x`. `tart exec <vm> <cmd>` runs a command in the guest's GUI session through the guest agent.
  `tart run --vnc` or the guest's own Screen Sharing gives a view when a human wants one.
- Files: ssh, `scp` and `rsync`. `tart run --dir=name:/host/path[:ro]` shares a host folder with virtiofs.
  It appears in the guest under `/Volumes/My Shared Files/name`.
- Display: `tart set <vm> --display 1024x768` matches CI's 1x screen.
- Reports: Flavio Copes (2026-10) runs Tart so agents test his Mac apps "without taking over your screen",
  with a script `testvm` (open, shot, ui, click, type, key). Eugene Petrenko (2026-07) drives Tart VMs over
  ssh with agent skills. Crabbox has a Tart provider that leases throwaway VMs to agents.

#### Lume and the cua stack

Lume is cua's VM CLI on the same framework. It builds a vanilla VM from an Apple restore image with
unattended setup, ssh and auto-login (`lume create ... --unattended`). It has `lume ssh`, shared folders,
clones, a local HTTP API and an MCP server. Its docs state 50 GB disk per guest and the two-guest limit.

The rest of the cua stack:

- Cua Spaces (launched 2026-10-02) is a host app that gives each agent a desktop. Each desktop is a macOS
  VM built locally, or a Linux image. It needs macOS 26 or later. It is free for individuals.
- `cua-spacesd` (port 3211) runs inside Space images and gives agents processes, files, screenshots and
  input. It replaces the older `computer-server`.
- cua-driver is the background computer-use driver (see below). It also runs inside a VM.

Risk: cua issue #912 (open) reports that app windows do not render in Tahoe guests under Lume on a Sequoia
host, in screenshots and in VNC. A later comment shows SwiftUI apps crashing in the display cycle in a
Tahoe 26.2 guest. GitHub's runners and Flavio's Tart setup render Tahoe and Golden Gate guests without this
problem, so it looks specific to that Lume setup. Make sure that the first Oriel screenshot in any new VM
shows the window.

#### UTM, VirtualBuddy, Parallels, Orka Desktop, Anka

These run the same guests with the same limits. UTM headless VMs still need the UTM app open, and `utmctl`
wraps AppleScript. VirtualBuddy is GUI first. Version 2.2 installs macOS 27 guests on macOS 26 hosts.
Parallels has `prlctl` and a paid Pro edition. Orka Desktop pulls OCI images that keep a recovery partition,
which helps in-guest upgrades. Anka is a commercial CI product with a registry and CLI. None of them beats
Tart for agents on one Mac.

### Running XCUITest headless in a guest

- `xcodebuild test` over ssh works when a user is logged in to the guest's GUI. Auto-login gives that.
- Automation Mode must not ask for a password. Run `automationmodetool` to see the setting. The output must say "DOES
  NOT REQUIRE user authentication".
- Build on the host and test in the guest:
  `xcodebuild build-for-testing` writes `Build/Products/` and an `.xctestrun` file with relative paths.
  Copy `Build/Products/` into the guest. Then run
  `xcodebuild test-without-building -xctestrun <file> -destination platform=macOS`. The guest still needs
  Xcode, because `xcodebuild` and `testmanagerd` come from it.
- Debug builds that are signed to run locally run in the guest without changes. `rsync` does not add the
  quarantine flag.
- Screenshots in the guest: `ssh <vm> screencapture -x -l <windowid> /tmp/x.png`, then `scp`. On macOS 15
  and later, the first capture over ssh shows a "bypass the system private window picker" prompt. It comes
  back every 30 days. Flavio's post has a `plutil` fix that moves the reminder date.
- Agents can drive the guest by hand in three ways. They can run single XCUITest tests (the current
  approach). They can use `ssh <vm> osascript` and `cliclick` against the guest's screen (Flavio's
  `testvm`). Or they can run cua-driver inside the guest. In a VM, `osascript` and System Events are safe:
  no user apps exist there to receive stray keys.

### No-VM options on the host

#### A second user session

macOS keeps the GUI apps of a switched-out user running, but that session has no display. XCUITest needs a
logged-in, unlocked session with a screen. Apple documents nothing about UI tests in a background session.
No 2025 or 2026 report shows XCUITest working there. Screen Sharing can show a second user's session
("log in as yourself"), but Apple's Screen Sharing app does not connect to the same Mac. High Performance
screen sharing virtual displays need a second Apple silicon Mac. Do not rely on this option.

#### Virtual displays

`CGVirtualDisplay` is a private API. BetterDisplay, DeskPad and Chromium's test helpers use it. A virtual
display belongs to the user's session. The pointer can move onto it, and XCUITest clicks move the user's
pointer there. It helps only to keep Oriel's window off the visible screen. Headless Mac mini setups use
virtual displays so that the Mac has a screen at all.

#### An AX-only driver instead of XCUITest

The Accessibility API can press a control without a mouse event: `AXUIElementPerformAction(element,
kAXPressAction)`. It can also set values (`kAXValueAttribute`) and raise windows. Keys can go to one process
with `CGEvent.postToPid`, so they never reach another app. This is how cua-driver addresses elements.

Limits for Oriel:

- Key events reach only the key window. For a background app, that needs private SkyLight calls
  (`SLPSPostEventRecordTo`) that make Oriel active without raising it.
- Drags, hover, scroll and the terminal grid need pixel events. `SLEventPostToPid` delivers them without a
  pointer move, but it is private and undocumented.
- Oriel's windows still open on the user's desktop. The launch must not activate Oriel (`open -g`).
- The suite (13 test files, about 240 clicks and key presses) would need a new driver and rewrites. CI
  would test something different from what users do.

The cost is high and the isolation is partial. Do not do this.

#### Background computer-use drivers

- cua-driver (MIT, 2026-04): posts events to one pid with SkyLight `SLEventPostToPid`, activates without
  raising (the yabai pattern), and keeps AX trees live for occluded windows. The pointer does not move,
  focus does not change, and Spaces do not switch. Element-indexed clicks call AX actions directly. Pixel
  clicks are the fallback. Canvas apps that accept only HID-tap events still get activated, and the pointer
  moves for them. A libghostty `NSView` takes normal AppKit events, so Oriel is likely not in that group.
  This is not verified.
- Codex computer use (2026-04) and Claude Code and Cowork background computer use (2026-09-02, macOS 15 and
  later, Pro and Max plans) work the same way: hidden background windows, no pointer takeover. Anthropic
  states that there is no sandbox.
- Peekaboo (CLI and MCP): screenshots of single windows, and background clicks routed to a pid without
  moving the pointer, for several click types.
- `actuallyepic/background-computer-use` and `mediar-ai/mcp-server-macos-use` are smaller open-source
  takes on the same idea.

These tools let an agent look at a running Oriel and poke it while the user works. They do not run the
XCUITest suite. Oriel's windows still appear on the user's desktop and in Cmd-Tab. They are good for an
exploratory look. They are not a test platform.

#### Apple's own options

`xcodebuild` has no "background" or "virtual session" flag for macOS UI tests. `-parallel-testing-enabled`
runs test clones on the same screen, so it makes the conflict worse. `automationmodetool` only removes the
password prompt.

### Remote and cloud

- GitHub-hosted runners: already the gate. They are free for this public repo. A run takes about 10
  minutes, and the e2e job takes 8 to 12 minutes of its 20. A free account gets up to 5 concurrent macOS
  jobs. CI cannot be driven live, and its feedback is slow for an agent's edit loop.
- A self-hosted runner in a Tart VM on this Mac: possible. GitHub paused its planned $0.002 per minute fee.
  It adds a queue and nothing else over ssh to the same VM.
- Cirrus Runners: $150 per month per M4 Pro runner, unlimited minutes. Cirrus CI itself shut down on
  2026-06-01.
- Xcode Cloud: 25 compute hours per month come with the developer program. More hours cost $49.99 per 100.
  It has no live driving and a slow turnaround.
- AWS EC2 Mac: dedicated hosts with a 24-hour minimum. M1 is $0.65 per hour, M4 is $1.23 per hour.
- Scaleway: Mac mini M4 at €0.22 per hour (24-hour minimum) or €149 per month. MacStadium and smaller hosts
  rent dedicated minis from about $85 to $160 per month.
- Latency for an agent loop: ssh round trips are fine over the internet. Each test run copies about a few
  hundred MB of build products, or the remote Mac builds from git.

## What agents and teams use (2025 to 2026)

- Solo developers who build Mac apps with agents: a local Tart VM driven over ssh (Flavio Copes' `testvm`,
  Eugene Petrenko's skills, Crabbox leases), or a spare Mac mini with auto-login and ssh.
- Agent platforms: cua (Lume VMs, Cua Spaces, cua-driver), Cursor's self-hosted worker with computer use on
  a Mac, Codex and Claude background computer use on the host.
- CI for macOS UI tests: GitHub-hosted arm64 runners (Virtualization.framework VMs), Tart-based runners
  (Cirrus images, Orchard), Anka and Orka fleets, EC2 Mac, and closet Mac minis prepared with
  `automationmodetool` and an MDM profile for TCC.
- XCUITest-specific reports agree that macOS UI tests run on the Mac you use. People move them to a
  dedicated machine or a VM and take a machine-wide lock.

## Risks and gotchas

- The two-VM limit is per host and is enforced by the framework. Tart issue #1217 (macOS 26.3.1 host)
  reports the limit error after a few start and stop cycles, fixed only by a host reboot. Keep VMs running
  and reset state inside them, instead of stopping them after each run.
- Disk: 135 GB free. The base image needs about 41 GB, the guest's Xcode 4 GB, and run products a few GB.
  A second VM is an APFS clone and grows with writes. Do not pull the 97 GB Xcode image.
- RAM: two 8 GB VMs plus Xcode builds on the host can make the laptop swap. Run one VM by default.
- Guest version: keep the guest at the host's version or older. Run `sw_vers` in the guest after the
  first boot.
- The first UI test run in a new guest can still show a TCC prompt for the test runner. Open the guest's
  screen once over VNC (`open vnc://$(tart ip oriel-vm)`) and allow it, then save a clean clone.
- The guest's GPU reports an old Metal family. Oriel renders fine on CI. Timing-sensitive checks can be
  slower in a VM. This already holds on CI.
- Metal shim and `ForceUnrestrictedDeviceFeatureLevel`: not needed. Do not turn them on.
- The 30-day screen-capture prompt for ssh in the guest returns unless you move its date (see Flavio's
  post).
- Pre-release software risk: cua issue #912 shows that some host and guest pairs do not composite windows.
  Make sure that the first screenshot shows Oriel's window.
- Clipboard and audio: start the VM with `--no-clipboard --no-audio`, so the guest cannot touch the user's
  clipboard.
- Security: the guest password is `admin`, and the guest is reachable only on the host's private
  `192.168.64.x` network. Use a dedicated ssh key.
- Background computer-use drivers use private SkyLight calls. A macOS update can break them.

## Top 3 recommendations

### 1. A headless Tart VM on this Mac for all agent GUI work

Agents keep building on the host. GUI runs (single XCUITest tests, the full `make e2e`, screenshots,
manual driving) go to a VM. One VM gives one GUI slot that never touches the user. A second VM gives a
second slot when RAM allows.

Setup (the user approves the install and the 34 GB download):

```bash
brew install openai/tools/tart
tart clone ghcr.io/cirruslabs/macos-golden-gate-base:latest oriel-vm   # 34 GB download, ~41 GB on disk
tart set oriel-vm --cpu 4 --memory 8192 --display 1024x768             # CI's 1x screen
tart run oriel-vm --no-graphics --no-audio --no-clipboard              # run in background (bash background: true) or from a launchd agent
VM=$(tart ip oriel-vm)
ssh-keygen -t ed25519 -N '' -f ~/.ssh/oriel_vm
ssh-copy-id -i ~/.ssh/oriel_vm admin@$VM                               # password: admin
ssh -i ~/.ssh/oriel_vm admin@$VM sw_vers                               # must be 27.0.1 or older
rsync -a -e "ssh -i ~/.ssh/oriel_vm" /Applications/Xcode.app admin@$VM:/Applications/
ssh -i ~/.ssh/oriel_vm admin@$VM 'sudo xcode-select -s /Applications/Xcode.app &&
  sudo xcodebuild -license accept && sudo xcodebuild -runFirstLaunch && automationmodetool'
ssh -i ~/.ssh/oriel_vm admin@$VM 'mkdir -p .local/bin && echo "export PATH=\$HOME/.local/bin:\$PATH" >> ~/.zshrc'
scp -i ~/.ssh/oriel_vm ~/.local/bin/herdr admin@$VM:.local/bin/herdr  # same pinned herdr as CI (0.9.5)
tart stop oriel-vm && tart clone oriel-vm oriel-vm-clean               # cheap APFS copy to reset from
tart run oriel-vm --no-graphics --no-audio --no-clipboard
```

If sudo asks for a password in the guest, it is `admin`. Add a `Host 192.168.64.*` block to
`~/.ssh/config` with `User admin`, the key, and `StrictHostKeyChecking no`, because the IP can change.

One test run, by agent `$NAME` (later wrapped in a `make vm-e2e ONLY=…` target and a `scripts/vm.sh`):

```bash
DD=/tmp/oriel-dd-$NAME
xcodebuild -project Oriel.xcodeproj -scheme Oriel -derivedDataPath $DD -destination 'platform=macOS' build-for-testing
VM=$(tart ip oriel-vm)
rsync -a --delete $DD/Build/Products/ admin@$VM:runs/$NAME/Products/
rsync -a --delete scripts/ admin@$VM:runs/$NAME/scripts/
ssh admin@$VM "cd runs/$NAME && scripts/e2e.sh xcodebuild test-without-building \
  -xctestrun Products/Oriel_*.xctestrun -destination platform=macOS \
  -only-testing:OrielUITests/PaneTests -resultBundlePath e2e.xcresult"
rsync -a admin@$VM:runs/$NAME/e2e.xcresult /tmp/oriel-e2e-$NAME.xcresult
```

`scripts/e2e.sh`, `herdr-session.sh` and `e2e-helper.py` run unchanged in the guest. They start the guest's
own herdr servers. Manual looks: `ssh admin@$VM 'open runs/$NAME/Products/Debug/Oriel.app --args -session
oriel-dev-$NAME'`, then `ssh admin@$VM screencapture -x -l <windowid> /tmp/s.png` and `scp` it to
`/tmp/oriel-shots/`.

Changes to the plan and rules:

- `plan/rules.md`, Building and running: GUI runs go to the VM. A run on the user's screen needs the
  orchestrator's approval and the old GUI lock. The VM gets its own slot lock with the same `mkdir` pattern:
  `/tmp/oriel-vm-1.lock` (and `-2` for a second VM). Hold it for one run. Agents wait for a slot instead of
  for the user.
- `plan/execution.md`, GUI budget: drop the minute limits that protect the user. Keep a fair-share rule per
  slot. Phase agents can run single tests freely. The E2E reviewer can drive the new UI in the VM in every
  round. When the user holds `/tmp/oriel-gui.lock`, VM work goes on.
- `osascript` and System Events: still forbidden on the host. Allowed inside the VM (`ssh admin@$VM
  osascript …`), because the VM has no user apps.
- herdr safety: the guest runs its own herdr, so the user's `default` session is out of reach. Keep the
  `oriel-e2e-*` and `oriel-dev-*` names and the cleanup. Reset a dirty VM from `oriel-vm-clean`.
- The note that an e2e run changes the user's Oriel defaults (Glass Dark) no longer applies.
- `plan/ci.md`: a local VM at 1024 × 768 and 1x reproduces CI's screen. CI-only failures can now be
  reproduced locally first.

### 2. GitHub CI on demand for single tests

CI already isolates the user's screen and is free for this public repo. Add a `workflow_dispatch` input to
`.github/workflows/ci.yml` so that agents can run chosen tests on a pushed commit without any lock:

```yaml
on:
  workflow_dispatch:
    inputs:
      only_testing: {description: "xcodebuild -only-testing value, e.g. OrielUITests/PaneTests", required: false}
```

Pass it to `make e2e` as `ONLY=…`, and add `$(if $(ONLY),-only-testing:$(ONLY))` to the `e2e` target. An
agent then runs `gh workflow run ci.yml --ref main -f only_testing=OrielUITests/PaneTests` and `gh run watch`.
Up to 5 macOS jobs run at once. Each run takes about 10 minutes, so this is a second lane, not the edit
loop. Rule change: when the VM slots are busy, agents use this lane instead of waiting. The 20-minute rule
for CI-only failures stays.

### 3. A dedicated Mac mini (or a rented one) running the same Tart setup

When one or two VM slots on the laptop are not enough, or the laptop runs short of RAM or disk, add a Mac
mini (M4 or M5, 24 GB or more, about $800 to $1,000) on the local network. Give it auto-login and Remote
Login, and run two Tart VMs on it. It adds two GUI slots and takes all VM load off the laptop. A rented
Scaleway M4 (€149 per month, 24-hour minimum) works the same over the internet. EC2 Mac costs several times
more.

```bash
# On the mini (once):
sudo systemsetup -setremotelogin on
sudo pmset -a sleep 0 displaysleep 0
brew install openai/tools/tart
# then the same clone, set and run steps as in recommendation 1, for oriel-vm and oriel-vm-2
```

Agents reach the guests through the mini with `ssh -J user@mini.local admin@<guest-ip>`. The slot locks
move to the mini: `ssh mini 'mkdir /tmp/oriel-vm-1.lock'`. All other rules match recommendation 1.

## Sources

- Flavio Copes, "How to let coding agents test Mac apps in a VM", 2026-10-04: https://flaviocopes.com/mac-test-vm/
- Tart repository and quick start: https://github.com/openai/tart, https://tart.run/quick-start/
- Cirrus Labs image templates, releases (Xcode 27.1 images, 2026-10-21), base template and TCC script:
  https://github.com/cirruslabs/macos-image-templates
- Tart licensing (100 CPU core free tier): https://tart.run/licensing/
- Tart issue #1217, VM limit after restarts: https://github.com/openai/tart/issues/1217
- Crabbox Tart provider: https://crabbox.sh/providers/tart.html
- Eugene Petrenko, "A Real macOS Desktop for a Linux Agent", 2026-07-16:
  https://jonnyzzz.com/blog/2026/07/16/a-real-macos-desktop-for-a-linux-agent/
- Lume docs: https://cua.ai/docs/lume. Cua README (Spaces, cua-driver, cua-spacesd): https://github.com/trycua/cua
- cua, "Inside macOS window internals" (cua-driver), 2026-04-23:
  https://github.com/trycua/cua/blob/main/blog/inside-macos-window-internals.md
- cua, Metal capability shim and the paravirtualized GPU, 2026-08-11:
  https://github.com/trycua/cua/blob/main/blog/gpu-passthrough-macos-vms.md
- cua issue #912, Tahoe guest windows not rendering: https://github.com/trycua/cua/issues/912
- Show HN, cua-driver: https://news.ycombinator.com/item?id=47936312
- motionbug, "Virtualising macOS 27", 2026-06-11: https://motionbug.com/virtualising-macos-27/
- Eclectic Light, "macOS virtualisation is leaping forward in Golden Gate", 2026-06-12:
  https://eclecticlight.co/2026/06/12/macos-virtualisation-is-leaping-forward-in-golden-gate/
- Apple two-VM limit: https://eclecticlight.co/2022/08/04/virtualisation-on-apple-silicon-macs-8-how-apple-limits-vms/,
  https://kb.parallels.com/en/128867
- GitHub-hosted runner limits (arm64 runs on Virtualization.framework):
  https://docs.github.com/en/actions/reference/runners/github-hosted-runners
- GitHub Actions pricing and the paused self-hosted fee:
  https://github.blog/changelog/2026-01-01-reduced-pricing-for-github-hosted-runners-usage/,
  https://www.theregister.com/software/2025/12/17/github-walks-back-plan-to-charge-for-self-hosted-runners/2064954
- Corey Daley, "XCUITest on macOS: side effects nobody warns you about", 2026-06-25:
  https://coreydaley.dev/posts/2026/06/xcuitest-macos-side-effects/
- Corey Daley, "Two gates guard unattended macOS UI tests", 2026-06-09:
  https://coreydaley.dev/posts/2026/06/unattended-xcuitest-self-hosted-mdm/
- automationmodetool notes (macOS 27.0.1, Xcode 27.0), 2026-07-01:
  https://jaemyeong.com/en/blog/xcode-ui-automation-automationmodetool/
- Peekaboo MCP: https://peekaboo.sh/MCP.html
- background-computer-use: https://github.com/actuallyepic/background-computer-use
- macos-use MCP: https://github.com/mediar-ai/mcp-server-macos-use
- Claude background computer use, 2026-09: https://aitoolsreview.co.uk/insights/claude-background-computer-use
- Cirrus Runners pricing: https://cirrus-runners.app/pricing/. Cirrus CI shutdown: https://www.warpbuild.com/blog/cirrus-ci-shutting-down
- Xcode Cloud pricing: https://developer.apple.com/xcode-cloud/
- AWS EC2 Mac: https://aws.amazon.com/ec2/instance-types/mac/, https://macyou.co/blog/aws-ec2-mac-pricing-explained
- Scaleway Apple silicon pricing: https://www.scaleway.com/en/pricing/apple-silicon/
- Mac mini 2026 prices: https://www.macworld.com/article/2964754/2026-mac-mini-m5-pro-design-specs-release-date.html
- Local checks on this Mac: `sysctl`, `sw_vers`, `xcodebuild -version`, `man xcodebuild`, `df`, `du`, the
  ghcr.io registry manifests for image sizes, and `gh run view` for the CI image name.
