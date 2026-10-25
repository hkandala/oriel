# Main window layout (agreed with the user)

The source of truth for the window's layout in phases 10–21. The mock-ups are
`resources/mockups/layout.html` (scenes A–K; `resources/mockups/build.py` rebuilds them). Where this file and an
older design page disagree, this file wins until the page is updated.

## Never send the user to herdr

Everything a user does with sessions, workspaces, tabs, panes and (later) remote machines is done in the
app. No text in the UI tells the user to run a herdr command; where there is nothing yet (no workspace, no
tab), the app shows the button that makes it. The one exception: when herdr is not installed, the page shows
the install command (`curl -fsSL https://herdr.dev/install.sh | sh`), because the app cannot install herdr.

## Words

| Word | Meaning now |
|---|---|
| machine | a host: This Mac now, SSH hosts later. Each has its own icon |
| session | one herdr server on a machine (`default`, `pi-herd`, …) |
| page | one session's page in the sidebar; a window shows only the sessions the user opened in it |
| window | an Oriel window; it shows one machine |

## Windows and machines

- Each window shows one machine. The user can open several windows (File ▸ New Window, ⌘N, opens a window
  on the same machine). Two windows can show different machines, or the same machine.
- Two windows on the same machine share the live data of each session. Each window keeps its own
  selection: page, workspace, tab, keyboard card, zoom, sidebar view and sidebar width.
- **Control is per session.** When two windows show the same session, the window where the user last typed
  or clicked in a terminal controls that session's panes (herdr `control` streams). The other window watches
  (`observe`), dims its cards a little, and shows a bottom capsule "Controlled in another window" with
  **Take Back**. Two windows on different sessions each control their own session.
- **Machine button** (title row, after the sidebar toggle): the machine's icon only: no chevron (phase 22, the
  user), no name. Its menu lists the machines with icon and name, a checkmark on the current one, then "Add
  Remote Host…" (a placeholder until remote machines are built). Picking a machine replaces the window's
  sessions with that machine's. ⌥-click on a machine opens it in a new window; the menu does not show this as
  an item.
- Adding a remote host (later) asks for a name, the SSH target and an icon (laptop, desktop, server, cloud,
  chip, house, flask, game controller), because the button shows only the icon.

## Title row (always the same row; 46 pt, as in Rex)

Left to right. While the sidebar is open, the traffic lights, the sidebar toggle and the machine button sit in a
leading area as wide as the sidebar (it follows the resize handle live), so the first tab capsule starts where the
cards start. With the sidebar collapsed the items follow one another as before.

1. Traffic lights.
2. **Sidebar toggle** (⌃⌘S). No highlight when the sidebar is open: the icon changes instead (an outline
   window with a sidebar line when closed; the sidebar part filled when open). Always shown.
3. **Machine button** (above).
4. **Workspace button**, only while the sidebar is collapsed: an outline folder icon, then
   "‹page title› | ‹workspace›" (the machine's name for `default`; title in the row's chrome color, a thin vertical line, workspace a step brighter), a chevron.
   Its menu: a filter field ("Filter or create…"; a typed name that matches nothing offers
   "New Workspace “‹text›”"), every workspace of every session open in this window,
   **grouped under a session header** (rows show only the workspace's state icon, its name and its branch on
   the right), then New Workspace and "Open Session…" (⌥⌘T).
