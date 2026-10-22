# Phase 12: program icons

Goal: every pane and tab shows the icon of the program that runs in it, like Rex: a colored rounded
tile in tab capsules and Agents rows, a plain glyph in card headers, and overlapping tiles, one per
pane, for a tab with several panes. The sidebar has no tab rows (`plan/ui-layout.md`), so it shows no
program icons.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md` (title row, item 5), `resources/mockups/layout.html`
(scene A, the tab bar), `resources/icons/` (`catalog.json`, `svg/`, `SOURCES.md`,
`contact-sheet.png`), `resources/research/clients/rex-ui.md` (tab icon, icon stack, how Rex matches
programs), `docs/content/docs/ui/window.mdx` (tab bar: "the icon of the pane last selected in that
tab"), `Packages/HerdrKit/Sources/HerdrKit/Models.swift` (`Pane`, `PaneProcesses`).

## Build

1. **Assets.** Import every `resources/icons/svg/*.svg` into `Oriel/Assets.xcassets` as an image set
   named `program.<id>` with "Preserve Vector Data" on and "Render As: Template" for the monochrome
   ones. Bundle `resources/icons/catalog.json` as an app resource (or turn it into one Swift table if
   that is fewer lines; pick one, not both). Keep `SOURCES.md` and the license texts in the repo and add
   an "Icons" entry to the app's credits (About panel `Credits.rtf` or similar).
2. **HerdrKit.** Decode the pane fields the matcher needs: `agent`, `display_agent` and
   `terminal_title_stripped` on `Pane` (all optional). `program(_:)` already reads
   `pane.process_info`; return the foreground process's `name`, `argv0` and the first script argument
   (for Node CLIs like `pi`), not only the name, as a small value type.
3. **Matching** (one function, unit tested in HerdrKit because it branches; the catalog's `match`
   field drives it), first hit wins:
   1. herdr's `agent` (or `display_agent`) → the catalog entry whose `match.agent` has it.
   2. The foreground process from `pane.process_info`, when known: `name`, then `argv0` basename, then
      a script path suffix (`match.scriptSuffix`).
   3. The first word of `terminal_title_stripped` (`match.titlePrefix`).
   4. A shell or nothing known → `terminal`. Unknown program → `placeholder` (a neutral tile with the
      program's first letter).
   Strip a login shell's leading `-` (`-zsh`) before matching. The catalog's `scriptSuffix` values for
   claude, codex, gemini and qwen and the `titlePrefix` values `✳` (claude) and `π` (pi) are guesses:
   check them against real panes and fix `catalog.json`.
   Catalog notes: 106 icons in one style (solid filled single paths, normalized size, one tile color
   rule; see `docs/content/docs/ui/program-icons.mdx`). All are monochrome templates. Weakest at
   1x: podman, fish, postgres, java, jupyter, aws (thin marks); fix them in `resources/icons/tools/`
   (`README.md` there), not by hand in the asset catalog.
4. **When to ask herdr for the process** (no polling; one bridge call each):
   - the first time a pane is shown in a card;
   - 1 s after the user presses Return in that card;
   - when a snapshot shows the pane's `terminal_title_stripped` or `agent` changed.
   Keep the result on `HostStore.Pane` (`program`), so the views only read.
5. **Views** (in `Style.swift` or one new `ProgramIcon.swift` if it passes ~200 lines):
   - `ProgramTile(icon:size:)`: the catalog's tile background and glyph color, rounded rect
     radius 5 at 22×18 pt (the size of today's `IconTile`), the 24 pt glyph box drawn at about 17 pt
     (the SVGs carry their own optical padding), a 1 px dark outline and a faint top highlight, as in
     Rex. Replaces `IconTile`.
   - `ProgramGlyph(icon:)`: the glyph alone at 16 pt in `.secondary`, for card headers.
   - `IconStack(icons:)`: one tile per pane of the tab, up to 5, overlapping: each tile 4 pt to the
     right of the one in front, the keyboard card's icon in front, a 1 px separation ring in the
     background color so the stack reads as layers. A one-pane tab shows one tile.
6. **Where they show:**
   - Title-bar tab capsule: the tab's `IconStack`. Today's sidebar tab rows get nothing new: phase 14
     replaces them with workspace rows.
   - Agents rows (phase 15) and hover card rows (phase 19): the pane's `ProgramTile`.
   - Card header: `ProgramGlyph`, then the program's title in primary text and the folder in
     secondary text (Rex: "zsh ~", "bash /private/tmp"). The pane's herdr label still wins when set.
   - Palette rows for tabs: the stack's front tile.
7. **Docs.** A short design page `docs/content/docs/ui/program-icons.mdx`: where icons show, the match
   order, when the app asks herdr, the catalog and its licenses. Add it to `ui/meta.json`. Update
   `ui/window.mdx` (tab capsule, pane card header) and `reference/herdr-calls.mdx` (`pane.process_info`
   is now also used for icons).

## e2e

- In a throwaway session, start `vim` in one pane and `sleep 600` in another; the tab's capsule
  accessibility value lists the icon ids (for example `icons: vim, sleep`), and the card headers show
  the program names. Quit `vim`; the icon goes back to `terminal` within 2 s of Return.
- A pane where the test reports an agent (`pane.report_agent` through the helper, agent `claude`)
  shows the `claude` icon.
- Unit tests for the matcher: agent, process name, argv0, script suffix, title prefix, shell, unknown.

## Done when

- Screenshot of a tab bar with at least six different programs, and a three-pane tab's overlapping
  stack, next to the card headers of that tab.
