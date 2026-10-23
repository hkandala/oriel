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
   an accent pill, radius 8. On the root page with an empty field, four sections under headers, in
   order: Tabs (of the selected workspace), Workspaces (of every page open in the window, with the
   session name in secondary text), Sessions (the open pages; Enter shows that page), Commands. A typed
   filter gives one ranked list without headers (item 3). A sub-page shows only its own rows, filtered,
   under its title as a small header above the field. Sessions that are not
   open are not listed: the "Open Session…" command (⇧⌘N) opens the Open Session sheet for them. No
   footer with key hints (no hint text in the UI).
3. **Matching.** Fuzzy and in order of the typed letters, over title and keywords (for example
   "split" finds Split Right; "dark" finds Appearance ▸ Dark). Ties: commands before places, then the
   list's order (the menu's for commands, the tab bar's and the sidebar's for places).
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

### Deviations

- **Move to New Tab and Move to New Workspace live inside Move Pane to Tab ▸.** The palette's Move Pane to Tab ›
  lists New Tab and New Workspace; the palette and the menu bar draw the same command, so the card's context menu
  and View ▸ Pane now show Move Pane to Tab ▸ {other tabs, New Tab, New Workspace} instead of three items. Its title
  is "Move Pane to Tab" everywhere, so the palette row says what moves. It is enabled with one tab too.
- **Enter Full Screen stays AppKit's item.** AppKit adds Enter Full Screen (⌃⌘F) to the View menu itself. The palette
  has a palette-only command, Enter or Exit Full Screen, that shows ⌃⌘F and calls `toggleFullScreen`; only AppKit's
  item binds the key, so it is still defined once.
- **Rename Tab and Rename Workspace are palette-only.** The phase's menu tree has neither; the capsule's and the row's
  context menus keep their own items, which act on the clicked capsule or row, not on the selection.
- **⌘= needs exactly ⌘ now.** Phase 11's monitor took ⌘= with Shift allowed (layouts where = needs Shift). The one
  second-shortcut table compares modifiers exactly, because ⌃⇥ and ⌃⇧⇥ differ only by Shift.
- **Show Agents keeps its title in the palette.** Only settings (`Command.setting`: Fade Inactive Panes, Focus
  Follows Mouse) say "Turn On …" / "Turn Off …"; Show Agents is a view, with a checkmark in the menu as before.
- **Orchestrator decisions after the e2e review:** ties break by the list's order, not by shorter titles ("split"
  lit Split Up and "move pane" lit Move Pane Up, a silent swap, before Move Pane to Tab ›); the empty root shows
  Tabs, Workspaces and Sessions before Commands (they sat under about 60 commands).
- **Workspace rows of the palette are `palette.workspace.<session>.<id>`**: every page's workspaces are listed, and
  two sessions both have a `w1`.
- **The palette lists only the selected workspace's tabs**, as the phase asks, so the old test of jumping to another
  workspace's tab is gone; a workspace row jumps to its selected tab.

### Decisions

