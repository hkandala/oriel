# Phase 15: agents, notifications and the Dock

Goal: Rex's way of showing agent activity, on herdr's data, in the layout of `plan/ui-layout.md`:
working dots and status badges in tabs, state icons on workspace rows, a "seen" state for finishes,
the Agents button with its needs-you popover, the session-scoped Agents view, notifications, the Dock
badge (no sounds) and a Dock menu. This replaces the design's status area and the Activity view of the
earlier plan.

Read first: `resources/research/clients/rex-internals.md` (§3.4, §3.5, §5.1: status dots animation, activity; facts only, write your own code), `plan/archive/ui-polish.md`, `plan/ui-layout.md` (title row item 7, Agents view),
`resources/mockups/layout.html` (scenes A, G, H), `resources/research/clients/rex-ui.md` (status indicator,
badges, Activity, notification settings), `resources/inspirations/rex-app/` (tabs-with-status,
sidebar-activity), `docs/content/docs/status.mdx`, `docs/content/docs/layout.mdx` (selection and
"seen"), decisions D13, D14, D31, D42, D55, D61, `Packages/HerdrKit/Sources/HerdrKit/Models.swift`
(`Agent`), `Oriel/Store/HostStore.swift`.

## Build

1. **HerdrKit.** Decode from `snapshot.agents[]`: `pane_id`, `terminal_id`, `agent`, `display_agent`,
   `agent_status`, `completion_seq` (lenient, all optional except the pane id).
2. **Seen (D14).** A small value type in HerdrKit (unit tested: it branches) that takes each snapshot
   and the panes the user is looking at, and returns per agent pane: `needsYou`, `working`,
   `finishedUnseen` or `idle`, plus the changes since the last snapshot (for notifications). herdr's
   statuses map as: blocked → `needsYou`, working → `working`, done / idle / unknown → `idle` unless
   `completion_seq` makes it `finishedUnseen` (herdr's `done` is not used, `layout.mdx`).
   - Finished and not seen = `completion_seq` not null and different from the seen value.
   - The first sighting of an agent records its value as seen (no flood after launch).
   - Looking at a pane records its value: its tab is selected on the page in view and the window is
     key.
   - The first snapshot after launch or after a page opens reports no changes. After a reconnect,
     changes against the last known state count.
   - Each change carries the time the app saw it, for the "3m" ages.
   Each page's store keeps the result per pane and rolls it up per tab and workspace (needs you >
   finished > working > idle).
3. **Working dots.** Replace the static ◔ (D42 changes). Three dots 3.5 pt, corner radius 1.75, 5.5 pt
   apart, in a 14 × 14 pt box. Each dot's opacity runs 0.3 → 0.85 → 0.3 over 1.2 s (key times 0, 0.25,
   0.5), dot *i* starts 0.2 s × *i* later, all computed from the wall clock so every tab is in step.
   Draw with a `TimelineView(.animation(minimumInterval: 1/15))`, only while visible. Reduce Motion:
   three still dots at 0.6. Shown in the status slot of every tab with a working agent except the
   selected one.
4. **Badges.** A 7 pt dot on the top-right of a tab's front icon tile and of an Agents row's tile,
   with a 1.5 pt ring in the background color: needs-you color (amber) when an agent needs you,
   finished color (green) when a finish is unseen. A tab's status slot order: × while hovered >
   working dots. The words stay for VoiceOver ("codex, needs you").
5. **Workspace state icons** in the phase 14 slot of each workspace row and in the workspace menu
   rows: needs you: amber dot (7 pt); working: the three working dots; finished and not seen: green
   dot; idle agent: gray ring (7 pt, 1.5 pt stroke); no agent: nothing. Accessibility value adds the
   state word.
6. **Bounce and announcement.** When a tab's state turns to needs you or finished while it is not
   selected: its front icon bounces once (scale 1 → 1.15 → 1, spring, off under Reduce Motion), and
   its title shows "‹agent› needs you" or "‹agent› finished" for 3 s, then the title again. A long text
   fades at its end like any title.

### Agents button

7. In the title row after the spacer, before ⌘. Outline chat bubbles: SF Symbol
   `bubble.left.and.bubble.right`. While the Agents view is on, the first bubble is filled (a custom
   symbol made from it, since `.fill` fills both bubbles), with no highlight. An amber 7 pt dot on its
   top-right when an agent of the current session (the page in view) needs you. Id `titlebar.agents`,
   accessibility value "N need you".
