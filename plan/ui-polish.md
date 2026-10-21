# UI polish: every Rex interface feature, checked against Oriel and herdr

This file is the scope of phases 10–19. It lists every interface feature of Superlogical's Rex app
(build 1327, reverse engineered in October 2026) and says, for each one, whether Oriel builds it, in
which phase, and with which herdr call. It also lists what Oriel leaves out, and why.

The Rex research is in `resources/research/clients/rex-ui.md` (UI, sizes, timings, materials) and
`resources/research/clients/rex-server.md` (protocol). Screenshots are in
`resources/inspirations/rex-app/`. The program icons are in `resources/icons/`.

Rules that hold for every phase:

- Oriel copies Rex's layout, sizes, timings and behavior. It does not copy Rex's files: no icon art,
  no theme files, no material files and no decompiled code go into the repo.
- herdr stays the only multiplexer. Rex as a second multiplexer is future work
  (`docs/content/docs/rex-backend.mdx`).
- The house rules still hold: every herdr argv carries `--session`, creates pass `focus:false`, the
  app never calls herdr's focus methods (D13), and after a write the app reads the snapshot again.
- Each phase updates the design pages it changes, in the same commits as the code.

## What changes in the design

| Decision | Before | After (phases 10–19) |
|---|---|---|
| D44 look | Dark only, frosted | Appearance: Auto, Light or Dark. Interface style: Glass (the frosted look) or Classic (an opaque window). Still no glass on pane cards. No themes beyond one light and one dark terminal palette |
| D42 status | A static ◔ in one status slot | Rex's three working dots (an animation at 15 fps or less, in sync on every tab, still under Reduce Motion), and a status badge on the program icon for needs you and finished |
| Status area (status.mdx) | A fixed list at the bottom of the sidebar | The Activity view: an eye button in the title bar (⌘.), with a badge. It lists the tabs whose agents work, need you or finished, in the sidebar or in a popup |
| D48 palette | Jump to tab, workspace, session | Also every command, with sub-pages, shortcuts and settings |
| Program icons | One `>_` tile | A tile per program (our own SVG set), stacked per tab, with badges |
| Settings | None | A Settings window with a few basic settings (phase 11) |

New decisions get the next numbers (D60 onward) when each phase records them.

## Built in phases 10–19

`P` is the phase number. "herdr" names the call when a feature writes to herdr or reads more than
the snapshot.

### Window and look

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Color scheme Auto / Light / Dark | Same; View ▸ Appearance and Settings | 10 | — |
| Interface style Glass / Classic | Same two styles. Classic drops the window blur and the glass selection pill; floating panels (palette, popups, hover card, notices) keep system glass in both. "Tint with theme" is left out | 10 | — |
| Material values per style, appearance and key or non-key window | A small token table per style and appearance (`Style.swift`) | 10 | — |
| Terminal palette per appearance | libghostty-spm's light and dark palettes, switched with the appearance | 10 | — |
| Pane card radius 10, window corners from macOS | Same | 10 | — |
| Fade inactive panes: content opacity 0.7; in a window that is not key 0.5, the focused card 0.8 (0.85 light) | Same, as a setting (on by default). Replaces today's black overlay | 15 | — |
| Window title "‹tab› - ‹session›" | Same | 13 | — |
| Settings window | Native Settings scene, four tabs: General, Panes, Terminal, Notifications | 11 | — |
| Terminal font, size (⌘0, ⌘+, ⌘-), cursor style and blink, Option as Alt, copy on select | Same, in Settings ▸ Terminal | 11 | — |
| Program icons per process | Our own SVG catalog, matched by herdr's `agent`, the terminal title and the foreground process | 12 | `pane.process_info` |
| Empty and loading states with clear words and one button | Same words, our layout | 19 | — |
| Floating notices (toast) | Today's notice restyled: a bottom capsule, a tone color, an optional action | 19 | — |
| Cards fade in when their first frame arrives (launch cover) | Same | 19 | — |
| Folders dropped on the Dock icon open a new workspace there | Same | 19 | `workspace.create {cwd}` |
| Dock menu with agents that need you | Same, plus New Tab | 14 | — |

