# Phase 15: agents, notifications and the Dock

Goal: Rex's way of showing agent activity, on herdr's data, in the layout of `plan/ui-layout.md`:
working dots and status badges in tabs, state icons on workspace rows, a "seen" state for finishes,
the Agents button with its needs-you popover, the session-scoped Agents view, notifications, the Dock
badge, sounds and a Dock menu. This replaces the design's status area and the Activity view of the
earlier plan.

Read first: `plan/ui-polish.md`, `plan/ui-layout.md` (title row item 7, Agents view),
`resources/mockups/layout.html` (scenes A, G, H), `resources/research/clients/rex-ui.md` (status indicator,
badges, Activity, notification settings), `resources/inspirations/rex-app/` (tabs-with-status,
sidebar-activity), `docs/content/docs/status.mdx`, `docs/content/docs/layout.mdx` (selection and
"seen"), decisions D13, D14, D31, D42, D55, D61, `Packages/HerdrKit/Sources/HerdrKit/Models.swift`
(`Agent`), `Oriel/Store/HostStore.swift`.

## Build

1. **HerdrKit.** Decode from `snapshot.agents[]`: `pane_id`, `terminal_id`, `agent`, `display_agent`,
   `agent_status`, `completion_seq`, `state_change_seq` (lenient, all optional except the pane id).
2. **Seen (D14).** A small value type in HerdrKit (unit tested: it branches) that takes each snapshot
   and the panes the user is looking at, and returns per agent pane: `needsYou`, `working`,
   `finishedUnseen` or `idle`, plus the changes since the last snapshot (for notifications).
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
   scrolls once (30 pt/s) instead of fading.

### Agents button

7. In the title row after the spacer, before ⌘. Outline chat bubbles: SF Symbol
   `bubble.left.and.bubble.right`. While the Agents view is on, the first bubble is filled (a custom
   symbol made from it, since `.fill` fills both bubbles), with no highlight. An amber 7 pt dot on its
   top-right when an agent of the current session (the page in view) needs you. Id `titlebar.agents`,
   accessibility value "N need you".
8. **Click**, ⌘. and View ▸ Show Agents toggle the Agents view. Turning it on while the sidebar is
   collapsed opens the sidebar in the Agents view. Turning it off shows the Workspaces view; the
   sidebar stays open.
9. **Hover popover.** The pointer rests 0.25 s on the button: a floating glass panel under it,
   320 pt wide, at most 480 pt tall, with a small header "Needs you · ‹session›" (secondary, 11 pt),
   lists the agents of the current session that need you, with the Agents view's rows. A click on a row selects that workspace and tab and gives the pane the keyboard
   (never herdr focus, D13); the sidebar view does not change. With nobody waiting: "Nobody needs
   you". No footer text. It stays while the pointer moves from the button into the panel (0.15 s
   grace), and closes when the pointer leaves both, on a click elsewhere, or with Esc. Not while
   dragging.

### Agents view

10. The same sidebar page, listing the agents of that page's session only. A sideways swipe or a
    page dot shows the next session's agents. Page dots and the footer stay.
    - Header: "‹session› · agents" and a sort menu: **Priority** (groups Needs you, Working, Done,
      Idle, each with a count; herdr's order inside a group) or **Workspace order** (herdr's order of
      workspaces, tabs and panes). Default Priority, kept per window (`@SceneStorage`).
    - One row per agent pane, even when several share a tab. Row 44 pt: the program tile (phase 12)
      with its badge, the agent's name (`display_agent`, else `agent`), and on the right the status
      capsule ("Needs you" amber, "Working" blue, "Done" green, "Idle" gray: text in the color on a
      0.15 fill of it). Line 2 in secondary text: "‹workspace› · ‹tab›" and the age on the right
      ("now", "3m", "2h").
    - Idle agents show. "Done" is a finish not yet seen; once seen, the agent is Idle.
    - Rows do not move while the pointer is over the list; the new order applies when it leaves.
    - A click selects the workspace and tab and gives the pane the keyboard, which records a finish as
      seen.
    - The footer filter keeps rows whose agent, workspace or tab name matches.
    - With no agents the list is empty, with no text (the UI explains nothing the layout file does
      not list).

### Notifications and the Dock

11. **Notifications (D31).** `UNUserNotificationCenter`, delegate set at launch. They cover every
    open page of the window, not only the one in view.
    - A pane turns to needs you: "‹agent› needs you", body "‹session› · ‹workspace› · ‹tab›".
    - A new finish: "‹agent› finished", same body, unless the user is looking at that pane.
    - Only while the app is not active, or the pane is not shown.
    - Id `"<session>|<terminal_id>"`, so a newer one replaces the older; removed when the pane is seen.
    - A click activates the app, shows that session's page and selects the pane.
12. **Dock.** Badge = the number of panes that need you over all open pages, plus unseen finishes
    when that setting is on. Sounds: one system sound per status (`NSSound(named:)`: "Funk" for needs
    you, "Glass" for finished), off by default. Dock menu (`applicationDockMenu`): a row per pane that
    needs you or finished ("codex needs you · default · infra", a click selects it), a separator, New
    Tab.
13. **Settings ▸ Notifications.** For Needs you and Finished each: Notify (on), Badge the Dock icon
    (on for needs you, off for finished), Play a sound (off).

### Docs

14. The design pages already describe the Agents button and view (D61); make them match what you
    built. Check `status.mdx` (the Agents button, popover and view; notifications; Dock), D61, D42
    (dots and badges), the status table in `ui/theme-and-accessibility.mdx` (glyphs become dots, rings
    and badges; words and colors stay), `ui/window.mdx` (Agents button, popover, Agents view,
    workspace state icons), `features.mdx`, the glossary (Agents view, badge; drop "status area" and
    "Activity"), `ui/settings.mdx`, the keyboard table (⌘.).

## e2e

All status changes come from `pane.report_agent` through the e2e helper on a throwaway pane (source
`oriel-e2e`, increasing `seq`). The tests use two throwaway sessions, `oriel-e2e-<id>-a` (launched)
and `oriel-e2e-<id>-b` (opened as a second page through the Open Session sheet).

- Report `working` on a pane of another tab: that tab's status slot shows working (accessibility
  value "working"); the selected tab shows none; the workspace row's value says working.
- Report `blocked`: the tab's value is "needs you", the workspace row shows needs you, and the Agents
  button's value is "1 need you". Hover the button: the popover (id `agents.popover`) lists that
  agent; a click on it selects the tab, gives its card the keyboard, and the sidebar still shows
  workspaces.
- Report `blocked` in session `b` while `a` is in view: the Agents button shows no dot, the Dock badge
  is 1; show `b`'s page: the dot shows.
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
