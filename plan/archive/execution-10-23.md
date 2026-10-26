# Run notes of phases 10–23

Archived in phase 32, kept as history: the parts of [../execution.md](../execution.md) that applied only to the
UI polish (phases 10–23) and its final review.

## Parallel work in worktrees (user, 2026-10-22)

Independent work runs in parallel, each agent in its own git worktree (`/Users/hkandala/code/oriel-<name>`),
pushing straight to `main` after `git pull --rebase`. Phase 22 runs next to phase 20 and then phase 21:
phase 22 owns the `Look` token values and the sizes of the title row, tab bar, cards and sidebar; phases 20
and 21 own their own views (palette; find bar, notices, empty states) and use the tokens. The GUI lock and
the 5 CI macOS runners are shared. Phase 23 (comment pass) starts when 21 and 22 are both done; the final review after it.

## After phase 23: final review and report (user's request)

1. **Final whole-repo review**, read only, in parallel: a ponytail reviewer (unneeded complexity,
   duplication, dead code, abstractions, over-long files), a bugs and edge cases reviewer (races, leaks,
   error paths, herdr safety rules, multi-window and restore cases), and a spec reviewer (the app against
   `plan/ui-layout.md`, `plan/ui-polish.md` and the design pages; docs against the code). Each reports a
   numbered list with file:line, severity and the fix.
2. **Fix** every blocker and should with one fixer agent (small commits, CI green), nits fixed or
   answered; a second short round only for the reviewers whose blockers or shoulds were fixed.
3. **Metrics dashboard** from `plan/metrics/*.json` and git/CI data: time per phase, commits and lines,
   review agents and rounds, minutes and value per reviewer role, GUI-lock minutes, CI runs; one HTML page
   (`resources/metrics/dashboard.html`, no external assets) plus a short summary of which reviews were a
   must. Then report to the user with the "For the user to check at the end" list.

## Decisions without the user

The user is not asked during phases 10–21. The orchestrator decides open questions from the design and the
ponytail rules, records each choice in the design pages, keeps going until phase 21 is done, and lists
here what the user should check at the end.

### Hand checks waiting for the GUI

- Phase 18: the 9 checks in `plan/phases/18-drag-and-drop.md` Findings, "To check by hand when the GUI is
  free" (Esc, forbidden pointer, window not moving, spring-load to an edge in another tab, full track or
  sidebar). The orchestrator runs them (or a short agent) when the user frees the GUI.

### Open tasks

- Phase 21 Build 11: update the docs site's mock-ups to the new look (`docs/components/design/` split demo and chat
  card, `docs/public/overview/index.html`) once phase 22's look settles. Then bring back the "Interactive
  overview" nav link in `docs/lib/layout.shared.tsx` (dropped in the final review: it showed the old sidebar).

### For the user to check at the end

- Phase 10: the four looks next to Rex (`/tmp/oriel-shots/10/final-*.png`). Known gaps kept on purpose:
  the Classic dark pill is a little brighter than Rex (`#303030` vs `#292929`); Glass dark cards are
  lighter than the window until phase 17's fade.
- Phase 11: the Settings window is dropped for now (comes back after its mock-ups). ⌘= (second Bigger key)
  has no CI test; try it by hand. Phase 11's osascript keys may have landed in your browser or Raycast.
- Phase 13: the machine menu has no icons (macOS 27 draws no item images in app menus). A tab renamed
  to only digits shows the program title (herdr's default labels are digits). Tab status glyphs come back
  in phase 15.
- Phase 14: the Open Session sheet lists every herdr session on the Mac (your `default` and `pi-herd`
  too). Workspaces the app creates in a repo are not indented as worktrees (herdr fills the worktree
  fields only for `worktree.*` calls). The "herdr is too old" page still says to update herdr.
- Phase 15: notifications and the Dock badge need a signed build: the ad-hoc dev build gets no
  notification permission, so neither showed on this Mac. One reviewer's scripted mouse click landed in
  your Ghostty window (no keys sent).
- Phase 16: the app stays open with no window, as WindowGroup apps do. Window restore after quit is
  made independent of the macOS "close windows when quitting" setting in phase 21.
- Phase 17: herdr 0.9.5's `pane.swap` moves herdr's focus even with `focus:false`, so Split Left / Up
  and swaps change the focused pane a herdr TUI on the same session sees. ⌃⌘= (Balance Splits) is taken
  by a global hotkey on your Mac (BetterTouchTool or Raycast); the menu item works.
- Phase 21: find highlights shift on wide characters; a find bar dropped while reconnecting or at quit
  leaves herdr scrolled; a new session that timed out and was retried gets no first workspace; a hung
  server shows Reconnecting only after 30–40 s.
- Phase 22: composites of every element against Rex in `/tmp/oriel-shots/22/compare/`. Kept gaps: Rex's
  tab track runs 1.5 pt past the first and last tab (ours lines up with the cards); Rex's Glass window
  inner edge glow has no public API. Traffic lights are moved with public frame changes (re-applied after
  layout and full screen).
- The UI tests share the app's defaults with your own Oriel (same bundle id): an e2e run leaves the look
  at Glass Dark.
