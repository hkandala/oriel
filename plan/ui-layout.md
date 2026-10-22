# Main window layout (agreed with the user)

The source of truth for the window's layout in phases 10–21. The mock-ups are
`plan/mockups/layout.html` (scenes A–J; `plan/mockups/build.py` rebuilds them). Where this file and an
older design page disagree, this file wins until the page is updated.

## Words

| Word | Meaning now |
|---|---|
| machine | a host: This Mac now, SSH hosts later. Each has its own icon |
| session | one herdr server on a machine (`default`, `pi-herd`, …) |
| page | one session's page in the sidebar |
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
- **Machine button** (title row, after the sidebar toggle): the machine's icon and a small chevron, no name.
  Its menu lists the machines with icon and name, a checkmark on the current one, then "Add Remote Host…"
  (a placeholder until remote machines are built). Picking a machine replaces the window's sessions with
  that machine's. ⌥-click on a machine opens it in a new window; the menu does not show this as an item.
- Adding a remote host (later) asks for a name, the SSH target and an icon (laptop, desktop, server, cloud,
  chip, house, flask, game controller), because the button shows only the icon.

## Title row (always the same row; 40 pt)

Left to right:

1. Traffic lights.
2. **Sidebar toggle** (⌃⌘S). No highlight when the sidebar is open: the icon changes instead (an outline
   window with a sidebar line when closed; the sidebar part filled when open). Always shown.
3. **Machine button** (above).
4. **Workspace button**, only while the sidebar is collapsed: an outline folder icon, then
   "‹session› | ‹workspace›" (session dimmed, a thin vertical line, workspace in primary text), a chevron.
   Its menu: a filter field ("Filter or create…"), every workspace of every running session on the machine,
   **grouped under a session header** (rows show only the workspace's state icon, its name and its branch on
   the right), then New Workspace and "Open Session…" (⇧⌘N).
5. **Tab bar**: the selected workspace's tabs, always in the title row, whether the sidebar is open or
   collapsed (phase 13 has the tab geometry from Rex). A tab with several panes shows its panes' program
   icons **overlapping** (up to 5, 4 pt apart, the keyboard card's icon in front); a one-pane tab shows one
   icon.
6. Spacer.
7. **Agents button**: outline chat bubbles. The first bubble fills while the Agents view is on (no
   highlight). An amber dot when an agent of the current session needs you. ⌘. toggles the Agents view.
   - **Hover** (0.25 s): a popover under the button lists the agents of the current session that need you
     (same rows as the Agents view). A click on one goes straight to its workspace, tab and pane; the sidebar
     does not change. With nobody waiting: "Nobody needs you". No footer text.
8. **⌘** (command palette, ⌘K) and **+** (new tab, ⌘T).

The strip under the title row still pages sideways between the selected workspace's tabs (swipe, ⇧⌘[ ⇧⌘],
⌃⇥).

## Sidebar (Arc-style pages, one per running session)

- One page per **running** herdr session on the window's machine. A sideways swipe on the sidebar moves to
  the next or previous session; page dots at the bottom of the page show where you are, and a click on a dot
  switches. Swiping the sidebar never pages the strip, and the reverse.
