# Rex.app (Superlogical): the macOS client

This document describes the user interface of Superlogical's Rex Beta app for macOS, build 1327 (bundle `com.superlogical.rex` 0.1.0, minimum macOS 15.0). It is for implementers who copy parts of the Rex UI into Oriel. It covers geometry, colors, timings, behaviors, settings, menus and strings.

Rex uses other names for the herdr concepts:

| Rex term | herdr / Oriel term |
|---|---|
| session | workspace |
| window (shown as a tab) | tab |
| block | pane |
| Rex Server | the multiplexer server (one per user) |

Each fact carries one of two tags:

| Tag | Meaning |
|---|---|
| observed | Seen in the running app, read from an accessibility (AX) frame, or measured from a 2x screenshot (1 pt = 2 px). Values with "~" are visual estimates (about ±1 pt). |
| inferred | Read from the app bundle or binary (strings, JSON files, constants), but not seen on screen. Where the meaning of a name is a guess, the text says "unconfirmed". |

## 2. Window anatomy

The default layout puts tabs in a bar at the top of the window ("Above"). The window has no standard title bar. The tab bar is the title bar.

```
┌──────────────────────────────────────────────────────────────────────────────┐
│ ● ● ●  [▤ session]  ( [icon] tab 1 | [icon] tab 2 | ... )    [eye] [⌘] [+]   │ 46 pt
├──────────────────────────────────────────────────────────────────────────────┤
│ 8 ┌────────────── pane card ─────────────┐ 8 ┌────── pane card ──────┐ 8     │
│   │ >_ title  cwd        [▯▯][▭][⤢][×]  │gap│ ...                   │       │
│   │ terminal                            │   │                       │       │
│   └─────────────────────────────────────┘   └───────────────────────┘       │
│ 8                                                                            │
└──────────────────────────────────────────────────────────────────────────────┘
```