- **One list:** `CommandList` (`Oriel/App/CommandList.swift`) builds every command from the window's pages, its
  panel bindings, `openWindow` and `AppSettings` (a `DynamicProperty` of the five `@AppStorage` settings; not
  `Settings`, SwiftUI's scene). The window
  publishes it as one focused value (`\.commands`, replacing five); `AppCommands` draws the menu bar from it, or from a
  list with no window (New Window and the settings still work). The palette gets the same value from the window.
- **`Command` grew** `symbol`, `keywords`, `setting`, `previews`, `name` (current name, async save) and `id` (a
  move's target tab: two tabs can share a title such as "zsh ~", so sub-page rows are `choice.<id or title>`). A command
  with a `menu` is a submenu in the menu bar and a sub-page in the palette; a command with a `name` is a name page in
  the palette (its menu action, for Rename Pane…, still opens the header's field). Section `.palette` is palette-only.
- **Second shortcuts** (`KeyboardShortcut.seconds`: ⇧⌘P → ⌘K, ⌃⇧⇥ → ⇧⌘[, ⌃⇥ → ⇧⌘], ⌘= → ⌘+): the local key
  monitor in `OrielApp.init` finds the main menu's item with the first shortcut and runs it when enabled, so the
  second always does what the menu item does, with its current state. A disabled item lets the key go on.
  `performKeyEquivalent` with a made-up event was tried (ponytail review): ⇧⌘P worked, but AppKit did not match
  "]" with ⇧⌘ to Show Next Tab, so the walk stays. ⌘= still has no e2e test (phase 11: CI's 1x display hides a
  one-step change).
- **Matching:** `String.fuzzyScore` in HerdrKit (unit tests): the typed letters in order, spaces ignored, case and
  accent blind; a match not starting a word costs 1, each break 1, a break not on a word start 2; the best start
  wins. A keyword match costs 3 more than a title match. Ties: commands before places, then the list's order.
- **Sub-pages are one level** (`Palette.sub`, the command's title); no sub-page opens another, so a stack would be
  an array of one. ⌫ on an empty field (not its key repeats: holding ⌫ to clear the field stays on the page) and
  Esc go back; Esc on the root closes. Sub-page rows filter with the same fuzzy match, in their own order. The
  Command Palette command is not a palette row (it is open).
- **View ▸ Pane starts with Focus Follows Mouse** (its own `paneSetting` section), as the phase lists it.
- **Preview:** a `.task(id: lit)` waits 0.75 s and runs the lit choice's action, unless the page was left or a row
  chosen meanwhile. The page keeps the choice it opened on (`Palette.kept`): it keeps the checkmark while another
  previews, and Esc, ⌫ or closing the palette (`onDisappear`) picks it again; Enter clears it.
- **⌃⇥ and ⌃⇧⇥ stay a text field's keys** (the palette, a rename): the tabs behind the palette do not move.
- **List height:** Rex's clamp, min(460, max(84, window height − 154)).
- **Rename rules moved into the store:** `rename(tab:)`, `rename(workspace:)` trim and skip empty or unchanged
  labels, `rename(pane:)` trims and skips unchanged; the capsule, the row, the card header and the palette share them.
- **Go to Directory / Insert Path:** `Page.choosePath(directory:)`: `NSOpenPanel` as a sheet on the key window, at
  `pane.get`'s cwd; the path single-quoted (`'` → `'\''`), a folder's trailing slash kept (`cd -- '/x/'` works, and
  an inserted folder path ends in a slash as shell completion's does); Go to Directory asks `program(_:)` again and
  shows "A program is running in the pane" when it is not the shell, or the error when herdr does not answer. `Multiplexer.sendInput` is `pane.send_input {pane_id,
  text, keys}` (spike: `cd -- '/private/var'` + `["enter"]` ran; text alone stays on the line).
- **Move into a tab** (menu and palette) goes through `Page.drop(_, on: .tab)`, the capsule drop's path: right of the
  tab's last card, equal splits, the page follows.

### Assumptions

- **SwiftUI's menu items carry the shortcut's key and modifiers as AppKit key equivalents** (`keyEquivalent` "]" with
  ⇧⌘ for ⇧⌘]); the second-shortcut lookup compares those. `testSecondShortcuts` shows ⇧⌘P, ⌃⇥ and ⌃⇧⇥ work.

### Learned

- **⌫ is DEL (U+7F) in `onKeyPress`**, which `KeyEquivalent.delete` (U+8) does not match; the field takes both.
- **Menu bar items collide with context-menu items in XCUITest.** `app.menuItems["Close Page"]` matched File ▸ Close
  Page too once it existed; tests take context-menu items from `app.windows.firstMatch.menuItems`.
- **The open panel's Go to Folder looks up every typed letter**: a 30-letter path took about 10 s in XCUITest, so the
  panel test waits up to 10 s.
