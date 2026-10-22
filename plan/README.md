# Oriel v0 plan

**Status: v0 is done** (phases 1–6 merged): the v0 subset of build-order step 1, This Mac only. See the root
`README.md` for how to build, run and test.

Deferred past v0 (in the design, not built): remote machines over SSH, the iOS app (the target only builds and
shows an empty state), plugins and plugin cards, the chat view, floating panes, notifications, the Dock badge,
the Agents view, pills and agent rows in the sidebar, Start an agent, the "seen" state for finished agents,
drag and drop (with swapping and moving panes), divider drag, keyboard resize, equal splits and divider
double-click, renaming and reordering tabs and workspaces, more machines in the sidebar ("Add Remote Host" is
a placeholder), a text size setting, IME composition tests, and trackpad gestures in e2e (checked by hand).

**Next: UI polish (phases 10–21)**, see [UI polish](#ui-polish-phases-1021) below.

The working plan for the first app code. The design lives in `docs/content/docs/` and wins
on any conflict, except where this file narrows the scope for v0, and except `plan/ui-layout.md`, which
wins for phases 10–21 until the pages match it.

## The request (from the user, structured)

Build the first, very basic version of the Oriel app:

1. **Scaffold.** A standard Xcode project (created the way Xcode creates it), one
   multiplatform SwiftUI app target. macOS is the real target. iOS is boilerplate only: it
   builds, launches and shows an empty state. No iOS backend, no simulator work in v0.
2. **Terminal panes with libghostty.** Use the official `Lakr233/libghostty-spm`
   (`GhosttyTerminal`). Switch to uHerdr's patched build only if tests show double replies
   to terminal queries.
3. **Interface like herdr.** Sidebar, tabs, panes, horizontal and vertical splits, laid out
   exactly as herdr lays them out (its split tree and ratios).
4. **First backend: herdr on This Mac.** Follow the design
   ([talking-to-herdr](../docs/content/docs/talking-to-herdr.mdx)): `remote-api-bridge` per
   call, one `events.subscribe` stream, paced `session.snapshot` reads, and
   `herdr terminal session control` per visible pane.
5. **Live panes.** As soon as the app opens, the selected tab's panes attach and fit their
   card (cols × rows from the card size). Typing, clicks, Nerd Font glyphs and scrolling
   work.
6. **Horizontal scrolling across tabs.** One tab = one page in a horizontal strip. A
   sideways trackpad swipe pages between tabs.
7. **Session picker.** The sidebar lets the user pick a herdr session
   (`herdr session list`). Default: `default`.
8. **Liquid Glass**, dark theme, and the look of the reference screenshots in
   `resources/inspirations/ui-target/` (frosted window, glass sidebar with filter, session
   picker with filter, title-bar tabs, frosted pane cards). See phase 3b.
9. **Clear modules**, easy to extend later (machines, iOS, plugins come after v0).
10. **Ponytail, strictly.** The simplest thing that works. No speculative code.
11. **End-to-end tests first.** The app must be testable end to end, by agents too: launch
    it, see the GUI, drive it, fix what breaks. Unit tests only where logic is non-trivial.
12. **CI.** GitHub Actions runs lint, builds and the e2e suite.
13. **Lint and format** on every commit (pre-commit hook) and in CI.
14. **Small atomic commits**, pushed regularly.
15. **`AGENTS.md`**, concise. Anything a tool can check goes in a tool, not in prose.

## Confirmed decisions

| Topic | Decision |
|---|---|
| Transport | The design: `herdr --session S remote-api-bridge` (one call per request, 10 s timeout), events on one long-lived bridge run, terminals via `herdr --session S terminal session control <terminal_id>` |
| Scope | This Mac only. Read the layout, show it live, type, click, scroll, resize to fit, swipe tabs, pick a session. No divider drag, drag and drop, close/split UI, plugins, chat, floating panes, zoom, remote machines, notifications. Widened by phase 4b: close, split and zoom buttons, new tab/workspace/session, the ⌘K palette |
| iOS | Boilerplate: the same target builds for iOS and shows an empty state |
| Terminal | Official `libghostty-spm`, exact pin |
| Project | A committed `Oriel.xcodeproj` in Xcode's own format (file-system synchronized groups), plus a local Swift package `HerdrKit` |
| Lint / format | SwiftFormat (formatting) + SwiftLint (lint), the most common pair in the Swift community |
| CI | GitHub Actions, `runs-on: xcode-27`. Repo is public |
| herdr safety | Existing sessions: read only. Every write goes to throwaway sessions named `oriel-e2e-*` / `oriel-dev-*`, cleaned up afterwards |
| Bundle id | `dev.hkandala.oriel`, signed to run locally, no team. App Sandbox off, Hardened Runtime on |
| Minimum OS | macOS 26, iOS 26 |

## Modules

```
Oriel.xcodeproj
Oriel/                     the app target (SwiftUI, macOS + iOS)
  App/                     @main, scenes, launch arguments
  Store/                   HostStore: the live @Observable model of one herdr session
  Terminal/                libghostty glue, TerminalStream wiring, PaneViewRegistry
  Views/                   Palette, SessionPicker, Sidebar, Strip, Style, TitleBar
OrielUITests/              XCUITest end-to-end suite (macOS)
Packages/HerdrKit/         Swift package, no UI: Exec, ProcessExec, HerdrClient (call,
                           events, pacing), lenient models, split-tree rebuild,
                           TerminalStream (control NDJSON). Tests: `swift test`
scripts/                   e2e session setup/teardown, helpers
```

`HerdrKit` knows nothing about SwiftUI or libghostty. The app knows nothing about argv or
JSON. That seam is where remote machines and iOS plug in later.

## Phases

| # | Phase | File |
|---|---|---|
| 1 | Scaffold, tooling, CI, e2e harness | [phases/01-scaffold.md](phases/01-scaffold.md) |
| 2 | HerdrKit control plane | [phases/02-herdrkit.md](phases/02-herdrkit.md) |
| 3 | App shell: sidebar, tabs, strip, splits | [phases/03-app-shell.md](phases/03-app-shell.md) |
| 3b | UI style: match the reference look | [phases/03b-ui-style.md](phases/03b-ui-style.md) |
| 4 | Live terminals | [phases/04-terminals.md](phases/04-terminals.md) |
| 4b | Actions: close, zoom, new tab/workspace/session, palette | [phases/04b-actions.md](phases/04b-actions.md) |
| 5 | Swipe across tabs, tab pills, chrome polish | [phases/05-strip-and-glass.md](phases/05-strip-and-glass.md) |
| 6 | Hardening and v0 wrap-up | [phases/06-hardening.md](phases/06-hardening.md) |

Rules for working: [rules.md](rules.md). Coding standards: [standards.md](standards.md).

## UI polish (phases 10–21)

The request (from the user, structured): give Oriel every interface feature that Superlogical's Rex
app has and that works with herdr, built now even where the design put it in a later step, in the
window layout the user agreed in [ui-layout.md](ui-layout.md) (mock-ups: `resources/mockups/layout.html`,
scenes A–K). Rex was reverse engineered for this (`resources/research/clients/rex-ui.md`,
`rex-server.md`, screenshots in `resources/inspirations/rex-app/`). In short:

1. Rex's look and behavior for the tab bar, pane cards, dividers, palette and states, with Rex's sizes
   and timings.
2. The agreed layout: a machine (This Mac now) per window and several windows; one title row with the
   sidebar toggle, the machine button, the workspace button (sidebar collapsed only), the tab bar
   always in the title row, and the Agents button; a sidebar with one Arc-style page per session open
   in the window, listing workspaces like herdr (state, git branch, ahead and behind, worktrees); the
   Open Session sheet to create, start or open a session.
3. Light and dark (and Auto), and two interface styles: Glass and Classic. No other themes, no
   compact density.
4. Program icons from our own SVG set (`resources/icons/`, open licenses), overlapping per pane in
   each tab, with status badges.
5. Agents: working dots, needs-you and finished badges, workspace state icons, the needs-you popover,
   the session-scoped Agents view, notifications, the Dock badge.
6. Several windows with per-session control: the window with the last terminal input controls, the
   other watches with Take Back.
7. The hover card (peek), keycap hints, tooltips with keys.
8. Pane resizing, balancing, moving with keys, context menus, drag and drop within what herdr allows.
9. A Settings window with a few basic settings.
10. No explanatory text in the UI beyond what ui-layout.md lists.
11. Rex as a multiplexer is **not** built: it is future work (`docs/content/docs/rex-backend.mdx`).
    No tab tear-off.

The full list of what is built and what is left out, feature by feature, is
[ui-polish.md](ui-polish.md). Each phase updates the design pages it changes.

| # | Phase | File |
|---|---|---|
| 10 | Appearance (Auto, Light, Dark) and interface style (Glass, Classic) | [phases/10-appearance.md](phases/10-appearance.md) |
| 11 | Settings window and terminal options | [phases/11-settings.md](phases/11-settings.md) |
| 12 | Program icons | [phases/12-program-icons.md](phases/12-program-icons.md) |
| 13 | Title row, tab bar and menus | [phases/13-title-row.md](phases/13-title-row.md) |
| 14 | Sidebar: session pages, workspace rows and the Open Session sheet | [phases/14-sidebar.md](phases/14-sidebar.md) |
| 15 | Agents, notifications and the Dock | [phases/15-agents.md](phases/15-agents.md) |
| 16 | Several windows and per-session control | [phases/16-windows.md](phases/16-windows.md) |
| 17 | Pane cards and layout | [phases/17-panes-and-layout.md](phases/17-panes-and-layout.md) |
| 18 | Drag and drop | [phases/18-drag-and-drop.md](phases/18-drag-and-drop.md) |
| 19 | Hover card and tooltips | [phases/19-hover-card.md](phases/19-hover-card.md) |
| 20 | Command palette and the key map | [phases/20-palette-and-keys.md](phases/20-palette-and-keys.md) |
| 21 | Find, links, states and finish | [phases/21-find-and-finish.md](phases/21-find-and-finish.md) |

The phases run in this order, one implementer at a time ([rules.md](rules.md)); each builds on the
tokens and views of the ones before.

The orchestrator starts each phase with the brief in
[execution.md](execution.md#phase-agent-brief-the-orchestrator-sends-this).

## Known risks (check early)

- **Key encoding.** herdr frames carry none of the inner app's modes (application cursor
  keys, kitty keyboard, bracketed paste). libghostty encodes keys from its own state, which
  may be wrong. herdr-web solved it by sending special keys as herdr logical keys
  (`pane.send_keys`). Phase 4 tests arrows in `less`/`vim` and Shift+Enter, and picks the
  simplest path that works.
- **Session resolution for `terminal session`.** herdr-web had to set `HERDR_SOCKET_PATH`;
  the design uses `--session S`. Phase 2 checks which one herdr 0.9.3 honors.
- **Scroll routing.** Terminal views eat scroll events; horizontal swipes must page the
  strip (design: one `NSEvent` monitor with an axis lock). Phase 5.
- **XCUITest drives the real mouse and keyboard** on this Mac. Local e2e runs interrupt
  the user; keep them short and scoped.

## References

- herdr-web (`~/code/herdr-web`, the user's working web client): stream handling, input,
  mouse and sizing notes in its README and `server/terminal-stream.ts`, `src/lib/keys.ts`.
- `resources/research/herdr/herdr-core.md`, `resources/research/clients/macos-clients.md`,
  `resources/research/clients/gorex.md` (tab bar behavior).
- libghostty-spm README and its `Example/GhosttyTerminalApp/`.
