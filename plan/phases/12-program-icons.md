# Phase 12: program icons

Goal: every pane and tab shows the icon of the program that runs in it, like Rex: a colored rounded
tile in tab capsules and Agents rows, a plain glyph in card headers, and overlapping tiles, one per
pane, for a tab with several panes. The sidebar has no tab rows (`plan/ui-layout.md`), so it shows no
program icons.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md` (title row, item 5), `resources/mockups/layout.html`
(scene A, the tab bar), `resources/icons/` (`catalog.json`, `svg/`, `SOURCES.md`,
`contact-sheet.png`), `resources/research/clients/rex-ui.md` (tab icon, icon stack, how Rex matches
programs), `docs/content/docs/ui/window.mdx` (tab bar: "the icon of the pane last selected in that
tab"), decision D60, `Packages/HerdrKit/Sources/HerdrKit/Models.swift` (`Pane`, `PaneProcesses`).

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
   - when a snapshot shows the pane's `agent` changed;
   - on a title change (`terminal_title_stripped`): the events stream does not subscribe to
     `pane.updated` today, so a title change waits for the 30 s beat. Spike: if herdr sends
     `pane.updated` on a title change, add it to the subscription and record it; else drop this
     trigger, because the Return trigger covers it.
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
   - Agents rows (phase 15): the pane's `ProgramTile`. Hover card rows (phase 19): `ProgramGlyph`.
   - Card header: `ProgramGlyph`, then the program's title in primary text and the folder in
     secondary text (Rex: "zsh ~", "bash /private/tmp"). The pane's herdr label still wins when set.
   - Palette rows for tabs: the stack's front tile.
7. **Docs.** Make `docs/content/docs/ui/program-icons.mdx` (where icons show, the match order, when the
   app asks herdr, the catalog and its licenses) match what you built. Update `ui/window.mdx` (tab capsule, pane card header) and `reference/herdr-calls.mdx` (`pane.process_info`
   is now also used for icons).

## e2e

- In `ORIEL_SESSION`, in a new workspace closed after, start `vim` in one pane and `sleep 600` in another; the tab's capsule
  accessibility value lists the icon ids (for example `icons: vim, sleep`), and the card headers show
  the program names. Quit `vim`; the icon goes back to `terminal` within 2 s of Return.
- A pane where the test reports an agent (`pane.report_agent` through the helper, agent `claude`)
  shows the `claude` icon.
- Unit tests for the matcher: agent, process name, argv0, script suffix, title prefix, shell, unknown.

## Done when

- Screenshot of a tab bar with at least six different programs, and a three-pane tab's overlapping
  stack, next to the card headers of that tab.

## Findings

### Deviations

- **The title prefix matches herdr's stripped title, so `✳` is gone from the catalog.** herdr's
  `terminal_title_stripped` drops status glyphs (`✳ hello` → `hello`, `⠋ Claude Code` → `Claude Code`) and keeps
  `π`. A prefix matches the whole title or its start up to a space, so the two-word "Claude Code" works; claude's
  `✳` could never match and was removed in `tools/build.mjs`.
- **A Node CLI's script comes before the process name.** The phase's order (name, argv0, then the script suffix)
  would always say `node` for `pi`, because the catalog has a `node` icon. For a `node` or `bun` process the
  script's path suffix is checked first, then the script's base name, then name and argv0. Only a runtime's
  script counts (vim editing a file named `git` stays vim).
- **The script's base name also matches `match.process`.** A CLI run through its npm bin link has the link as
  `argv[1]` (`node /opt/homebrew/bin/gemini`), not the package path (checked with a symlinked script), so the
  `scriptSuffix` values only catch launches by the package path.
- **No `display_agent`.** herdr's `display_agent` is a human label set through `pane.report_metadata`, not an
  agent kind (`resources/research/herdr/herdr-core.md`), so it would rarely match `match.agent`; only `agent` is decoded.
  Phase 15 reads it from `snapshot.agents[]` if it needs it.
- **The asset catalog is generated.** `tools/build.mjs` also writes `Oriel/Assets.xcassets/program.<id>.imageset`
  (the SVG, template, vector data kept), so a fix goes into the tool, not the asset catalog. The build is
  deterministic: rerunning it changed no other SVG.
- **`ProgramTile(icon:letter:)` has no `size`.** Every tile today is 22×18; a later phase adds a size when it
  needs one.
- **Sidebar tab rows show the plain `terminal` tile** (no stack, no value), as the phase asks: phase 14 replaces
  them.

### Decisions

- **`Program { name, argv0, script, isShell }` in HerdrKit**; `script` is the first argv element after argv0 that
  is not an option. `program(_:)` returns the first foreground process besides the shell, else the shell itself
  with `isShell` (so the header says "zsh ~", as in Rex); the close check asks unless `isShell`. `title` is the
  header's name: a Node CLI's script name, else the process name.
- **Unknown agent → `placeholder`** with the agent's first letter, like an unknown program.
- **Asks land in order:** a per-pane counter drops an answer older than the latest ask (each ask is its own
  herdr run). A held Return asks once (`isARepeat`). A pane id herdr reuses with another terminal starts over.
- **Matcher:** `[ProgramIcon].iconID(agent:program:title:) -> String` in `HerdrKit/ProgramIcon.swift`, tested
  against the real `resources/icons/catalog.json` (read by path), so the catalog's values are tested too.
  `ProgramIcon` decodes only `id`, `tile` and `match`.
- **The app bundles `catalog.json` by a file reference** in the project (not a copy, not a Swift table): one
  source, read once into a global `programIcons`.
- **Credits:** `Oriel/Credits.rtf` (the About panel reads it). RTF, not HTML: HTML import sets black text, which
  vanishes in a dark About panel.
- **Capsule accessibility value:** `"in view; icons: vim, sleep, nano"` (front first); `"icons: …"` when not in
  view. Two older tests now check the `in view` prefix.
- **Stack layers:** each tile in front cuts a 1 pt ring (`destinationOut` in a compositing group) out of the
  tiles behind, instead of a ring in a background color: Glass has no solid background color.
- **Front tile:** the keyboard card (the store's per-tab keyboard terminal, now observed), else herdr's focused
  pane. Others in herdr's order, up to 5.
- **Header name:** herdr's agent, else the program's `title` ("vim /private/tmp", "zsh ~"); the label still wins.
- **`HostModels.swift`.** The store's nested `Workspace`, `Tab` and `Pane` moved to an extension in their own file:
  `HostStore.swift` passed SwiftLint's 400-line and 250-line body limits.
- **Weak 1x icons**, fixed in `tools/build.mjs`: fish → Phosphor fish-simple, podman → Phosphor package (Podman
  purple), java → Phosphor coffee (Java orange), jupyter → Phosphor planet (Jupyter orange); postgres and aws keep
  their marks, thickened by a new `bold` option (the union of copies shifted around a small circle: 0.3 and 0.35
  units at 24).
- **Placeholder letter, tile widths.** The palette's SF Symbol slot is 22 pt, a tile's width, so tab and
  workspace titles line up. A catalog that fails to load trips an `assertionFailure` in debug builds.
- **Catalog fixes from npm's `bin` fields:** claude's native binary is `claude.exe`; gemini's script is
  `@google/gemini-cli/bundle/gemini.js`; qwen's is `@qwen-code/qwen-code/cli-entry.js`. The old paths stay for
  older installs.

### Assumptions


- **A tab that never showed keeps the `terminal` icon** while a program without an agent or title match runs in
  it (python3 on launch): the phase asks herdr only when a card shows (lazy neighbour pages count). One
  `process_info` per pane on the first snapshot would fix it; not done, as the phase lists the triggers.
- **The header shows the process's real name**: macOS's `nano` is `pico`, a Node CLI started by its package path
  shows `cli.js`. The catalog's `title` ("Pager / man") reads worse than the process name, so it is not used.

### Learned

- **herdr sends `pane.updated` when the stripped title changes** (not on `cd`); it is now in the subscription.
  Spinner frames send none (the spec reviewer: 80 frames, one event); a progress title sends one per change (100
  changes in 2 s, 85 events), absorbed by the snapshot pacing. The program is asked again only when the title's
  first word changes.
- **herdr reports no foreground process for a setuid program** (`top`): `process_info` has no
  `foreground_processes`. Decoding then fails, the icon stays `terminal`, and the close check asks ("A
  program"), which is the safe side. The e2e test uses nano instead (macOS's `nano` is `pico`).
- **A SwiftUI `.task` on a card in the strip's `LazyHStack` got cancelled** when a page was built and dropped
  during a scroll; the cancelled `process_info` call failed and the pane was never asked again (the logs tab
  stayed `terminal`). The card now starts an unstructured `Task` in `onAppear`, and a failed ask clears `asked`.
- **An `XCTNSPredicateExpectation` checks about once a second**, so "within 2 s" failed at ~1.2 s real time. The
  icon test polls every 100 ms with the suite's `poll`.
- **The front tile once jumped to an unclicked card** (E2E reviewer, not reproduced): after the window was
  re-activated, tab 1's stack showed nano in front. The stack follows the tab's keyboard card, which
  `becomeFirstResponder` records; AppKit's key-view fallback when a page changes may move it. The keyboard logic
  is older than this phase; a lead for phase 17.
- **Return reaches `keyDown` with key code 36 (76 on the keypad)** for XCUITest's `typeKey(.return)`; plain Return
  goes to libghostty, so the hook sits before the key routing.
