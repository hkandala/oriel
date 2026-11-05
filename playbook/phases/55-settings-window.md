# Phase 55: Settings window

Goal: a Settings window (⌘,) in the style of macOS System Settings, with the settings that work today: seven topic
pages in a sidebar, a page per machine and per plugin, and settings that plugins declare in their manifest. The plan is
idea 1 of the research `settings-plan.html`; the design is `docs/content/docs/ui/settings.mdx` (D106, D107).

The user's words: "can you also start one agent on settings window, go with your recommendation idea 1 and implement
everything end to end, and test and review everything".

## Track A: the window and the app's pages (p55-settings)
1. **The window.** A SwiftUI `Settings` scene: sidebar (General, Appearance, Terminal, Agents, Machines, Plugins,
   Privacy), search in the sidebar that rings the row it finds, 715 × 560 pt. Privacy shows only with approved websites.
2. **General and Appearance.** Focus follows mouse, Show Shortcuts; picture tiles for the look, the text size.
3. **Terminal.** Font, cursor, blink, Option as Meta, copy on select, through libghostty's configuration, live.
4. **Agents.** Terminal or Chat first, extra arguments and a New Pane switch per agent, the notification switches
   (the Ovvi ▸ Notifications submenu goes; the palette keeps three commands).
5. **Machines and Privacy.** The machine list and a page per machine (name, target, icon, Clear website data,
   Remove); the approved websites per machine.

## Track B: Plugins (p55-plugins)
1. **The Plugins page** replaces the Plugins panel; a plugin's page with its settings, permissions, Allow, Don't Allow
   and Forget Trust; a badge for plugins that wait.
2. **Plugin settings** in the manifest (toggle, choice, number, text, path), global scope, in `settings.json`, read
   by cards through plugin API 3 (`ovvi.settings.get`, the `settings` event).
3. **The default plugins** use them: File Explorer, Git, the browser.

## Findings

### Track A
- **Decisions.** A SwiftUI `Settings` scene with a `NavigationSplitView` and grouped forms; the sidebar toggle is
  removed. Privacy holds the approved websites and shows only when a machine has one. Agents switched off in New Pane
  join `hideInNewPane`, the list that hides plugins. Extra arguments go right after the command, before Ovvi's flags
  (OpenCode ignores what follows its `--`); the second try types the bare command. Blink on leaves libghostty's
  default (a program may still ask for a steady cursor); off sets `cursor-style-blink = false`. Copy on select is
  `clipboard`: libghostty-spm drops `true`'s selection-clipboard writes.
- **Left out.** The live terminal preview (every card shows a change at once), Disconnect, drag to reorder machines
  (a grouped form takes no `onMove`), and everything that needs an unbuilt plan (updates, telemetry, the tour, Open at
  Login, herdr import).
- **Cause.** With no main window's command list (Settings or About key), the disabled Close Pane took ⌘W: Close Window
  now has it there.
- **Tests.** UI tests pin the new keys at launch like the notification switches (the defaults are shared with the
  user's app); the Settings tests launch unpinned and put the shipped values back.
- **For the user.** The cursor shape and blink (no test can see them); Notification Settings… opens Ovvi's page in
  System Settings; a search pick rings its row for a second.

### Track B
- **Decisions.** The browser's one setting is its network for new cards on a remote machine (The Machine or This
  Mac); each card's chip still switches it. A choice is segmented with at most 4 options of at most 24 characters in
  all, else a pop-up. A path setting is a plain field (one value for every machine). The default plugins keep the
  user's own choice in their card's state and start new cards from the setting.
- **Left.** The Plugins badge counts waiting cards from `Plugin` init and deinit, so a waiting card that the kept-cards
  limit drops leaves the count while its pane still waits. A page that polls under the trust prompt after Forget Trust
  writes a `denied:` line to its log on every call.
- **For the user.** Git ▸ Diff layout with a diff open, File Explorer ▸ Show hidden files with a tree open, Browser ▸
  This Mac then a new remote browser card (its chip says This Mac), and a hand-edited `settings.json` with a typo (a
  switch then shows the notice and leaves the file as it is).