- **Page header**: the session's name (small, secondary) and a `+` that makes a new workspace in that session.
- **Workspaces view** (default): one row per herdr workspace of the session, in herdr's order, like herdr's
  Spaces panel.
  - Line 1: the rolled-up state icon (needs you: amber dot; working: the three working dots; finished and not
    seen: green dot; idle agent: gray ring; no agent: nothing) and the workspace name.
  - Line 2, only for a git repository: a branch glyph, the branch, then ↑ahead (green) and ↓behind (red)
    when nonzero. No changed-file count. A workspace that is not a git repository has one line and no text
    about git.
  - Rows are 44 pt with two lines, 30 pt with one. The selected workspace is the raised pill.
  - A workspace herdr marks as a linked git worktree (`worktree.is_linked_worktree`, same `repo_key`) sits
    indented under the workspace of its repository, with a thin guide line, as in herdr.
  - Git data: the app runs `git -C <root> status --porcelain=v2 --branch` on the machine through `Exec.run`
    (root = `worktree.checkout_path`, else the cwd of the workspace's first pane). It runs when a snapshot
    changes and every 10 s for the page in view, one run per workspace, never for hidden pages.
  - Click: select the workspace (app only, never herdr focus). Context menu: New Tab, Rename Workspace,
    Move Up, Move Down, Close Workspace. Double-click the name to rename. Drag to reorder (phase 18).
- **Agents view** (the Agents button): the same page, listing the agents of **that session only**; a sideways
  swipe shows the next session's agents.
  - Header: "‹session› · agents" and a sort menu: **Priority** (groups Needs you, Working, Done, Idle, each
    with a count) or **Workspace order** (herdr's order).
  - One row per agent pane, even when several share a tab. Row 44 pt: the program tile with its badge, the
    agent's name, the status capsule on the right ("Needs you" amber, "Working" blue, "Done" green, "Idle"
    gray); line 2 "‹workspace› · ‹tab›" and the age ("now", "3m", "2h").
  - Idle agents show by default. A click goes to that workspace, tab and pane, and records a finish as seen.
- **Footer**: the filter field (filters the rows of the current view) and one button, **Open Session**
  (⇧⌘N), which opens the sheet below. No New Workspace and no Add Remote Host here.
- Width 240 pt, resizable 227–480 pt (kept per window).

## Open Session sheet

The one place to create or open a session. The footer's Open Session button, the workspace menu's
"Open Session…" and ⇧⌘N open it. The UI never says "New or Open"; the sheet is titled "Open Session".
- A text field ("Name a new session, or find one"), empty at first.
- The list, filtered by the field:
  - **New**: "Create session “‹typed name›”" when the text is a valid new herdr name; with an empty field,
    "Create session “‹two-word name›”" with a suggested name.
  - **Stopped** sessions ("starts it") and **Running** sessions.
- Arrows move, Enter or **Open** acts on the highlighted row: create and start a new session and open its
  page; start a stopped session (launchd job, D47) and open its page; open a running session's page. Cancel
  or Esc closes.

## Moving panes, tabs and workspaces by drag and drop

What herdr 0.9.5 allows (tested on a throwaway session, October 2026):

| herdr call | Allowed | Refused |
|---|---|---|
| `pane.swap {source_pane_id, target_pane_id}` (or `{pane_id, direction}`) | two panes of the **same tab** | panes of different tabs (`changed:false`, `reason:"cross_tab"`) |
| `pane.move {destination:{type:"tab", tab_id, split: right\|down, target_pane_id?, ratio?}}` | into **another tab** of any workspace of the session, beside `target_pane_id` (or the tab's whole layout when omitted), with an optional ratio | into its own tab (`reason:"same_tab"`) |
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
| a tab capsule in the title row | the tab pages into view after 0.65 s (spring-loading), so the drop lands on a card there; a drop on the capsule itself moves the pane into that tab, split right of its layout | `pane.move {type:"tab", split:"right"}` |
| an edge of a card in another tab (after spring-loading) | split beside that card | `pane.move {type:"tab", tab_id, split, target_pane_id}`, then `pane.swap` for left or top |
| the empty end of the tab track, or the `+` | a new tab in the selected workspace | `pane.move {type:"new_tab", workspace_id}` |
| a workspace row in the sidebar | a new tab in that workspace; holding 0.65 s selects the workspace instead, so its tabs show and the drop can go on a capsule or card | `pane.move {type:"new_tab", workspace_id}` |
| empty space at the bottom of the sidebar page | a new workspace | `pane.move {type:"new_workspace"}` |
| another session's page dots, the Agents view | not a target (the pointer shows it) | — |

Tabs and workspaces:

| Drag | Result | herdr call |
|---|---|---|
| a tab capsule along the tab track | reorder the workspace's tabs | `tab.move` |
| a tab capsule onto a workspace row | not a target: herdr moves tabs only inside a workspace | — |
| a workspace row up or down its page | reorder the session's workspaces (a worktree child moves with its parent group) | `workspace.move` (`workspace.move_block` for a group) |

The look and timings (drop indicator, preview, spring-load pulse) are in phase 18.

## Removed by this layout

- Tabs as sidebar rows, workspace sections with collapse chevrons, keycap hints on sidebar rows.
- The Activity filter (eye button), "Show idle agents" and any status area at the bottom of the sidebar.
- The session picker in the title row (sessions are sidebar pages; stopped ones are in the sheet).
- New Workspace and Add Remote Host in the sidebar footer.
- "One main window" (D34).