| Item | Value | Source |
|---|---|---|
| Window size (user's saved frame) | 1180×760 pt | observed |
| Minimum window width, horizontal tabs | 480 pt | inferred |
| Minimum window width, sidebar shown | 720 pt. With the sidebar collapsed: 720 − sidebarWidth, but at least 480. | inferred |
| Window title | `<active tab title> - <session label>`, for example "Claude Code ~ - crisp-forest" | observed |
| Title bar and tab bar height | 46 pt (comfortable). Content starts at y = 46. | observed (AX) and inferred |
| Traffic lights | 16×16 pt, x = 15 / 38 / 61, y = 15 | observed (AX) |
| Space kept for the traffic lights | 84 pt, when the window is not full screen | inferred |
| Content inset | 8 pt at left, right and bottom. No top inset under the tab bar. | observed (AX) |
| Gap between pane cards | 8 pt | observed (AX) |
| Window corner radius | ~16 pt on screen. The material files give 12. | observed / inferred |
| Inactive window | The whole window gets darker. The bar goes from #202123 to #141518, cards from #0D0D0E to #08080A. | observed |

Accessibility tree of a window with three panes (frames in pt, relative to the window, observed):

| Element | Frame | Notes |
|---|---|---|
| Group "Tabs" | 0,0 1180×46 | the bar |
| Button "Change Session" | 85,6 133×34 | help "Change Session (⌘K)" |
| Radio button per tab | 226,7 222×32 | one per tab, the active one is selected |
| Button "Activity" | 1071,7 35×32 | help "Show Activity (⌘.)", value On or Off |
| Button "Command Palette" | 1105,7 35×30 | help "Command Palette (⇧⌘P)" |
| Button "New Tab" | 1139,6 36×32 | help "New Tab (⌘T)" |
| Split group "Split layout" | 8,46 1164×706 | the pane area |
| Group per pane, for example "zsh ~" | 8,46 578×706 | a pane card |
| Pane header title | 14,46 463×36 | button "Move zsh ~ pane", the drag handle |
| Pane controls | 485,46 94×36 | four 22×22 buttons, pitch 24 |
| Text area "Terminal" | 8,82 578×670 | the terminal |
| Splitter "Divider between A and B" | 582,46 16×706 | value = ratio, for example 0.5 |

Window behaviors:

- Rex moves the traffic lights into its own bar with private NSWindow calls (a custom title bar height and a button group offset). In full screen it resets the title bar height. (inferred)
- Empty parts of the bar and of a pane header drag the window. A double click there follows the system setting `AppleActionOnDoubleClick` (zoom or minimize). (inferred)
- File ▸ New Window (⌘N) creates a new session with a random two-word label, for example `lively-alcove`. It opens the session in a new window with one shell tab. (observed)
- A rename from the CLI updates the session label in the bar at once. (observed)
- When the app opened a session, it selected the blocked tab, not the server's active tab. This suggests that Rex selects a tab that needs attention first. (observed, the rule is unconfirmed)
- Folders dropped on the Dock icon open as new sessions. The Dock menu lists sessions and the tabs that have activity. (inferred)
- Rex restores open windows, their frames and sidebar widths, and the last focused session. (inferred)

## 3. Tab bar

### 3.1 Layout

From left to right: traffic lights, session picker, tabs, Activity button, Command Palette button, New Tab button. (observed)

You can hide each of the three right buttons. Right-click the bar and use "Customize View". The setting is `Workspace.hiddenChromeButtons` with values `activity`, `commandPalette`, `newTab`. (inferred)

### 3.2 Geometry

| Item | Value | Source |
|---|---|---|
| Bar height | 46 pt comfortable, 40 pt compact | observed and inferred |
| Track (capsule behind all tabs) | 34 pt tall, y 6 to 40, fully round. It ends after the last tab and does not stretch when "Fill available space" is off. | observed |
| Track color (key window) | #27292B on a #202123 bar | observed |
| Tab height | 32 pt (AX) | observed |
| Active tab capsule | 30 pt tall, 2 pt inset inside the track. Corner radius = min(height / 2, 16.5). | observed and inferred |
| Active tab look (Glass) | A raised glass pill: vertical gradient #4A4B4D → #3D3E41 → #4A4B4D, and a 1 px light rim (#838588 at the top, fading down) | observed |
| Active tab look (Classic + tint) | Flat fill, no rim | observed |
| Inactive tabs | No fill | observed |
| Tab width rule | `w = (avail − (n − 1) × 1) / n`. Maximum 220 pt, minimum 64 pt. All tabs have the same width. | inferred |
| Tab width seen | 222 pt with 1 tab (AX), ~218 pt with 3 tabs, ~119 pt with 7 tabs | observed |
| "Fill available space" on | The 220 pt maximum goes away, and tabs grow to fill the bar | inferred |
| Gap between tabs | 1 pt, used by the divider | inferred |
| Divider | 1 pt wide, height = tab height − 18 (seen as ~18 pt), centered, color #3A3C3E | inferred and observed |
| Divider visibility | Only between two inactive tabs. Hidden next to the active tab. | observed |
| Hover and menu-highlight radius | Hover uses min(height / 2, 16.5). The menu-highlight variant uses 8 pt. | inferred |
| Close button | 22×22 pt, x = width − trailing inset − 22 + 7. Hidden when the tab is narrower than 52 pt. | inferred |
| Tab icon left inset | ~10 pt | observed |
| Tab title | ~14 to 15 pt SF Pro, medium weight. Program name in primary color, directory part in secondary color. | observed (estimate) |

With one tab, the tab shows its capsule in `three-splits.jpg` (observed). With "Fill available space" on, Rex shows tab backgrounds only for two or more tabs (inferred, from the setting's description).

### 3.3 Session picker

| Item | Value | Source |
|---|---|---|
| Content | A stack icon plus the session label (~15 pt semibold). For a remote host it adds a host subtitle and symbol. | observed and inferred |
| Label visibility | The label shows only when the host has more than one session. With one session the picker is icon only. | observed |
| Width | Icon only: 36 pt. With a label: 44 pt chrome (42 pt compact) + min(max(title width, subtitle width), 224 − chrome). Maximum 224 pt. | inferred |
| Slot in the bar | At least 36 pt, or the measured width + 4 | inferred |
| Badge | An attention badge when another session needs attention | inferred |
| Title change | The label slides when the session changes | inferred |
| Click | Opens the session popup: a filter field "Filter or create...", then sessions, New Session, New Session on Host, Reconnect host, Add Remote Host. A right-click or alternate click opens the session in a new window. | inferred |
| Tooltip | "Change Session" with its shortcut ⌘K | observed |

### 3.4 Right buttons

| Button | Icon | Behavior | Source |
|---|---|---|---|
| Activity | eye | Toggles Activity (⌘.). A blue dot badge shows when unseen activity exists. A filled circle behind the eye shows when Activity is on. | observed |
| Command Palette | ⌘ | Opens the palette (⇧⌘P) | observed |
| New Tab | + | New tab (⌘T) | observed |

The buttons are 35×30 to 36×32 pt hit targets at a pitch of about 34 pt. (observed, AX)

### 3.5 Titles and overflow

- A long title ends in a fade mask, not an ellipsis. (observed)
- When a tab title is a status message (for example a blocked message), the message scrolls as a marquee, in active and inactive tabs. (observed)
- When tabs reach the 64 pt minimum, the bar scrolls sideways. Gradient fades show at the leading and trailing edge. The bar scrolls the selected tab into view. During a drag near an edge, the bar scrolls on its own. (inferred, not seen: seven tabs still fit)

### 3.6 Selection, hover and close

- One selection capsule slides between tabs. Rex does not give each tab its own fill. The capsule moves with a spring (see §16). (inferred)
- Hover uses a separate surface with its own fade of 0.14 s. (inferred)
- An × shows on hover. The tooltip on it reads "Close Tab" (a 64×20 pt panel). (observed) The × also shows on the selected tab. (inferred)
- After you close a tab, the other tabs keep their frames while the pointer stays in the bar. The next tab moves under the pointer, as in Safari. (inferred)

### 3.7 Tab drag and drop (inferred)

- Drag a tab to reorder it.
- Drag a tab out of the bar to tear it off. A snapshot card of the tab follows the pointer, morphs into a window-shaped preview, and then the real window animates into place. Drop it back on a window to attach it again.
- Drop a pane on the bar to make it a new tab.
- Hold a dragged pane over a tab for 650 ms to switch to that tab (spring loading). The tab gets a tint and a pulse.

### 3.8 Context menus (inferred)

| Target | Items |
|---|---|
| Tab | Rename Tab, Move Tab Left, Move Tab Right, Close Tab |
| Session picker | Rename Session…, Close Session, New Session, Add Remote Host…, Customize View |

### 3.9 Tab bar animations (inferred)

These timings are the same in the tab bar, the sidebar, the session headers and the tab items.

| Animation | Duration | Curve |
|---|---|---|
| geometry (selection capsule, tab frames) | 0.28 s | spring |
| insertion of a new tab | 0.22 s | production |
| tab return (after a drag) | 0.42 s | easeInOut |
| return layout | 0.40 s | spring |
| session departure | 0.12 s | production |
| session arrival | 0.20 s | production |
| session label | 0.26 s | production |
| hover | 0.14 s | production |
| divider | 0.20 s | production |
| title clipping | 0.25 s | production |

The "production" curve is a cubic Bézier with control points (0.2, 0.9, 0.3, 1.0). The "spring" is mass 1, stiffness 520, damping 46, initial velocity 0. That is close to critical damping (2√520 = 45.607). In SwiftUI terms it is about `.spring(response: 0.276, dampingFraction: 1.0)`.

When you switch sessions, the old tabs leave and the new tabs arrive with the departure, arrival and label timings above.

## 4. Tab icons, badges and status

### 4.1 Icon tile

| Item | Value | Source |
|---|---|---|
| Shape | Rounded rectangle ~22×18 pt, radius ~5 | observed |
| Look | Dark fill, 1 px black outline, inner top highlight | observed |
| Glyph | A colored program glyph, for example a green `>_` for a shell, `zz` for `sleep`, a waveform for `top` | observed |
| Glyph source size | 24 pt vector glyphs | inferred |
| Tile style parameters | gradient strength, style and blend, a highlight, a border, an inner shadow, an outer shadow with a contact shadow, an outer rim | inferred |
| Default shell tile | background #2b2d31, glyph #7ee787. Named shells and `top`/`sleep`/`log`/`caffeinate` use glyph #98e491. | inferred |

The pane header uses a monochrome version of the icon (~16 pt), not the colored tile. (observed)

### 4.2 Icon stack

- A tab with several panes shows a stack of pane icons. The focused pane's icon is in front. (observed)
- The stack holds up to 5 icons in horizontal tabs and up to 3 in vertical tabs. Each icon sits ~4 pt behind the one in front. (observed and inferred)
- The setting "Show tab icons" sets the count. Rex animates the stack when a pane needs attention, when panes swap and when panes reorder. (inferred)
- The setting `Workspace.bouncesTabIcons` makes an icon bounce on attention. (inferred)
- The stack stays in a zoomed tab. (observed)

### 4.3 Status badge

| Item | Value | Source |
|---|---|---|
| Shape | ~7 pt dot at the top-right of the icon. A dark ring cuts it out of the icon. | observed |
| Blue | Done, or blocked (needs you) | observed |
| Red | Error | observed |
| No badge | Exit code other than 0, BEL, OSC 9, OSC 777 | observed |

Finished and failed dots clear once you view the tab. Rex keeps a "seen" record per pane in `Workspace.programActivitySeen`. (inferred)

### 4.4 Working dots

Rex shows three dots that pulse while a program works. (inferred. Only frames from an older build show them.)

| Item | Value |
|---|---|
| Container | 14×14 pt, centered |
| Dots | 3 dots, 3.5×3.5 pt, corner radius 1.75 |
| Pitch | 5.5 pt (2 pt gap). The first dot's x = midX − 7.25. |
| Animation | Opacity keyframes 0.3, 0.85, 0.3, 0.3 at key times 0, 0.25, 0.5, 1. Ease in and out. Duration 1.2 s, repeats forever. |
| Stagger | Dot *i* starts at *i* × 0.2 s |
| Phase lock | The start time snaps to a multiple of 1.2 s of the media clock, so every tab pulses in sync |
| Show and hide | 0.18 s fade |
| Frame rate | minimum 8, maximum 15, preferred 15 fps (to save battery) |
| Reduce Motion | The dots respect it |

A progress pie replaces the dots when the program reports a percentage. (inferred)

### 4.5 Status kinds

Rex reads agent status from OSC 7501 (Rex's protocol) and from ConEmu progress (OSC 9;4). (inferred)

| Kind | Variants | UI text | Source |
|---|---|---|---|
| working | optional progress (Int) | "Working" | inferred |
| blocked | permission, question, auth | "Waiting for permission", "Waiting for an answer", "Waiting for a password" | inferred |
| error | | "Failed" | inferred |
| finished (done) | | "Done" | observed |
| idle | | none | inferred |

### 4.6 What each status shows

Tests used `printf` of OSC 7501 sequences in background tabs. (observed)

| Program sends | Tab | Sidebar row | Activity view |
|---|---|---|---|
| `state=done` | blue dot, normal title | blue dot | "Done", relative time |
| `state=blocked kind=permission msg=…` | blue dot. The title becomes the message and scrolls as a marquee. | the title becomes the message | "Blocked" pill and the message |
| `state=error msg=…` | red dot | red dot | "Failed" red pill and the message |
| `state=working[:progress]` | dots or progress pie | | only with "Include idle processes in activity" |
| exit other than 0, BEL, OSC 9, OSC 777 | nothing | nothing | nothing. OSC 9 and OSC 777 become macOS notifications when allowed. |
| `sleep` running | the icon becomes `zz` | | |

### 4.7 Announcements (inferred)

When a program finishes, the tab title is replaced for a short time by a ticker with the program icon. Then the normal title comes back.

### 4.8 Icon color settings (inferred)

| Setting | Values | Effect |
|---|---|---|
| Use color for tab icons (`tabIconColorMode`) | Always, For active panes, For active tabs, Never | Which icons get their colored tile. The others are drawn without color. |
| Tint (`tabIconTintMode`) | Default (`off`), Use theme accent (`accent`), Use theme (`terminal`) | Tints icons with the theme |
| Shell icon theme (`shellIconTheme`) | `default`, `themed`, `themedAlt` | The look of the shell tile |

## 5. Hover card (peek)

Not seen live. All of this section is inferred.

| Item | Value |
|---|---|
| Delay | 250 ms of hover over a tab |
| Width | natural width, at most 280 pt |
| Anchor | a tooltip-style popover attached to the tab |
| Header | tab title (directory part styled apart), title activity, details (directory or message) |
| Rows | one per pane: icon, name, directory, activity message, progress pie, working dots. Indent guides show the process tree. |
| Overflow | "+N more" for hidden panes |
| Click on a row | focuses that pane |

Rex uses no terminal thumbnails in the hover card. A pane minimap type exists (pane rectangles with an animated highlight). Where it shows is unconfirmed. No Mission Control style overview of all tabs exists in this build.

## 6. Sidebar (vertical tabs)

Turn it on with View ▸ Customize View ▸ Tab Style ▸ Left Side or Right Side. Settings: `Workspace.tabStyle = vertical`, `Workspace.sidebarPosition = left | right`. (observed)

### 6.1 Structure

- The sidebar lists all sessions on the host. Each session is a section header with its tabs as rows. (observed)
- With more than one host, host headers group the sessions. A host header has an icon, a connection spinner, a warning button with a Retry popover, a "New Session" button and a collapse chevron. (inferred)
- A session header supports inline rename, a "+" for a new tab and a collapse chevron. The chevron rotates in 0.18 s. (inferred)
- Headers stick to the top while you scroll ("tucked" headers). The list fades over 18 pt at the top and the bottom. (inferred)
- A blocked tab's row shows the status message in place of its label. (observed)
- `client.tab.goto index=N` counts tabs across all sessions in the sidebar. index=1 jumped to another session's first tab. (observed)

### 6.2 Geometry

| Item | Value | Source |
|---|---|---|
| Sidebar width | default 240 pt, clamped to 227 to 480, rounded | inferred |
| Width seen | The pane card starts at x = 240, so the column is ~232 pt plus the 8 pt gap | observed |
| Row height | 30 pt single line, 44 pt with an activity detail line. Spacing between rows 6 or 10. | inferred |
| Row pitch seen | 32 pt | observed |
| Selected row | The same 30 pt glass pill as the active tab (rim #828385, gradient #4A4B4D ↔ #3D3E41), inset ~10 pt from both edges | observed |
| Row icon | ~20 pt | observed |
| Row title | ~15 pt | observed |
| Section header | session label, ~13 pt semibold, secondary color | observed |
| Section spacing | ~31 pt from the last row to the next header, ~31 pt from a header to its first row | observed |
| Footer | ~25 pt from the bottom edge | observed |

### 6.3 Title bar row in sidebar mode

The title bar row holds the traffic lights, a sidebar toggle (x ≈ 107 pt), then the eye, ⌘ and + buttons. The pane card starts at y = 8, and its header shares the traffic-light row. (observed)

When you hide the sidebar, the pane header moves up into the title bar row next to the traffic lights and the sidebar toggle. There is no separate tab bar, and the eye, ⌘ and + buttons are not shown. The pane title slides around the traffic lights. (observed. The slide is inferred.)

### 6.4 Footer

| Position | Control | Source |
|---|---|---|
| left | Filter (`line.3.horizontal.decrease.circle`). It expands into a field "Filter" with "Clear Filter". A host filter popover offers "All hosts" and "Filter Hosts". | observed and inferred |
| left | "Show idle processes" toggle (`moon.zzz`) | inferred |
| right | New Session (a stack with a plus) | observed |
| right | Add Remote Host (a globe with a plus) | observed |

The filter field expands in 0.3 s and uses 0.16 s and 0.12 s for its parts. (inferred)

### 6.5 Show, hide and resize

| Behavior | Value | Source |
|---|---|---|
| Toggle | ⌘/ or the toolbar button ("Hide Sidebar" / "Show Sidebar", `sidebar.leading` / `sidebar.trailing`). In horizontal mode ⌘/ reports that it "isn't available here right now". | observed |
| Gesture | Two-finger swipe to collapse or expand | inferred |
| Collapse and expand | 0.3 s. Panes travel with the sidebar. | inferred |
| Preserve width | With "Preserve width when resizing sidebar" on, the window folds in or out and the panes keep their size. Full-screen and maximized windows always keep their width. | inferred |
| Resize | Drag the edge handle. The resize animates in 0.25 s. The width goes to `Workspace.sidebarWidth`. | inferred |

### 6.6 Drag and context menus (inferred)

- Drag tabs to reorder them within a session or move them between sessions.
- Drag a session header to reorder sessions. The lifted card tilts with a damped spring (stiffness 260, damping 18, integrated in 240 Hz substeps). The pointer velocity uses a low-pass factor of min(dt × 18, 1).
- Context menu items: New Tab in Session, New Local Session, New Session on Host, Edit Host, Remove Host, Move Session Up, Move Session Down, Rename Session, Close Session, Rename Tab, Move Tab, Close Tab, "Show Activity" / "Show All Tabs", "Show Buttons".
- Row moves use the same spring as the tab bar (mass 1, stiffness 520, damping 46).

## 7. Activity view

### 7.1 In the sidebar (observed)

Toggle it with ⌘. or the eye button. Setting: `Workspace.sidebarShowsActivity`. The sidebar then lists only tabs with an unseen program status, grouped by session.

| Item | Value |
|---|---|
| Row | two lines, pitch ~46 pt |
| Line 1 | tab label (primary color), and a right-aligned status pill |
| Pills | "Blocked": gray fill. "Failed": red text on a red-tinted fill. Done has no pill. |
| Line 2 | the status message, or "Done", in secondary color. A right-aligned relative time ("now", "3m"). |
| Selected row | the glass pill, ~12 pt radius, two lines tall |
| Eye button | shows a filled circle while Activity is on |
| Empty text | "No processes are reporting activity" (inferred) |

The binary also has the capsule texts "Working", "Waiting" and "Failed" for the vertical-tab detail line. (inferred)

### 7.2 In horizontal mode (inferred)

In horizontal mode the toggle opens a floating Activity popup. The popup uses the same list as the sidebar. You can drag it off to detach it. It fades in over 0.1 s and out over 0.12 s, and its morph uses a spring with damping 22. In an off-screen window the toggle showed nothing. (observed)

### 7.3 What counts as activity (inferred)

- Statuses: working, blocked, error, done, and idle when "Include idle processes in activity" is on.
- Rex keeps a seen ledger keyed by pane id, record id and date (plus the message and reason for blocked). A status leaves the list once you view it.
- The Dock badge counts blocked, failed and finished statuses not yet seen.
- System notifications post only while Rex is in the background. A click opens the tab.

## 8. Panes

### 8.1 Cards (comfortable density)

| Item | Value | Source |
|---|---|---|
| Inset and gaps | 8 pt from the window at left, right and bottom. 8 pt between cards. | observed (AX) |
| Corner radius | ~10 pt continuous corner. The material files give 10. | observed and inferred |
| Card color seen | #0D0D0E in a key window, #08080A in a non-key window | observed |
| Card layers (pane glass off) | see §12. Backdrop `theme:surface` at 0.2, a 0.7 pt `plusLighter` rim, a 1 pt black outer stroke. | inferred |

### 8.2 Header

| Item | Value | Source |
|---|---|---|
| Height | 36 pt | observed (AX) |
| Title group | starts 6 pt into the card | observed (AX) |
| Icon | monochrome, ~16 pt | observed |
| Text | program in primary color, directory in secondary color, ~15 pt | observed (estimate) |
| Drag | Drag the title to move the pane. AX label "Move <title> pane". | observed (AX) |
| Hiding | "Show pane headers" setting. Headers always show when the vertical sidebar is hidden or on the right. | inferred |
| Tint | With "Match program backgrounds", the header takes the background color that a full-screen program paints | inferred |

### 8.3 Header buttons

| Button | SF Symbol | Notes | Source |
|---|---|---|---|
| Split Right | `rectangle.split.2x1` | custom filled variant `custom.rectangle.split.2x1.righthalf.filled` exists | observed and inferred |
| Split Down | `rectangle.split.1x2` | custom filled variant `custom.rectangle.split.1x2.bottomhalf.filled` exists | observed and inferred |
| Zoom Pane | `arrow.up.left.and.arrow.down.right` | disabled when the tab has one pane | observed |
| Close Pane | `xmark` | disabled when the tab has one pane | observed |

- Each button is 22×22 pt, with a 2 pt gap (pitch 24) and an 8 pt right inset. (observed, AX)
- The buttons show on the focused pane and on hover. In `three-splits.jpg`, two of three panes show the buttons in an inactive window, so the exact rule is unconfirmed. (observed)
- You can hide each button with `Workspace.hiddenPaneButtons`: `splitRight`, `splitDown`, `zoom`, `close`. (inferred)

### 8.4 Terminal inside the card (observed)

| Item | Value |
|---|---|
| Line pitch | 14.2 pt, which gives ~12 pt monospaced text |
| Left text inset | ~12 pt |
| Cursor | hollow block when the window is not key, solid when it is key |
| Scroller | overlay scroller at the right edge |

### 8.5 Dividers

| Item | Value | Source |
|---|---|---|
| Look | The divider is the 8 pt gap between cards. No line is drawn. | observed |
| Hit area | 16 pt (AX splitter), centered on the gap | observed (AX) |
| Accessibility | A slider with increment and decrement. The value is the ratio. Hint: "Swipe up or down to resize panes." | observed and inferred |
| Server update | Resizes are sent to the server after a 120 ms debounce | inferred |
| Keyboard resize | `pane.resize`, step 5% of the split by default | inferred |
| Balance | `pane.balance` (Balance Splits). "Autobalance splits" balances on every pane create or close. | inferred |

### 8.6 Zoom

- The zoomed pane fills the whole content area. (observed)
- The header controls become only unzoom (an arrows-in icon on a blue, accent-tinted circle) and close. The split buttons hide. (observed)
- Zoom is a server operation. Covered panes are hidden. (inferred)

### 8.7 Inactive pane fade

The setting "Fade inactive panes" has four values: None (`none`), Surface (`styling`), Content (`text`), Surface & Content (`both`). Surface fades the card layers. Content fades the terminal content opacity. The user has `both`. (inferred)

Content opacity per state, comfortable density (inferred, from the material files):

| Window | Inactive pane | Active pane |
|---|---|---|
| key | 0.7 (BlendTheme with pane glass: 0.8. UseTheme light: 0.6.) | 1.0 |
| non-key, dark | 0.5 | 0.8 |
| non-key, light | 0.5 | 0.85 |

"Fade panes for inactive windows" (`usesStandardInactiveWindowPaneStyles`, user value 1) uses the non-key styles above while it respects the "Fade inactive panes" choice. When it is off, that choice applies to every pane in an inactive window. A second label, "Fade content for inactive windows", reads "Fades content in every pane when its window is inactive." Glass panes manage their own inactive-window look. (inferred)

### 8.8 Find bar (inferred)

- A floating panel per pane. Placeholder "Find in Scrollback".
- Buttons: Find Previous (`chevron.up`), Find Next (`chevron.down`), close (`xmark`).
- The bar moves aside when it covers the selected match.
- It appears with `easeOut` 0.08 s.
- Shortcuts: Find… ⌘F, Find Next ⌘G.

### 8.9 Pane drag and motion (inferred)

- Drag a pane by its header. Drop zones: center, left, right, top, bottom. Drop on the tab bar for a new tab. Drag out to tear it off.
- A new pane grows from the split edge. Panes fade in and out.
- Split view transitions use `easeOut` 0.16 s, 0.2 s, 0.07 s and 0.08 s. The focus ring uses `easeOut` 0.16 s, then `linear` 0.05 s.

### 8.10 Terminal overlays (inferred)

| Overlay | Text |
|---|---|
| Reconnect | "Reconnecting… Content preserved." |
| Size owned by another client | "Sized by another client · <cols×rows>", "Click to resize it to fit this window." |
| Contrast | "Raised text contrast for a device in <mode> mode" |
| Paste | "Paste Unsafe Text?" alert |
| Links | a confirmation for custom-scheme links |

## 9. Command palette

### 9.1 Structure

| Item | Value | Source |
|---|---|---|
| Panel | floating, 330×498 pt in the capture | observed |
| Search field | placeholder "Search commands, sessions, and tabs...", rounded ~10 pt, filled | observed |
| Sub-page placeholder | "Search commands…" | inferred |
| Rows | 28 pt tall, ~15 pt text | observed |
| Selected row | accent-blue fill, ~8 pt radius | observed |
| Shortcut | trailing, secondary color glyphs | observed |
| Sub-page marker | a trailing › on rows that open a page | observed |
| Footer | under a hairline: "Change Keybinding ⌘↩" and "Action ↩", each with keycap chips | observed |
| List height | clamped to 84 to 460 pt. Available = window height − 76 − 40 − 38. | inferred |
| Sections | commands, sessions, tabs. An activity heading indicator. | inferred |
| No match | "No Results" | inferred |

### 9.2 Rows seen at the top level (observed)

| Row | Shortcut | Opens a page |
|---|---|---|
| Change Session… | ⌘K | yes |
| Rename Session | | yes |
| Rename Tab | | yes |
| Add Remote Host… | | yes |
| New Session | ⇧⌘N | |
| New Tab | ⌘T | |
| Go to Directory… | ⇧⌘G | yes |
| New Window | ⌘N | |
| Show Previous Tab | ⌃⇧⇥ | |
| Show Next Tab | ⌃⇥ | |
| Move Tab Left | ⌃⇧⇞ | |
| Move Tab Right | ⌃⇧⇟ | |
| Move Tab to New Window | | |
| Close Tab | ⌥⌘W | |
| Refresh Sessions | ⌘R | |

### 9.3 Row fields (inferred)

A row can carry: title, subtitle, a subtitle prefix (icon and text), shortcut, a "current" mark, emphasis, a needs-attention mark, a file icon, an SF Symbol, tab icons, search keywords, completion text, an alternate action with its hint, and a page to open.

### 9.4 Pages (inferred)

Pages stack. A row can push a page, close the palette or keep it open.

- Change Session, Rename Session, Rename Tab
- Go to Directory… (a folder browser), Insert Path, Move Pane to Tab…
- Select Interface Style…, theme picker, Custom Themes (filter, "Migrate theme from Ghostty config", "Import Theme File…", "Delete Custom Theme…")
- Select Terminal Font… (Monospaced Fonts, Other Fonts), Terminal Font Size, Cursor Style, Cursor Blink Interval, Option Key Behavior, Terminal Padding Color, selection colors
- Update Channel: Preview ("Tagged builds for testers."), Bleeding Edge ("Every commit that passes CI. Expect some instability.")
- Host pages: add, switch, remove
- Shortcuts: "Search actions…", "Press a shortcut for …", "Choose a Key to Remove It", "Reset to Default"
- Modes
- Toggles for settings, for example "Enable/Disable Focus Follows Mouse", "Autobalance Splits", "Show/Hide Pane Headers"

### 9.5 Behaviors (inferred)

- Highlighting a theme or update channel row previews it after 750 ms.
- A loading indicator shows after 150 ms. Shortcut hints refresh after 75 ms and change when you press a modifier.
- Inline completion fills the field.
- The footer turns into a shortcut recorder for "Change Keybinding".
- Each row has keyword strings for fuzzy matching. For example, Go to Directory… matches "go to directory folder path cd new tab open navigate".

## 10. Notices, toasts, tooltips, keycap hints, which-key

### 10.1 Floating notices (inferred)

| Item | Value |
|---|---|
| Fields | id, title, scrolling text, description, progress fraction, indicator (symbol, determinate progress or progress), tone, glass tint on or off, dismissible, dismiss shortcut hint, actions |
| Tones | accent, success, standard, warning, error |
| Action roles | standard, primary, destructive |
| Position | `Workspace.notificationPosition`: top-left, top-center, top-right, bottom-left, bottom-center, bottom-right. The picker is a window diagram. |
| Message | expandable: "Show full message" / "Collapse message" |
| Extras | progress ring, title ticker, dismiss `xmark` |
| Animation | `.spring(response: 1.0, dampingFraction: 1.0)` |
| Size constants | widths 300 and 360, heights 32 and 36, radii 16 and 12 were found. Which field uses which value is unconfirmed. |
| Known ids | `updates`, `serverRestart`, `raisedTextContrast` |

Rex uses notices for updates: "Rex App Update Available", "Restart to Update Rex…", "Your terminal tabs won't be lost".

### 10.2 Toasts (observed)

Every remote action shows a toast at the bottom center: "rex: <Action Title>", for example "rex: Toggle Tab Style". The prefix is the name of the calling client.

| Item | Value |
|---|---|
| Shape | capsule, ~26 pt tall, dark glass |
| Text | ~13 pt |
| Position | ~30 pt above the bottom edge of the window, centered |

### 10.3 Tooltips

- Rex draws its own tooltip: a label plus keycaps. Placements: below, below leading, trailing. It fades in 0.13 s. (inferred)
- Chrome buttons show their shortcut in the help text, for example "Show Activity (⌘.)". (observed)
- The tab × tooltip "Close Tab" is a 64×20 pt panel. (observed)

### 10.4 Keycap hints on tabs (inferred)

Hold the modifier for 700 ms and keycaps appear on the tabs. They fade in over 0.13 s and out over 0.1 s.

### 10.5 Which-key panel (inferred)

| Item | Value |
|---|---|
| Trigger | 300 ms after the first key of a key sequence (a tmux-style prefix) |
| First state | a pill with the keys pressed so far |
| Expanded | a grid of next keys. Each row: key labels, title, kind (action, sequence or mode), and whether it leaves the mode. |
| Extras | mode badge or bar while a mode is active, an escape hint, "Show Keys", "+N more" |
| Animation | expand `.spring(response: 0.3, dampingFraction: 1.0)`. Row insertion `easeOut` 0.2 s after 0.08 s. Removal `easeOut` 0.1 s. |
| Setting | `Workspace.showsKeySequenceHints` |

## 11. Settings window

### 11.1 Structure

| Item | Value | Source |
|---|---|---|
| Size | 740×572 pt | observed |
| Sidebar | 215 pt wide, with a "Search Settings" capsule field at the top | observed |
| Status card | at the top of the sidebar: the gradient Rex icon, "Server", "Running" | observed |
| Groups | Interface, Themes / Terminal, Shortcuts, Notifications, Integrations, Remote Hosts / Developer | observed |
| Sidebar entry | a colored rounded-square icon (~20 pt) and a ~15 pt label | observed |
| Toolbar | a back and forward capsule, then the page title | observed |
| Content | grouped cards, ~12 pt radius, #1A1D21 on #0D1013 | observed |
| Search | full-text search over settings. The matched row gets a spotlight highlight. | inferred |
| Theme | the window takes the terminal theme background | inferred |
| Section animation | `easeInOut` 0.24 s | inferred |
| URL | `rex://settings/<section>`, for example `rex://settings/interface` | inferred |

### 11.2 Server (observed)

| Card | Content |
|---|---|
| Rex Server | "Running for ‹time› ⓘ", button "Stop Server..." |
| Tailscale | "Sign in to Tailscale", "Access Rex securely from your other devices.", button "Sign In". After sign-in (inferred): "Serve over Tailscale", "Limit access to your Tailscale account", "Preferred Hostname". |
| Client Info | Label (text field, the Mac's name). "Remote Control: Let Rex and other clients perform actions in this app." (switch) |

### 11.3 Interface (inferred)

| Section | Setting | Values | What it does | Key |
|---|---|---|---|---|
| Window | Color scheme | Auto, Light, Dark (live material previews) | Sets the appearance | `Workspace.appearance` (`system`, `light`, `dark`) |
| Window | Interface style | Glass, Classic (picture cards) | Picks the material family, see §12 | `Workspace.interfaceStyle` |
| Window | Tint with theme | on, off | "Apply the selected theme's colors to interface surfaces" | part of `interfaceStyle` |
| Window | Use glass for panes | on, off (Glass only) | Draws panes with Liquid Glass. "Pane background colors ignore the theme when Glass is active." | `Workspace.usesPaneGlass` |
| Tabs | Tab style | Above, Left Side, Right Side | Tab bar or sidebar | `Workspace.tabStyle`, `Workspace.sidebarPosition` |
| Tabs | Fill available space | on, off (horizontal only) | Expands tabs equally to fill the bar, with backgrounds only for two or more tabs | `Workspace.tabsFillAvailableSpace` |
| Tabs | Show tab icons | count: 0 to 3 vertical, up to 5 horizontal | "Show up to five pane icons in horizontal tabs." "Show up to three pane icons in vertical tabs." | `Workspace.tabIconCount` |
| Tabs | Use color for tab icons | Always, For active panes, For active tabs, Never | Which icons keep their color | `Workspace.tabIconColorMode` |
| Tabs | Tab icon tint | Default, Use theme accent, Use theme | Tints icons | `Workspace.tabIconTintMode` (`off`, `accent`, `terminal`) |
| Tabs | Shell icon theme | default, themed, themed alt | The shell tile style | `Workspace.shellIconTheme` |
| Tabs | Preserve width when resizing sidebar | on, off | "Keeps the window width unchanged when showing or hiding the sidebar. Full-screen and maximized windows always keep their width." | `Workspace.preservesWindowWidthOnSidebarToggle` |
| Panes | Pane style | Comfortable, Compact | Separate cards with gaps, or one sheet with hairline dividers | `Workspace.paneDensity` |
| Panes | Show pane headers | on, off | "Pane headers are always shown when the vertical sidebar is hidden or positioned on the right." | `Workspace.showsPaneHeaders` |
| Panes | Match program backgrounds | on, off | "Colors a pane and its header with the background a full-screen program such as an editor paints. Works when the terminal padding color extends." | `Workspace.tintsPanesWithProgramBackground` |
| Panes | Fade inactive panes | None, Surface, Content, Surface & Content | See §8.7 | `Workspace.inactivePaneFadeMode` (`none`, `styling`, `text`, `both`) |
| Panes | Fade panes for inactive windows | on, off | See §8.7 | `Workspace.usesStandardInactiveWindowPaneStyles` |
| Panes | Autobalance splits | on, off | "Evenly resizes a tab's panes whenever a pane is created or closed." | `Workspace.balancesSplitsOnCreation` |
| Panes | Focus follows mouse | on, off | "Focuses a pane when you move the pointer over it, without clicking." | `Workspace.focusFollowsMouse` |
| App icon | App icon | Default (Dynamic), Bright, Twilight | The Dock icon | `Workspace.appIcon` (`default`, `light`, `dark`) |
| App icon | Show app icon | Dock and menu bar, Dock only, menu bar only | Where the app shows | `Workspace.appIconVisibility` |
| Launch | Show window on launch | on, off | Opens a window at launch | `Workspace.showsWindowOnLaunch` |

Settings with no page of their own: `Workspace.bouncesTabIcons`, `Workspace.hiddenChromeButtons`, `Workspace.hiddenPaneButtons`, `Workspace.sidebarWidth`, `Workspace.sidebarShowsActivity`. (inferred)

### 11.4 Themes (inferred)

| Setting | What it does | Key |
|---|---|---|
| Dark theme, Light theme | A carousel picker per appearance | `Workspace.darkThemeID`, `Workspace.lightThemeID` |
| Use extended theme palette | "Disable this option to use a standard set of extended colors." | `Workspace.darkUsesExtendedThemePalette`, `Workspace.lightUsesExtendedThemePalette` |
| New Dark Theme, New Light Theme, Edit Theme, Duplicate Theme, Delete Theme | Opens the theme customizer | `Workspace.customThemes` |
| Import Theme | "Import a Ghostty or iTerm theme file". "Themes are matched to an appearance based on their background color." | |

The theme customizer has color wells for Background, Foreground, Cursor, Cursor Text, Selection, Selected Text, ANSI Standard and ANSI Bright. You can drag a swatch onto another to swap them. The color picker is an OKLCH hue and chroma plane with a Display P3 gamut mask, plus a Lightness slider. The extended palette shows the Color Cube and the Grayscale Ramp, with Regenerate, Reset Overrides and "Automatically regenerate palette". A Preview switch updates the sheet as you edit. Buttons: Revert Changes, Cancel, Save & Apply.

### 11.5 Terminal (inferred)

| Section | Setting | Values or description | Key |
|---|---|---|---|
| Typography | Font, Style | installed fonts, fallback `Menlo` | `Workspace.terminalFontName`, `terminalFontStyle`, `terminalFallbackFontNames` |
| Typography | Font size | default 12 pt, clamped to 8 to 64 | `Workspace.terminalFontPointSize` |
| Typography | Weight | | `Workspace.terminalFontWeight` |
| Typography | Line height | adjustment in percent | `Workspace.terminalCellHeightPercent` |
| Typography | Ligatures | on, off | `Workspace.terminalAllowsLigatures` |
| Typography | Font smoothing | | `Workspace.terminalFontSmoothing` |
| Colors | Improve text contrast | "Adjust unreadable text against its background." | `Workspace.terminalImproveTextContrast` |
| Colors | Force theme palette for text | "Map text colors to the nearest theme color." | `Workspace.terminalUseThemePalette` |
| Colors | Use Display P3 color space | "Read theme and program colors as wide-gamut Display P3." | `Workspace.terminalUsesDisplayP3` |
| Cursor | Cursor style | Block, Bar, Underline | `Workspace.terminalCursorStyle` |
| Cursor | Force style | "Ignore application requests to change cursor shape." | `Workspace.terminalCursorStyleForced` |
| Cursor | Blink speed | Off, Slow, Normal, Fast, Custom (interval in milliseconds) | `Workspace.terminalCursorBlinkIntervalMilliseconds`, `terminalCursorBlinkUsesCustomInterval` |
| Keyboard | Option key | automatic, composes text, acts as Alt, left acts as Alt, right acts as Alt. "Automatic sends Alt on U.S. layouts and types special keys elsewhere. Applies to all terminals on this Mac, including remote hosts." | `Workspace.terminalOptionKeyBehavior` |
| Padding | Padding color | Background, Extend, Extend Always. "Background uses the pane background. Extend carries edge-cell backgrounds into the padding when appropriate. Extend Always extends them without those checks." | `Workspace.terminalPaddingColor` |
| Selection | Foreground, Background | Theme, Cell Foreground, Cell Background | `Workspace.terminalSelectionForeground`, `terminalSelectionBackground` |
| Selection | Rounded corners | on, off | `Workspace.terminalSelectionRoundedCorners` |
| Selection | Copy on selection | on, off | `Workspace.terminalCopyOnSelect` |
| Selection | Play animation on copy | "Shine across the selection to confirm each copy" | `Workspace.terminalCopyAnimation` |
| Links | Custom scheme links | ask, open, block. A list of trusted handlers per scheme. | `Workspace.terminalCustomSchemeLinks`, `terminalTrustedLinkHandlers` |
| Integrated Path Browser | Show recently used paths | "Insert Path types the path of a file or folder at the cursor. Recently used paths are shared by every session on the same host." | `Workspace.insertPathShowsRecentPaths` |
| Titles | Prefer generated titles | "Show the running program and its directory instead of titles that shells set. Titles that programs set for themselves, and names you give tabs, still appear." | `Workspace.prefersGeneratedTitles` |
| Shell | Startup command | placeholder "Default login shell". Applies to new terminals on this Mac. New tabs and splits use the working directory of the source terminal. | `Workspace.terminalStartupCommand` |

### 11.6 Shortcuts (inferred)

A searchable list of actions with a shortcut recorder per row and "Reset to Default". "Copy Shortcuts as Lua" exports your overrides. The recorder refuses some chords, for example: "Hold ⌘, ⌃, or ⌥ with the key. Shift on its own types a character." Reserved chords: ⌘Tab, ⌘Space, ⌘Q, ⌘H, ⌥⌘H, ⌘M, ⌘,. Rows animate with `.spring(response: 0.3, dampingFraction: 0.8)`.

### 11.7 Notifications (inferred)

| Section | Setting | What it does | Key |
|---|---|---|---|
| In-App Notifications | Notification position | Six positions on a window diagram | `Workspace.notificationPosition` |
| Program Activity ("How status from processes and agents is handled") | Show activity in tabs | Status dots and messages in tabs | `Workspace.showsProgramStatusInTabs` |
| Program Activity | Show system notifications | macOS notifications while Rex is in the background | `Workspace.showsProgramActivityNotifications` |
| Program Activity | Badge Dock icon | Dock badge count | `Workspace.showsProgramActivityDockBadge` |
| Program Activity | Play sounds | Sounds per status | `Workspace.playsProgramActivitySounds` |
| Program Activity | Include idle processes in activity | Lists idle programs in Activity | `Workspace.showsIdleProgramsInActivity` |
| Program Activity | Per-status rows: Working, Waiting for you, Errors, Finished | Each row opens a page with: Enable status, Show activity in tabs, Show system notifications, Badge Dock icon, Play sound, Sound | `Workspace.programActivityStatusPreferences` |
| System Notifications | Terminal notifications | "Programs can send notifications with OSC 9 or OSC 777" | `Workspace.allowsTerminalNotifications` |
| System Notifications | Tailscale sign-in, Tailscale device approval, Tailscale failures | Notification switches | |

Status descriptions: Working "Shown when a program is busy or reports progress". Waiting for you "needs you to respond". Errors "reports that something went wrong". Finished "finishes a task". Sounds: `attention`, `warning`, `error`, `success`, `ready`, `loading`, `tap`.

### 11.8 Integrations, Remote Hosts, Developer (inferred)

| Page | Content |
|---|---|
| Integrations | Coding Agents: "Teach agents in Rex terminals to use Rex" (installs a Rex skill and a session hook into Claude Code, Codex, OpenCode and Pi). Agent Behavior: "Let agents name sessions" ("Agents label the session after the task they're working on"). "Changes apply to new agent sessions." |
| Remote Hosts | A list of hosts. Empty state: "No Remote Hosts", "Add a Rex HTTP or HTTPS address to use its sessions in every window." Button "Add Remote Host…". Warning: "Rex does not provide transport authentication. Use a trusted tunnel such as Tailscale." |
| Developer | App Version, Developer Mode ("Expose settings for development and debugging."), Update Channel (Preview, Bleeding Edge), Rex Installation (bundled, source checkout, Nix), Local API, web-client origins, diagnostics |

## 12. Interface styles and materials (comfortable density)

### 12.1 Styles

| UI choice | `interfaceStyle` | File | Look in a dark key window | Source |
|---|---|---|---|---|
| Glass + Tint with theme | `blendTheme` (user default) | `MaterialStyles-BlendTheme.json` | translucent glass bar tinted by the theme, near-black panes (bar #202123, track #27292B, cards #0D0D0E) | observed |
| Glass, no tint | `modern` | `MaterialStyles-Modern.json` | neutral gray glass (bar #2F2F2F, panes #262627) | observed |
| Classic + Tint with theme | `useTheme` | `MaterialStyles-UseTheme.json` | opaque theme colors (bar #131519, panes #16181B), flat active tab with no rim | observed |
| Classic, no tint | `system` | `MaterialStyles-System.json` | opaque system grays (#1E1E1E / #222222) | observed |
| Light appearance (`blendTheme`) | | | bar #F5F5F5, panes #FAFAFA, white pill tab, theme `merino-light` | observed |

Glass colors depend on the wallpaper behind the window. (observed)

### 12.2 How to read the material tables

All values in §12 are inferred from the bundled JSON files.

- Each style has one profile per appearance (light, dark), per window state (key, non-key) and per density. Only comfortable is listed here.
- A surface has layers in this order: shadow, backdrop, glass, fill, fill2, strokes, inner shadow, content.
- `role→#hex@a` means: use the palette role if it exists, else the fixed fallback color, at alpha `a`. `theme:` roles come from the terminal theme, `macOS:` roles from the system. `op` is the layer opacity, on top of the color alpha.
- `glass` uses Liquid Glass. On macOS 15 it falls back to `NSVisualEffectView` with the named material.
- `r` is the corner radius. `matchSurface` means the layer uses the surface's radius.
- "pane" applies to every pane. "activePane" is a patch over "pane" for the focused pane.
- "pane (no glass)" and "activePane (no glass)" apply when "Use glass for panes" is off. The user has it off.
- An empty cell means the file does not set it, and a compiled default applies. Those defaults are not known.
- `co` is the content opacity.

Shared values in all four styles: window r 12, pane r 10, tab container r 40 (a capsule), tab selection r 16.5.

### 12.3 Window inner shadow

| Style | Dark | Light |
|---|---|---|
| BlendTheme, Modern | `macOS:content→#ffffff@0.6`, blend `overlay`, blur 2.5, y 1.5, knockout, r concentric | `#ffffff`, blend `plusLighter`, blur 1, y 0.5, knockout, op 0.15, r fixed 16 |
| UseTheme, System | not set | not set |

### 12.4 BlendTheme (Glass + tint)

| Component | Dark, key | Dark, non-key | Light, key | Light, non-key |
|---|---|---|---|---|
| window | glass `hudWindow`, tint `theme:canvas→#f4edda@0.5`. Backdrop `theme:surfaceRaised→#fffffe@0.5`, blend `color`. Fill `#000000`, blend `overlay`, op 0.3. | glass, tint `theme:canvas→#131714@0.5`. Backdrop `canvas→#121212@0`. Fill `#000000@0.2`. | glass `hudWindow`, tint `macOS:canvas→#1e1e1e@0.5`. Backdrop `canvas→#070e09@0.55`. | glass, tint `macOS:canvas→#ffffff@0.5`. Backdrop `canvas→#f4edda@0.6`. Fill `canvas→#000515@0`. |
| tabContainer | | fill `contentTertiary→#878a8e@0.1` | fill `content→#1f2328@0.05`, blend `plusDarker` | |
| tabSelection | glass, r matchSurface | glass. Stroke `#ffffff@0.05`, 1 pt, below content. | glass, tint `surfaceRaised→#f6f6f6@0.25`. Shadow `contentSecondary→#616468`, blur 3.5, y 1, op 0.15. | glass, tint `surfaceRaised→#f6f6f6@0.25` |
| tabHover | glass off, fill `#ffffff@0.05` | | glass off, fill `contentSecondary→#5c706a@0.08`, blend `plusDarker`, no shadow | glass off, fill `contentSecondary→#5c706a@0.08`, blend `plusDarker` |
| pane (glass) | co 0.8. Backdrop `#000000@0.2`. Glass tint `canvas→#100c1a@0.35`. Fill `#000000@0.2`. | co 0.5. Backdrop `#000000@0.6`. Glass tint `canvas→#100c1a@0.35`. | co 0.7. Glass tint `canvas→#f4edda@0.1`. Fill `content→#1f2328@0.05`, blend `plusDarker`. | co 0.5. Glass tint `canvas→#f4edda@0.1`. Fill `surfaceRaised→#ffffff@0.4`. |
| activePane (glass) | co 1. Fill `#000000`, blend `overlay`, op 0. | co 0.8 | co 1. Backdrop `surfaceRaised→#f6f6f6`. Fill `surfaceRaised→#faffff@0.5`, blend `normal`. | co 0.85 |
| pane (no glass) | co 0.7. Backdrop `theme:surface→#0a120c@0.2`. Stroke 1: `#ffffff@0.5`, `plusLighter`, 0.7 pt, op 0.2. Stroke 2: `#000000@0.5`, 1 pt, outside, below content. | | co 0.7. Fill `theme:surface→#fbf3dd@0`. Stroke 1: `#000000@0.05`, `plusDarker`, 1 pt, outside. Stroke 2: `#ffffff@0.4`, `plusLighter`, op 0.1. Shadow `#000000@0.5`, blur 5, y 2, op 0.15. | co 0.5. Fill `theme:contentTertiary→#878a8e@0.05`. |
| activePane (no glass) | co 1. Backdrop `#0a120c@0.3`. Fill `#ffffff`, op 0.05. Stroke 1 `#ffffff`, op 0.1. | | co 1. Backdrop `surfaceRaised→#1e2023`. Fill `#ffffff@0.5`, blend `overlay`. Stroke 1 `#000000@0.07`. Stroke 2 `#ffffff@0.1`, op 1. Shadow `#000000@0.65`. | co 0.85 |

### 12.5 Modern (Glass, no tint)

| Component | Dark, key | Dark, non-key | Light, key | Light, non-key |
|---|---|---|---|---|
| window | glass `hudWindow`, tint `canvas→#1e1e1e@0.5`. Backdrop `#000000@0.6`, blend `overlay`. | glass `hudWindow`, tint `canvas→#ffffff@0.5` | glass `hudWindow`, tint `canvas→#1e1e1e@0.7` | glass on |
| tabContainer | fill `#ffffff@0.05` | fill `#ffffff@0.03` | fill `content→#000000@0.05`, blend `plusDarker` | |
| tabSelection | glass, r matchSurface | glass. Stroke `#ffffff@0.05`, 1 pt, below content. | glass, tint `canvas→#1e1e1e@0.25`. Shadow `content→#ffffff@0.4`, blur 3.5, y 1.5, op 0.15. | glass, tint `canvas→#1e1e1e@0.25` |
| tabHover | glass off. Backdrop `#ffffff@0.13`. Fill `#ffffff@0.05`, blend `overlay`. | | glass off. Fill `contentSecondary→#000000@0.05`, blend `plusDarker`. No shadow. | |
| pane (glass) | co 0.7. Backdrop `canvas→#1e1e1e@0.48`, blend `overlay`. Glass tint `canvas→#1e1e1e@0.3`. Fill `#000000@0.15`. | co 0.5. Backdrop `#000000@0.5`. Glass tint `canvas→#1e1e1e@0.3`. | co 0.7. Glass tint `canvas→#1e1e1e@0.25`. Fill `#000000@0.05`, blend `plusDarker`. | co 0.5. Glass tint `canvas→#1e1e1e@0.25`. |
| activePane (glass) | co 1. Fill `#000000@0`. | co 0.8. Fill `#ffffff@0.02`. | co 1. Backdrop on. Fill `#ffffff@0.3`, blend `overlay`. | co 0.85 |
| pane (no glass) | same as BlendTheme dark key | | co 0.7. Fill `theme:surface→#fbf3dd@0.1`. Stroke 1: `#000000@0.05`, `plusDarker`, 1 pt, outside. Stroke 2: `#ffffff@0.4`, `plusLighter`, op 0.1. Shadow `#000000@0.5`, blur 5, y 2, op 0.15. | co 0.5. Fill `surfaceRaised→#f6f6f6@0.5`. |
| activePane (no glass) | co 1. Fill `#ffffff`, op 0.05. Stroke 1 `#ffffff`, op 0.1. | | co 1. Fill `#fbf3dd@0.7`, blend `overlay`. Stroke 1 `#000000@0.07`. Stroke 2 `#ffffff@0.1`, op 1. Shadow `#000000@0.65`. | co 0.85. Fill `surfaceRaised→#f6f6f6@0.5`. |

### 12.6 UseTheme (Classic + tint)

UseTheme and System have no glass layers and no separate no-glass pane profile.

| Component | Dark, key | Dark, non-key | Light, key | Light, non-key |
|---|---|---|---|---|
| window | backdrop `theme:canvas→#131714` | backdrop `surfaceSubtle→#1a160f` | backdrop `theme:canvas→#f4edda` | backdrop `canvas` (fallback not decoded) |
| tabContainer | fill `surfaceRaised→#1d1d25` | | fill `content→#1f2328@0.05` | |
| tabSelection | backdrop `theme:surfaceRaised→#24202f`. Fill `#ffffff@0.5`, blend `overlay`. Inner stroke `#ffffff@0.1`, `plusLighter`, 0.8 pt. | backdrop `surfaceRaised→#272220` | backdrop `surfaceRaised→#faffff`. Container stroke `content→#1f2328@0.1`, centered. Inner stroke `#ffffff@0.05`, `plusLighter`, 0.7 pt. Shadow `content→#2f4640@0.65`, blur 3.5, y 1.5, op 0.15. | backdrop `contentSecondary→#696d71@0.05` |
| tabHover | backdrop `#ffffff@0.05`. Fill off. Inner stroke off. | | backdrop off. Fill `contentSecondary→#5c706a@0.06`, blend `plusDarker`. Strokes and shadow off. | backdrop off. Fill `contentSecondary→#5c706a@0.05`, blend `plusDarker`. |
| pane | co 0.7. Backdrop `surface→#191216`, op 0. Container stroke `#ffffff@0.07`, `plusLighter`, 0.8 pt. | co 0.5. Backdrop `surfaceRaised→#241f18@0.3`. Fill op 0. | co 0.6. Fill `canvas→#f4edda@0.3`, blend `plusDarker`, op 0.25. Container stroke `theme:stroke→#d7cdb9`, 0.7 pt, op 0.5. | co 0.5. Backdrop `surfaceSubtle→#eceef2@0.4`. Fill op 0. |
| activePane | co 1. Backdrop `theme:surface`, op 1. Fill `#000000@0`. Container stroke `#ffffff@0.1`. | co 0.8 | co 1. Fill `theme:surface→#eaeaea`, blend `normal`, op 1. Container stroke `#d7cdb9`, 0.8 pt, op 0.7. | co 0.85 |

### 12.7 System (Classic, no tint)

| Component | Dark, key | Dark, non-key | Light, key | Light, non-key |
|---|---|---|---|---|
| window | (system default) | (system default) | backdrop `surfaceRaised→#f6f6f6`. Fill `#ffffff@0.5`. | backdrop `canvas→#ffffff` (dark fallback `#1e1e1e`), alpha 1 |
| tabContainer | fill `content→#ffffff@0.05` | | fill `content→#000000@0.05` | fill `content` (fallback not decoded) |
| tabSelection | backdrop `#ffffff@0.08`. Fill `#ffffff@0.2`, blend `overlay`. Inner stroke `#ffffff@0.1`, `plusLighter`, 0.8 pt. | backdrop `#ffffff@0.05` | backdrop `surface→#ffffff`. Container stroke `stroke→#000000@0.1`, centered. Inner stroke `#ffffff@0.05`, `plusLighter`, 0.7 pt. Shadow `content→#000000@0.5`, blur 3.5, y 1.5, op 0.15. | backdrop `contentSecondary→#000000@0.03` |
| tabHover | backdrop off. Fill `#ffffff@0.05`. Inner stroke off. | | backdrop off. Fill `contentSecondary→#000000@0.05`, blend `plusDarker`. Strokes and shadow off. | |
| pane | co 0.7. Backdrop `theme:surface→#191216`, op 0.5. Container stroke `#ffffff`, 0.7 pt, outside, op 0.07. | co 0.5. Backdrop `control→#ffffff@0.02`. Fill op 0. | co 0.7. Backdrop `theme:surface→#191216`, op 0.5. Container stroke `theme:stroke→#51454b`, 0.7 pt, op 0.5. | co 0.5. Backdrop `surfaceRaised→#f6f6f6@0.3`. Fill op 0. |
| activePane | co 1. Backdrop op 1. Fill `#000000@0.1`. Container stroke 0.8 pt. | co 0.8 | co 1. Backdrop op 1. Container stroke 0.8 pt, inside. | co 0.85 |

### 12.8 Overrides without Liquid Glass

`MaterialStyles-Sequoia.json` patches `system` and `useTheme`. The file name suggests that Rex applies it on macOS 15, where Liquid Glass does not exist (unconfirmed). A `null` removes a key.

| Style | Dark, key | Non-key (both appearances) | Light, key |
|---|---|---|---|
| system | window glass with material `windowBackground`, r fixed | dark: window removed. Light: window shape removed. | window backdrop removed, glass on, r fixed. Pane stroke aligned outside. |
| useTheme | pane backdrop op 0.49. Window backdrop removed, glass `windowBackground` with tint `theme:canvas→#0a0d12@0.5`, r fixed. | window shape removed | window backdrop removed, glass tint `theme:canvas→#f9f9f9@0.5`, r fixed. Pane strokes aligned outside. |

## 13. Menus and default shortcuts

### 13.1 Menu tree (observed, AX)

| Menu | Items |
|---|---|
| Rex Beta | About Rex Beta, Check for Updates..., Settings… ⌘,, Services ▸, Hide ⌘H, Hide Others ⌥⌘H, Show All, Quit ⌘Q |
| File | New Window ⌘N, New Session ⇧⌘N, Add Remote Host…, New Tab ⌘T, Go to Directory… ⇧⌘G, Close ⌘W, Close Tab ⌥⌘W, Close Session, Close Window ⇧⌘W |
| Edit | Undo ⌘Z, Redo ⇧⌘Z, Cut ⌘X, Copy ⌘C, Paste ⌘V, Delete, Select All ⌘A, Insert Path… ⌃⌘I, Find ▸ (Find… ⌘F, Find Next ⌘G, Find Previous), AutoFill ▸, Start Dictation…, Emoji & Symbols |
| View | Command Palette… ⇧⌘P, Change Session… ⌘K, Refresh Sessions ⌘R, Pane ▸, Customize View ▸, Reset Font Size ⌘0, Increase ⌘+, Decrease ⌘-, Toggle Sidebar ⌘/, Toggle Activity ⌘., Enter Full Screen fn F |
| View ▸ Pane | Split Left ⇧⌘←, Split Right ⌘D, Split Up ⇧⌘↑, Split Down ⇧⌘D, Split Best Fit ⌘↩, Zoom Pane ⇧⌘↩, Focus Left/Right/Up/Down ⌥⌘←/→/↑/↓, Focus Previous Pane ⌘[, Focus Next Pane ⌘], Move Pane Left/Right/Up/Down ⌥⇧⌘←/→/↑/↓ |
| View ▸ Customize View | Change Theme…, Color Scheme ▸ (Auto, Light, Dark), Tab Style ▸ (Above, Left Side, Right Side), Pane Style ▸ (Comfortable, Compact), Interface Style ▸ (Glass, Classic, Tint with theme) |
| Window | Minimize ⌘M, Minimize All ⌥⌘M, Zoom, Zoom All, Fill fn⌃F, Center fn⌃C, Move & Resize ▸, Full Screen Tile, Rex Beta Diagnostics ⇧⌘,, Copy Version Info, Copy Debug Info, Show Previous Tab ⌃⇧⇥, Show Next Tab ⌃⇥, Move Tab Backward ⌃⇧PgUp, Move Tab Forward ⌃⇧PgDn, Previous Session, Next Session, Bring All to Front, Arrange in Front, Remove Window from Set, window list |
| Help | search, Rex Help |

"Close" (⌘W) closes the focused pane, else the selected tab, else the window. (inferred)

### 13.2 Default shortcuts (observed)

| Shortcut | Action |
|---|---|
| ⌘N | New Window (creates a new session) |
| ⇧⌘N | New Session |
| ⌘T | New Tab |
| ⌘W | Close (pane, else tab, else window) |
| ⌥⌘W | Close Tab |
| ⇧⌘W | Close Window |
| ⌘D | Split Right |
| ⇧⌘D | Split Down |
| ⇧⌘← | Split Left |
| ⇧⌘↑ | Split Up |
| ⌘↩ | Split Best Fit |
| ⇧⌘↩ | Zoom Pane |
| ⌥⌘←/→/↑/↓ | Focus pane in a direction |
| ⌘[ / ⌘] | Focus Previous / Next Pane |
| ⌥⇧⌘←/→/↑/↓ | Move pane in a direction |
| ⌃⇥ / ⌃⇧⇥ | Show Next / Previous Tab |
| ⌃⇧PgUp / ⌃⇧PgDn | Move Tab Backward / Forward (palette: Move Tab Left / Right) |
| ⌘K | Change Session… |
| ⇧⌘P | Command Palette… |
| ⌘R | Refresh Sessions |
| ⇧⌘G | Go to Directory… |
| ⌃⌘I | Insert Path… |
| ⌘F / ⌘G | Find… / Find Next |
| ⌘/ | Toggle Sidebar (vertical mode only) |
| ⌘. | Toggle Activity |
| ⌘0 / ⌘+ / ⌘- | Reset / Increase / Decrease Font Size (per pane) |
| ⌘, | Settings… |
| ⇧⌘, | Rex Beta Diagnostics |

The real default keymap lives on the Rex Server in a Lua file (`init.lua`). The app mirrors the bindings onto its menu items and keeps your overrides in its own store. (inferred)

## 14. Program icon matching

This section describes the approach only. It leaves out Rex's icon art and glyph data. (inferred, unless marked)

1. For each terminal pane, the server reports the foreground process: `name`, `path`, `invoked_path`, `argv0` and `script`.
2. The app keeps a table of 109 icon definitions. Each definition has a glyph id, a tile background color, a glyph color, optional gradients (linear, radial or mesh), Display P3 flags, a title and a list of extra command names.
3. The app matches the process against the glyph id and the extra command names. For example, `nvim` maps to Neovim, `lazygit` to "Git Changes", and `python3.12` to Python.
4. For CLIs that run on Node, the app matches a suffix of the `script` path. For example, pi matches `pi-coding-agent/dist/cli.js`, and Copilot matches `copilot/npm-loader.js`.
5. A plain shell gets the "Shell" tile. A named shell and some long-running shell commands (`top`, `sleep`, `log`, `caffeinate`) get a "Shell - <name>" tile with a lighter glyph color. The `sleep` icon shows as `zz`. (observed)
6. An unknown program gets a placeholder glyph with the title "Block".
7. There is no `ssh` entry, so `ssh` falls back to the shell or placeholder tile.

Of the 113 glyph assets, 97 are monochrome masks that the app tints at run time, and 16 are full color.

## 15. Empty and loading states (inferred)

| State | Strings |
|---|---|
| App launch | "Opening Rex". A launch cover stays until the first terminal frame, then a reveal animation runs (it respects Reduce Motion). |
| New window | "Creating Session…", "Preparing a new session for this window." |
| Creation error | "Session Creation Failed", button "Retry" |
| Loading a host | "Loading Sessions on <host>", "Connecting to <host> and reading its sessions." |
| Reconnect | "Reconnecting to <host>" (`arrow.trianglehead.2.clockwise`), "Connection attempt N failed. Trying again automatically.", "Open Diagnostics…" |
| No sessions | "No Sessions", button "Create Session" |
| Server down | "Rex Server Is Stopped", "Rex Server Exited", "Rex Server Failed", "Rex Server Is Unavailable", "Restart Required". "Start the local Rex server to list and create sessions.", button "Start Again". "Couldn’t Connect to the Rex Server". |
| Session view | "Session View Failed", button "Try Again". "Loading the window's blocks…" |
| Empty tab | "Empty session", "Open a new tab to start a terminal.", button "New Tab", "Keyboard shortcut: …" |
| Server change | A "melt" transition covers the content when the server restarts or the content changes |

## 16. Animation reference

All values are inferred unless the row says otherwise.

### 16.1 Curves

| Name | Definition |
|---|---|
| production | cubic Bézier (0.2, 0.9, 0.3, 1.0) |
| spring (Core Animation) | mass 1, stiffness 520, damping 46, initial velocity 0. About `.spring(response: 0.276, dampingFraction: 1.0)`. |
| session drag tilt | stiffness 260, damping 18, 240 Hz substeps |
| others | linear, easeIn, easeOut, easeInOut |

### 16.2 Durations and delays

| What | Value |
|---|---|
| Tab selection and tab geometry | 0.28 s spring |
| Tab insertion | 0.22 s production |
| Tab return after drag | 0.42 s easeInOut |
| Return layout | 0.40 s spring |
| Session departure / arrival / label | 0.12 s / 0.20 s / 0.26 s |
| Tab hover | 0.14 s |
| Tab divider | 0.20 s |
| Tab title clipping | 0.25 s |
| Working dots | 1.2 s cycle, 0.2 s stagger, 0.18 s show and hide, 8 to 15 fps |
| Hover card delay | 250 ms |
| Keycap hints delay | 700 ms. Fade 0.13 s in, 0.1 s out. |
| Spring-load a tab during a pane drag | 650 ms |
| Which-key delay | 300 ms |
| Which-key expand | `.spring(response: 0.3, dampingFraction: 1.0)`. Rows: `easeOut` 0.2 s after 0.08 s, removal `easeOut` 0.1 s. |
| Divider resize debounce | 120 ms |
| Palette preview on highlight | 750 ms |
| Palette loading indicator / hint refresh | 150 ms / 75 ms |
| Palette selector | 25 ms |
| Insert Path loading reveal | 150 ms |
| Sidebar collapse and expand | 0.3 s |
| Sidebar resize | 0.25 s |
| Sidebar header chevron | 0.18 s |
| Sidebar footer filter | 0.3 s / 0.16 s / 0.12 s |
| Sidebar basic animations | 0.28 s / 0.18 s / 0.2 s |
| Activity and session popups | fade 0.1 s in, 0.12 s out. Morph spring with damping 22. |
| Tooltip fade | 0.13 s |
| Floating notice | `.spring(response: 1.0, dampingFraction: 1.0)` |
| Pane find bar | `easeOut` 0.08 s |
| Focus ring | `easeOut` 0.16 s, then `linear` 0.05 s |
| Pane split transitions | `easeOut` 0.16 s / 0.2 s / 0.07 s / 0.08 s |
| Settings sections | `easeInOut` 0.24 s |
| Transient reveal | `easeOut` 0.15 s |
| Shortcut rows, recorder, pane minimap highlight | `.spring(response: 0.3, dampingFraction: 0.8)` |
| Fallback-font list | `.spring(response: 0.28, dampingFraction: 1.0)` |

The environment variable `REX_SLOW_ANIMATIONS` slows the animations down.

## 17. Themes

### 17.1 Summary (inferred)

| Item | Value |
|---|---|
| Built-in themes | 41: 27 dark, 14 light |
| Named pairs | only Merino (Light, Dark) and Silver Point (Light, Dark) |
| Defaults | `merino-dark` and `merino-light` |
| Roles per theme | 73 |
| Theme source fields | background, foreground, cursor, cursor text, selection background and foreground, 16 ANSI colors |
| 256-color palette | generated: 0 to 15 = ANSI, 16 = background, 231 = foreground, 232 to 255 = a gray ramp. This matches Ghostty's `palette-generate = true` with `palette-harmonious = true`. |
| Custom themes | from a Ghostty configuration file, a Ghostty theme file, an iTerm color file, or made by hand. The app derives the roles at run time in OKLab and OKLCH. |
| UI font | the system font. SF Mono for digits and keys. No custom UI font. |
| Bundled font | `SymbolsNerdFont-Regular.ttf`, as a Nerd Font glyph fallback in the terminal |

### 17.2 Roles

| Group | Roles |
|---|---|
| Surfaces | `canvas`, `surfaceSubtle`, `surface`, `surfaceRaised`, `terminalBackground` |
| Lines | `strokeSubtle`, `stroke`, `scrollbarHover` |
| Controls (foreground at low alpha) | `control`, `controlHover`, `controlPressed`, `controlOnOverlay` (opaque) |
| Text | `content`, `contentSecondary`, `contentTertiary` |
| Accent | `accent`, `accentSolid`, `accentOnSolid`, `accentContainer`, `accentOnContainer`, `accentBorder`, `accentRgb`, `accentDim`, `accentDimSubtle`, `accentLine`, `accentRingOuter`, `selection`, `selectionForeground` |
| Status (×4: `danger`, `success`, `warning`, `info`) | base, `Solid`, `OnSolid`, `Container`, `OnContainer`, `Border`, plus `dangerBg` |
| Terminal | `terminalForeground`, `terminalCursor`, `terminalSelection`, `terminalSelectionForeground`, `terminalAnsi0` to `terminalAnsi15` |

### 17.3 How roles derive from the source colors

These rules come from a fit over all 41 themes, not from code. (inferred)

| Role | Rule |
|---|---|
| `canvas` | about the background |
| `content` | the foreground |
| `accent` | about the cursor color, moved in OKLab lightness until it reaches about 5.0:1 contrast against `canvas`. A neutral cursor gets a replacement accent. |
| `danger`, `success`, `warning`, `info` | about ANSI 1, 2, 3, 4, moved to about 5.0:1 contrast |
| `*Solid` | about 4.0 to 4.3:1 contrast |
| `*OnSolid` | the background, or `#ffffff` / `#000000` when the contrast is too low |
| `*Container` | OKLab mix of `canvas` and the color: t = 0.160 for dark themes, about 0.075 for light themes |
| `terminal*` | exact copies of the source |

Surface and text roles keep the canvas hue and chroma and shift OKLab lightness by a fixed amount:

| Role | Dark ΔL | Light ΔL |
|---|---|---|
| `surface` | +0.018 | +0.004 |
| `surfaceSubtle` | +0.030 | −0.032 |
| `surfaceRaised` | +0.070 | +0.009 |
| `controlOnOverlay` | +0.085 | −0.004 |
| `strokeSubtle` | +0.136 | −0.047 |
| `stroke` | +0.212 | −0.115 |
| `scrollbarHover` | +0.262 | −0.255 |
| `contentTertiary` | +0.345 | −0.348 |
| `contentSecondary` | +0.444 | −0.446 |

Alpha roles pick the alpha that shifts lightness over `canvas` by a target amount:

| Role | Dark ΔL | Light ΔL |
|---|---|---|
| `control` | +0.017 | −0.012 |
| `controlHover` | +0.036 | −0.027 |
| `controlPressed` | +0.063 | −0.051 |
| `accentDimSubtle` | +0.036 | −0.027 |
| `accentDim` | +0.069 | −0.057 |
| `accentRingOuter` | +0.096 | −0.085 |

### 17.4 Default theme values (inferred)

| Role | merino-dark | merino-light |
|---|---|---|
| source background / foreground | #0d1117 / #e6edf3 | #ffffff / #1f2328 |
| canvas | #0c0e11 | #f6f7f9 |
| surfaceSubtle | #131519 | #eceef2 |
| surface | #0f1319 | #f8f9fb |
| surfaceRaised | #1e2023 | #fafbfc |
| strokeSubtle / stroke | #2e3135 / #424549 | #e7e9eb / #d1d2d5 |
| content / secondary / tertiary | #e6edf3 / #82878c / #666a6f | #1f2328 / #696d71 / #878a8e |
| control / hover / pressed | #e6edf3 at 2% / 4.3% / 7.5% | #1f2328 at 2% / 3.9% / 7.8% |
| accent / accentSolid | #3485fa / #2f81f7 | #0667d8 / #0969da |
| danger / success / warning / info | #ff7b72 / #3fb950 / #d29922 / #58a6ff | #cf222e / #116329 / #9d5c00 / #0667d8 |

Status art in Settings uses these approximate colors: blocked #FBB54A, done #99CE76, error #FE8464, progress #4597F8. (inferred)

## 19. Modules and packages

Swift modules compiled into the one executable (from type metadata and `#file` strings; count = source files seen):

| Module | Files | Role |
|---|---|---|
| `RexMacOS` (SwiftPM target in package `RexApp`, resources in `RexApp_RexMacOS.bundle`) | 281 | All macOS UI. Most view types are nested as `extension RexShared.Workspace { class X }`, so ObjC names look like `_TtCE8RexMacOSO9RexShared9Workspace20HorizontalTabBarView`. |
| `Rex` | 1 | App entry (`ResourceBundleClass` only). |
| `RexShared` | 26 | Platform-neutral workspace model shared with iOS: actions (`RexAction`), program activity, themes (`ThemeSettings`, `CustomThemeStore`, Ghostty/iTerm importers, OKLCH color math), shortcut editor, remote hosts, titles, `PaneMinimap`, `LaunchReveal`, `RexNotice`. |
| `RexSync` | 16 | Client-side sync engine: `Hub`, `Server`, `Session`, `Window`, `WindowPresentation`, mutations, snapshots, block ownership, checkpoints. |
| `RexAPI` | 3 (+generated) | Wire types for the server control API (484 types: `session.*`, `block.*`, `client.*`, `hosts.*`, `server.*`), control/data WebSocket + pipe transports, API-revision translation. |
| `RexCompat` | 2 | API history registry, JSON-pointer rewrites between API revisions. |
| `RexActions` | 2 | `ActionCenter`, `KeyRouter` (key sequences, modes, pending keys), `ShortcutTable`, Lua value bridge. |
| `RexTerminal`, `RexSyncTerminal` | 1+2 | Terminal data stream (`rex.data.terminal.v1`, `com.superlogical.rex.terminal-v1`), live terminal, input. |
| `SuperSplit` | 17 | Pane split layout engine (AppKit + SwiftUI): dividers, drag/drop of panes, glass, motion, accessibility. |
| `SuperDesignTokens` (bundle `SuperUI_SuperDesignTokens`) | 1 | Themes (`themes.json`), color roles (`accent-container`, `content-secondary`, `terminal-ansi-*`, ...), `SuperTheme`, `SuperCubicBezier`. `themes.json` holds 41 built-in themes (e.g. Merino Light/Dark = current defaults, Abyssal Trench, Alpine Milk, Cathode Amber, Neon Arcade, Static Noir, Whitby Bay …), each `{id, name, appearance, source, palette, semantic, cssVariables}`. |
| `SuperBlockIcons` | 10 | Per-program icon catalog ("block icons": glyph + gradient + mesh backgrounds), `BlockGroupIconView` (stack of pane icons in a tab, attention/swap/reorder animations), icon package editor. Recognizes e.g. `pi-coding-agent/dist/cli.js`, `copilot/npm-loader.js`, jupyter, `Shell - caffeinate`. |
| `GhosttyVT`, `GhosttyTerminal`, `GhosttyRender` (package `swift-ghostty`, bundle `swift-ghostty_GhosttyRender`) | 9 | libghostty-vt terminal core (`0.1.0-dev`), AppKit `SurfaceView`, Metal renderer, Symbols Nerd Font. Embedded C ABI JSON lists `GHOSTTY_PROGRAM_STATUS_STATE_{IDLE,WORKING,DONE,BLOCKED,ERROR,CLEAR}`, `..._KIND_{NONE,PERMISSION,QUESTION,AUTH}`, OSC `PROGRAM_STATUS`(28), ConEmu progress, Kitty notifications. |
| `Monoh` | — | 24 types; `monoh.engine` (unclear; diagnostics/engine). |
| swift-nio (NIOCore/Posix/HTTP1/WebSocket/TransportServices/TLS), swift-atomics, swift-collections (DequeModule) | — | Networking. |

Frameworks linked: Sparkle 2.9.6, SwiftUI, AppKit, Charts (GPU diagnostics), ScreenCaptureKit (tab tear-off
snapshot), UserNotifications, AVFAudio (sounds), Metal, Symbols, Network, CryptoKit, Carbon (keyboard layout),
Accessibility. No `.sdef` (no AppleScript dictionary), no App Intents, no NSUserActivity.
