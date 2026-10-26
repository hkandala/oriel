# UI polish: every Rex interface feature, checked against Oriel and herdr

This file is the scope of phases 10–21. It lists every interface feature of Superlogical's Rex app
(build 1327, reverse engineered in October 2026) and says, for each one, whether Oriel builds it, in
which phase, and with which herdr call. It also lists what Oriel leaves out, and why.

The window's layout comes from [ui-layout.md](ui-layout.md), agreed with the user, with the mock-ups in
`resources/mockups/layout.html` (scenes A–K). Where this file and ui-layout.md disagree, ui-layout.md wins.

The Rex research is in `resources/research/clients/rex-ui.md` (UI, sizes, timings, materials) and
`resources/research/clients/rex-server.md` (protocol). Screenshots are in
`resources/inspirations/rex-app/`. The program icons are in `resources/icons/`.

Rules that hold for every phase:

- Oriel copies Rex's sizes, timings and behavior inside the layout of ui-layout.md. It does not copy
  Rex's files: no icon art, no theme files, no material files and no decompiled code go into the repo.
- herdr stays the only multiplexer. Rex as a second multiplexer is future work
  (`docs/content/docs/rex-backend.mdx`).
- The house rules still hold: every herdr argv carries `--session`, creates pass `focus:false`, the
  app never calls herdr's focus methods (D13), and after a write the app reads the snapshot again.
- No explanatory text in the UI: sheets, popovers and empty areas show only the text ui-layout.md
  lists.
- Each phase updates the design pages it changes, in the same commits as the code.

## What changes in the design

| Decision | Before | After (phases 10–21) |
|---|---|---|
| D44 look | Dark only, frosted | Appearance: Auto, Light or Dark. Interface style: Glass (the frosted look) or Classic (an opaque window). Still no glass on pane cards. No themes beyond one light and one dark terminal palette |
| D45 title row | Sidebar toggle, session picker, tab capsules only while the sidebar is hidden, eye, ⌘, + | Sidebar toggle (its icon shows the state), machine button, workspace button (sidebar collapsed only), the tab bar always in the title row, Agents button, ⌘, + |
| D34 windows | One main window | Several windows (⌘N). Each shows one machine; windows on one session share its data and keep their own selection. Control is per session (D66): the window with the last terminal input controls, the other watches with Take Back |
| Sidebar | Workspaces as sections with tabs as rows; one session; session picker | One Arc-style page per session open in the window, with page dots and a sideways swipe. Each page lists the session's workspaces like herdr's Spaces panel: state icon, name, git branch with ahead and behind, linked worktrees indented. Footer: filter and Open Session |
| Sessions | A session picker that switches the window's one session | The Open Session panel: create a session, start a stopped one, or open a running one as a new page. A window starts with `default` only |
| D42 status | A static ◔ in one status slot | Rex's three working dots (an animation at 15 fps or less, in sync on every tab, still under Reduce Motion), a status badge on the program icon for needs you and finished, and a state icon on each workspace row |
| Status area (status.mdx), D61 | A fixed list at the bottom of the sidebar; later the Activity filter (eye) | The Agents button (`list.bullet.rectangle`, filled while on; an amber dot when an agent of the current session needs you; phase 22 replaced the chat bubbles). Hover: a panel of the agents that need you. Click (⌘.): the Agents view, the agents of the page's session sorted by priority or workspace order, idle ones too |
| D48 palette | Jump to tab, workspace, session | Also every command, with sub-pages, shortcuts and the menu bar's toggles |
| Program icons | One `>_` tile | A tile per program (our own SVG set), overlapping per pane in each tab, with badges |
| Settings | None | A few settings in the menu bar (phase 11); a Settings window later, after its mock-ups (D62) |

New decisions get the next free numbers when each phase records them.

## Built in phases 10–21

`P` is the phase number. "herdr" names the call when a feature writes to herdr or reads more than
the snapshot.

