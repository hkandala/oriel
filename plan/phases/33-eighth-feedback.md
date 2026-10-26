# Phase 33: The user's eighth round of feedback

The user tested on 2026-10-26 (about 15:00), after phase 32. Captures (read them with the scrawl skill,
`/Users/hkandala/.agents/skills/scrawl/SKILL.md`; open `contact-sheet.png` and `frames/` first):

- G (app): `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1793052592368-62b.scrawl`
- H (docs and plan): `/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1793053526839-62b-3.scrawl`

Each lane writes its Findings under its own heading at the end. The GUI lock is free for agents (one run
per hold, at most 10 minutes, released with a trap).

## Lane I: remove the iOS placeholder (item 1), first

1. **Remove every iOS placeholder** (user's decision on phase 32's big item): the iOS destination and
   settings in the Xcode project, the iOS build in the Makefile (`Makefile:28`) and CI, the iOS app icon
   files (`icon_ios_1024.png`, its line in `scripts/app-icon.py`), the iOS stubs (OrielApp's
   ContentUnavailableView, the WorkingDots stub, others), and every `#if os(macOS)` / `#if canImport(AppKit)`
   guard in `Oriel/`, `Packages/HerdrKit` and the tests that only exists for iOS. One or two commits, pushed
   early: every other lane rebases over it. Docs lines about building for iOS go to lane D.

## Lane C: chrome regressions and contrast (items 2–4)

