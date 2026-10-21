# Phase 18: command palette and the key map

Goal: the ⌘K palette becomes Oriel's command center, like Rex's: every command with its shortcut,
sub-pages for choices and names, settings as commands. The menu bar gets Rex's structure and the
shortcuts in one table.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (command palette, menu tree,
default shortcuts), `resources/inspirations/rex-app/command-palette.jpg`, decision D48,
`docs/content/docs/ui/theme-and-accessibility.mdx` (keyboard shortcuts), `Oriel/Views/Palette.swift`,
`Oriel/App/OrielApp.swift` (`ActionCommands`, `TabCommands`).

## Build

1. **One command list.** A single list of commands (title, SF Symbol, shortcut, search keywords,
   enabled, and either an action or a sub-page). The menu bar items and the palette both come from it,
   so a title or shortcut is written once. Phases 11–17 added their commands to the menus; move them
   into this list.
2. **Palette layout.** Width 480 (as now). Search field "Search commands, tabs and sessions…". Rows
   28 pt: symbol, title, and on the right the shortcut in secondary glyphs and a › for a row that opens
   a sub-page. The selected row is an accent pill, radius 8. Sections, in order: the current page's
   items when a filter is empty (Recent commands first: the last five run, in memory), then Commands,
   Tabs, Workspaces, Sessions. A footer under a hairline: "↩ Run   ⎋ Close" (and "⌫ Back" on a
   sub-page) as keycap chips.
3. **Matching.** Fuzzy and in order of the typed letters, over title and keywords (for example
   "split" finds Split Right; "dark" finds Appearance ▸ Dark). Ties: commands before tabs, shorter
   titles first.
4. **Sub-pages** (a stack; ⌫ on an empty field or ⎋ goes back one page, ⎋ on the root closes):
   - Change Session ›: the session list (running first), Enter switches.
   - Rename Tab ›, Rename Workspace ›, Rename Pane ›: the field holds the current name; Enter saves.
   - Move Pane to Tab ›: the workspace's tabs plus "New Tab" and "New Workspace".
   - Go to Directory › (⇧⌘G): a folder browser that starts at the keyboard card's directory (fresh
     from `pane.get`). Rows are subfolders; → or Enter on a row goes in, ← goes up, ⌘↩ chooses the
     shown folder. Choosing sends
     `pane.send_input {pane_id, text: "cd -- '<path>'", keys: ["enter"]}`. Enabled only when the card
     runs only its shell (`program(_:) == nil`, D41's check). Lists
     folders with `FileManager` on This Mac (`ponytail:` remote machines will list through `Exec.run`).
   - Insert Path › (⌃⌘I): the same browser with files too; choosing sends the shell-quoted path at the
     cursor with `pane.send_input {pane_id, text}`, no Return.
   - Appearance › (Auto, Light, Dark) and Interface Style › (Glass, Classic): highlighting a row for
     0.75 s previews it on the window; Enter keeps it, ⎋ restores the old one.
   - Font Size ›, Cursor Style ›.
5. **Settings as commands.** Each toggle in Settings is one command whose title says what it does now:
   "Turn On Focus Follows Mouse" / "Turn Off Focus Follows Mouse".
6. **Menu bar** (Rex's structure, Oriel's commands):
   - File: New Tab ⌘T, New Workspace, New Session ⇧⌘N, Go to Directory… ⇧⌘G, Close Pane ⌘W, Close Tab
     ⌥⌘W, Close Workspace, Close Window ⇧⌘W.
   - Edit: (system items), Insert Path… ⌃⌘I, Find… ⌘F (phase 19).
   - View: Command Palette ⌘K, Show Activity ⌘., Toggle Sidebar ⌃⌘S, Appearance ▸, Interface Style ▸,
     Pane ▸ (Split Right ⌘D, Split Down ⇧⌘D, Split Left, Split Up, Zoom ⇧⌘↩, Balance Splits ⌃⌘=,
     Focus Left/Right/Up/Down ⌥⌘arrows, Previous Pane ⌘[, Next Pane ⌘], Move Left/Right/Up/Down
     ⌥⇧⌘arrows, Resize ⌃⌘arrows), Bigger ⌘+, Smaller ⌘-, Actual Size ⌘0, Enter Full Screen ⌃⌘F.
   - Window: (system items), Show Previous Tab ⇧⌘[ and ⌃⇧⇥, Show Next Tab ⇧⌘] and ⌃⇥, Move Tab Left
     ⌃⇧PgUp, Move Tab Right ⌃⇧PgDn, Previous Session, Next Session, the tabs on ⌘1…⌘9.
   A command with two shortcuts gets a hidden second menu item.
7. **Rex shortcuts not taken, and why** (record in the keyboard table): ⌘K stays the palette (D48), so
   Change Session has no shortcut (it is ⌘K in Rex); ⇧⌘P also opens the palette for Rex users; ⌘N
   (new window) is not used (one window, D34); ⌘/ (sidebar) is not used, ⌃⌘S is the macOS sidebar key;
   ⌘R (refresh) is not needed, the snapshot is live; ⇧⌘← and ⇧⌘↑ (Split Left, Split Up)
   would steal "select to line start" from text fields, so those splits have no shortcut.
8. **Docs.** D48 (commands, sub-pages, ⇧⌘P); the keyboard table in
   `ui/theme-and-accessibility.mdx` (all keys above; ⌥⌘← → now move between cards, keyboard focus order
   for the chrome follows Full Keyboard Access); `ui/window.mdx` palette section.

## e2e

- ⌘K, type "split r", Enter: the keyboard card splits right.
- ⌘K, Rename Tab ›, type a name, Enter: herdr's label changes; ⌫ on an empty field goes back.
- ⌘K, "dark", Appearance › Light highlighted 1 s: the window previews light; ⎋ restores dark.
- ⇧⌘G, go into a folder, ⌘↩: the pane's shell is in that folder (`pane.read` shows the `cd`, then
  `pwd` matches).
- ⌃⌘I inserts a quoted path into the shell line (`pane.read`).
- ⇧⌘P opens the palette.

## Done when

- Screenshots: root page, a filtered list, the folder browser, a rename page.
- Every menu item has its shortcut from the one list; no shortcut is defined twice.
