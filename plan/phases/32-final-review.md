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
