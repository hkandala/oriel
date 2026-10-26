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

8. **One dedicated agent** cleans up `docs/`, `playbook/`, `resources/`, `README.md` and `AGENTS.md`
   (capture H #1–#12):
   - **docs/:** minimal and matching the app as built. Remove every UI mock-up (the overview page,
     `docs/public/mockups`, `docs/components/design`) and old or deprecated content.
   - **playbook/:** keep the phases (they track the whole build); make them concise and well structured.
     Remove `playbook/archive/` (fold anything still useful into the phases or the files below) and
     `playbook/metrics/`. Merge `workflow.md`, `execution.md`, `rules.md`, `standards.md` and the other small
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
   - **The folder name `playbook/`** does not fit; the user picks a new name (orchestrator's suggestions).
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
- **Tests:** `make lint build test` green. No behavior change on macOS, so no new tests. CI run 40414849033 on
  9b0886e (a targeted run that builds and tests the whole tree) passed. The full push runs 40414394168 and
  40414747064 were cancelled by later pushes; lane F's full runs cover this lane.
- **Docs:** the lines that say the app builds for iOS (README, AGENTS.md, playbook/README, ci.md, standards.md,
  features, machines, platform, decisions D34, index, iphone-and-ipad, resources/branding/README.md) went to
  lane D (l33-docs) as a list.
- **Review:** l33-ios-review: no blockers or shoulds. Two nits: `SUPPORTED_PLATFORMS` (fixed) and the branding
  README line (sent to lane D).

### Lane R

- **What:** a file or image dropped on a remote machine's card now pastes a path on that machine (item 7). Each
  file is copied there first, over the machine's one SSH connection (the relay), and the copies' paths are pasted,
  shell-escaped as local drops are, in one paste once all are copied. Insert Path on a remote machine does the same
  with the file it picks (a few lines in `choosePath`); its panel shows only files there, not This Mac's folders, and
  no longer opens at the remote cwd. Go to Directory on a remote machine stays as it was (it would need a remote
  picker).
- **Cause:** drops pasted This Mac's paths everywhere (`FileDrop.swift` had a `ponytail:` note for it).
- **How herdr does it** (source `ogulcancelik/herdr`, `src/server/clipboard_image.rs`,
  `src/client/clipboard_images.rs`): its remote client sends a dropped image's bytes over its private protocol;
  the server writes them to `$TMPDIR/herdr-clipboard-images-<uid>/client-<id>-clipboard-<ns>-<n>.<ext>` (folder
  0700, file 0600), pastes the bare path, removes the files when the client leaves and any older than 24 h on each
  new one. Images only (png, jpg, gif, webp, bmp), at most 16 MB. The protocol is private, so Oriel does the same
  itself.
- **Fix:** `Exec.upload` (HerdrKit, `Exec.swift`): one run per file of a small `sh` script that makes
  `${TMPDIR:-/tmp}/oriel-drops-<uid>` (0700, refused if it is a link or not the user's own), deletes the folders in
  it older than a day, makes a new `mktemp -d` folder so the file keeps its name, and decodes the base64 lines it
  is sent (`base64 -d`, which the relay envelope needs anyway). Whole 3-byte groups per line, so no padding mid
  stream. Any file type; a folder or a file over 16 MB (herdr's limit; the whole file is queued on the relay ahead
  of the panes' streams) shows a notice and pastes nothing. `FileDrop.drop` picks the remote path through the
  card's page store (`PaneSurfaceView.store`, set by the registry). Skipped: herdr's delete-on-disconnect (a path an
  agent has not read yet would break); the day-old cleanup covers it.
- **Commits:** 2adc428 (feature, tests, docs), 0916f13 (review fixes: 16 MB cap, link check, trimmed error text,
  docs).
- **Tests:** unit `upload copies a file whole` (SSHExecTests: 100 001 binary bytes, a `'` and a newline in the name,
  through a real relay process; a folder is refused). e2e `testAFileDroppedOnARemoteCardPastesItsCopysPath`
  (RemoteTests, CI's sshd): types `cat `, drops a file on Key Host's card, checks the pasted path is under
  `oriel-drops-` and not the dropped file's own, then Return and `cat` prints its content. The helper's file-drag
  file now holds one line. Targeted CI runs 40415387083 (2adc428) and 40415922180 (0916f13): both drop tests pass.
- **Docs:** drag-and-drop (Files and images), machines (dropped files; not built yet list), window (Insert Path),
  terminal-and-agent (image paste reuses the copy; marked not built).
- **Review:** l33-drop-review: no blockers. Applied: 16 MB cap (was 100 MB), symlink/owner check on the shared
  folder, trimmed stderr, image paste marked not built, helper doc wrap. Left: two quick drops may paste out of
  order (each copies on its own); `base64 -d` is missing on macOS 12 and older remotes, which the relay envelope
  already needs, so such a machine never connects.

### Lane A

- **What:** item 6. The About panel showed the credits as one paragraph, and it named only the icon sources.
- **Cause:** `Oriel/Credits.rtf` (phase 12) was a single centered paragraph that pointed at `resources/icons/SOURCES.md`
  in the repo for the license texts. The app shipped no license texts, and Ghostty, libghostty-spm, DisplayLink and
  bash-preexec (Ghostty's bash integration) had no credit.
- **Fix:** the system panel is gone. Oriel ▸ About Oriel opens Oriel's own window (`Oriel/Views/About.swift`, a
  `Window` scene in `OrielApp.swift`): the icon, name and version, then two glass cards, Terminal and Program Icons,
  one line per credit (the name links its home page, the license sits on the right), a "License Texts" glass button
  and "Brand marks belong to their owners." The window background is the app's `WindowBackground` (Glass blur or
  Classic opaque). It cannot be resized or minimized, is not restored, and ⌘W closes it. The button opens
  `Oriel/Acknowledgements.txt` (bundled) in the default text editor: every license in full (Ghostty, libghostty-spm,
  DisplayLink, bash-preexec, and the seven icon licenses from `resources/icons/licenses/`). `make test` fails when an
  icon license file is missing from it. A first version kept the system panel with short lines
  (`2-mid-panel-*.png`); the user asked for more padding and the app's glass, so it became the window.
- **Commits:** 8e92766, f23a72f, 684d465, 9fcda42, d0a43b8, a912f74, ec3e737, 68be12b.
- **Tests:** e2e `testAboutWindowListsTheCreditsAndOpensTheLicenseTexts` (AboutTests): opens About from the menu,
  checks the link and license of five credits, ⌘W closes it, then where TextEdit opens .txt files and is not
  running, the button opens a TextEdit window titled Acknowledgements (TextEdit quits in teardown). Run locally on a
  Release build (`xcodebuild -configuration Release test`, under the GUI lock). Targeted CI runs 40415963020 and
  40416668954 (the panel version), 40417516982 and 40418053483 (the window).
- **Screenshots** (`/tmp/oriel-shots/33about/`, the About window only, Release build, throwaway e2e sessions):
  `1-before-system-panel.png`, `2-mid-panel-lines-dark.png` / `-light.png`, `3-after-window-dark.png` /
  `-light.png`, and `4-after-libraries-ci.png` (CI run 40419209275, 1x: 643 pt of the 674 pt screen).
- **Docs:** program-icons (the About window, the license texts, where a new credit goes).
- **Review:** l33-about-review, two rounds, no blockers. Applied: the bash-preexec credit, the TextEdit guard and
  teardown, the license check, ⌘W, plainer docs, a light screenshot. Left: a grouped `Form` instead of the glass
  cards (the user asked for the app's glass); no scroll view (the window is about 620 pt tall, CI's screen 674 pt:
  add one with the next few credits).
- **Smaller window** (user, after the cards): the About window keeps only the icon, the name, the version and
  one "Acknowledgements" glass button that opens `Acknowledgements.txt`; the two credit cards and the brand-marks
  line are gone (the file's header keeps that line). The test is now `testAboutWindowOpensTheAcknowledgements`
  (name and version, ⌘W, the button opens TextEdit); CI run 40419941830. Screenshots `5-small-dark-ci.png` (CI)
  and `5-small-light.png`, `5-small-dark.png` (local Release). Commits eebbd35, 75c844e.
- **Ghostty's libraries** (follow-up): `libghostty.a` (the macOS slice: its object files, symbols and strings)
  builds in FreeType, libpng, zlib, Oniguruma, simdutf, Highway, Wuffs, stb_image, GNU libintl, libxev, libvaxis,
  zig-objc, z2d, uucode, Zig's standard library and compiler-rt, and two fonts (JetBrains Mono, Symbols Nerd Font).
  Their texts, from the exact versions Ghostty's `build.zig.zon` pins (ref 35a81a9), are in `Acknowledgements.txt`
  under "Inside Ghostty"; the Terminal card has one line for them, "Ghostty's libraries · Various". Not built in:
  HarfBuzz, fontconfig, imgui, glslang, Sentry, Noto Emoji (no symbols or names in the archive). The window is still
  about 640 pt tall, under CI's 674 pt screen, so no scroll view.
- **For the user:** GNU libintl is LGPL-2.1, and libghostty links it statically. The LGPL asks that users can relink
  the app with their own libintl (for example, the app's object files on request). That is a libghostty-spm build
  choice; decide whether it matters for how Oriel ships. z2d is MPL-2.0: its source is at the linked repo.

### Lane C

- **Item 2, the sidebar header moved** (G #1 0:14, #2 0:23). Frames from the recording before and after the switch:
  in the Agents view the name sat about 3 pt higher and 4 pt further left. **Cause:** two old choices, not a phase
  32 commit (phase 32 changed only comments in that code; `git log -L` on the header). The Agents view placed the name
  18 pt in, on the group labels' edge (91f201f, 2026-10-24), against 22 pt in the workspaces view. And its row aligned
  the name on the first text baseline of the 22 pt sort capsule (8c831e7, then 27f6ca4), where the workspaces view
  centers it on the 28 pt `+`. **Fix** (cac708b): the name is 22 pt in in both views, and its text has the `+`'s
  28 pt height, so the name and the sort label still share one baseline and the name does not move. The name no
  longer lines up with the group labels (4 pt to their right): the user asked for one position.
  **Test:** `testSwipesPageTheSidebarAndTheStripApart` compares the header's origin before and after ⌘. (it fails
  if either half is undone); `testAgentsViewListsEveryAgentByPriorityOrWorkspaceOrder` drops the assertion the
  user overruled.
- **Item 3, the pill slid after the overview** (G #3 0:43 to #5 1:05). Frame by frame at 1:05 (30 fps), the tab bar
  shows at 64.60 s and the pill crosses from "cli" to "swebench autopilot" in about 0.1 s while it fades in.
  **Cause:** `Overview.open` selects the tab in the same update as `leaving = true`, and the chrome's fade,
  `.animation(.easeOut(0.12), value: open)` on the whole title row and sidebar, animated everything that changed in
  that update: the pill's offset too (and the sidebar's page and rows). This came with 39915d5 (phase 31, the pill
  under the overview sits on the selected tab, so its place changes in that update), not with phase 32's
  `.id(page.id)` (the user picked a tab in the same session). The item 12 test missed it because the pill's note
  read the model value, which was right; only the drawing slid. **Fix:** the fade animates the opacity alone
  (e6d4768, `.animation(_:body:)`), and the pill never animates its place (40cee39, `.animation(nil, value: place)`:
  it follows the strip frame by frame and jumps on any other switch). **Guard:** the pill's offset is drawn by an
  `Animatable` modifier (`Slide`) that notes "pill slides <drawn> <place>" under `-recordLatency` at any frame
  drawn short of its place; `testTheCapsuleRestsOnTheTabShownHoweverItShows` asserts there are none, after the
  overview, a workspace round trip and ⌘4. Red on the unfixed code on this Mac (8 notes, "pill slides 0.26 2.0" to
  "1.74 2.0"), green with the fix.
- **Item 4, contrast.** Measured from the four look scenes on CI (1x): the backgrounds sampled from the screenshots,
  the token color composited over them, checked against the darkest drawn glyph pixel (they agree within 0.02).
  Script and screenshots: `/tmp/oriel-shots/l33c/` (`contrast.py`, `before/`, `after/`).

  | Look | Card buttons before | after | Grip before | after |
  |---|---|---|---|---|
  | Glass dark | 2.99:1 | 3.93:1 | 3.0:1 | 4.1:1 |
  | Glass light | 2.31:1 | 3.35:1 | 2.1:1 | 3.3:1 |
  | Classic dark | 3.00:1 | 4.00:1 | 3.0:1 | 4.0:1 |
  | Classic light | 2.31:1 | 3.35:1 | 2.1:1 | 3.3:1 |

  **Fix** (36a093a, ecb0896): `Look.paneButton` white 0.42 / black 0.45 (from 0.33); the grip takes the same color
  (was `secondary` at 0.6). `Look.contrast` (from `colorSchemeContrast`, set where both windows build their `Look`)
  makes the app's own dim colors stronger under Increase Contrast: title row and sidebar text 0.65 → 0.85, the
  selected title 0.9 → 1, tab dividers 0.17/0.14 → 0.3/0.28, the track 0.05 → 0.1, card buttons and grip → 0.6/0.65
  (about 6.6:1). The system's colors follow it by themselves. In Glass the ratios depend on the desktop behind the
  window (these are CI's). No test: a token switch with no logic, and Increase Contrast is a system setting a UI test
  cannot turn on.
- **Docs:** window (Agents view header, card header buttons, the overview's fade), theme-and-accessibility (token
  table, Increase Contrast, the 3:1 note).
- **CI:** 40416165976 (36a093a: the four look scenes, the pill and swipe tests green; the Agents view test red on a
  second overruled check, the workspace labels on the header's edge) and 40417149176 (ecb0896: the pill test, four
  overview tests, the flicker test and the swipe test green; the same Agents check red), fixed in 57790a1 (the labels
  on the rows' icon edge). 40418115375 (57790a1, the same eight tests): all eight pass.
  Learned: `gh run watch --exit-status` exited 0 on a failed run; read `gh run view --json conclusion`.
- **Review** (l33-c-review): one should, applied: scope the chrome's fade to its opacity (the root cause; other
  changes of the same update slid too). Nits applied: the slide check after the later switches, the selected title
  under Increase Contrast, docs wording, "on CI's desktop". Kept `Look.grip` as a name (it reads better at its use).
- **For the user to check by hand:** with Increase Contrast on (System Settings ▸ Accessibility ▸ Display), the title
  row, tab dividers and card buttons look stronger; the card buttons in light read clearly; a tab picked in the
  overview (also in another session or workspace) shows its pill there with no slide.

### Lane S

- **Result: not reproduced, so no fix (user's decision: leave it, they will report the pattern if it comes back).**
  The user swiped by hand in a logging build on the throwaway sessions `oriel-dev-33strip-full` and `-empty`.
  Three-finger swipes worked on the empty session in two setups. With one window: 10 steps in a row, into and out
  of the empty session, 5 of them starting on it, with the pointer over the empty area. With two Oriel windows
  stacked at the same frame, as in the capture (where "reviews - devvm-aai" sat behind the front window): 7 steps,
  all in the front, key window. Logs: `/tmp/oriel-shots/lane-s-touch.log` and `lane-s-touch-two-windows.log`.
  The first hand test logged nothing because of a mistake in the probe.
- **What was checked.** A temporary probe build (never committed) read AppKit's touch routing in the running app,
  first on an empty session and then on one with a terminal. In both, AppKit's own touch-target function
  (`_touchTargetViewForPosition`, called directly) picks the window's frame view at every point. The gesture event
  masks are the same, and no view or gesture recognizer takes indirect touches in only one case. Two things differ
  in the empty session: the view under the pointer is WindowReader's background view, and the window itself is
  the first responder. The hand tests show that neither stops the swipes. A two-finger scroll posted over the
  empty area of the front window of two stacked windows also went to the front window. Reconnecting and loading
  take the same path: touches go to the frame view whatever the window shows, and `take` only needs the window and
  its pages. They were not tested by hand.
- **What can make a swipe step nothing.** (1) A fourth finger landing (within about 7 ms in the log): the system
  takes it as its four-finger swipe (Spaces), as designed. In the capture, though, the screen neither switched nor
  bounced from 1:33 to 1:41. (2) The direction: steps do not wrap, as with ⌥⌘[ ]. In the capture the empty session
  (pi-herd) is the last page, so fingers to the left (next) do nothing there. A user who repeats the swipe that
  worked from the first page sees "works on a session, not on the empty one". (Touches with no window, while
  another app or Space is in front, step nothing either. But in the log they were all one-finger touches, and
  scrawl.json shows Oriel in front from 88 to 108 s, so that does not explain G #6.)
- **Seen in the capture, not changed:** two-finger swipes over the sidebar at 1:30 and 1:48 landed on the previous
  page. The one at 1:42 slid toward it and sprang back, because the lift was slow and the page was short of half
  (`Swipe.landing`).
- **Also:** `SplitDivider`'s doc comment now says the grip is drawn in `Look.grip` (lane C's request).
- **Check by hand:** if it happens again, note the swipe's direction (the last page has no next), the number of
  fingers, and whether the page in view was the last.

### Lane D

- **What capture H asked** (watched every frame, 0:00–8:59, at 2 s steps plus the keyframes): docs minimal and
  current with no mock-ups; drop `plan/archive/` and `plan/metrics/`; keep the phases but make them concise; one
  reusable way of working (phases or not, reviews, review agents, cleanups) that `AGENTS.md` points at; lessons
  in one file; `ci.md` current only; `ui-layout.md` short or gone; a better name than `plan/`; resources with
  no dates (the user highlighted "Similarity screening — 26 October 2026" at 5:34); inspirations out of the repo;
  drop metrics, mock-ups and their scripts, visual-compare; research as a few flat folders of md files, one file
  per client, no spikes or scripts; `scripts/` stays (8:49).
- **Cause:** 33 phases of notes piled up next to each other: four rule files that repeated each other, run logs,
  metrics, mock-ups that stopped matching the app at phase 22, design pages for parts never built (plugins, chat,
  pills, iOS), and research written as dated agent reports.
- **playbook/** (renamed from `plan/`, the user's pick, 67e1fad, last commit, every link fixed, also in
  `ci.yml`, `Makefile`, `.swiftlint.yml`, a UI test comment and `scripts/test-times.tsv`):
  - `workflow.md` (274 lines) replaces `workflow.md`, `execution.md`, `rules.md`, `standards.md` (550): when to
    use phases, roles, the whole run, feedback rounds, the mechanics the user listed (worktrees `../oriel-NN<lane>`
    and `wt-NN<lane>`, push to main after a rebase and a build, no stash, own DerivedData, the GUI lock with the
    `user` owner, throwaway herdr sessions, starting, naming, watching and stopping agents, chosen-tests vs full
    CI runs), the phase loop, the orchestrator's check, reviews, the phase template, briefs, the coding rules and
    the design bar for every UI surface (user, mid-round).
  - `lessons.md` (114 lines): only problems that came back, each with its rule; lane L's 46 lessons folded in
    after cutting one-offs (process ones went into `workflow.md` and `ci.md`).
  - `ci.md` (93 lines, from 230): layout, chosen-tests runs, sign-off runs, CI-only failures, fast tests, the
    test-times refresh, and why XCUITest needs another session (from the deleted GUI-testing research).
  - `README.md`: the index and the phase table. Deleted: `archive/` (its one unique part, the Rex features left
    out, is now "Left out on purpose" in Future work), `metrics/`, `execution.md`, `rules.md`, `standards.md`,
    `ui-layout.md` (its one rule not in the docs, "never send the user to herdr", is now a principle on the
    docs' index page).
  - Phases 1–32 trimmed by a script (1731 lines): "Read first" lists (mostly dead links), Done when, Out of
    scope, e2e lists, Checks, How to ship, Learned, Assumptions, Spike, CI and Reviews parts, hand-check lists.
    Kept: goal, Build, Deviations, Decisions, root causes, numbers. Remaining dead links rewritten.
- **docs/:** deleted the overview, `public/mockups`, `public/inspirations`, `components/design` (diagrams
  became one sentence or nothing), and 19 pages for parts that are not built (inspirations, build-order, risks,
  rex-backend, chat-view, the ten plugins pages, pills, iphone-and-ipad, sources). `future-work` is one short
  page; `index` rewritten. Every other page lost its iOS, plugin, chat, pill and `dial` lines and its "phase NN"
  history; D-rows for unbuilt parts and the Superseded table went. One false claim fixed: libghostty-spm is a plain
  exact pin, not a patched build. The unused `cnfast` dependency went. Internal links and anchors checked by a
  script (0 broken); `pnpm build` green.
- **resources/:** inspirations moved to `~/Downloads/oriel-inspirations/` (124 MB, with the git-ignored videos
  from the main checkout); metrics, mock-ups and visual-compare deleted. Research: `clients/` has one file per
  client (29 plus an index; the web, macOS, mobile and primary-repos reports split, web-clients-notes merged,
  Rex.app in `clients/rex.md`), `multiplexers/` gained `herdr.md` (the old herdr-core, 379 → 150 lines) and Rex
  Server's protocol merged into `multiplexers/rex.md`, `plugins/` has `plugin-ui-options.md` (two reports and the
  spike's numbers), `ui/` has `floating-panes.md` and `pill-panel.md`. No spikes, scripts, images, BRIEF, `dev/`
  or `herdr/` folders; dates, clone paths and the user's machine and session names cut. Branding: no dated
  screening, no iOS line; `Oriel.icns` (used by nothing) and its export code in `scripts/app-icon.py` deleted
  (`make icons` checked). icons/ kept as is (tools/ is the only way to rebuild the catalog).
- **README.md** rewritten short (user, mid-round): what it is, what it does, requirements (Perl on remote
  machines), build and install, use, future work, links. **AGENTS.md** points every agent at `playbook/workflow.md`,
  `lessons.md` and the phases.

  | Folder | Before (files, text lines) | After |
  |---|---|---|
  | docs | 96, 8207 | 47, 3572 |
  | plan → playbook | 60, 10910 | 39, 7059 |
  | resources | 278, 22853 | 164, 11973 |
  | AGENTS.md, README.md | 28, 109 | 23, 56 |

  ```
  before                                   after
  docs/components/design/  (6)             docs/content/docs/ (12, ui 9, reference 3)
  docs/content/docs/ (16, ui 10,           playbook/README.md ci.md workflow.md lessons.md
    plugins 10, reference 3)               playbook/phases/ (35)
  docs/public/{mockups,overview,           resources/branding/ (3)
    inspirations}/ (23)                    resources/icons/ (svg, licenses, tools)
  plan/README ci execution rules           resources/research/clients/ (30)
    standards ui-layout workflow           resources/research/multiplexers/ (5)
  plan/archive/ (3), plan/metrics/ (15)    resources/research/plugins/ (3)
  plan/phases/ (35)                        resources/research/ui/ (2)
  resources/branding/ (4), icons/
  resources/inspirations/ (60), metrics/ (4), mockups/ (4), visual-compare/ (50)
  resources/research/BRIEF.md, clients/ (10 + web-clients-notes/ 4), dev/ (1),
    herdr/ (1), multiplexers/ (4), plugins/ (4 + spike/ 7), ui/ (3)
  ```

- **Tests:** docs only, plus comment and link edits in code: `make lint build test` green on each rebased push;
  `pnpm build` of the docs green. CI: the rename commit 67e1fad runs the full suite (40422038011).
- **For the user to check:** the README and `playbook/workflow.md` read the way you want; `~/Downloads/oriel-inspirations/`
  has everything (the main checkout no longer has the ignored video folders).
