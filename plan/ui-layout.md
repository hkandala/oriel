# Main window layout (as built)

A short map of the main window as the app builds it after phase 31. It started as the layout the user
agreed for phases 10–21, with the mock-ups in `resources/mockups/layout.html` (scenes A–K;
`resources/mockups/build.py` rebuilds them). The mock-ups show phase 10's plan, not every later change.
The full spec, with every size and timing, is [Main window](../docs/content/docs/ui/window.mdx) and the
pages it links. Where this file and a design page disagree, the design page wins.

## Never send the user to herdr

Everything a user does with sessions, workspaces, tabs, panes and remote machines is done in the app. No
text in the UI tells the user to run a herdr command. Where there is nothing yet (no workspace, no tab),
the app shows the button that makes it. The one exception: when herdr is not installed, the page shows
the install command (`curl -fsSL https://herdr.dev/install.sh | sh`), because the app cannot install herdr.

## Words

| Word | Meaning |
|---|---|
| machine | a host: This Mac, or a remote machine that the app reaches over SSH. Each has its own icon |
| session | one herdr server on a machine (`default`, `pi-herd`, …) |
| page | one session's page in the sidebar. A window shows only the sessions the user opened in it |
| window | an Oriel window. It shows one machine |

## Windows and machines

- Each window shows one machine. File ▸ New Window (⌘N) opens a window on the same machine. Two windows
  can show different machines, or the same machine. A new window opens at 90 % of the screen, at least
  1200 × 760 pt.
- Two windows on the same machine share the live data of each session. Each window keeps its own
  selection: page, workspace, tab, keyboard card, zoom, sidebar view and sidebar width.
- **Control is per session.** When two windows show the same session, the window where the user last typed
  or clicked in a terminal controls that session's panes (herdr `control` streams). The other window watches
  (`observe`), dims its cards a little, and shows a bottom capsule "Controlled in another window" with
  **Take Back**.
- **Machine button** (title row, after the sidebar toggle): the machine's icon only, with no chevron and no
  name. Its menu lists the machines with icon and name, a checkmark on the current one, then "Open
  Session…", "Add Remote Host…" and "Edit Remote Host ▸". Picking another machine brings its window
  forward, else opens a new one on it. This window keeps its sessions.
- Adding a remote host asks for a name, the SSH target and an icon from a searchable grid of SF Symbols
  ([Add a machine](../docs/content/docs/ui/add-a-machine.mdx)), because the button shows only the icon.

## Title row (one row, 46 pt, as in Rex)

While the sidebar is open, the traffic lights, the sidebar toggle and the machine button sit in a leading
area as wide as the sidebar, so the first tab capsule starts where the cards start. From left to right:

