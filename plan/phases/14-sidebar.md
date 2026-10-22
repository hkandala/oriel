# Phase 14: sidebar: session pages and workspace rows

Goal: the sidebar of `plan/ui-layout.md`. It has one Arc-style page per herdr session open in the
window, with page dots and a sideways swipe between pages. Each page lists the session's workspaces
like herdr's Spaces panel: a state icon, the name, the git branch with ahead and behind counts, and
linked worktrees indented under their repository. The footer has the filter and one Open Session
button, which opens the Open Session sheet. Tabs are no longer sidebar rows.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md` (sidebar, Open Session sheet),
`resources/mockups/layout.html` (scenes A, B, F), `resources/research/clients/rex-ui.md` (sidebar),
`resources/research/herdr/herdr-core.md` (workspace calls, worktrees),
`docs/content/docs/ui/window.mdx`, `docs/content/docs/ui/swiping.mdx`, `docs/content/docs/layout.mdx`
(selection), `docs/content/docs/data.mdx`, decisions D13, D35, D41, D43, D47, D67, D68,
`Oriel/App/OrielApp.swift` (`ContentView`), `Oriel/Store/HostStore.swift`,
`Oriel/Views/Sidebar.swift`, `Oriel/Views/SessionPicker.swift`,
`Packages/HerdrKit/Sources/HerdrKit/Models.swift`.

## Build

### Pages and stores

1. **Open pages.** The window keeps an ordered list of open session names and the page in view. Each
   open page has its own `HostStore` (snapshot reads, one event stream). A session that is not open
   in the window has no store and costs nothing. Each page keeps its own selection (workspace, tab,
   keyboard card, zoom), so switching pages brings it back. Terminal streams run only for the shown
   tab of the page in view, as today (plus the existing 24-surface cache).
2. **First page.** A new window opens one page: the `-session` launch argument when it is given (the
   e2e suite always passes it), else `default`. If that session is stopped, the app starts it as it
   does today (launchd job, D47). The app never opens other sessions by itself. The `session` key in
   `UserDefaults` goes away.
3. **Restore.** The open page names and the page in view are kept in `@SceneStorage`. A restored
   window reopens them; a name that no longer runs is skipped (`herdr session list --json`, the
   existing `sessions()`). If none is left, the first page rule applies.
4. **Close Page.** The context menu of the page header and of its page dot has "Close Page". It
   removes the page from the window and its store disconnects (events stream and terminal streams
   end). The herdr session keeps running. Disabled on the last page.

### Paging

5. **Swipe.** A sideways two-finger swipe over the sidebar moves to the next or previous page. The
   existing scroll monitor (axis lock, D35) routes by place: over the sidebar it pages the sidebar,
   over the strip it pages tabs, never both. The page slides with the strip's spring; under Reduce
   Motion it switches without motion. At the first or last page the swipe rubber-bands.
6. **Page dots.** At the bottom of the page, above the footer: one 6 pt dot per open page, 6 pt
   apart, the current one in primary text color, the others tertiary. A click on a dot switches.
   Hidden when one page is open. Each dot's accessibility label is the session name.
7. **Page header.** The session name (11 pt, secondary) and, at the trailing end, a `+` that makes a
   new workspace in that session: `workspace.create {cwd: $HOME, focus:false}`, then read the snapshot
   and select it.

### Workspace rows

8. **Rows.** One row per herdr workspace of the page's session, in herdr's order.
   - Line 1: a 14 pt state slot (phase 15 draws the state icons; empty in this phase) and the name
     (13 pt).
   - Line 2, only for a git repository: `arrow.triangle.branch` (10 pt), the branch, then ↑ahead in the
     finished color and ↓behind in red when nonzero, all 11 pt secondary. No changed-file count. A
     workspace that is not a git repository has one line and no text about git.
   - 44 pt with two lines, 30 pt with one, 2 pt apart. The selected workspace is the phase 10 pill
     (radius 10).
   - Accessibility value: "‹branch› ahead N behind M" when known, plus "worktree of ‹parent›" for a
     child.
9. **Linked worktrees.** Decode the workspace's worktree fields from the snapshot
   (`worktree.is_linked_worktree`, `worktree.repo_key`, `worktree.checkout_path`; check the names on
   herdr 0.9.5 and record them). A linked worktree shows right after the workspace that has the same
   `repo_key` and is not a linked worktree, indented 14 pt, with a 1 pt guide line in the separator
   color from the parent's state slot down. herdr's own order wins otherwise. With no parent in the
   session, it is a normal row.
10. **Git data.** For each workspace: root = `worktree.checkout_path`, else the cwd of the workspace's
    first pane. The app runs `git -C <root> status --porcelain=v2 --branch` on the machine through
    `Exec.run` (find `git` the way the app finds herdr, in the login shell's `PATH`; 5 s timeout). It
    reads `# branch.head` (when `(detached)`, the first 7 characters of `# branch.oid`) and
    `# branch.ab +A -B`. A nonzero exit means not a repository. The parser is one function, unit
    tested (it branches). When it runs:
    - when a snapshot of the page in view changes, for the changed workspaces;
    - every 10 s for every workspace of the page in view, while the window is visible;
    - never for a page that is not in view; one run per workspace at a time.