### Window and look

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Color scheme Auto / Light / Dark | Same; View ▸ Appearance | 10 | — |
| Interface style Glass / Classic | Same two styles. Classic drops the window blur and the glass selection pill; floating panels (palette, menus, popovers, sheets, hover card, notices) keep system glass in both. "Tint with theme" is left out | 10 | — |
| Material values per style, appearance and key or non-key window | A small token table per style and appearance (`Style.swift`) | 10 | — |
| Terminal palette per appearance | libghostty-spm's light and dark palettes, switched with the appearance | 10 | — |
| Pane card radius 10, window corners from macOS | Same | 10 | — |
| Fade inactive panes: content opacity 0.7; in a window that is not key 0.5, the focused card 0.8 (0.85 light) | Same, as one toggle, View ▸ Fade Inactive Panes (on by default). Replaces today's black overlay | 17 | — |
| Window title "‹tab› - ‹session›" | Same, with the session of the page in view | 13 | — |
| Settings window | Later, after its mock-ups, once phases 10–21 are done (D62, future work). Phase 11 built a stock tabbed form; the user dropped it | — | — |
| Terminal font size (⌘0, ⌘+, ⌘-) | View ▸ Bigger (⌘+ and ⌘=), Smaller, Actual Size | 11 | — |
| Terminal font, cursor style and blink, Option as Alt, copy on select | Fixed defaults until the Settings window: SF Mono, a blinking block, Option types characters, no copy on select | 11 | — |
| Program icons per process | Our own SVG catalog, matched in this order: herdr's `agent`, the foreground process, the terminal title | 12 | `pane.process_info` |
| Several windows (File ▸ New Window ⌘N) | Same, a machine per window; ⌥-click a machine in the machine menu opens it in a new window | 16 | — |
| Windows restore their state | `@SceneStorage`: open pages, selection, sidebar view, sort and width | 16 | — |
| Empty and loading states with clear words and one button | Same words, our layout; no hint text | 21 | — |
| Floating notices (toast) | Today's notice restyled: a bottom capsule, a tone color, an optional action | 21 | — |
| Cards fade in when their first frame arrives (launch cover) | The terminal fades in once herdr's frames settle (states.mdx) | 21 | — |
| Folders dropped on the Dock icon open a new workspace there | Same | 21 | `workspace.create {cwd}` |
| Dock menu with agents that need you | Same, and finished ones not yet seen, plus New Tab | 15 | — |