8. **Click**, ⌘. and View ▸ Show Agents (an entry in the command list) toggle the Agents view. Turning it on while the sidebar is
   collapsed opens the sidebar in the Agents view. Turning it off shows the Workspaces view; the
   sidebar stays open.
9. **Hover popover.** The pointer rests 0.25 s on the button: a floating glass panel under it,
   320 pt wide, at most 480 pt tall, with a small header "Needs you · ‹session›" (secondary, 11 pt),
   lists the agents of the current session that need you, with the Agents view's rows. A click on a row selects that workspace and tab and gives the pane the keyboard
   (never herdr focus, D13); the sidebar view does not change. With nobody waiting: "Nobody needs
   you". No footer text. It stays while the pointer moves from the button into the panel (0.15 s
   grace), and closes when the pointer leaves both, on a click elsewhere, or with Esc. Not while
   dragging. Build these rules once, as one hover-panel modifier (on native `.popover` if it gives the
   glass, click-outside and Esc), so phase 19's hover card reuses it.

### Agents view

10. The same sidebar page, listing the agents of that page's session only. A sideways swipe or a
    page dot shows the next session's agents. Page dots and the footer stay.
    - Header: "‹session› · agents" and a sort menu: **Priority** (groups Needs you, Working, Done,
      Idle, each with a count; herdr's order inside a group) or **Workspace order** (herdr's order of
      workspaces, tabs and panes). Default Priority, kept per window (`@SceneStorage`).
    - One row per agent pane, even when several share a tab. Row 44 pt: the program tile (phase 12)
      with its badge, the agent's name (`display_agent`, else `agent`), and on the right the status
      capsule ("Needs you" amber, "Working" blue, "Done" green, "Idle" gray: text in the color on a
      0.15 fill of it). Line 2 in secondary text: "‹workspace› · ‹tab›" (the tab named by the
      phase 13 title rule, since herdr's default label is a bare number) and the age on the right
      ("now", "3m", "2h").
    - Idle agents show. "Done" is a finish not yet seen; once seen, the agent is Idle. Rows reorder on
      each snapshot.
    - A click selects the workspace and tab and gives the pane the keyboard, which records a finish as
      seen.
    - The footer filter keeps rows whose agent, workspace or tab name matches.
    - With no agents the list is empty, with no text (the UI explains nothing the layout file does
      not list).

### Notifications and the Dock

11. **Notifications (D31).** `UNUserNotificationCenter`, delegate set at launch in an
    `NSApplicationDelegateAdaptor` (the Dock menu uses the same adaptor; phase 21 adds folder opens to
    it). They cover every
    open page of the window, not only the one in view.
    - A pane turns to needs you: "‹agent› needs you", body "‹session› · ‹workspace› · ‹tab›".
    - A new finish: "‹agent› finished", same body, unless the user is looking at that pane.
    - Only while the app is not active, or the pane is not shown.
    - Id `"<machine>|<session>|<terminal_id>"` (machine is "local" for This Mac), so a newer one replaces the older; removed when the pane is seen.
    - A click activates the app, shows that session's page and selects the pane.
12. **Dock.** Badge = the number of panes that need you over all open pages. No sounds (no Settings
    window to turn them on, D62). Dock menu (`applicationDockMenu`): a row per pane that
    needs you or finished ("codex needs you · default · infra", a click selects it), a separator, New
    Tab. Expose the badge as the accessibility value of an element with id `app.badge` on the window
    root (as `window.look` does), so e2e can read it.
13. **No notification settings.** There is no Settings window (D62): notifications are on for needs
    you and finished, the badge counts needs you only, and nothing plays a sound (`ui/settings.mdx`,
    fixed defaults). Do not add a Settings page or menu items for these.

### Docs

14. The design pages already describe the Agents button and view (D61); make them match what you
    built. Check `status.mdx` (the Agents button, popover and view; notifications; Dock), D61, D42
    (dots and badges), the status table in `ui/theme-and-accessibility.mdx` (glyphs become dots, rings
    and badges; words and colors stay), `ui/window.mdx` (Agents button, popover, Agents view,
    workspace state icons), `features.mdx`, the glossary (Agents view, badge; drop "status area" and
    "Activity"), `ui/settings.mdx`, the keyboard table (⌘.).

## e2e

All status changes come from `pane.report_agent` through the e2e helper on a throwaway pane (source
`oriel-e2e`, increasing `seq`). The tests use the sessions `scripts/e2e.sh` makes: `ORIEL_SESSION`
(launched) and `ORIEL_SESSION2` (opened as a second page through the Open Session sheet). A test that
needs another name adds it to e2e.sh and the helper.

- Report `working` on a pane of another tab: that tab's status slot shows working (accessibility
  value "working"); the selected tab shows none; the workspace row's value says working.
