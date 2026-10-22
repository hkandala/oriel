# Phase 13: title row, tab bar and menus

Goal: the title row of `plan/ui-layout.md`, left to right: traffic lights, sidebar toggle, machine
button, workspace button (only while the sidebar is collapsed), the tab bar (always in the title row,
with Rex's geometry), a spacer, then ⌘ and +. Phase 15 adds the Agents button before ⌘. The session
picker stays where it is until phase 14 removes it.

Read first: `resources/research/clients/rex-internals.md` (§3.1, §3.2, §3.4, §5.1: tab bar view, traffic lights, timings; facts only, write your own code), `plan/ui-polish.md`, `plan/ui-layout.md` (title row; windows and machines),
`resources/mockups/layout.html` (scenes A, C, D, E), `resources/research/clients/rex-ui.md` (tab bar, tab
item, animation table), `resources/inspirations/rex-app/` (tabs-with-status, three-splits),
`docs/content/docs/ui/window.mdx`, decisions D42, D45, D65, `Oriel/Views/TitleBar.swift`,
`Oriel/Views/Sidebar.swift`, `Oriel/Views/SessionPicker.swift`.

## Build

The row stays 40 pt (no private API for a taller one). Its items are 8 pt apart.

### Sidebar toggle

1. Always shown, right after the traffic lights. No highlight or fill when the sidebar is open: the
   icon changes instead. Closed: an outline window with a sidebar line (SF Symbol `sidebar.left`).
   Open: the same window with the sidebar part filled. First check `rectangle.leftthird.inset.filled`
   (SF Symbols 4+) as the open icon. Only if it does not fit, make one custom symbol from `sidebar.left`
   in the asset catalog. Record what you chose.
2. ⌃⌘S and View ▸ Toggle Sidebar do the same. The sidebar slides 0.3 s (Rex's collapse time); under
   Reduce Motion it does not slide. The choice is kept per window (`@SceneStorage`).
3. The sidebar no longer hides the tab bar: the tab bar is in the title row in both states (D45 changes).

### Machine button

4. The machine's icon, then a small chevron (`chevron.down`, 8 pt), no name. This Mac's icon is
   `laptopcomputer` when IOKit lists an internal battery (`IOPSCopyPowerSourcesList`, type
   `InternalBattery`), else `desktopcomputer` (`hw.model` no longer starts with `MacBook` on M2 and
   later laptops). Accessibility label "Machine: This Mac", id `titlebar.machine`, `.help("Machine")`.
5. Its menu (a native `Menu`): one row per machine with its icon and name and a checkmark on the
   current one (only "This Mac" for now), a separator, then "Add Remote Host…". That item does nothing
   yet (`ponytail:` no-op until remote hosts), as today's footer button does. The footer button goes
   away in phase 14. Picking the current machine does nothing. ⌥-click on a machine opens it in a new
   window: phase 16 builds it.

### Workspace button (sidebar collapsed only)

6. Shown only while the sidebar is collapsed, after the machine button. An outline folder (`folder`),
   then "‹session› | ‹workspace›": the session name in secondary text, a thin vertical line
   (1 × 12 pt, the separator color), the workspace name in primary text, then the 8 pt chevron. At most
   260 pt wide. When the text does not fit, the workspace name's end fades out over 16 pt. Id
   `titlebar.workspace`.
7. A click opens the workspace menu: a floating glass panel under the button, 300 pt wide, at most
   420 pt tall (system glass, as the palette). It reuses the palette's list (`FilterField` + `MenuRow` +
   arrow handling): one filter-list view, used by the palette, this menu and phase 14's sheet.
   - A filter field "Filter or create…" with the keyboard.
   - Every workspace of every session open in this window, grouped under a header with the session
     name (secondary, 11 pt). In this phase the window has one session, so there is one group; phase 14
     adds a group per open page. Rows are 26 pt: the workspace's state icon (empty until phase 15), the
     name, and the git branch on the right in secondary text (empty until phase 14). The selected
     workspace is the highlighted row.
   - Under a separator: "New Workspace" (in the session of the selected workspace). "Open Session…"
     (⇧⌘N) comes with the sheet in phase 14.
   - Arrows move, Enter acts, Esc closes. A typed name with no match shows "New Workspace “‹text›”"
     first: Enter makes it with `workspace.create {label, cwd: $HOME, focus:false}` (a launchd-started
     server's cwd is not `$HOME`), then reads the snapshot and selects the new workspace.
   - Picking a workspace selects it (the app's own selection, never herdr focus, D13). In phase 14, a
     workspace of another page also switches the sidebar to that page.
8. Today's session picker (`SessionPicker`) and ⇧⌘N's session list stay until phase 14 removes them.

### Sidebar and commands

9. **Sidebar tab rows go.** Remove the tab rows (id `tab.<id>`) from the sidebar now, so XCUITest finds
   one `tab.<id>` element (the capsule). The sidebar shows workspace rows only until phase 14 restyles
   them.
10. **One command list** (D48). Make the one list of commands (title, shortcut, action, enabled) that
    the menu bar reads, put this phase's commands in it, and move today's menu items
    (`ActionCommands`, `TabCommands`) and those of phases 10–11 into it. Phases 14–19 append to it;
    phase 20 adds the palette's rendering and sub-pages. No later phase writes a menu item that phase
    20 must move.

### Tab bar (always in the title row)

11. **Place.** After the workspace button (sidebar collapsed) or the machine button (sidebar open), up
    to the spacer before the right-side buttons. It shows the tabs of the selected workspace.
12. **Track.** A capsule 34 pt tall behind all tabs, filled with the track fill (phase 10), hidden when
    the workspace has one tab.
13. **Tab width.** All tabs share one width: `(space − (n − 1) × 1) / n`, at most 220 pt, at least
    64 pt. Below 64 pt the bar scrolls sideways, with the existing edge fades (8 pt leading, 16 pt
    trailing).
14. **Dividers.** 1 pt, tab height − 18 pt tall, centered between tabs; hidden next to the selected,
    the lit and the hovered tab; fade 0.2 s.
15. **Selection.** Keep the one glass marker that follows the strip's scroll (D12, Cube). Its radius
    is min(height / 2, 16.5). A click, ⌘digit or a key step moves it with Rex's spring
    (`.spring(response: 0.28, dampingFraction: 1)`, the SwiftUI form of stiffness 520 / damping 46);
    Reduce Motion jumps. Classic draws the phase 10 Classic pill instead of glass.
16. **Hover.** The hover fill (phase 10), 0.14 s ease-out.
17. **Close button.** × (22 pt hit area, glyph 10 pt bold) at the trailing end, shown only on the
    hovered tab (the selected tab too has none until hovered; user, like Rex). It sits over the title's
    fade, so showing it never changes a tab's width. Hidden when the tab is narrower than 52 pt. After a close, tab widths stay as
    they were while the pointer stays in the bar, so the next × is under the pointer (Safari); they
    settle when the pointer leaves.
18. **Content.** The tab's overlapping program icons (phase 12, up to 5), then the title. One line.
    When the title does not fit, the end fades out over 16 pt (a mask), no ellipsis. The title is the
    herdr tab label; when the label is herdr's default (a bare number), the title is the keyboard
    card's program and folder ("zsh ~", "pi oriel", D65). The folder part is in secondary text. Then
    a trailing status slot (× now; phase 15 adds working dots).
19. **Context menu** on a capsule: Rename Tab, Move Tab Left, Move Tab Right, Close Tab, Close Other
    Tabs (asks once with the total pane count, D41). Move = `tab.move {tab_id, insert_index}`. Rename =
    an inline text field in place of the title (Enter saves with `tab.rename {tab_id, label}`, Esc
    cancels); a double-click on the title also starts it. Close = `tab.close {tab_id}`. Read the
    snapshot after each write.
20. **Keycap hints.** Hold ⌘ for 0.7 s with the window key: each of the first nine capsules shows a
    small keycap "⌘1"… over its icons. Fade in 0.13 s, out 0.1 s on release. An `NSEvent`
    flags-changed local monitor, no global monitor. The sidebar shows no keycaps.

### Window title

21. "‹tab title› - ‹session name›" (the Window menu and Mission Control show it), set with
    `navigationTitle`; the title row does not draw it.

### Docs

22. The design pages already describe the agreed layout; make them match what you built. Check
    `ui/window.mdx` (title row, machine button, workspace button and menu, tab bar), D45 (the
    tab bar always in the title row; the sidebar toggle swaps its icon; machine and workspace buttons
    replace the session picker), D42 (dividers, widths), `talking-to-herdr.mdx` writes table
    (`tab.rename`, `tab.move`, `tab.close`, `workspace.create {label}`), the keyboard table (⌃⌘S,
    keycap hints).

## e2e

All in a throwaway `oriel-e2e-*` session. Tests that create tabs or workspaces do it in a new
workspace and close it after (as `newTab(closeAfter:)` does), so the w1/w2 fixture stays as `setUp`
expects.

- Sidebar open and collapsed: the tab capsules (`tab.<id>`) are in the title row both times; the
  workspace button exists only while collapsed and its value is "‹session› | ‹workspace›".
- ⌃⌘S toggles the sidebar; the toggle's accessibility value is "open" or "closed".
- The machine button's menu lists "This Mac" with a checkmark and "Add Remote Host…".
- Workspace menu: type a new name, Enter: herdr's snapshot has a workspace with that label, and it is
  selected (the workspace button shows it). Pick another workspace: the tab bar shows its tabs.
- Rename a tab from the capsule's context menu; herdr's snapshot has the new label.
- Move Tab Right; herdr's tab order changes.
- Close Other Tabs asks once and leaves one tab.
- With 12 tabs, tabs are 64 pt or wider and the bar scrolls to the selected one.
- The window title is "‹tab title› - ‹session›".

## Done when

- Screenshots: sidebar open and collapsed; tab bar with 1, 3 and 12 tabs; hover and × states;
  the machine menu; the workspace menu; keycap hints showing; light and dark.

## Findings
