# Phase 13: tab bar and sidebar

Goal: the title-bar tab bar and the sidebar look and behave like Rex's: a capsule track, equal-width
tabs, a sliding selection, fades, dividers, context menus, rename, keycap hints, a resizable sidebar
with collapsible sections.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (tab bar, tab item, sidebar,
animation table), `resources/inspirations/rex-app/` (tabs-with-status, three-splits, sidebar-tabs),
`docs/content/docs/ui/window.mdx`, decisions D42, D45, `Oriel/Views/TitleBar.swift`,
`Oriel/Views/Sidebar.swift`, `Oriel/Views/SessionPicker.swift`.

## Build

### Title-bar tab bar (sidebar hidden, D45)

1. **Track.** A capsule 34 pt tall behind all tabs, filled with the phase 10 track token, hidden
   when the workspace has one tab. The title row stays 40 pt (no private API for a taller one).
2. **Tab width.** All tabs share one width: `(space − (n − 1) × 1) / n`, at most 220 pt, at least
   64 pt. Below 64 pt the bar scrolls sideways, with the existing edge fades (8 pt leading, 16 pt
   trailing). Setting **Tabs fill the bar** (General, off by default) removes the 220 pt cap.
3. **Dividers.** 1 pt, tab height − 18 pt tall, centered between tabs; hidden next to the selected,
   the lit and the hovered tab; fade 0.2 s.
4. **Selection.** Keep the one glass marker that follows the strip's scroll (D12, Cube). Its radius
   is min(height / 2, 16.5). A click, ⌘digit or a key step moves it with Rex's spring
   (`.spring(response: 0.28, dampingFraction: 1)`, the SwiftUI form of stiffness 520 / damping 46);
   Reduce Motion jumps. Classic draws the phase 10 Classic pill instead of glass.
5. **Hover.** The hover token fill, 0.14 s ease-out.
6. **Close button.** × (22 pt hit area, glyph 10 pt bold) on the selected tab and on the hovered one,
   at the trailing end. Hidden when the tab is narrower than 52 pt. After a close, tab widths stay as
   they were while the pointer stays in the bar, so the next × is under the pointer (Safari); they
   settle when the pointer leaves.
7. **Title.** One line. When it does not fit, the end fades out over 16 pt (a mask), no ellipsis. The
   title is the herdr tab label; when the label is herdr's default (a bare number), the title is the
   keyboard card's program and folder ("zsh ~", "pi oriel"). The folder part is in secondary text.
8. **Context menu** on a capsule and on a sidebar row: Rename Tab, Move Tab Left, Move Tab Right,
   Close Tab, Close Other Tabs (asks once with the total pane count). Move = `tab.move {tab_id,
   insert_index}`. Rename = an inline text field in place of the title (Enter saves with `tab.rename`,
   Esc cancels); a double-click on a sidebar row's title also starts it.
9. **Keycap hints.** Hold ⌘ for 0.7 s with the window key: each of the first nine tabs of the shown
   list (capsules, or rows of the selected workspace) shows a small keycap "⌘1"… over its icon. Fade in
   0.13 s, out 0.1 s on release. An `NSEvent` flags-changed local monitor, no global monitor.
10. **Session button.** Shows the session name only when more than one herdr session runs (the
    laptop icon alone otherwise), up to 224 pt.
11. **Window title.** "‹tab title› - ‹session name›" (the Window menu and Mission Control show it).

### Sidebar (D45)

12. **Rows.** 30 pt tall, icon stack (3) + title + status slot; the selected row is the phase 10
    pill (radius 10). Row spacing 2 pt.
13. **Width.** 240 pt default, drag a 6 pt handle at the sidebar's trailing edge to resize between
    227 and 480 pt, resize cursor, kept in app storage. The strip keeps its pages whole during the drag
    (pages are the strip's width).
14. **Sections.** A workspace header sticks to the top while its tabs scroll under it (a pinned
    section header). A chevron collapses the section (rotation 0.18 s); a collapsed workspace shows the
    number of its agents that need you, in the needs-you color. Collapse state is per device, in memory
    plus `@SceneStorage` (design `data.mdx`: sidebar expand state).
15. **Header actions.** On hover, a `+` at the trailing end makes a new tab in that workspace
    (`tab.create {workspace_id, cwd}`, cwd of that workspace's keyboard card or `$HOME`). Context menu:
    New Tab, Rename Workspace (inline field, `workspace.rename`), Move Up, Move Down
    (`workspace.move {workspace_id, insert_index}`), Close Workspace (always asks with the tab and pane
    count, D41; `workspace.close`).
16. **Scroll fade.** 18 pt fades at the top and bottom of the scrolling list when content is under
    them.
17. **Docs.** Update `ui/window.mdx` (sidebar, tab bar), `layout.mdx` if selection rules change, D42
    (dividers, widths), `talking-to-herdr.mdx` writes table (rename, move, close workspace), the
    keyboard table (keycap hints). Record a decision for the default-label title rule.

## e2e

- Rename a tab from the capsule's context menu; herdr's snapshot has the new label.
- Move Tab Right; herdr's tab order changes.
- Close Other Tabs asks once and leaves one tab.
- Collapse a workspace section; its tab rows leave the accessibility tree; expand again.
- Resize the sidebar by dragging its handle; the sidebar width (accessibility frame) changes and
  survives a relaunch.
- New tab from a section header's `+` lands in that workspace.
- Rename and close a workspace from its context menu.
- With 12 tabs and the sidebar hidden, tabs are 64 pt or wider and the bar scrolls to the selected one.

## Done when

- Screenshots: tab bar with 1, 3 and 12 tabs; hover and × states; sidebar with a collapsed section;
  keycap hints showing; light and dark.