- Report `blocked`: the tab's value is "needs you", the workspace row shows needs you, and the Agents
  button's value is "1 need you". Hover the button: the popover (id `agents.popover`) lists that
  agent; a click on it selects the tab, gives its card the keyboard, and the sidebar still shows
  workspaces.
- Report `blocked` in `ORIEL_SESSION2` while `ORIEL_SESSION` is in view: the Agents button shows no
  dot, and `app.badge` is 1; show `ORIEL_SESSION2`'s page: the dot shows.
- ⌘.: the Agents view lists every agent of the session, idle ones too, grouped Needs you, Working,
  Done, Idle; switch to Workspace order: herdr's order. ⌘. again: the Workspaces view.
- Report `working` then `idle`: the row shows "Done"; a click on it selects the pane and the row shows
  "Idle".
- Relaunch with an agent already finished: no "finished" badge (first sighting is seen).
- No agent needs you: the popover says "Nobody needs you".
- Unit tests for the seen type: first sighting, a finish, a seen finish, a restart of herdr (counter
  back to 0), a reconnect.

## Done when

- Screenshots: tabs with working dots, a needs-you badge and a finished badge; workspace rows with
  each state icon; the needs-you popover; the Agents view in both sorts; a notification banner; the
  Dock badge.

## Findings

### Deviations

- **The hover panel is an in-window overlay, not `.popover`.** A native popover is its own window, which takes the
  keyboard when shown: resting the pointer on the button would have taken keys away from the terminal. The
  `hoverPanel` modifier hangs the panel from the trigger's bottom (`overlay` + `frame(height: 0, alignment: .top)`),
  tracks the pointer over both with `onHover`, and closes on a click outside it or Esc through a local event monitor
  that does not swallow the click. The title row has `zIndex(1)` so the panel draws over the sidebar and the cards,
  and its window-drag area moved behind the row (`background`): a `contentShape(.rect)` on the row cut off hits and
  hovers on the hanging panel (its row click did nothing in the first run).
- **The "on" icon is two SF Symbols, not a custom symbol file.** `bubble.left.and.bubble.right.fill` in palette mode
  with the back layer clear, over the outline symbol, bottom-aligned (both measured equal there): only the front
  bubble fills. The symbols render as bitmaps into a PDF, so there was no vector to build a symbol template from.
- **The whole icon stack bounces**, not only its front tile: the stack is one composited view (its ring cuts).
- **Dots and badges read the panes, not the rollup alone.** A tab's badge is its strongest pane's state (needs you
  or finished); its dots show while any of its panes works, so a tab with one agent waiting and one working shows
  both. The bounce and the announcement follow the strongest pane only: a second pane finishing in a tab where
  one already needs you does not bounce it.
- **No notification banner on this Mac.** The dev build is ad-hoc signed (`CODE_SIGN_IDENTITY = "-"`);
  `requestAuthorization` returns an error and Notification Center stores the requests with no visibility (seen in
  `log show`). The code path posts (logged "Added notification request"); a banner screenshot needs a signed build.
- **No Dock badge on this Mac either.** `dockTile.badgeLabel` is set (`app.badge` says so, and e2e reads it), but the
  Dock shows a badge only for an app allowed `.badge` notifications; the E2E reviewer saw the Dock item's
  `AXStatusLabel` empty. The app asks for `.alert` and `.badge` at launch. Both shots need a signed build: for the
  user to check at the end.
- **The hover panel does not open after a click on the button** until the pointer leaves it (E2E review: it opened
  over the cards 0.25 s after each click).

### Decisions

- **`Seen` (HerdrKit, value type).** `update(agents, looking:)` per snapshot, `look(_:)` when the looked-at tab
  changes; `states`, `since` (for the ages) and the changes since the last call. Keyed by terminal id (else pane id,
  spec review): a pane moved to another workspace keeps its terminal and its unseen finish, and a pane id herdr
  gives to a new terminal is a first sighting. An agent that goes away starts over. `AgentState` is ordered idle <
  working < finished < needs you (synthesized `Comparable`), so a rollup is `max`.