### Title-bar tab bar (sidebar hidden)

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| A 34 pt capsule track behind the tabs, hidden when there is one tab | Same | 13 | — |
| Equal-width tabs: (space − gaps) ÷ count, at most 220 pt, at least 64 pt, then scroll with edge fades | Same. "Tabs fill the bar" setting removes the 220 pt cap | 13 | — |
| 1 pt dividers, hidden next to the selected and the hovered tab | Same | 13 | — |
| One sliding selection capsule, radius min(h/2, 16.5), spring (stiffness 520, damping 46) | Our glass marker keeps following the strip's scroll; clicks and keys move it with Rex's spring | 13 | — |
| Hover fill, 0.14 s | Same | 13 | — |
| × on the selected and the hovered tab, hidden below 52 pt | Same | 13 | — |
| Tab widths stay put after a close while the pointer is in the bar | Same | 13 | — |
| Title fades out instead of an ellipsis; the folder part is dimmed | Same | 13 | — |
| Tab context menu: Rename, Move Left, Move Right, Close | Same, plus Close Other Tabs | 13 | `tab.rename`, `tab.move`, `tab.close` |
| Drag a tab to reorder | Same | 16 | `tab.move` |
| Icon stack: up to 5 pane icons in a tab (3 in sidebar rows), focused one in front | Same | 12 | — |
| Status badge on the icon | Amber for needs you, green for finished and not seen (Oriel's colors) | 14 | — |
| Three working dots, 1.2 s cycle, in sync on every tab | Same | 14 | — |
| Icon bounce when an agent starts to need you or finishes | Same, off under Reduce Motion | 14 | — |
| Finish announcement: the title shows "‹agent› finished" for a few seconds | Same | 14 | — |
| Hold ⌘ for 0.7 s: keycaps ⌘1…⌘9 on the tabs | Same, on title-bar tabs and sidebar rows | 13 | — |
| Session button shows the name only when more than one session runs | Same | 13 | — |
| Right-side buttons: Activity (eye with a badge), Command Palette, New Tab | Same | 14 (eye) | — |

### Sidebar (tabs as rows)

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Rows 30 pt, the selected row a raised pill | Same, with Classic and Glass pills from phase 10 | 13 | — |
| Width 240 pt, drag to resize between 227 and 480 pt, kept | Same | 13 | — |
| Sticky section headers, scroll edge fade 18 pt | Same | 13 | — |
| Collapse a section (chevron, 0.18 s); a collapsed workspace shows how many agents need you | Same | 13 | — |
| `+` on a section header: new tab in that workspace | Same | 13 | `tab.create` |
| Inline rename of a workspace or tab (double-click) | Same | 13 | `workspace.rename`, `tab.rename` |
| Section context menu: New Tab, Rename, Move Up, Move Down, Close | Same | 13 | `workspace.move`, `workspace.close` |
| Drag to reorder tabs and workspaces | Same (tabs stay in their workspace: herdr moves tabs only inside one) | 16 | `tab.move`, `workspace.move` |
| Footer: filter, new session or workspace, add host | Ours already: filter, New Workspace, Add Remote Host (placeholder) | — | — |

### Activity

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Activity toggle (eye, ⌘.): the sidebar lists tabs with activity, grouped by workspace | Same | 14 | — |
| Popup with the same list while the sidebar is hidden | Same | 14 | — |
| Two-line rows: title, status capsule (Needs you, Working, Done), message or status word, relative age ("now", "3m") | Same; the age comes from the time the app saw the change | 14 | — |
| "Include idle processes" | "Show working agents" toggle in the list | 14 | — |
| Seen ledger: a finish counts until the user views the tab | Oriel's `completion_seq` rule (D14), in memory | 14 | — |
| Notifications per status (only while the app is not active; a click opens the pane) | Needs you and finished, as the design says | 14 | — |
| Dock badge count | Agents that need you, plus unseen finishes if the setting is on | 14 | — |
| Sounds per status | One system sound per status, off by default | 14 | — |
| Per-status settings: tab indicator, notification, Dock badge, sound | Same, in Settings ▸ Notifications | 14 | — |

### Hover card ("peek")

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Hover a tab for 0.25 s: a card with the tab title and one row per pane (icon, name, folder, status), at most 280 pt wide | Same, on title-bar tabs, sidebar rows and Activity rows | 17 | — |
| Click a row: select the tab and give that pane the keyboard | Same | 17 | — |
| Pane minimap (tiles of the split layout) | Same, at the top of the card | 17 | — |
| Status message of a blocked program | herdr 0.9.5 sends no message. The card shows the last 3 lines of a blocked agent's screen instead | 17 | `pane.read {source:"visible"}` |
| Tooltips with keycaps on chrome buttons | Same | 17 | — |

### Pane cards and layout

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Header 36 pt: program glyph, program name, folder in secondary text | Same | 12, 15 | — |
| Four 22 pt buttons (split right, split down, zoom, close) on the focused card and on hover | Same | 15 | — |
| Zoom disabled with one pane; a zoomed card shows only Restore (accent circle) and Close | Same | 15 | — |
| Show pane headers (setting) | Same | 15 | — |
| Card context menu: Split Right, Down, Left, Up; Zoom; Move to New Tab; Move to Tab ▸; Move to New Workspace; Rename; Close | Same. Left and Up are a split then a swap | 15 | `pane.split`, `pane.swap`, `pane.move`, `pane.rename` |
| Dividers: 16 pt hit area over the 8 pt gap, resize cursor, live drag, sent on release | Same (and design: a grip on hover) | 15 | `layout.set_split_ratio` |
| Double-click a divider: 0.5 | Same | 15 | `layout.set_split_ratio` |
| Balance splits (⌃⌘=) | Same | 15 | `layout.set_split_ratio` |
| Resize with keys (⌃⌘ arrows) | Same, 5 % per press | 15 | `pane.resize` |
| Dividers as accessibility sliders | Same | 15 | — |
| Autobalance splits on creation (setting) | Same | 15 | `layout.set_split_ratio` |
| Focus pane left, right, up, down (⌥⌘ arrows), previous and next (⌘[, ⌘]) | Same; the app's own keyboard card, never herdr focus | 15 | — |
| Move pane left, right, up, down (⌥⇧⌘ arrows) | Same | 15 | `pane.swap {direction}` |
| Focus follows mouse (setting) | Same | 15 | — |
| Layout changes animate | Card frames animate 0.2 s; terminals resize once the motion ends | 15 | — |
| Drag a pane by its header: drop zones (center swap, edges split), spring-load a tab after 0.65 s, drop on the tab bar for a new tab, on a workspace for a new tab there, on empty sidebar for a new workspace | Same (design: drag-and-drop.mdx) | 16 | `pane.swap`, `pane.move` |
| Find in the pane (⌘F): a find bar, match count, previous and next | Same; the text comes from herdr and the match scrolls into view | 19 | `pane.read {source:"recent"}`, `pane.scroll` |
| ⌘-click a link: open it | Same, http and https only (design) | 19 | — |

### Command palette and keys

| Rex feature | Oriel | P | herdr |
|---|---|---|---|
| Sections: commands, tabs, workspaces, sessions; fuzzy match with keywords | Same | 18 | — |
| Rows 28 pt, accent selection, shortcut glyphs on the right, › for sub-pages, a footer with key hints | Same | 18 | — |
| Sub-pages: Change Session, Rename Tab, Rename Workspace, Rename Pane, Move Pane to Tab, Go to Directory, Insert Path, Appearance, Interface Style, Font Size, Cursor Style | Same | 18 | the write of each command |
| Live preview while a choice is highlighted (0.75 s) | Same, for Appearance and Interface Style | 18 | — |
| Settings as commands ("Turn On Focus Follows Mouse") | Same | 18 | — |
| Go to Directory (⇧⌘G): browse folders, then `cd` in the pane | Same, only when the pane runs only its shell | 18 | `FileManager` on This Mac, then `pane.send_input` |
| Insert Path (⌃⌘I): browse, then type the quoted path | Same | 18 | `FileManager` on This Mac, then `pane.send_input` |
| Rex's default shortcuts | Adopted where they do not clash with the design (table in phase 18) | 18 | — |

## Left out

| Rex feature | Why |
|---|---|
| Rex as a multiplexer | Future work: `docs/content/docs/rex-backend.mdx` |
| Tab tear-off into a new window, several windows | One main window (D34); the user dropped it |
| Compact density (panes as one sheet with hairlines) | The user dropped it |
| 41 themes, the theme editor, Ghostty and iTerm theme import, "Tint with theme" | The user wants only light, dark, Glass and Classic |
| Key sequences, modes, the which-key panel, custom shortcuts, the shortcut recorder, Lua | Oriel has no key sequences; macOS menus hold the shortcuts |
| Traffic lights moved into the tab bar or a pane header | Needs private AppKit API (`setCustomTitlebarHeight:`) |
| Sidebar on the right, tab placement setting, icon count, icon tint and shell icon themes, hiding single chrome or pane buttons | Settings nobody asked for; one layout |
| Two-finger swipe to fold the sidebar, folding the window instead of the panes | The sidebar swipe is for machine pages (Arc, design) |
| Session drag with a tilting card | A plain drag is enough |
| Blocked message as a scrolling tab title, progress pie, red error state | herdr 0.9.5 sends no message, no progress and no error state. Future work with OSC 7501 (herdr PR #5172) |
| Jump to the previous or next prompt | Needs OSC 133 prompt marks; herdr frames carry none |
| Tab thumbnails and an overview grid | Rex has none in build 1327 either; stays in future work |
| Remote hosts, Tailscale, pairing by QR code, Open Session on Web | Machines come later (machines.mdx) |
| Menu bar status item | The floating pills cover it later (D32) |
| Sparkle updates, app icon choices, Dock and menu bar visibility, diagnostics window | Not interface polish |
| Doom-melt transition, selection pulse and copy shine | Decoration with a GPU cost |
| Per-pane font size | One text size for the app (design) |
| Paste of unsafe text confirmation, recent paths | Small; revisit on request |
| Agent integration installer (Rex "Install Rex for Agents") | herdr has `integration.install`, but it writes agent config files. Revisit with a Settings ▸ Agents page |
| Attention badge on the session button for other sessions | Needs a store per session; comes with machine pages |
