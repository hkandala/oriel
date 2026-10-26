# Phase 32: Final whole-repo review and cleanup

The user asked for this on 2026-10-26 (about 03:00), to start once phase 31's lanes (integration, herdr
float requests, paging and pill, hotkey routing) are done and main is green. The orchestrator runs it with
the workflow in `plan/workflow.md` (final review → fixers → metrics and report) and decides open points
itself.

## Goals

1. **Bugs and edge cases, every file.** Split the app code into areas (for example: HerdrKit; store and
   models; terminal and surfaces; views: strip, tab bar, sidebar, agents, overview, floating, panels; app:
   commands, keys, windows; remote: SSH, relay, machines; UI tests and scripts; CI and Makefile). One review
   agent per area reads every file in it, finds bugs and edge cases, and fixes them with small, safe changes
   and a test where one can see it.
2. **Comments.** Same rule as phase 23: a comment stays only when it says what the code cannot (an
   assumption, a herdr or macOS quirk, a measured number and where it came from, a decision link, a known
   limit, a safety rule). Delete comments that restate code, narrate, or are stale; fix wrong ones.
3. **Code quality and simplicity (ponytail).** Many features were added, changed and dropped (Settings
   window, Fade Inactive Panes, ⌥ + swipe, the tab preview, …): remove dead code, leftover flags and test
   hooks nothing uses, needless abstractions and duplication. Keep the code simple and easy to read.
4. **Docs and markdown.** Organise the md files: remove stale and no-longer-true ones (plans, research
   notes that no longer apply), make the spec (`docs/content/docs/`, `plan/ui-layout.md`, decisions) match
   the app as built, fix broken links, keep `plan/workflow.md`, `plan/execution.md`, `plan/ci.md`, rules and
   standards current.
5. **No big changes without the user.** Reviewers make only minor cleanups that cannot break things. A
   large change (a redesign, a big refactor, a removal that changes behaviour) is not made: it goes on a
   list for the user with the reason, the cost and a recommendation.
6. **Green at the end.** `make lint build test` and the full CI suite green (twice without reruns), local
   checks under the GUI budget, everything pushed.

## Agents

- One bug-and-edge-case reviewer-fixer per code area (about 8–10), each also cleaning comments and
  quality in its area, in worktrees, files not overlapping.
- Two or three ponytail agents across areas, looking for dead code and needless complexity (they report
  to the area owners or fix in their own non-overlapping files).
- Docs agents: one for `docs/content/docs/` (the spec and decisions vs the code), one for `plan/` and
  `resources/` md files (stale plans and research, workflow and CI docs).
- An e2e/CI agent at the end: full suite twice, local checks, flakes.
- Any other reviewer that adds value (for example accessibility or security of the SSH path).

## Areas (files do not overlap; baseline 9995aa6)

Baseline: app 12,596 lines (Oriel/), HerdrKit 4,276 (sources and tests), UI tests 7,215, scripts 929, docs
pages 4,871 (mdx), plan and resources md 22,622; 1,390 commits.

