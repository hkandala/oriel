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

## Final report to the user

- The list of big items the reviewers found but did not change: what, why, cost, recommendation.
- A summary of the code: lines of code by language and area, number of modules, files, types, tests (UI and
  unit), docs pages, commits, and other stats; what the cleanup removed.

## Findings
