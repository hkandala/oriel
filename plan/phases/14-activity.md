# Phase 14: agent activity, notifications and the Dock

Goal: Rex's way of showing agent activity, on herdr's data: working dots, status badges on icons, a
"seen" state for finishes, the Activity view (eye button, ⌘.), notifications, the Dock badge, sounds
and a Dock menu. This replaces the design's status area.

Read first: `plan/ui-polish.md`, `resources/research/clients/rex-ui.md` (status indicator, badges,
Activity, notification settings), `resources/inspirations/rex-app/` (tabs-with-status,
sidebar-activity), `docs/content/docs/status.mdx`, `docs/content/docs/layout.mdx` (selection and
"seen"), decisions D13, D14, D31, D42, D55, `Packages/HerdrKit/Sources/HerdrKit/Models.swift`
(`Agent`), `Oriel/Store/HostStore.swift`.

## Build

1. **HerdrKit.** Decode from `snapshot.agents[]`: `pane_id`, `terminal_id`, `agent`, `display_agent`,
   `agent_status`, `completion_seq`, `state_change_seq` (lenient, all optional except the pane id).
2. **Seen (D14).** A small value type in HerdrKit (unit tested: it branches) that takes each snapshot
   and the panes the user is looking at, and returns per pane: `working`, `needsYou`,
   `finishedUnseen`, or nothing, plus the changes since the last snapshot (for notifications).
   - Finished and not seen = `completion_seq` not null and different from the seen value.
   - The first sighting of an agent records its value as seen (no flood after launch).
   - Looking at a pane records its value: its tab is selected and the window is key.
   - The first snapshot after launch reports no changes. After a reconnect, changes against the last
     known state count.
   - Each change carries the time the app saw it, for the "3m" ages.
   The store keeps the result per pane and rolls it up per tab and workspace (needs you > finished >
   working).
3. **Working dots.** Replace the static ◔ (D42 changes). Three dots 3.5 pt, corner radius 1.75, 5.5 pt
   apart, in a 14 × 14 pt box. Each dot's opacity runs 0.3 → 0.85 → 0.3 over 1.2 s (key times 0, 0.25,
   0.5), dot *i* starts 0.2 s × *i* later, all computed from the wall clock so every tab is in step.
   Draw with a `TimelineView(.animation(minimumInterval: 1/15))`, only while visible. Reduce Motion:
   three still dots at 0.6. Shown in the tab's status slot on every tab with a working agent except
   the selected one, in sidebar rows and on collapsed sections.
4. **Badges.** A 7 pt dot on the top-right of the front icon tile, with a 1.5 pt ring in the
   background color: needs-you color (amber) when an agent needs you, finished color (green) when a
   finish is unseen. The status slot order becomes: × while hovered > working dots. The words stay for
   VoiceOver ("codex, needs you").
5. **Bounce and announcement.** When a tab's state turns to needs you or finished while it is not
   selected: its front icon bounces once (scale 1 → 1.15 → 1, spring, off under Reduce Motion), and
   its title shows "‹agent› needs you" or "‹agent› finished" for 3 s, then the title again. A long text
   scrolls once (30 pt/s) instead of fading.
6. **Activity view.**
   - An eye button (`eye`, `eye.fill` while on) in the title bar, before ⌘, with a dot badge: amber if
     anything needs you, else green if a finish is unseen. ⌘. and View ▸ Show Activity toggle it.
   - Sidebar shown: the sidebar lists Activity instead of tabs. Sidebar hidden: the same list in a
     floating glass panel under the eye, 320 pt wide, at most 480 pt tall (`floatingPanel`).
   - Content: one section per workspace (when remote machines come, sections group under each
     machine); one row per agent pane that needs you or has an unseen finish
     (and, with "Show working agents" on, the working ones). Row 44 pt: tile, title (agent display name,
     else the tab title), and on the right a status capsule ("Needs you" amber, "Done" green, "Working"
     blue: text in the color on a 0.15 fill of it); second line: tab label in secondary text and the
     age on the right ("now", "3m", "2h").
   - Order in a section: needs you, then done, then working; ties by age, newest first; rows never jump
     while the pointer is over the list.
   - A click selects the workspace and tab, gives that pane the keyboard (never herdr focus, D13), and
     so records it seen.
   - Empty: "Nothing needs you". Footer: a "Show working agents" toggle.
7. **Notifications (D31).** `UNUserNotificationCenter`, delegate set at launch.
   - A pane turns to needs you: "‹agent› needs you", body "‹workspace› · ‹tab›".
   - A new finish: "‹agent› finished", same body, unless the user is looking at that pane.
   - Only while the app is not active, or the pane is not shown.
   - Id `"<session>|<terminal_id>"`, so a newer one replaces the older; removed when the pane is seen.
   - A click activates the app and selects the pane.
8. **Dock.** Badge = the number of panes that need you, plus unseen finishes when that setting is on.
   Sounds: one system sound per status (`NSSound(named:)`: "Funk" for needs you, "Glass" for finished),
   off by default. Dock menu (`applicationDockMenu`): a row per pane that needs you or finished
   ("codex needs you · infra", a click selects it), a separator, New Tab.
9. **Settings ▸ Notifications.** For Needs you and Finished each: Notify (on), Badge the Dock icon
   (on for needs you, off for finished), Play a sound (off). Plus "Show working agents in Activity"
   (the same toggle as the list footer).
10. **Docs.** Rewrite `status.mdx` (status area → Activity; notifications; Dock), D42 (dots and
    badges), the status table in `ui/theme-and-accessibility.mdx` (glyphs become dots and badges; words
    and colors stay), `ui/window.mdx` (eye button), `features.mdx`, the glossary (Activity, badge; drop
    "status area"), `ui/settings.mdx`.

## e2e

All status changes come from `pane.report_agent` through the e2e helper on a throwaway pane (source
`oriel-e2e`, increasing `seq`).

- Report `working` on a pane of another tab: that tab's status slot shows working (accessibility
  value "working"); the selected tab shows none.
- Report `blocked`: the tab's value is "needs you", the eye's value says 1 needs you, the Activity
  list (⌘.) has the row; a click on it selects the tab and gives its card the keyboard.
- Report `working` then `idle`: the tab shows "finished"; selecting the tab clears it; the Activity
  row goes.
- Relaunch with an agent already finished: no "finished" badge (first sighting is seen).
- Sidebar hidden: ⌘. opens the popup; Esc closes it.
- Unit tests for the seen type: first sighting, a finish, a seen finish, a restart of herdr (counter
  back to 0), a reconnect.

## Done when

- Screenshots: tabs with working dots, a needs-you badge and a finished badge; Activity in the
  sidebar and as a popup; a notification banner; the Dock badge.