| Agent | Files it owns |
|---|---|
| r-herdrkit | Packages/HerdrKit except SSHExec, Relay, StartServer and their tests |
| r-remote | HerdrKit SSHExec.swift, Relay.swift, StartServer.swift (+ their tests); Oriel/Store/Machines.swift, Presence.swift; Oriel/Views/RemoteHost.swift |
| r-store | Oriel/Store: Ahead, Gate, HostModels, HostStore, Page, PaneWrites, WindowPages |
| r-terminal | Oriel/Terminal/* |
| r-app | Oriel/App/* |
| r-strip | Oriel/Views: Strip, SwipeRouter, ThreeFingers, PaneCard, Detail, Drag, ListDrops, CloseDialog |
| r-chrome | Oriel/Views: TabBar, TabButton, TitleBar, Sidebar, WorkspaceRow, Agents, HoverCard, ProgramIcons, Style, Keycap |
| r-panels | Oriel/Views: Overview, OverviewPage, Miniature, FloatingPane, FindBar, FilterList, Palette, OpenSession, Shortcuts |
| r-tests | OrielUITests/*, scripts/*, Makefile, .github/workflows/*, .swiftlint.yml, .swiftformat |
| d-spec | docs/content/docs/**, docs app config only if links break |
| d-plan | plan/**, resources/**, README.md, AGENTS.md, other root md |

Read-only auditors (send findings to the owning agent by name, never edit): a-ponytail-app (Oriel/),
a-ponytail-kit (HerdrKit, tests, scripts), a-security-a11y (the SSH path, secrets, sandbox and entitlements,
VoiceOver labels and keyboard access).

Rules for writers: only your files; a fix that needs another area's file goes to that owner by message.
Small commits by area; no behaviour changes beyond bug fixes; anything big goes to the orchestrator's list.
Targeted CI runs only; the final e2e agent (f-e2e) runs the full suite twice, refreshes
scripts/test-times.tsv, and checks locally under the GUI budget.

## Final report to the user

- The list of big items the reviewers found but did not change: what, why, cost, recommendation.
- A summary of the code: lines of code by language and area, number of modules, files, types, tests (UI and
  unit), docs pages, commits, and other stats; what the cleanup removed.

## Findings

### r-panels

Overview, OverviewPage, Miniature, FloatingPane, FindBar, FilterList, Palette, OpenSession, Shortcuts: every
line read. No dead code or leftover hooks found: every test value and identifier has a reader in the UI tests.

- **Bugs fixed.** (1) A floating window's ⌘K lit the row at the main window's selected tab's index (it lists
  no tabs), so Return ran some other command (`Palette`, 3f24e30; the test line went to r-tests for
  FloatTests). (2) A tile clicked while its page slid away (a wheel's or a key's step) selected its tab, but
  the zoom took the new current page's tab (`Overview.open`). (3) A page two away is not made: its tiles
  reported no leaving, so their tabs stayed in `overviewTabs` and could stream out of view when the page came
  back (`OverviewPage.onDisappear`). (4) A float request (an `oriel://float` URL, herdr's metadata) put any
  session name into a herdr argv; it now needs `Session.isValidName` (a-security-a11y; a leading `-` still
  passes, sent to r-herdrkit). (5) VoiceOver said nothing when ↑↓ moved the lit row of a filter list
  (a-security-a11y). Floating Close Pane is picked by its key, not its title (a-ponytail-app).
- **Comments.** 3 fixed: `Overview.frames` (frames, not miniatures), `FilterField` (stale caller list),
  `MiniCard` (a doc split in two).
- **Not done (small, cross-area):** `reduceMotion && !Animation.forceMotion` repeats in 8 files of 5 areas (one
  `Animation` helper would do); `Mini.fit` and `TerminalCard`'s `Host.fit` share a debounce; FloatingWindow
  can use r-strip's `PaneTitle` and r-app's `windowChrome(look:)` once they land. No big items.

### r-herdrkit

HerdrKit except SSHExec, Relay and StartServer, with its tests: every line read. Every public API and every
`Multiplexer` requirement has a caller in Oriel/ (a-ponytail-kit agrees); no dead code or leftover hooks.

- **Bugs fixed.** (1) A write's `refresh()` that came during the 250 ms wait between spaced reads waited it out,
  though D5 says a write's result is read at once (`HerdrClient.read`: the wait is now a task `refresh` cancels;
  test `a write while events keep coming is read at once, not spaced`, which fails on the old code).
  (2) `Session.isValidName` let a name start with `-`, which an argv reads as an option; float requests now pass
  their session through it (r-panels; a test line).
- **Code.** `Program.title` takes the path's last part without `URL(filePath:)` (phase 31's getcwd note);
  `Program.init` is internal (only tests build one); the observe wrapper is one `TerminalStream.observeWrapper`,
  so r-remote's SSHExec test uses it instead of a copy; one `leaf` helper for the tree tests.
- **Comments.** A doc split in two (`SplitNode.split`) rejoined; a swap note said twice dropped; the "like Rex"
  extension doc moved onto `evened`; `refresh`'s doc reworded.
- **Seen, not changed.** `TerminalStream.init` sets `onTermination` after its reader starts, so a stream that
  closes in that first instant never calls `terminate` (harmless: the run already ended). A login shell slower
  than 3 s at launch finds no herdr until the next ask 30 s later; under a load of 200 a local integration test
  saw `.notFound` once (a rerun passed). No big items.

### r-remote

SSHExec, Relay, StartServer (and SSHExecTests), Machines, Presence, RemoteHost: every line read, the relay's
Perl too. No dead code, flags or test hooks found (`-machines` and `-session` have readers in RemoteTests).

- **Bugs fixed.** (1) A master gone while its pid lived on (reused) or its socket was deleted kept
  `connection` set for good: every run failed with "Oriel needs Perl", and the ponytail note claimed it
  cleared "until a run fails". A relay that does not start now asks `-O check` once; a master that answers
  with another pid or not at all is dropped, so the next run starts a new one (`currentRelay`). (2) Quit ran
  `ssh -O exit` per machine on the main thread and waited without limit: a stopped master hung the quit. No
  wait now; the child outlives the app (a-security-a11y). (3) An ssh answer pasted with a newline sent its
  second line to ssh's next question, as a password try; only the first line goes now (a-security-a11y).
  (4) The remote host and question dialogs were not modal to VoiceOver, and a question appeared silently;
  `isModal` and an announcement of ssh's text (a-security-a11y). No unit test: the master's life needs an
  sshd, which only the UI tests have (RemoteTests on CI's sshd, run below).
- **Simpler.** The 10 s mark refresh walks `HostStore.all` once, not every visible window's stores (a store in
  two windows sent every mark twice); `WindowPages.markShown(refresh:)` lost its parameter. `unhex` lost a
  redundant bound check.
- **Comments.** 6 fixed: three broken doc wraps (SSHExec's login timeout, Relay's protocol and script docs),
  `k` closes stdin after the kill (said before), askpass is written on the first asking connect (said "at
  launch"), the Perl `k` comment's history ("as with a killed ssh before"), and the stale ponytail above.
- **Skipped.** Moving `thisMacIcon` from TitleBar.swift into Machines.swift (a-ponytail-app): a move across
  two owners' files breaks main between the two pushes, for one block's place.
- **For the user (small, not changed).** The sockets' folder and askpass are made once per launch
  (`static let`): a cache cleaner that deletes `~/Library/Caches/oriel` while Oriel runs breaks remote
  connects until a relaunch. Cost: make both per start (about 5 lines). Recommendation: leave it unless seen.

### r-tests

UI tests, scripts, Makefile, CI, lint config: every file read. 8 commits, +109 −150 lines. Every helper, e2e-helper
action and launch-argument hook has a user, and `scripts/test-times.tsv` matches the tests one to one.

- **Bug fixed: the e2e helper served one request at a time** (`scripts/e2e-helper.py`, a plain `TCPServer`).
  `testOverviewOfManyTabsStaysBounded` takes "the main thread's profile while it scrolls back" with an `async let`
  `sample` beside four swipes, but the swipes waited until the 3 s sample ended, so it profiled an idle app. Now a
  `ThreadingTCPServer`. Checked with two 2 s `usage` calls at once: 4.2 s before, 2.4 s after.
- **Tests added for other areas' fixes:** a floating window's ⌘K lights its first row (r-panels, 3f24e30); an
  `oriel://float/?…` URL floats the pane and opens no workspace (r-app, 429a02c).
- **Code removed:** checks of dropped features (the Fade Inactive Panes menu item, ⌥ + scroll); a ⌃⇥ check that
  repeats `testControlTabStepsTabsNeverPanes`; `expectValue`, `expectRatio`'s unused path, `Entry.time`, `throws` on
  helpers that throw nothing; a wait nested inside another wait. One `createTab` helper replaces nine copies of
  `tab.create`, one `drawn` replaces three, one `sheetText` replaces three, `keep` replaces two hand-made attachments,
  and one helper replaces two copies of the held drag through the workspace menu (a-ponytail-kit's findings, except
  `sharpness` over `crop`: a risk at CI's 1x).
- **Comments:** 7 fixed (two docs wrapped mid-sentence, a doc on the wrong function, `////`, the helper's missing
  `open-url` line and its one-request-at-a-time note) and 2 history notes removed (`pane.neighbor`, ⌃⇧Page Up).
- **Big items for the user:** none.

### d-plan

Docs only: plan, resources, the root README and AGENTS.md. No code changed, so CI does not run on these
commits (`paths-ignore`). The working docs went from 1,517 to 1,150 lines; 371 lines moved to
`plan/archive/`.

- **Archived, kept as history:** `plan/ui-polish.md` (the scope of phases 10–21), the v0 request and decisions
  from the old `plan/README.md` (`plan/archive/v0-plan.md`), and the phases 10–23 run notes of
  `plan/execution.md` (`plan/archive/execution-10-23.md`: parallel worktrees, the old final review, the user
  checks of phases 10–22). Phase files keep their Findings. Their "Read first" lines point at the archive.
- **Rewritten to the app as built:** `plan/README.md` is the plan's index (status, files, modules, all 32
  phases). `plan/ui-layout.md` is a short map of the window that adds the overview button, the overview,
  floating panes, three-finger swipes, remote machines and the empty session, and drops its copy of the drag
  and drop tables (drag-and-drop.mdx has them). The design pages now win over it, also in `AGENTS.md`.
  The root `README.md` had v0's feature list, "32 tests, 6.5 minutes" and limits that are built now (remote
  machines, floating panes, drag and drop, trackpad tests).
- **Kept current:** one GUI lock recipe in `plan/rules.md` (take it only if free, `trap` release, one run, at
  most 10 minutes; no wait loop), which execution.md and workflow.md point at. `plan/ci.md` starts with the
  layout today (five jobs, job 0's checks, shards by `scripts/test-times.tsv`, `ON_DEMAND`, ad-hoc and
  on-demand dispatches, artifacts). `plan/execution.md` drops the verifier (workflow.md's numbers), the
  local full `make e2e` (about 40 minutes for about 170 tests: CI runs it), and "4 jobs by name", and logs phases
  24–32. `plan/workflow.md` adds feedback rounds in lanes and the per-area review of this phase.
  `plan/standards.md`: Rex's fixed sizes, system materials, the three-finger check script. `AGENTS.md`:
  `make lint build test` and the touched UI tests before a push (it asked for a full `make e2e`).
- **Links:** no broken markdown link in plan, resources or the root files (a script checks every relative
  link). The kero notes pointed at `ui-layout.md` sections that moved to the design pages.
- **Sent to d-spec:** window.mdx says the card header has four buttons; PaneCard.swift has five (Float Pane
  first). The phase 21 open task (the docs site's overview page and design mock-ups show the old look) is
  still open.
- **For the user:** `resources/mockups/layout.html` shows phase 10's plan, not the app, and
  `docs/public/overview/index.html` dates from phase 9. Redrawing them is a day of work for little use now
  that CI recordings show the app. Recommendation: leave them as history, or delete the overview page.
### d-spec

`docs/content/docs/**`: every page read and checked against the code (39 pages; 31 changed, +217 −119 lines).
Links: a script checked every `/docs/…#anchor`, every `/public` file and every repository path the pages name: no
broken link. `pnpm build` in `docs/` is green.

- **Wrong now, fixed.** The Mac app has remote machines, but index, features, build order, machines, the glossary and
  D43 said "This Mac only" or "SSH hosts later". D43 still had the pre-relay plan (close the least recently shown
  stream when sshd refuses a channel; moved to Rejected). D5 said no event payload is read (float requests are).
  talking-to-herdr showed remote runs as one `ssh` each (they go through the relay) and `herdr()` without `throws`.
  platform said 4 terminals stream out of view (D46: 16), the pill panel was the only other window (floating panes),
  and listed unit tests that do not exist (label parser, state file, transcripts). The pane header has five buttons
  (Float Pane first), and the card menu starts with Float Pane. The keys table had no ⌃⌘O; the second-key monitor
  runs the key window's command (phase 31), not a menu item. 105 program icons, not 106. machines.mdx said a host
  without Perl shows "Oriel needs Perl"; r-strip then showed the reason under Reconnecting (6c85120), and the pages say so. D45 gains
  the overview button, D62 names Focus Follows Mouse, data.mdx the `machine` key, the floats in `selection`,
  `agentsFolded` and the floating windows' frames; herdr-calls gains `pane.report_metadata` and the UI tests' calls.
- **Not built, now said so.** Each page or row for a part that is not built says "not built yet" or "planned":
  plugins and the pane picker, web pages, the chat view, image paste, pills, iOS, herdr's machines in the Add dialog,
  the Local Network preflight, `dial`, and the states and herdr calls of those parts.
- **Decisions.** A Superseded table keeps the history of D16, D19, D23, D28, D33 and D39 (from git), each with the
  decision that replaced it.
- **Big items for the user.** (1) `docs/public/overview/index.html` and the `docs/components/design/` mock-ups (chat
  card, pills, phones) show the look from before phases 10–22 (d-plan's open item from phase 21). Redrawing them is a
  design task; recommendation: redraw only when chat, pills or iOS are built, and keep the sources.mdx note meanwhile.
  (2) The pages follow plain English only in part: long sentences with semicolons remain in window, swiping and
  talking-to-herdr. A full rewrite touches every page (about a day); recommendation: rewrite a page when its feature
  next changes.


### r-terminal

Read all nine files in `Oriel/Terminal/` (1,652 lines) line by line; the stream, settle, still and keyboard-claim
paths had been through phases 24–31 and held up: no race or stale-state bug found that a change could show.

- **Bug fixed:** `FileDrop.escaped` backslash-escaped Ghostty's set but not a line break, so a dropped file whose
  name has one pasted as two lines, and a shell without bracketed paste ran the second (a-security-a11y). Such a
  path is single-quoted now, as `choosePath` does. No test: the e2e drag helper (r-tests') makes one fixed name, and
  the function needs AppKit, so it cannot join `make test`'s standalone checks.
- **Comments fixed:** `PaneTerminal.revealed` still named the hover card's picture (the tab preview was dropped);
  `PaneSurfaceView.wantsKeyboard` said "before it was in a window" (also set when it leaves one); `newFolder`'s
  broken wrap.
- **Code removed:** the registry's two claim-dropping loops are one `dropClaims(but:)`; `Links` reads
  `-recordLinks` once (`Links.record`; r-app switches OrielApp to it); a redundant `@MainActor` and a redundant
  `window != nil`. Skipped a-ponytail-app's optional `cancelSettle()` (two 3-line sites read fine).
- **Checked, not changed:** a failed card retries on every `show` pass of the registry (each snapshot), by design
  since phase 4; `TerminalCard`'s `.id(ObjectIdentifier(terminal))` cannot see a reused address (SwiftUI holds the
  old terminal until the new one is in); `purgeable` detaching the view's own old layer is the path RevealTests'
  evicted cards take, and they show.
- **For the user:** on a remote machine, a file drop, Insert Path… and Go to Directory… use This Mac's files and
  paths (known `ponytail:` limits in FileDrop.swift). Cost: disabling them for remote stores is a few lines in
  CommandList and the drop types (r-app, r-terminal); real support needs copying files over SSH. Recommendation:
  disable them on remote machines now; add the copy with image paste.

### r-strip

Read the eight files (Strip, SwipeRouter, ThreeFingers, PaneCard, Detail, Drag, ListDrops, CloseDialog; 1,943
lines) line by line. Paging, the swipe router, the drops and the close dialog had been worked over in phases 24–31
and held up. 7 commits, +49 −38 lines.

- **Bugs fixed:** (1) `SplitLayout.views` built its map with `Dictionary(uniqueKeysWithValues:)`, which traps on a
  pane id that appears twice in herdr's tree: the app crashed on bad herdr input. It keeps the first now. (2) A
  remote host with no Perl failed every try with "Oriel needs Perl…", but the page showed only "Reconnecting to
  ‹machine›": the reason now shows under it (`detail.text`; d-spec, machines.mdx). (3) A new notice was never
  announced to VoiceOver; it is now, once per notice (a-security-a11y). (4) The wheel's page turn was the one
  motion that ignored `-forceMotion`. No test for 1–3: herdr gives no duplicate pane, CI has no host without Perl,
  and XCUITest cannot hear an announcement.
- **Comments:** "The tab marker follows the scroll" sat on the change that scrolls to the selection (wrong,
  removed); the layout-motion note moved from the padding to `SplitLayout.motion`; two what-comments removed.
- **Code removed:** `ScrollAnchor.Anchor` copied the five fields of its representable; it holds one `marks` now. The
  card header's title is `PaneTitle`, for r-panels' `PaneInfo` to share (a-ponytail-app).
- **For the user:** each card's VoiceOver value is "content 100%" (85 % while another window controls the
  session), left from the dropped Fade Inactive Panes; the tests read only its `content` prefix and `, loading`.
  Cost: the value becomes "loading" or empty, and five UI test files change their checks (r-tests). Recommendation:
  do it with the next a11y pass.
