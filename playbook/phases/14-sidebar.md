# Phase 14: sidebar: session pages and workspace rows

Goal: the sidebar of the window design (`docs/content/docs/ui/window.mdx`). It has one Arc-style page per herdr session open in the
window, with page dots and a sideways swipe between pages. Each page lists the session's workspaces
like herdr's Spaces panel: a state icon, the name, the git branch with ahead and behind counts, and
linked worktrees indented under their repository. The footer has the filter and one Open Session
button, which opens the Open Session sheet. Tabs are no longer sidebar rows.

## Build

### Pages and stores

1. **Stores.** One app-level store registry: a dictionary from session name to `HostStore` (snapshot
   reads, one event stream). A page takes its session's store from it, made on first use. A session
   with no page has no store and costs nothing. Phase 16 adds refcounts for several windows.
2. **Open pages.** The window keeps an ordered list of open session names and the page in view. Each
   page keeps its own selection (workspace, tab, keyboard card per tab, zoom, `arriving`) in a small
   per-window value per page, not in `HostStore`: move `HostStore.selectedWorkspaceID`,
   `Workspace.selectedTabID`, `zoomedPaneID` and `keyboardTerminals` out. Switching pages brings the
   selection back. One `PaneViewRegistry` per window: terminal streams run only for the shown tab of
   the page in view, and its cache keeps about 24 streams over all pages (D46).
3. **First page.** A new window opens one page: the `-session` launch argument when it is given (the
   e2e suite always passes it), else `default`. If that session is stopped, the app starts it
   (launchd job, D47). The app never opens other sessions by itself. Nothing writes a session to
   `UserDefaults`; `-session` is still read from the argument domain.
4. **Restore.** The open page names and the page in view are kept in `@SceneStorage`. A restored
   window reopens them; a name that no longer runs is skipped
   (`herdr --session <S> session list --json`, the existing `sessions()`). If none is left, the first
   page rule applies. macOS restores no window until phase 16 removes `window.isRestorable = false`;
   phase 16 checks restore.
5. **Close Page.** The context menu of the page header and of its page dot has "Close Page". It
   removes the page from the window and its store disconnects (events stream and terminal streams
   end). The herdr session keeps running. Disabled on the last page.

### Paging

6. **Swipe.** A sideways two-finger swipe over the sidebar moves to the next or previous page. The
   existing scroll monitor (axis lock, D35) routes by place: over the sidebar it pages the sidebar,
   over the strip it pages tabs, never both. `SwipeRouter` today gives the gesture to the innermost
   `enclosingScrollView`, which over the sidebar is the page's vertical list. Make it walk up
   `enclosingScrollView` to the first scroll view that can scroll sideways (its document is wider than
   its clip view). The page slides with the strip's spring; under Reduce Motion it switches without
   motion. At the first or last page the swipe does nothing.
7. **Page dots.** At the bottom of the page, above the footer: one 6 pt dot per open page, 6 pt
   apart, the current one in primary text color, the others tertiary. A click on a dot switches.
   Hidden when one page is open. Each dot's accessibility label is the session name.
8. **Page header.** The session name (11 pt, secondary) and, at the trailing end, a `+` that makes a
   new workspace in that session: `workspace.create {cwd: $HOME, focus:false}`, then read the snapshot
   and select it.

### Workspace rows

9. **Rows.** One row per herdr workspace of the page's session, in herdr's order.
   - Line 1: a 14 pt state slot (phase 15 draws the state icons; empty in this phase) and the name
     (13 pt).
   - Line 2, only for a git repository: `arrow.triangle.branch` (10 pt), the branch, then ↑ahead in the
     finished color and ↓behind in the error color (phase 10) when nonzero, all 11 pt secondary. No changed-file count. A
     workspace that is not a git repository has one line and no text about git.
   - 44 pt with two lines, 30 pt with one, 2 pt apart. The selected workspace is the phase 10 pill
     (radius 10).
   - Accessibility value: "‹branch› ahead N behind M" when known, plus "worktree of ‹parent›" for a
     child.
10. **Linked worktrees.** Decode the workspace's worktree fields from the snapshot
   (`worktree.is_linked_worktree`, `worktree.repo_key`, `worktree.checkout_path`; herdr 0.9.5's schema
   has them). Spike: does herdr fill `workspace.worktree` for a plain `workspace.create {cwd}` in a
   repository, or only for `worktree.open` / `worktree.create`? Record it. A linked worktree shows right after the workspace that has the same
   `repo_key` and is not a linked worktree, indented 14 pt, with a 1 pt guide line in the separator
   color from the parent's state slot down. herdr's own order wins otherwise. With no parent in the
   session, it is a normal row.