11. **Click** selects the workspace (the app's own selection, never herdr focus, D13); the tab bar
    and the strip show its tabs.
12. **Context menu:** New Tab (`tab.create {workspace_id, cwd, focus:false}`, cwd of that workspace's
    keyboard card or `$HOME`), Rename Workspace (inline field in place of the name, Enter saves with
    `workspace.rename {workspace_id, label}`, Esc cancels; a double-click on the name also starts it),
    Move Up and Move Down (`workspace.move {workspace_id, insert_index}`; a workspace with worktree
    children moves with them: `workspace.move_block {workspace_ids, before_workspace_id}`), Close
    Workspace (always asks with the tab and pane count, D41; `workspace.close {workspace_id}`). Read the
    snapshot after each write. Drag to reorder comes in phase 18.

### Size and footer

13. **Width.** 240 pt default. A 6 pt handle at the sidebar's trailing edge resizes it between 227 and
    480 pt, with the resize cursor. Kept per window (`@SceneStorage`). The strip keeps its pages whole
    during the drag (pages are the strip's width).
14. **Scroll fade.** 18 pt fades at the top and bottom of the scrolling list when content is under
    them.
15. **Footer.** The filter field and one button, Open Session (`plus.square.on.square`, tooltip
    "Open Session… ⇧⌘N"). The filter keeps the rows whose name or branch matches; a matching worktree
    child also keeps its parent. Today's New Workspace and Add Remote Host buttons go away (the page
    header has `+`; the machine menu has Add Remote Host).
16. **Remove** the tab rows, the workspace sections and their collapse state.

### Open Session sheet

17. A sheet on the window titled "Open Session", 420 pt wide. The footer button, the workspace menu's
    "Open Session…" and File ▸ Open Session… (⇧⌘N) open it. It replaces `SessionPicker` and
    `SessionList`. The UI calls it only "Open Session".
    - A text field "Name a new session, or find one", empty and with the keyboard at first.
    - The list, filtered by the field, read once when the sheet opens (`sessions()`):
      1. "Create session “‹typed name›”" when the text is a valid herdr name (`Session.isValidName`)
         that no session has; with an empty field, "Create session “‹two-word name›”" with today's
         suggested name (`lunar-ridge`).
      2. Running sessions not open in this window, with "opens it" on the right.
      3. Stopped sessions, with "starts it".
      4. Sessions already open in this window, last, with "open".
    - Arrows move, Enter or the **Open** button acts on the highlighted row; Cancel or Esc closes.
      - Create: start the new server (launchd job, D47; herdr makes one workspace in `$HOME`), add its
        page after the current one and show it.
      - A running session: add its page after the current one and show it; its store connects.
      - A stopped session: start it (D47), then the same.
      - An open session: show its page.
    - While a server starts, the row shows a spinner; a failure shows today's notice and keeps the
      sheet open (phase 21 adds the final wording).
18. The workspace menu (phase 13) gets one group per open page, in page order, and the branch from
    the git data on each row. Picking a workspace of another page shows that page and selects it.
19. The window title is "‹tab title› - ‹session of the page in view›".

### Docs

20. Rewrite the sidebar part of `ui/window.mdx` (pages, workspace rows, footer, Open Session sheet),
    `layout.mdx` (selection is per page), `data.mdx` (open pages and width in `@SceneStorage`),
    `ui/swiping.mdx` (the sidebar swipe pages sessions), `talking-to-herdr.mdx` (git status,
    `workspace.move_block`, the writes table), `machines.mdx` (sessions open as pages). D43 (open
    pages), D67 (git status) and D68 (the sheet) are already recorded: change them if the build
    differs.

## e2e

Each test creates two throwaway sessions, `oriel-e2e-<id>-a` and `oriel-e2e-<id>-b`, launches with
`-session` set to `a` and `-ApplePersistenceIgnoreState YES`, and deletes every session it made in
teardown (also one it created through the sheet).

- At launch the sidebar has one page (`a`), no page dots, and the app runs no bridge for `b`
  (`pgrep` as in `e2e-helper.py`).
- Open Session (footer button): the sheet lists `b` under "opens it" and `a` as "open". Pick `b`:
  two pages, two dots, the header shows `b`. Click the first dot: the header shows `a`.
- ⇧⌘N, type `oriel-e2e-<id>-c`, Enter: `herdr session list` shows it running and a third page shows
  it.
- Stop `b`'s server; Open Session lists it under "starts it"; Enter: it runs again and its page shows.
- Close Page on `b` (header context menu): the page and its dot go, and `herdr session list` still
  shows `b` running. Close Page is disabled on the last page.
- Workspace rows: a workspace in a temporary git repository with one local commit ahead of its
  upstream shows its branch and "ahead 1" (accessibility value); a workspace in `/tmp` has one line
  (row height 30). A `git worktree add` folder opened as a workspace is indented with "worktree of
  ‹parent›". A new commit in the repo shows within 11 s.
- The page header `+` makes a workspace in that session. Rename and Close Workspace from the row's
  context menu change herdr's snapshot; Move Down changes herdr's workspace order.
- Drag the sidebar handle: the sidebar width (accessibility frame) changes, within 227–480 pt.
- The filter hides rows that do not match.

## Done when

- Screenshots: two pages with dots, a page with git branches, ahead and behind, and an indented
  worktree, the Open Session sheet with all four kinds of rows, light and dark.
- Swiping between pages and the strip checked by hand (trackpad gestures are not in e2e).
