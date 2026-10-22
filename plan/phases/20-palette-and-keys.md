# Phase 20: command palette and the key map

Goal: the ⌘K palette becomes Oriel's command center, like Rex's: every command with its shortcut,
sub-pages for choices and names, settings as commands. The menu bar gets Rex's structure and the
shortcuts in one table.

Read first: `resources/research/clients/rex-internals.md` (§3.7, §3.10, §4 in rex-ui.md, §5.2: palette panel, pages, list height; facts only, write your own code), `plan/ui-polish.md`, `plan/ui-layout.md` (title row, sidebar pages, Open Session sheet),
`resources/research/clients/rex-ui.md` (command palette, menu tree, default shortcuts),
`resources/inspirations/rex-app/command-palette.jpg`, decision D48,
`docs/content/docs/ui/theme-and-accessibility.mdx` (keyboard shortcuts), `Oriel/Views/Palette.swift`,
`Oriel/App/OrielApp.swift` (`ActionCommands`, `TabCommands`).

## Build

1. **One command list.** Phase 13 made the list and phases 14–19 appended to it. Add what the palette
   needs: an SF Symbol, search keywords, and either an action or a sub-page. The menu bar items and
   the palette both come from it, so a title or shortcut is written once.
2. **Palette layout.** Width 480 (as now). Search field "Search". Rows 28 pt: symbol, title, and on the
   right the shortcut in secondary glyphs and a › for a row that opens a sub-page. The selected row is
   an accent pill, radius 8. Sections, in order: the current page's items when the filter is empty,
   then Commands,
   Tabs (of the selected workspace), Workspaces (of every page open in the window, with the session
   name in secondary text), Sessions (the open pages; Enter shows that page). Sessions that are not
   open are not listed: the "Open Session…" command (⇧⌘N) opens the Open Session sheet for them. No
   footer with key hints (no hint text in the UI).
3. **Matching.** Fuzzy and in order of the typed letters, over title and keywords (for example
   "split" finds Split Right; "dark" finds Appearance ▸ Dark). Ties: commands before tabs, shorter
   titles first.
