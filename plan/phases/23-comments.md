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