1. Traffic lights.
2. **Sidebar toggle** (⌃⌘S). The icon changes with the sidebar's state; there is no highlight.
3. **Machine button** (above).
4. **Workspace button**, only while the sidebar is collapsed: a folder icon, "‹page title› | ‹workspace›"
   (the machine's name for `default`) and a chevron. Its menu: a filter field ("Filter or create…"), every
   workspace of every session open in this window, grouped under a session header, then New Workspace and
   "Open Session…" (⌥⌘T).
5. **Tab bar**: the selected workspace's tabs, always in the title row. Tabs are 220 pt and never shrink;
   the bar scrolls sideways when they do not fit. A tab with several panes shows its panes' program icons
   overlapping (up to 5, the keyboard card's in front).
6. Spacer.
7. **Agents button** (`list.bullet.rectangle`, filled while the Agents view is on). An amber dot when an
   agent of the current session needs you. A click (or ⌘.) toggles the Agents view. A rest of 0.25 s shows a
   panel with the agents that need you, then those done. With both groups empty, no panel.
8. **Overview** button (⌃⌘O).
9. **⌘** (command palette, ⌘K or ⇧⌘P) and **+** (new tab, ⌘T).

While the overview is open, the row shows only the traffic lights and one × that leaves it.

## Strip

- One page per tab of the selected workspace, each with its pane cards in herdr's split tree, 8 pt apart.
  A two-finger swipe, ⇧⌘[ ⇧⌘] or ⌃⇥ pages between tabs.
- A three-finger swipe sideways moves between sessions; up or down moves to the workspace above or below,
  or in the Agents view to the agent row above or below
  ([Swiping](../docs/content/docs/ui/swiping.mdx)).
- Card headers carry Float Pane, Split Right, Split Down, Zoom and Close. ⌘F opens the find bar on the
  keyboard card.

## Sidebar (Arc-style pages, one per session open in the window)

- **Open sessions, not all sessions.** A window starts with one page: the machine's `default` session
  (started if it is stopped). The user adds more pages with **Open Session**. Only open pages have a store,
  a snapshot read and an event stream.
- **Detach Session** (the context menu of the page header and of its page dot, and the File menu) removes
  the page from this window. The herdr session keeps running. The last page cannot be detached.
- **Restore**: after any quit, a window that macOS restores reopens the pages it had. A new window (⌘N)
  opens with `default` only.
- A sideways swipe on the sidebar moves to the next or previous open page. Page dots at the bottom show
  where you are, and a click on a dot switches. Swiping the sidebar never pages the strip, and the reverse.
- **Page header**: the page's title (the session's name; the machine's name for `default`) and a `+` that
  makes a new workspace in that session.
- **Workspaces view** (default): one row per herdr workspace, in herdr's order. Line 1: the rolled-up state
  icon and the name. Line 2, only for a git repository: the branch, ↑ahead and ↓behind. A linked git
  worktree sits indented under its repository's row. The list scrolls to keep the selected workspace in
  view. A session with no workspace shows a New Workspace button.
- **Agents view** (the Agents button): the agents of that session only, sorted by Priority (Needs you,
  Working, Done, Idle) or by Workspace, in groups that fold. A click goes to the agent's pane.
- **Footer**: the filter field and one button, **Open Session** (⌥⌘T).
- Width 240 pt, resizable 227–480 pt, kept per window.

## Open Session panel

The one place to create or open a session. A glass panel like the palette, with no title and no buttons.
A text field ("Name a new session, or find one") filters the groups "New", "Running", "Stopped" and "Open in
this window" (in a remote window, "Running on ‹machine›" and "Stopped on ‹machine›"). Enter or a click
creates, starts or opens a session as a page, or shows a page already open. The lit row's button: Stop or
Delete (red, both ask first), or Detach. One panel shows at a time.

## Overview

Every tab of the window's sessions at a glance, live: one page per session, side by side, its workspaces
in the sidebar's order and their tabs as tiles. A tile is a miniature of the tab's cards with their live
terminals. A click on a tile shows that tab and leaves the overview
([Overview](../docs/content/docs/ui/window.mdx#overview)).

## Floating panes

Float Pane opens a pane in a small window of its own, with an optional Stay on Top. The pane stays in its
herdr tab; its card there shows "This pane is open in a floating window." with **Show Window** and **Bring
Back Here**. Other tools can float a pane with `oriel://float?…` or a float request
([Floating pane](../docs/content/docs/ui/window.mdx#floating-pane)).

## Drag and drop

A pane moves by dragging its card header: onto another card (swap, or an edge to re-place it), onto a tab
capsule (spring-loads after 0.65 s), onto the end of the tab track or `+` (a new tab), onto a workspace row
(a new tab there), or onto the empty end of the sidebar page (a new workspace). Tab capsules reorder along
the track and move whole to another workspace or a new one. Workspace rows reorder. Every move is built
from herdr's own calls, with `focus:false`; nothing moves between sessions or machines
([Drag and drop](../docs/content/docs/ui/drag-and-drop.mdx)).

## Not in the app

- A Settings window: the few settings are menu items (D62). It comes after its mock-ups.
- Tabs as sidebar rows, and workspace sections with collapse chevrons.
- An activity filter, "Show idle agents" or a status area at the bottom of the sidebar.
- A session picker in the title row: sessions are sidebar pages, and stopped ones are in Open Session.
- New Workspace and Add Remote Host in the sidebar footer.
- "One main window" (D34).
- Removed after they were built: Fade Inactive Panes (phase 25, D64), the hover card's live tab preview
  (phase 27: the overview took its place), ⌥ + swipe (phase 31).