- **The store owns it** (`HostStore.seen`, shared by the windows on a session) and copies the result onto each
  `Pane` (`state`, `since`, `agentName`), so Observation redraws only the panes that changed. Rollups are
  `HostStore.strongest(tabIDs)`.
- **Looking** = `HostStore.lookingTabID`, set by `WindowPages.look(key:)` from the window's `appearsActive`, the page
  in view and its selected tab. Setting it records the tab's finishes as seen and removes their notifications.
- **Ids:** `titlebar.agents` (value "N need you"), `agents.popover`, `agents.popover.empty`, `agent.<pane id>` (value
  the capsule word), `agents.group.<capsule word>`, `agents.sort` (value `priority` / `workspace`), `tab.<id>.working`,
  `app.badge`. A tab's value adds "codex, needs you" between "in view" and "icons:".
- **Scene storage:** `agents` (the Agents view is on) and `agentSort`.
- **View ▸ Show Agents (⌘.)** is a checkmark item; `toggleAgents` is the one rule for the button and the menu.
- **One window for now:** `WindowPages.main` (weak) is the window the Dock menu and notification clicks act on
  (`ponytail:` note; phase 16 picks the window). It is set after the window restored its pages, not in `init`: a
  `@State` initial value is built again with every `ContentView` (spec review), and each throwaway copy would
  have taken it.
- **A click that comes early waits** (`WindowPages.pending`): a notification that starts the app, or names a page
  closed since, opens the page and selects the pane once a snapshot shows its terminal.
- **Notifications go when they no longer hold:** each snapshot sweeps the page's delivered ones whose pane no longer
  needs you or has an unseen finish (it works, idles, closed or lost its agent), reading the state after the
  `deliveredNotifications()` wait so a newer snapshot's banner stays; a closed page's are removed.
- **Kept against the ponytail review:** `Pane.state` / `since` copies of the ledger (an observed `Seen` would redraw
  every tab and row on each snapshot; D6 wants per-pane redraws); `AgentsWatch` as a modifier (WindowContent's body
  stopped type-checking with it inline); the sort menu as `Menu` + `ChromeStyle` label (a `.menu` Picker draws a
  pop-up button).
- **Dots pause on sidebar pages off to the side** (`EnvironmentValues.offscreen`): a page in the paging scroll view
  stays rendered.
- **Notification ids** use the terminal id, and a click finds the pane by terminal id (a pane moved to another
  workspace keeps it).

### Assumptions

- **macOS pauses a `TimelineView(.animation)` in a hidden window**; Reduce Motion and off-screen sidebar pages pause it
  outright. Tabs scrolled out of the title row's track still tick (at most 15 fps).
- **The Agents button gives the keyboard back to the card** after a click (E2E review: the terminal cursor went
  hollow); other title-row buttons were left as they are.

### Learned

- **Spike (herdr 0.9.5):** `pane.report_agent {pane_id, source, agent, state, seq}` takes idle, working, blocked,
  unknown; a report with a `seq` not above the last one is dropped. `state_change_seq` is one counter per server;
  `completion_seq` is set on working → idle and on blocked → idle, and null again at the next change; an idle → idle
  report changes nothing. herdr reports `done` instead of `idle` for a pane no herdr client looks at.
  `pane.release_agent {pane_id, source, agent}` drops only that source's report. `pane.report_metadata` needs a
  `source` too. A restarted server keeps pane ids and gives new terminal ids, so a restart is a first sighting
  (no flood); "different, not greater" still covers a pane without a terminal id.
- **Screenshots** (final `make e2e`, 57 tests green): `/tmp/oriel-shots/15/final/` (working dots, needs-you badge,
  finished badge, idle ring, the popover, the Agents view in both sorts). With a narrow sidebar the sort menu's
  label gives way first ("W…"), so the session name stays readable.
- **A static text's text is its value in XCUITest** (phase 14 again): "Nobody needs you" is read as `value`.

### Later

- **The icon changed in phase 22** (user): the chat bubbles did not fit; the button is `list.bullet.rectangle`, filled
  (`list.bullet.rectangle.fill`) while the Agents view is on. The two-symbol "front bubble filled" trick is gone.
