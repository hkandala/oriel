# Phase 23: Comment pass

Goal: every comment in the code says something the code cannot. The user asked for this pass after
phases 21 and 22, before the final review. Comments only: no code, test or behavior change.

Read first: `AGENTS.md`, `plan/standards.md`, the ponytail skill
(`/Users/hkandala/code/pi-hkandala/extensions/pi-ponytail/skills/ponytail/SKILL.md`).

## Build

1. Go through every source file: `Oriel/`, `OrielUITests/`, `Packages/HerdrKit/` (sources and tests),
   `scripts/`, `Makefile`, `.github/workflows/`, `.swiftlint.yml`.
2. **Delete** a comment when the code already says it: it restates the next line, names what a well-named
   type, function or variable already names, narrates steps, or is out of date. Delete commented-out code.
3. **Keep** (and tighten to one plain sentence where it rambles) a comment that says what the code cannot:
   why it is done this way, an assumption, a herdr or macOS quirk, a measured number and where it came
   from, a link to a decision (D-number) or a phase Findings entry, a `ponytail:` note, a known limit, a
   safety rule (for example why a call passes `--session` or `focus:false`).
4. **Fix** a comment that is wrong now: correct it, or delete it if the reason no longer holds.
5. Doc comments (`///`) on types and functions stay only when they add the why or a contract the name
   does not give.
6. Small commits by area (app views, store, terminal, HerdrKit, UI tests, scripts and CI), each
   `docs(<area>): comments say why, not what` style, ≤ 72 characters.

## Checks

- `git diff <base>..HEAD` changes comments only: verify with a diff that ignores comment lines (for
  Swift, strip `//` and `///` lines and trailing `// …` and compare), and `make lint build test` green.
  No local GUI run is needed; one CI run on the last commit confirms nothing moved.

## Review

One reviewer (read only): samples the diff for deleted comments that carried a real why (put back), kept
comments that only say what (delete), and any non-comment change (revert). One round.

## Done when

- Every file is done, the comment-only check passes, CI is green.

## Findings

Done 2026-10-22 (base 4cb16f3, last code commit 98afc2c): 7 commits, 33 files, +39 −80 lines, all comments.
Three helpers took disjoint files (App/Store/Terminal, Views, HerdrKit + UI tests); the phase agent took
scripts, Makefile, CI and `.swiftlint.yml`, reviewed every hunk and committed by area.

- **Most comments already said why.** Phases 9 and 21 trimmed hard, so the pass deleted 39 comments
  (out of about 1,700 comment lines) and fixed or tightened 29; the rest stay.

| Area | Deleted | Fixed or tightened | Comment lines now |
|---|---|---|---|
| App | 2 | 2 | 119 |
| Store | 6 | 1 (a broken wrap rejoined) | 216 |
| Terminal | 1 | 4 (+1 rewritten after review) | 168 |
| Views | 15 | 13 | 496 |
| HerdrKit (sources, tests, record.sh) | 10 | 4 | 308 |
| UI tests | 5 | 3 (+1 after review) | 353 |
| scripts, Makefile, CI, `.swiftlint.yml` | 0 | 0 | all kept |

- **Wrong comments fixed** (the code had moved on): `PaneTerminal.close()` claimed "the session is going away"
  (it runs when its pane, page or window closes); `State.idle` left out a stream still opening; `fontSize` is the
  default, not the setting; `stepFontSize` named a key monitor reason that 561a6d0 removed (the real reason, from
  phase 11's Findings, is back: SwiftUI keeps a shortcut's first action); `Strip.send` cited D42 for D10;
  `HerdrError.timeout` said 10 s (the request's timeout); `Channel.exit` gives the last 8 KB of stderr;
  `HerdrClient.lastRead` is a time, not a snapshot; `Seen.states` pointed at a `key(_:)` that does not exist; the
  hover card shows the first six panes; `StateIcon` draws a faint dot without an agent; `MenuRow`,
  `FilterField`, `floatingPanel`, `ProgramGlyph` and `IconButton` listed callers that had changed;
  ActionTests' header listed session tests that live in SidebarTests; the TabBar `ponytail:` note said "phase
  16 needs this" after phase 16 shipped (now it names the live ceiling and the fix).
- **Kept on purpose though they may read as "what":** `// MARK:` lines in files of 180–400 lines
  (PaneTerminal, HerdrClient, TerminalStream, HerdrClientTests, three UI test files); one-line docs that give a
  vague name its meaning (`Page.id` is the session's name, `lit`, `letter`, `iconID`, `rows` is herdr's screen
  height, PaneScroll's units); reply types' herdr method (`/// pane.read.`); TitleBar's "⌘K is the menu's" lines
  (why a button with `key:` has no shortcut); fixture and UI-test step comments that name the rule an assert
  checks or what a raw JSON input stands for; the e2e scripts' usage blocks and per-session notes.
- **Comments-only check:** `/tmp/oriel-p23/comments_only.py BASE [HEAD]` strips Swift `//`, `///` and `/* */`
  outside string literals (plain, multiline and raw, so `https://` in strings survives) and `#` comments outside
  quotes in shell, Python, Makefile and YAML, drops blank lines and trailing spaces, and compares every file
  under the phase's paths. 4cb16f3..98afc2c: 78 files, 0 non-comment changes. A planted code change in Swift and
  in a shell script was caught.
- **`file_length` is a hard 400 lines:** the restored `stepFontSize` doc first took PaneTerminal.swift to 401 and
  failed `make lint`; it is one line now.
- **CI:** run 39895584046 on 98afc2c green (lint-build and four e2e shards).
- **Review (one round, phase23-review):** 1 should, 4 nits, all taken: put back the `stepFontSize` why (with
  the phase 11 reason, not the stale one), move the "predicate expectations check once a second" why onto
  `poll`, drop a "repository root" doc and two more what-docs, and name the TabBar ponytail's trigger.
