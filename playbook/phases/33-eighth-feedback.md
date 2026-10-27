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

8. **One dedicated agent** cleans up `docs/`, `plan/`, `resources/`, `README.md` and `AGENTS.md` (capture
   H #1–#12): docs minimal and matching the app as built, no mock-ups; the phases kept but concise; one way
   of working (phases or not, reviews, review agents, lanes, cleanups) that `AGENTS.md` points at; the
   lessons in one file; `plan/archive/`, `plan/metrics/` and `ui-layout.md` gone; `ci.md` current only;
   resources with no dates, inspirations moved to `~/Downloads/oriel-inspirations/`, metrics, mock-ups
   and visual-compare deleted, research as a few flat folders of md files (one file per client); `plan/`
   renamed (the user picked `playbook/`), last, with every link fixed.

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

- **Cause.** Phase 32 kept a placeholder iOS target; the user dropped it until iOS is built.
- **Fix.** The app target, the Makefile and HerdrKit are macOS only; the iOS icon, every `#if os(macOS)` and
  the two iOS stubs are gone. No behavior change on macOS.

### Lane R

- **Cause.** Drops pasted This Mac's paths on remote cards too.
- **Fix.** `Exec.upload` copies each dropped file over the relay into a fresh folder under
  `${TMPDIR:-/tmp}/oriel-drops-<uid>` (0700, refused if it is a link or not the user's), pasting the copies'
  escaped paths in one paste; folders older than a day go. At most 16 MB a file, as herdr's own remote
  client (which does the same for images over its private protocol). Insert Path does the same.
- **Decisions.** No delete on disconnect (an agent may not have read the file yet).

### Lane A

- **Cause.** The system About panel showed `Credits.rtf` as one paragraph; the app shipped no license texts
  and credited neither Ghostty nor its libraries.
- **Fix.** Oriel's own small About window (icon, name, version, one Acknowledgements button) opens the bundled
  `Acknowledgements.txt` with every license in full, Ghostty's built-in libraries and fonts included. `make
  test` fails when an icon license is missing from it.
- **For the user.** libghostty links GNU libintl (LGPL-2.1) statically: decide whether relinking matters for
  how Oriel ships.

### Lane C

- **Cause, item 2.** The Agents view placed the header name 18 pt in and on the sort capsule's baseline; the
  workspaces view 22 pt in, centered on the `+`. Both now 22 pt in with the `+`'s height.
- **Cause, item 3.** The chrome's fade animated everything in its update, the pill's offset too (phase 31's
  change put the pill's move in that update). The fade now animates opacity alone, and the pill never animates
  its place; an `Animatable` probe makes the test catch a drawn slide, not only the model value.
- **Fix, item 4.** `Look.paneButton` and the grip at 3.3–4.1:1 in every look (from 2.1–3.0); Increase
  Contrast strengthens the app's own dim colors.

### Lane S

- **Not reproduced** in hand tests (one window and two stacked windows); AppKit routes touches to the frame
  view whatever the window shows. Likely causes: a fourth finger (the system's swipe), or swiping "next" on the
  last page (steps do not wrap). The user will note direction and fingers if it comes back.

### Lane D

- **Cause.** 33 phases of notes piled up: four rule files repeating each other, run logs, metrics, mock-ups
  stale since phase 22, design pages for parts never built (plugins, chat, pills, iOS), research written as
  dated agent reports, and code comments naming phases.
- **Fix.** `playbook/` (renamed from `plan/`): one `workflow.md` (the mechanics the user listed, the design
  bar), `lessons.md` (repeated problems only, lane L folded in), `ci.md` (current only), phases cut to items,
  causes and decisions. Docs: mock-ups, 19 unbuilt pages and all history gone; one short Future work page.
  Research: flat folders, one file per client, one plugins file. A comment pass replaced phase history in code
  comments with the why. docs 96 → 47 files, plan 60 → 39, resources 278 → 164.
- **Runs.** The comment-only commits end at 36b7c65; lane F proves the last code commit green.
- **For the user.** Read README.md and `playbook/workflow.md`; `~/Downloads/oriel-inspirations/` has the
  inspirations, with the git-ignored video folders.