4. **Sub-pages** (a stack; ⌫ on an empty field or ⎋ goes back one page, ⎋ on the root closes):
   - Rename Tab ›, Rename Workspace ›, Rename Pane ›: the field holds the current name; Enter saves.
   - Move Pane to Tab ›: the workspace's other tabs, plus "New Tab" and "New Workspace". A move into a
     tab names that tab's last card as `target_pane_id` (phase 18 Findings: without it herdr splits the
     tab's focused pane). Fix phase 17's Move to Tab ▸ menu item the same way.
   - Appearance › (Auto, Light, Dark) and Interface Style › (Glass, Classic): highlighting a row for
     0.75 s previews it on the window; Enter keeps it, ⎋ restores the old one.
   - Font Size › (no Cursor Style: that setting waits for the Settings window, D62).
   - **Go to Directory** (⇧⌘G, not a sub-page): an `NSOpenPanel` (`canChooseDirectories`) that starts
     at the keyboard card's directory (fresh from `pane.get`). Choosing sends
     `pane.send_input {pane_id, text: "cd -- '<path>'", keys: ["enter"]}`. Enabled when the keyboard
     card's cached `program` (phase 12, `HostStore.Pane`) is the shell; check again with `program(_:)`
     when the user picks the folder (D41's check). `ponytail:` This Mac only; remote machines need
     another picker.
   - **Insert Path** (⌃⌘I, not a sub-page): the same panel with `canChooseFiles` too; choosing sends
     the shell-quoted path at the cursor with `pane.send_input {pane_id, text}`, no Return.
5. **Settings as commands.** Each toggle in the menu bar (Fade Inactive Panes, Focus Follows Mouse) is
   one command whose title says what it does now:
   "Turn On Focus Follows Mouse" / "Turn Off Focus Follows Mouse".
6. **Menu bar** (Rex's structure, Oriel's commands):
   - File: New Window ⌘N, New Tab ⌘T, New Workspace, Open Session… ⇧⌘N, Go to Directory… ⇧⌘G, Close
     Pane ⌘W, Close Tab ⌥⌘W, Close Workspace, Close Page, Close Window ⇧⌘W.
   - Edit: (system items), Insert Path… ⌃⌘I, Find… ⌘F (phase 21).
   - View: Command Palette ⌘K, Show Agents ⌘. (the Agents view), Toggle Sidebar ⌃⌘S, Appearance ▸,
     Interface Style ▸, Fade Inactive Panes (phase 17), Pane ▸ (Focus Follows Mouse (phase 17), Split Right ⌘D, Split Down ⇧⌘D, Split Left, Split Up, Zoom ⇧⌘↩,
     Balance Splits ⌃⌘=, Focus Left/Right/Up/Down ⌥⌘arrows, Previous Pane ⌘[, Next Pane ⌘], Move
     Left/Right/Up/Down ⌥⇧⌘arrows, Resize ⌃⌘arrows), Bigger ⌘+, Smaller ⌘-, Actual Size ⌘0, Enter Full
     Screen ⌃⌘F.
   - Window: (system items), Show Previous Tab ⇧⌘[ and ⌃⇧⇥, Show Next Tab ⇧⌘] and ⌃⇥, Move Tab Left
     ⌃⇧PgUp, Move Tab Right ⌃⇧PgDn, Previous Page, Next Page (the sidebar's session pages), the tabs on
     ⌘1…⌘9, then the open windows.
   A command with two shortcuts (⌘K and ⇧⌘P; ⇧⌘[ and ⌃⇧⇥; ⇧⌘] and ⌃⇥): the menu shows the first; the
   second goes through phase 11's `NSEvent` key monitor in `OrielApp.init` (an invisible SwiftUI button's
   shortcut kept its first action, phase 11 findings); its action reads current state (the store,
   `UserDefaults`), not a value a view captured.
7. **Rex shortcuts not taken, and why** (record in the keyboard table): ⌘K stays the palette (D48), so
   switching sessions has no shortcut of its own (Rex's Change Session is ⌘K; Oriel uses Open
   Session… ⇧⌘N and the sidebar's pages); ⇧⌘P also opens it (Rex's key); ⌘N is New Window
   on the same machine, as in Rex; ⌘/ (sidebar) is not used, ⌃⌘S is the macOS sidebar key;
   ⌘R (refresh) is not needed, the snapshot is live; ⇧⌘← and ⇧⌘↑ (Split Left, Split Up)
   would steal "select to line start" from text fields, so those splits have no shortcut.
8. **Docs.** D48 (commands, sub-pages, ⇧⌘P); the keyboard table in
   `ui/theme-and-accessibility.mdx` (all keys above; ⌥⌘← → now move between cards, keyboard focus order
   for the chrome follows Full Keyboard Access); `ui/window.mdx` palette section.

## e2e

- ⌘K, type "split r", Enter: the keyboard card splits right.
- ⌘K, Rename Tab ›, type a name, Enter: herdr's label changes; ⌫ on an empty field goes back.
- ⌘K, "dark", Appearance › Light highlighted 1 s: the window previews light; ⎋ restores dark.
- ⇧⌘G, pick a folder in the open panel: the pane's shell is in that folder (`pane.read` shows the
  `cd`, then `pwd` matches).
- ⌃⌘I inserts a quoted path into the shell line (`pane.read`).
- ⇧⌘P opens the palette.
- ⌘K, "open session", Enter: the Open Session sheet opens. ⌘K, "new window", Enter: a second
  window opens (on `ORIEL_SESSION`).
- With `ORIEL_SESSION2` open as a second page, ⌘K, type its name, Enter: the sidebar shows its page.

## Done when

- Screenshots: root page, a filtered list, a rename page.
- Every menu item has its shortcut from the one list; no shortcut is defined twice.

## Findings