11. **Git data.** For each workspace: root = `worktree.checkout_path`, else the cwd of the workspace's
    first pane. The app runs `git -C <root> status --porcelain=v2 --branch` on the machine through
    `Exec.run` (find `git` the way the app finds herdr, in the login shell's `PATH`; 5 s timeout). It
    reads `# branch.head` (when `(detached)`, the first 7 characters of `# branch.oid`) and
    `# branch.ab +A -B`. A nonzero exit means not a repository. The parser is one function, unit
    tested (it branches). Check once at launch: if `xcode-select -p` fails, or `git` resolves only to
    the `/usr/bin` stub without the Command Line Tools, skip git data (rows have one line), so the
    "install developer tools" dialog never opens. When it runs:
    - for a workspace that is new, or whose root (`checkout_path` or first pane cwd) changed;
    - every 10 s for every workspace of the page in view, while the window is visible;
    - never for a page that is not in view; one run per workspace at a time.
12. **Click** selects the workspace (the app's own selection, never herdr focus, D13); the tab bar
    and the strip show its tabs.
13. **Context menu:** New Tab (`tab.create {workspace_id, cwd, focus:false}`, cwd of that workspace's
    keyboard card or `$HOME`), Rename Workspace (inline field in place of the name, Enter saves with
    `workspace.rename {workspace_id, label}`, Esc cancels; a double-click on the name also starts it),
    Move Up and Move Down (`workspace.move {workspace_id, insert_index}`; a workspace with worktree
    children moves with them: `workspace.move_block {workspace_ids, before_workspace_id}`), Close
    Workspace (always asks with the tab and pane count, D41; `workspace.close {workspace_id}`; spike
    what it does on a worktree parent, with and without `close_group`, and record it). Read the
    snapshot after each write. Drag to reorder comes in phase 18.

### Size and footer

14. **Width.** 240 pt default. A 6 pt handle at the sidebar's trailing edge resizes it between 227 and
    480 pt, with the resize cursor (`.pointerStyle(.columnResize)`). Kept per window (`@SceneStorage`). The strip keeps its pages whole
    during the drag (pages are the strip's width).
15. **Scroll fade.** 18 pt fades at the top and bottom of the scrolling list when content is under
    them.
16. **Footer.** The filter field and one button, Open Session (`plus.square.on.square`,
    `.help("Open Session ⇧⌘N")`). The filter keeps the rows whose name or branch matches; a matching worktree
    child also keeps its parent. Today's New Workspace and Add Remote Host buttons go away (the page
    header has `+`; the machine menu has Add Remote Host).
17. **Remove** the workspace sections and their collapse state (phase 13 removed the tab rows), and
    `SessionPicker` with its title-row button.

18. **Empty page.** A session with no workspace shows only a New Workspace button in the strip and on the
    page (today `OrielApp.swift` says "No workspaces. Create one in herdr:"). The user never needs herdr
    (the window design (`docs/content/docs/ui/window.mdx`), "Never send the user to herdr"). Add a SwiftLint custom rule that fails on a
    user-visible string literal telling the user to run herdr (for example `"herdr ` or `in herdr` inside
    `Text(`, `Label(`, `message(`, `Button(`), so it cannot come back.

### Open Session sheet

18. A sheet on the window titled "Open Session", 420 pt wide. The footer button, the workspace menu's
    "Open Session…" and File ▸ Open Session… (⇧⌘N) open it. It replaces `SessionPicker` and
    `SessionList`. Today's File ▸ "New Session" (⇧⌘N) item becomes "Open Session…" and opens the sheet
    (an entry in phase 13's command list). It reuses the phase 13 filter-list view.
    - A text field "Name a new session, or find one", empty and with the keyboard at first.
    - The list, filtered by the field, read once when the sheet opens (`sessions()`), in groups with
      the headers "New", "Running", "Stopped" and "Open in this window":
      1. "Create session “‹typed name›”" when the text is a valid herdr name (`Session.isValidName`)
         that no session has; with an empty field, "Create session “‹two-word name›”" with today's
         suggested name (`lunar-ridge`).
      2. Running sessions not open in this window.
      3. Stopped sessions.
      4. Sessions already open in this window, last.
      No hint text on the rows ("opens it", "starts it"): the group headers say it (orchestrator).
    - Arrows move, Enter or the **Open** button acts on the highlighted row; Cancel or Esc closes.
      Create, a running session and a stopped session take one path: start the server if it is not
      running (launchd job, D47; the app makes its first workspace in `$HOME`, as `HostStore.run`
      does today), then add its page after the current one and show it; its store connects. An open
      session: show its page.
    - While a server starts, the row shows a spinner; a failure shows today's notice and keeps the
      sheet open (phase 21 adds the final wording).
19. The workspace menu (phase 13) gets one group per open page, in page order, the branch from the git
    data on each row, and "Open Session…" with "⇧⌘N" on the right after New Workspace. Picking a workspace of another page shows that page and selects it.
20. The window title is "‹tab title› - ‹session of the page in view›".

### Docs

21. Rewrite the sidebar part of `ui/window.mdx` (pages, workspace rows, footer, Open Session sheet),
    `layout.mdx` (selection is per page), `data.mdx` (open pages and width in `@SceneStorage`),
    `ui/swiping.mdx` (the sidebar swipe pages sessions), `talking-to-herdr.mdx` (git status,
    `workspace.move_block`, the writes table), `machines.mdx` (sessions open as pages). D43 (open
    pages), D67 (git status) and D68 (the sheet) are already recorded: change them if the build
    differs.

## Findings

### Deviations

- **No hint text on the sheet's rows** (orchestrator, after the rough screenshot): no "opens it", "starts it" or
  "open"; the group headers say it. Tests check a row's group by its place between the headers
  (`open-session.section.<header>`).
- **Move Up and Move Down are one `workspace.move_block`** for a single workspace too: `before_workspace_id` is the
  next group's first workspace (or none, for last), so there is no index arithmetic. A worktree row has them
  disabled: it sits under its repository in any herdr order.
- **`--untracked-files=no` and `--no-optional-locks`** on the git run: the rows show no file counts, and the
  untracked scan is the slow part in a big repository; without optional locks a run every 10 s cannot leave
  `index.lock` in the way of the user's own `git commit` (spec review; VS Code does the same). Workspaces run one
  after another, not all at once.
- **git is usable unless** it resolves only to `/usr/bin/git` and `xcode-select -p` fails; a git elsewhere in the
  login shell's PATH (Homebrew) runs without the developer tools.
- **The first page always starts its session** (`start: true`); a server that already runs is left alone, and only
  a server the app started gets its first workspace (`startServer()` now returns whether it started one). A failed
  start shows its error and connects anyway, so the page says "not running" with Start instead of a dead end.
- **`-session` on the command line wins over restored pages** (E2E review): a run against a throwaway session must
  never reopen `default` or another session from an earlier window. It is read from the argument domain only.
- **The Start button no longer replaces the store**: `HostStore.start()` starts the server and the running store's
  health check finds it again.
- **The width handle sits beside the pages** (the sidebar's last 6 pt), not over the pages' scroll view or the strip.
- **The palette's sessions open as pages** (phase 20 rebuilds the palette).
- **The not-running page says "Start it to see its workspaces."** with the Start button, no herdr command; why a
  start failed shows under it. A stopped session keeps its last rows, with their write menu items disabled.
- **"herdr update" stays** on the too-old page: it updates herdr itself, not a session; phase 21 words the failure
  pages. The lint rule matches one line, so a string wrapped onto the next line passes (a regex limit).
- **The double-click to rename is on the whole row**, as the tab capsules (phase 13: a tap gesture on a short title
  missed most double-clicks).

### Decisions

- **Types:** `Page` (one session's page in a window: its store, the selection, zoom, the strip offset, keyboard cards,
  `arriving`) and `WindowPages` (the ordered pages, the one in view, the window's one `PaneViewRegistry`) in
  `Oriel/Store/Page.swift`. The store registry is a private static dictionary in `HostStore` (`named(_:start:)`,
  `disconnect()`). After each snapshot the store calls `onSnapshot`; the window settles that page's selection and
  shows the terminals. Phase 16 makes it a list for several windows.
- **Ids:** `sidebar`, `sidebar.header` (a static text; XCUITest gives its text as the value), `sidebar.new-workspace`,
  `sidebar.dot.<session>` (selected trait on the current one), `sidebar.open-session`, `sidebar.resize`,
  `new-workspace` (the empty page's button, in the page and the strip), `workspace.<id>.rename`; the sheet:
  `open-session.filter`, `open-session.new.<name>`, `open-session.session.<name>`, `open-session.open.<name>`,
  `open-session.open`, `open-session.notice`; the workspace menu's rows are `workspaces.<session>.<workspace id>`.
  Pages not in view are hidden from accessibility, so ids repeat safely across pages.
- **Scene storage keys:** `pages` (names joined by spaces: herdr names have none), `page`, `sidebarWidth`.
- **Sheet rows** show a symbol (`plus` for Create, `plus.square.on.square` for sessions, `checkmark` for the open
  ones), as the mock-up does, so their titles line up under the group headers.
- **A menu row's detail truncates** (middle) instead of keeping its full width, so a long branch in the workspace
  menu gives way to the title.
- **Visible window** = `scenePhase == .active`. The git refresh is one `.task(id:)` in `ContentView` keyed by the
  page in view while active: it sets the store's `showsGit`, runs now and every 10 s, and SwiftUI cancels it.
- **Look:** `finished` (`#3fb950` / `#116329`) and `error` (`#f85149` / `#cf222e`) tokens, for ↑ahead and ↓behind.
- **Lint rule `herdr_commands`:** a `Text(`, `Label(`, `message(` or `Button(` line whose string literal has
  `herdr --`, `herdr session|workspace|tab|pane|server|attach` or `in herdr` fails. "herdr update" (updating herdr
  itself) and "Restart herdr on This Mac" (a button) pass.