### Title row and tab bar

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Sidebar toggle in the title row | Always shown; no highlight, its icon shows the sidebar filled while open (⌃⌘S) | 13 | — |
| Machine (host) button and menu | The machine's icon only: no chevron (phase 22), no name. Menu: This Mac with a checkmark, then "Add Remote Host…" (a placeholder) | 13 | — |
| Session button shows the name only when more than one session runs | Replaced: a workspace button while the sidebar is collapsed, "‹session› \| ‹workspace›"; its menu lists the workspaces of the open sessions grouped by session, with New Workspace and Open Session… | 13, 14 | `workspace.create {label}` |
| Tab placement is a setting (Above / Left / Right) | No setting: the tab bar is always in the title row, with the sidebar open or collapsed | 13 | — |
| A 34 pt capsule track behind the tabs, hidden when there is one tab | Same | 13 | — |
| Equal-width tabs: (space − gaps) ÷ count, at most 220 pt, at least 64 pt, then scroll with edge fades | Same | 13 | — |
| 1 pt dividers, hidden next to the selected and the hovered tab | Same | 13 | — |
| One sliding selection capsule, radius min(h/2, 16.5), spring (stiffness 520, damping 46) | Our glass marker keeps following the strip's scroll; clicks and keys move it with Rex's spring | 13 | — |
| Hover fill, 0.14 s | Same | 13 | — |
| × on the selected and the hovered tab, hidden below 52 pt | × on the hovered tab only (D42), hidden below 52 pt | 13 | — |
| Tab widths stay put after a close while the pointer is in the bar | Same | 13 | — |
| Title fades out instead of an ellipsis; the folder part is dimmed | Same | 13 | — |
| Tab context menu: Rename, Move Left, Move Right, Close | Same, plus Close Other Tabs | 13 | `tab.rename`, `tab.move`, `tab.close` |
| Hold ⌘ for 0.7 s: keycaps ⌘1…⌘9 on the tabs | Same, on the title-bar tabs only | 13 | — |
| Drag a tab to reorder | Same, along the tab track | 18 | `tab.move` |
| Icon stack: up to 5 pane icons in a tab, focused one in front | Same: one icon per pane, overlapping 4 pt apart, the keyboard card's icon in front | 12 | — |
| Status badge on the icon | Amber for needs you, green for finished and not seen (Oriel's colors) | 15 | — |
| Three working dots, 1.2 s cycle, in sync on every tab | Same | 15 | — |
| Icon bounce when an agent starts to need you or finishes | Same, off under Reduce Motion | 15 | — |
| Finish announcement: the title shows "‹agent› finished" for a few seconds | Same | 15 | — |
| Right-side buttons: Activity (eye with a badge), Command Palette, New Tab | Agents (`list.bullet.rectangle`, amber dot; phase 22 replaced the chat bubbles), Command Palette, New Tab | 15 (Agents) | — |

### Sidebar: session pages and workspace rows

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Sidebar lists one session's tabs | One page per session open in the window, Arc style: a sideways swipe or a page dot switches. A window starts with `default`; Close Page removes a page without stopping its session | 14 | — |
| Rows 30 pt, the selected row a raised pill | Workspace rows, 44 pt with a git line, 30 pt without; the selected one is the phase 10 pill | 14 | — |
| Sections with tab rows, sticky headers, collapse chevrons | Left out: tabs are in the title row; the sidebar lists workspaces, like herdr's Spaces panel | — | — |
| (herdr's Spaces panel) git branch and worktrees | Line 2: branch, ↑ahead, ↓behind. Linked worktrees indented under their repository | 14 | `git status --porcelain=v2 --branch` through `Exec.run`; snapshot `workspace.worktree` |
| Width 240 pt, drag to resize between 227 and 480 pt, kept | Same, kept per window | 14 | — |
| Scroll edge fade 18 pt | Same | 14 | — |
| `+` on a section header | `+` on the page header: a new workspace in that session | 14 | `workspace.create` |
| Inline rename (double-click) | Same, for workspaces | 14 | `workspace.rename` |
| Context menu: New Tab, Rename, Move Up, Move Down, Close | Same, on workspace rows | 14 | `tab.create`, `workspace.rename`, `workspace.move_block`, `workspace.close` |
| Drag to reorder workspaces | Same; a worktree group moves together | 18 | `workspace.move_block` |
| Footer: filter, new session or workspace, add host | Filter and one Open Session button (⇧⌘N). New Workspace is the page header's `+`; Add Remote Host is in the machine menu | 14 | — |
| New session sheet | The Open Session panel (no title, no buttons): create (a suggested two-word name), start a stopped session, open a running one as a page | 14 | `herdr session list`, server start (D47) |

### Agents

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Activity toggle (eye, ⌘.): a filter on the tab list | The Agents button (⌘.) toggles the Agents view: the sidebar page lists the agents of that session only, one row per agent pane | 15 | — |
| Popup with the same list while the sidebar is hidden | A hover panel on the Agents button: the agents of the current session that need you; a click goes to the pane. "Nobody needs you" when none | 15 | — |
| Two-line rows: icon, title, status capsule (Needs you, Working, Done), message, relative age ("now", "3m") | Program tile with badge, agent name, capsule (Needs you, Working, Done, Idle); line 2 "‹workspace› · ‹tab›" and the age (herdr sends no message) | 15 | — |
| "Include idle processes" | Idle agents always show; a sort menu: Priority or Workspace order | 15 | — |
| Seen ledger: a finish counts until the user views the tab | Oriel's `completion_seq` rule (D14), in memory, shared by the windows on a session | 15, 16 | — |
| (herdr's Spaces panel) workspace state | A state icon on each workspace row: amber dot, working dots, green dot, gray ring | 15 | — |
| Notifications per status (only while the app is not active; a click opens the pane) | Needs you and finished, for every open page | 15 | — |
| Dock badge count | Agents that need you over all open pages | 15 | — |
| Sounds per status | Left out until the Settings window (off by default in Rex's sense: no switch, no sound) | — | — |
| Per-status settings: tab indicator, notification, Dock badge, sound | Fixed until the Settings window: notify for needs you and finished, badge for needs you | 15 | — |

### Several windows

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Several windows on one host | Same; windows on one session share its store and keep their own selection | 16 | — |
| (herdr) one controller per pane | Per session between windows (D66): the window with the last terminal input or click controls; the other observes, dims a little and shows "Controlled in another window" with Take Back | 16, 21 | `terminal session control` / `observe` |
| A pane shown in two windows | Two surfaces and two streams, one control and one observe | 16 | — |

### Hover card ("peek")

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Hover a tab for 0.25 s: a card with the tab title and one row per pane (icon, name, folder, status), at most 280 pt wide | Same, on title-bar tabs and Agents view rows | 19 | — |
| Click a row: select the tab and give that pane the keyboard | Same | 19 | — |
| Pane minimap (tiles of the split layout) | Left out (the user, phase 22) | — | — |
| Status message of a blocked program | herdr 0.9.5 sends no message. The card shows the last 3 lines of a blocked agent's screen instead | 19 | `pane.read {source:"visible"}` |
| Tooltips with keycaps on chrome buttons | Native tooltips (`.help`) with the name and the shortcut, except the Agents button (its hover is the panel) | 19 | — |

### Pane cards and layout

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Header 36 pt: program glyph, program name, folder in secondary text | Same | 12, 17 | — |
| Four 22 pt buttons (split right, split down, zoom, close) on the focused card and on hover | Same | 17 | — |
| Zoom disabled with one pane; a zoomed card shows only Restore (accent circle) and Close | Same | 17 | — |
| Card context menu: Split Right, Down, Left, Up; Zoom; Move to New Tab; Move to Tab ▸; Move to New Workspace; Rename; Close | Same, but the moves are one submenu, Move Pane to Tab ▸ (the other tabs, New Tab, New Workspace). Left and Up are a split then a swap | 17 | `pane.split`, `pane.swap`, `pane.move`, `pane.rename` |
| Dividers: 16 pt hit area over the 8 pt gap, resize cursor, live drag, sent on release | Same (and design: a grip on hover) | 17 | `layout.set_split_ratio` |
| Double-click a divider: 0.5 | Same | 17 | `layout.set_split_ratio` |
| Balance splits (⌃⌘=) | Same | 17 | `layout.set_split_ratio` |
| Resize with keys (⌃⌘ arrows) | Same, 5 % per press | 17 | `pane.resize` |
| Dividers as accessibility sliders | Same | 17 | — |
| Focus pane left, right, up, down (⌥⌘ arrows), previous and next (⌘[, ⌘]) | Same; the app's own keyboard card, never herdr focus | 17 | — |
| Move pane left, right, up, down (⌥⇧⌘ arrows) | Same | 17 | `pane.swap {direction}` |
| Focus follows mouse (setting) | Same, as a toggle in View ▸ Pane (off) | 17 | — |
| Layout changes animate | Card frames animate 0.2 s; terminals resize once the motion ends | 17 | — |
| Drag a pane by its header: drop zones, spring-loading after 0.65 s, drop on the tab bar for a new tab, on a workspace for a new tab there, on empty sidebar for a new workspace | Same, with the exact table in ui-layout.md: swap in the same tab, an edge drop in the same tab re-places the pane (move out, move back, swap), edges in another tab split, a center drop across tabs is refused | 18 | `pane.swap`, `pane.move` |
| Find in the pane (⌘F): a find bar, match count, previous and next | Same; the text comes from herdr and the match scrolls into view | 21 | `pane.read {source:"recent"}`, `pane.scroll` |
| ⌘-click a link: open it | Same, http and https only (design) | 21 | — |

### Command palette and keys

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Sections: commands, tabs, workspaces, sessions; fuzzy match with keywords | Same; sessions are the open pages, and Open Session… opens the panel for the others | 20 | — |
| Rows 28 pt, accent selection, shortcut glyphs on the right, › for sub-pages, a footer with key hints | Same, without the footer (no hint text in the UI) | 20 | — |
| Sub-pages: Change Session, Rename Tab, Rename Workspace, Rename Pane, Move Pane to Tab, Go to Directory, Insert Path, Appearance, Interface Style, Font Size, Cursor Style | Same, except Cursor Style (no such setting until the Settings window), Change Session (the Open Session panel and the sidebar pages do that job) and Go to Directory and Insert Path (they open the system folder panel) | 20 | the write of each command |
| Live preview while a choice is highlighted (0.75 s) | Same, for Appearance and Interface Style | 20 | — |
| Settings as commands ("Turn On Focus Follows Mouse") | Same, for the menu bar's toggles | 20 | — |
| Go to Directory (⇧⌘G): browse folders, then `cd` in the pane | Same, with `NSOpenPanel` at the pane's folder, only when the pane runs only its shell | 20 | `pane.send_input` |
| Insert Path (⌃⌘I): browse, then type the quoted path | Same, with `NSOpenPanel` | 20 | `pane.send_input` |
| Rex's default shortcuts | Adopted where they do not clash with the design (table in phase 20); ⌘N is New Window, as in Rex | 20 | — |

## Left out

| Rex feature | Why |
|---|---|
| Rex as a multiplexer | Future work: `docs/content/docs/rex-backend.mdx` |
| Tab tear-off into a new window | Several windows are built (phase 16), but a tab belongs to its herdr workspace; a window shows pages, not single tabs |
| Compact density (panes as one sheet with hairlines) | The user dropped it |
| 41 themes, the theme editor, Ghostty and iTerm theme import, "Tint with theme" | The user wants only light, dark, Glass and Classic |
| Key sequences, modes, the which-key panel, custom shortcuts, the shortcut recorder, Lua | Oriel has no key sequences; macOS menus hold the shortcuts |
| Traffic lights moved into the tab bar or a pane header | Needs private AppKit API (`setCustomTitlebarHeight:`) |
| Settings for full-width tabs, hidden pane headers, balancing after each split, and a second fade for windows that are not key | README item 9 asks for a few basic settings; ⌃⌘= balances on request |
| Sidebar on the right, tab placement setting, icon count, icon tint and shell icon themes, hiding single chrome or pane buttons | Settings nobody asked for; one layout (the tab bar is always in the title row) |
| Tabs as sidebar rows, collapsible workspace sections, keycap hints on sidebar rows | The agreed layout puts tabs only in the title row (ui-layout.md) |
| "Include idle processes" toggle, any status area at the bottom of the sidebar | The Agents view always shows idle agents; the Agents button holds the rest |
| Two-finger swipe to fold the sidebar, folding the window instead of the panes | The sidebar swipe moves between session pages (Arc) |
| Session drag with a tilting card | A plain drag is enough |
| Blocked message as a scrolling tab title, progress pie, red error state | herdr 0.9.5 sends no message, no progress and no error state. Future work with OSC 7501 (herdr PR #5172) |
| Jump to the previous or next prompt | Needs OSC 133 prompt marks; herdr frames carry none |
| Tab thumbnails and an overview grid | Rex has none in build 1327 either; stays in future work |
| Remote hosts, Tailscale, pairing by QR code, Open Session on Web | Machines come later (machines.mdx); the machine menu's "Add Remote Host…" is a placeholder |
| Moving panes, tabs or workspaces between sessions or machines | Separate herdr servers; herdr has no call for it |
| Menu bar status item | The floating pills cover it later (D32) |
| Sparkle updates, app icon choices, Dock and menu bar visibility, diagnostics window | Not interface polish |
| Doom-melt transition, selection pulse and copy shine | Decoration with a GPU cost |
| Per-pane font size | One text size for the app (design) |
| Paste of unsafe text confirmation, recent paths | Small; revisit on request |
| Agent integration installer (Rex "Install Rex for Agents") | herdr has `integration.install`, but it writes agent config files. Revisit with the Settings window (D62, future work) |
| Attention badge on the machine button for other sessions | Pages show their state in the Agents view and on workspace rows; the Dock badge counts every open page |