2. **The sidebar header moves** (G #1 0:14–#2 0:23): switching the sidebar between the Agents view and the
   workspaces view moves the header (the machine name row) up or down. Its position must be the same in both
   views. It was right before phase 32, so find the commit that moved it (`git log -L`, bisect) and fix the
   cause.
3. **The tab bar's pill slides after the overview again** (G #3 0:43–#5 1:05): coming back from the
   overview, the pill moves from the previous selection to the new tab. Phase 31 lane M item 12 made the tab
   bar come back with no pill and fade the pill in on the selected tab, together with the chrome. Find what
   broke it (phase 32 keyed `TabBar` by `page.id`, `r-chrome`, is one suspect) and fix it so it cannot come
   back; the test that guards item 12 missed this, so make it catch it.
4. **Contrast** (user's decision): the pane header buttons (`Look.paneButton`, about 2.3–2.6:1) and the
   grip reach at least 3:1 against their backgrounds in both looks and both schemes, and Increase Contrast
   (`colorSchemeContrast`) makes the app's own dim colors stronger. Measure the ratios before and after.

## Lane S: three-finger swipes on an empty session (item 5)

5. **Three-finger swipes do nothing on an empty session** (G #6 1:26): on a session with no workspaces
   ("This session is empty"), a horizontal three-finger swipe must move to the previous or next session,
   as it does everywhere else. Check every view a window can show (empty session, Reconnecting, loading).

## Lane A: the About panel (item 6)

6. **The About panel shows a huge dump of text.** Keep every credit, but lay it out well: short credit lines
   (name, license, link) in the panel, with the full license texts somewhere a click away (for example a
   bundled Acknowledgements file the panel links to), or whatever reads best. Show screenshots in Findings.

## Lane R: file drops on remote machines (item 7)

7. **Dropping a file or image on a remote machine's pane** pastes a path that exists on that machine. herdr
   does this already for its own remote client: when a file or image is dropped, it copies it into a temp
   file on the remote side and pastes that temp path. Find how herdr does it (its source, docs and
   `herdr --help`; the protocol is private, so look for the behavior, file names, temp folder, cleanup)
   and do the same or reuse it: copy the dropped files over the existing SSH connection (the relay or the
   ControlMaster), paste the remote paths, quoted the way local drops are. Insert Path… and Go to
   Directory… on a remote machine stay as they are unless the same copy fits in a few lines. e2e against
   CI's sshd (RemoteTests).

## Lane D: docs, plan and resources cleanup (capture H)

8. **One dedicated agent** cleans up `docs/`, `plan/`, `resources/`, `README.md` and `AGENTS.md`
   (capture H #1–#12):
   - **docs/:** minimal and matching the app as built. Remove every UI mock-up (the overview page,
     `docs/public/mockups`, `docs/components/design`) and old or deprecated content.
   - **plan/:** keep the phases (they track the whole build); make them concise and well structured.
     Remove `plan/archive/` (fold anything still useful into the phases or the files below) and
     `plan/metrics/`. Merge `workflow.md`, `execution.md`, `rules.md`, `standards.md` and the other small
     files into one standard way of working: when a task needs phases (a complex project) and when not (a
     small bug), the plan, review cycles, review agents, lanes, cleanups and the final pass. Move the
     lessons from all phases into one lessons file. `ci.md`: current setup only. `ui-layout.md`: short, or
     folded into the design pages. `AGENTS.md` points every new agent at the way-of-working file and the
     phases, so the user never has to repeat it.
   - **resources/:** current information only (no dates, no history). Keep `branding/`, `icons/` and
     `sources/` (review them). Move `inspirations/` out of the repo to `~/Downloads/oriel-inspirations/`.
     Delete `metrics/`, `mockups/` (and the scripts that build them) and `visual-compare/`.
     `research/`: a few flat folders of md files only, no scripts, no spikes, no nested folders, no
     repeated content. One `clients/` folder (web client notes merged in, one file per client), keep
     `multiplexers/` (deduplicated), and move the `dev/` (GUI testing) and `herdr/` notes to where they
     belong instead of their own folders.
   - **The folder name `plan/`** does not fit; the user picks a new name (orchestrator's suggestions).
     Rename it last, in one commit, and fix every link.

## Lane L: lessons from the sessions (feeds lane D)

9. **Mine every session of this project for lessons** (user, 15:40): the orchestrator's sessions
   (`~/.pi/agent/sessions/--Users-hkandala-code-oriel--/`) and the sub-agent sessions
   (`~/.pi/agent/pi-herd/sessions/*.jsonl` whose cwd is `/Users/hkandala/code/oriel*`), read only. Look for
   what went wrong and how it was fixed, what the user had to repeat or correct, rules that were added,
   checks that caught (or missed) bugs, slow or wasted steps, coordination failures between agents, and
   tool or harness tricks. Write a deduplicated list to `/tmp/oriel-lessons/lessons.md` (each lesson: what
   to do, why, the evidence in one line), split into "way of working" (goes into the workflow file) and
   "lessons" (goes into the lessons file). Lane D folds it in.

## Lane F: final integration (after the others)

10. Two full CI runs in a row green on the last code commit with no reruns, the on-demand suite once, and
   `scripts/test-times.tsv` refreshed.

## Findings

### Lane I

- **What:** the iOS placeholder is gone (item 1). The app target is macOS only: no iOS destination or
  `sdk=iphone*` settings, `SDKROOT = macosx`, no `TARGETED_DEVICE_FAMILY`, no `platformFilters` on
  GhosttyTerminal. `make build` builds only macOS. The iOS icon (`icon_ios_1024.png`, its three
  Contents.json entries, its lines in `scripts/app-icon.py`) is deleted. HerdrKit's `Package.swift` lists only
  macOS 26. Every `#if os(macOS)` in `Oriel/` and `Packages/HerdrKit` is removed, with the two `#else` stubs
  (OrielApp's "Oriel for iOS is coming" `ContentUnavailableView` and the empty `WorkingDots`). The imports that
  were inside guards moved to the file tops (`Commands.swift`, `Detail.swift`). The tests had no guards.
- **Cause:** phase 32 kept a placeholder iOS target. The user decided to drop it until iOS is built.
- **Commits:** 40109e6 (project, Makefile, icon, package), 520cd9a (guards and stubs; `git show -w` shows the
  guard lines only), 99d5402 (redundant `SUPPORTED_PLATFORMS`, a reviewer nit).
- **Tests:** `make lint build test` green. No behavior change on macOS, so no new tests. CI full run 40414394168
  on 520cd9a.
- **Docs:** the lines that say the app builds for iOS (README, AGENTS.md, plan/README, ci.md, standards.md,
  features, machines, platform, decisions D34, index, iphone-and-ipad, resources/branding/README.md) went to
  lane D (l33-docs) as a list.
- **Review:** l33-ios-review: no blockers or shoulds. Two nits: `SUPPORTED_PLATFORMS` (fixed) and the branding
  README line (sent to lane D).