5. **Tab bar**: the selected workspace's tabs, always in the title row, whether the sidebar is open or
   collapsed (phase 13 has the tab geometry from Rex). A tab with several panes shows its panes' program
   icons **overlapping** (up to 5, 4 pt apart, the keyboard card's icon in front); a one-pane tab shows one
   icon.
6. Spacer.
7. **Agents button**: a list of statuses (`list.bullet.rectangle`), filled while the Agents view is on (no
   highlight; phase 22, the user: the chat bubbles did not fit). An amber dot when an agent of the current
   session needs you. A click (or ⌘.) toggles the Agents view; with the sidebar collapsed, a click opens the
   sidebar in the Agents view. No tooltip (the hover panel takes its place).
   - **Hover** (0.25 s): a panel under the button with a small header "Needs you · ‹page title›" (the machine's name for `default`) lists the
     agents of the current session that need you (same rows as the Agents view). A click on one goes straight to its workspace, tab and pane; the sidebar
     does not change. With nobody waiting: no panel (phase 25). No footer text.
8. **⌘** (command palette, ⌘K; ⇧⌘P also opens it (Rex's key); its field says "Search") and **+** (new tab, ⌘T).

The strip under the title row still pages sideways between the selected workspace's tabs (swipe, ⇧⌘[ ⇧⌘],
⌃⇥).

## Sidebar (Arc-style pages, one per session open in the window)

- **Open sessions, not all sessions.** A window starts with one page: the machine's `default` session
  (started if it is stopped). It never loads the other sessions by itself, so a machine with many sessions
  costs nothing until the user asks. The user adds more pages with **Open Session** (the panel below); each
  opened session gets a page, as many as the user likes. Only open pages have a store, a snapshot read and
  an event stream.
- **Closing a page**: the context menu of the page header and of its page dot has "Detach Session". It only
  removes the page from this window (its store disconnects); the herdr session keeps running and stays in
  the panel's list. The last page cannot be closed.
- **Restore**: after any quit (the app registers `NSQuitAlwaysKeepsWindows`), a window that macOS restores reopens the pages it had (their names in `@SceneStorage`); a
  name that no longer runs is skipped. A new window (⌘N) opens with `default` only.
- A sideways swipe on the sidebar moves to the next or previous open page; page dots at the bottom show
  where you are, and a click on a dot switches. Swiping the sidebar never pages the strip, and the reverse.
- **Page header**: the session's name (small, secondary) and a `+` that makes a new workspace in that session.
- **Workspaces view** (default): one row per herdr workspace of the session, in herdr's order, like herdr's
  Spaces panel.
  - Line 1: the rolled-up state icon (needs you: amber dot; working: the three working dots; finished and not
    seen: green dot; idle agent: gray ring; no agent: a quiet 4 pt dot, phase 22) and the workspace name.
  - Line 2, only for a git repository: a branch glyph, the branch, then ↑ahead (green) and ↓behind (red)
    when nonzero. No changed-file count. A workspace that is not a git repository has one line and no text
    about git.
  - Rows are 44 pt with two lines, 30 pt with one. The selected workspace is the raised pill.
  - A workspace herdr marks as a linked git worktree (`worktree.is_linked_worktree`, same `repo_key`) sits
    indented under the workspace of its repository, with a thin guide line, as in herdr.
  - Git data: the app runs `git --no-optional-locks -C <root> status --porcelain=v2 --branch --untracked-files=no` on the machine through `Exec.run`
    (root = `worktree.checkout_path`, else the cwd of the workspace's first pane). It runs when a workspace
    is new or its root changed, and every 10 s for the page in view, one run per workspace, never for hidden pages.
  - Click: select the workspace (app only, never herdr focus). Context menu: New Tab, Rename Workspace,
    Move Up, Move Down, Close Workspace. Double-click the name to rename. Drag to reorder (phase 18).
- **Agents view** (the Agents button): the same page, listing the agents of **that session only**; a sideways
  swipe shows the next session's agents.
  - Header: the session's name (a `default` session shows its machine's name: This Mac's own name or the
    remote machine's; phase 27) and a sort button: **Priority** (groups Needs you, Working, Done, Idle, each
    with a count) or **Workspace** (a group per workspace under its name and count, herdr's order). The name is the
    title (13 pt bold, the rows' size, primary, also in the workspaces view); the sort button is a capsule filled on
    hover; the group labels are 10 pt semibold section labels with room above; no line under the header (phase 25).
    A click on a group label folds its rows (a chevron at its end); a folded group keeps its label and count; the
    folds are kept per session and order across relaunches (phase 27).
  - One row per agent pane, even when several share a tab. Row 48 pt, 4 pt apart, the program tile with its
    badge centered on both lines. Line 1: the pane's name, else the agent's name, then on the right the status capsule ("Needs you"
    amber, "Working" blue, "Done" green, "Idle" gray) and the age ("now", "3m", "2h"), on one centered line;
    line 2 "‹workspace› · ‹tab›" (only "‹tab›" in Workspace order). The header and the sort menu share a
    baseline (phase 24). The row of the shown tab's keyboard card is lit like the selected workspace row.
  - Idle agents show. A click goes to that workspace, tab and pane, and records a finish as seen.
- **Footer**: the filter field (filters the rows of the current view) and one button, **Open Session**
  (⌥⌘T), which opens the panel below. No New Workspace and no Add Remote Host here.
- Width 240 pt, resizable 227–480 pt (kept per window).

## Open Session panel

The one place to create or open a session. The footer's Open Session button, the workspace menu's
"Open Session…" and ⌥⌘T open it. A glass panel like the palette (phase 22, the user): no title, no buttons.
- A text field ("Name a new session, or find one"), empty at first.
- The list, filtered by the field, in groups with the headers "New", "Running", "Stopped" and "Open in this window":
  - **New**: "Create session “‹typed name›”" when the text is a valid new herdr name; with an empty field,
    "Create session “‹two-word name›”" with a suggested name.
  - **Running** sessions not open in this window and **Stopped** sessions; the sessions already open in this
    window last (Enter switches to their page). The rows carry no hint text: the group headers say it.
  - The lit row's button: Stop (running) and Delete (stopped), red, both ask first; Detach (open in this
    window, not its last page), plain (phase 25).
- The arrows or the pointer move the highlight, Enter or a click acts on a row: create and start a new session and open its
  page; open a running session as a new page (its store connects then); start a stopped session
  (launchd job, D47) and open it as a new page; switch to a page that is already open. Esc or a click outside closes.
- One panel at a time: opening it closes the palette or the workspace menu, and the reverse.

## Moving panes, tabs and workspaces by drag and drop

What herdr 0.9.5 allows (tested on a throwaway session, October 2026):

| herdr call | Allowed | Refused |
|---|---|---|
| `pane.swap {source_pane_id, target_pane_id}` (or `{pane_id, direction}`) | two panes of the **same tab** | panes of different tabs (`changed:false`, `reason:"cross_tab"`) |
| `pane.move {destination:{type:"tab", tab_id, split: right\|down, target_pane_id?, ratio?}}` | into **another tab** of any workspace of the session, beside `target_pane_id` (or, when omitted, the tab's focused pane), with an optional ratio | into its own tab (`reason:"same_tab"`) |
| `pane.move {destination:{type:"new_tab", workspace_id?, label?}}` | a new tab in any workspace of the session | — |
| `pane.move {destination:{type:"new_workspace", label?, tab_label?}}` | a new workspace | — |
| `tab.move {tab_id, insert_index}` | reorder inside its workspace | moving a tab to another workspace |
| `workspace.move {workspace_id, insert_index}` / `workspace.move_block` | reorder workspaces | — |

Notes: a pane moved to another workspace gets a new pane id (its terminal id stays, so its card stays).
Moving a tab's last pane closes that tab. Nothing moves between sessions or machines (separate herdr
servers). herdr splits only right or down, so a drop on a left or top edge is a move (or split) followed by
a swap.

Drag a card by its header (4 pt to start). Every target Oriel offers:

| Drop on | Result | herdr calls |
|---|---|---|
| the center of another card in the same tab | swap the two | `pane.swap` |
| the left, right, top or bottom edge of another card in the same tab | re-place the pane beside that card | `pane.move` to a new tab, then `pane.move` back beside the target (right or down), then `pane.swap` for left or top. If a later step fails, the pane stays where it got to and the notice says so |
| another tab's capsule in the title row | the tab pages into view after 0.65 s (spring-loading), so the drop lands on a card there; a drop on the capsule itself moves the pane into that tab, split right of its last card | `pane.move {type:"tab", split:"right", target_pane_id}` |
| the pane's own tab capsule | not a target (herdr refuses `same_tab`) | — |
| an edge of a card in another tab (after spring-loading) | split beside that card | `pane.move {type:"tab", tab_id, split, target_pane_id}`, then `pane.swap` for left or top |
| the empty end of the tab track, or the `+` | a new tab in the selected workspace | `pane.move {type:"new_tab", workspace_id}` |
| a workspace row in the sidebar | a new tab in that workspace; holding 0.65 s selects the workspace instead, so its tabs show and the drop can go on a capsule or card | `pane.move {type:"new_tab", workspace_id}` |
| empty space at the bottom of the sidebar page, or the page header's `+` | a new workspace | `pane.move {type:"new_workspace"}` |
| another session's page dots, the Agents view | not a target (the pointer shows it) | — |

Tabs and workspaces:

| Drag | Result | herdr call |
|---|---|---|
| a tab capsule along the tab track | reorder the workspace's tabs | `tab.move` |
| a tab capsule onto a workspace row | not a target: herdr moves tabs only inside a workspace | — |
| a workspace row up or down its page | reorder the session's workspaces (a worktree child moves with its parent group) | `workspace.move_block` with the row's group |
| a worktree row among its repository's worktrees | reorder those worktrees only | `workspace.move_block` |

Every `pane.move` passes `focus:false`. The look and timings (drop indicator, preview, spring-load pulse) are in
phase 18.

## Removed by this layout

- The Settings window, for now: the few settings are menu items (D62); the window comes after its mock-ups.
- Tabs as sidebar rows, workspace sections with collapse chevrons, keycap hints on sidebar rows.
- The Activity filter (eye button), "Show idle agents" and any status area at the bottom of the sidebar.
- The session picker in the title row (sessions are sidebar pages; stopped ones are in the Open Session panel).
- New Workspace and Add Remote Host in the sidebar footer.
- "One main window" (D34).
