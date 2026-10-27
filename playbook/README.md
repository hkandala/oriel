# Playbook

How Oriel is built, for the agents that build it. What the app does is in `docs/content/docs/`; how to build,
run and test it is in the root `README.md`.

| File | What it holds |
|---|---|
| [workflow.md](workflow.md) | How we work |
| [lessons.md](lessons.md) | Problems that came back, and the rule for each |
| [ci.md](ci.md) | How CI runs, and how to run, watch and read it |
| [phases/](phases/) | One file per phase: what was asked and its Findings; a new phase adds a row below |

## Phases

| # | Phase | File |
|---|---|---|
| 1 | Scaffold, tooling, CI, e2e harness | [01-scaffold.md](phases/01-scaffold.md) |
| 2 | HerdrKit control plane | [02-herdrkit.md](phases/02-herdrkit.md) |
| 3 | App shell: sidebar, tabs, strip, splits | [03-app-shell.md](phases/03-app-shell.md) |
| 3b | UI style: match the reference look | [03b-ui-style.md](phases/03b-ui-style.md) |
| 4 | Live terminals | [04-terminals.md](phases/04-terminals.md) |
| 4b | Actions: close, zoom, new tab, workspace and session, palette | [04b-actions.md](phases/04b-actions.md) |
| 5 | Swipe across tabs, tab pills, chrome polish | [05-strip-and-glass.md](phases/05-strip-and-glass.md) |
| 6 | Hardening and v0 wrap-up | [06-hardening.md](phases/06-hardening.md) |
| 7 | Rename Herdlight to Oriel | [07-rename.md](phases/07-rename.md) |
| 8 | Design refresh | [08-design-refresh.md](phases/08-design-refresh.md) |
| 9 | Simplify the design: same features, simpler mechanisms | [09-simplify.md](phases/09-simplify.md) |
| 10 | Appearance (Auto, Light, Dark) and interface style (Glass, Classic) | [10-appearance.md](phases/10-appearance.md) |
| 11 | Font size and menus | [11-settings.md](phases/11-settings.md) |
| 12 | Program icons | [12-program-icons.md](phases/12-program-icons.md) |
| 13 | Title row, tab bar and menus | [13-title-row.md](phases/13-title-row.md) |
| 14 | Sidebar: session pages, workspace rows, Open Session | [14-sidebar.md](phases/14-sidebar.md) |
| 15 | Agents, notifications and the Dock | [15-agents.md](phases/15-agents.md) |
| 16 | Several windows and per-session control | [16-windows.md](phases/16-windows.md) |
| 17 | Pane cards and layout | [17-panes-and-layout.md](phases/17-panes-and-layout.md) |
| 18 | Drag and drop | [18-drag-and-drop.md](phases/18-drag-and-drop.md) |
| 19 | Hover card and tooltips | [19-hover-card.md](phases/19-hover-card.md) |
| 20 | Command palette and the key map | [20-palette-and-keys.md](phases/20-palette-and-keys.md) |
| 21 | Find, links, states and finish | [21-find-and-finish.md](phases/21-find-and-finish.md) |
| 22 | Visual match with Rex | [22-visual-match.md](phases/22-visual-match.md) |
| 23 | Comment pass | [23-comments.md](phases/23-comments.md) |
| 24 | Fixes from the user's first hands-on use | [24-feedback-fixes.md](phases/24-feedback-fixes.md) |
| 25 | Second feedback: keys, agents, sessions, floating panes, speed | [25-second-feedback.md](phases/25-second-feedback.md) |
| 26 | Remote hosts, first prototype | [26-remote-hosts.md](phases/26-remote-hosts.md) |
| 27 | Third feedback: live surfaces, the overview | [27-third-feedback.md](phases/27-third-feedback.md) |
| 28 | Fourth feedback: empty sessions, overview, floats, remote hosts | [28-fourth-feedback.md](phases/28-fourth-feedback.md) |
| 29 | Fifth feedback: tab drags, menus, scale, selection colors | [29-fifth-feedback.md](phases/29-fifth-feedback.md) |
| 30 | Sixth feedback: many tabs, two windows, three-finger swipes | [30-sixth-feedback.md](phases/30-sixth-feedback.md) |
| 31 | Seventh feedback: selection in view, gestures, float requests, CI | [31-seventh-feedback.md](phases/31-seventh-feedback.md) |
| 32 | Final review of the whole repository and cleanup | [32-final-review.md](phases/32-final-review.md) |
| 33 | Eighth feedback: iOS removed, chrome, About panel, remote drops, this playbook | [33-eighth-feedback.md](phases/33-eighth-feedback.md) |
