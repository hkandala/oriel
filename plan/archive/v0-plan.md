# The v0 plan and the UI polish request

Archived in phase 32, kept as history: the user's first request (v0, phases 1–6) and the UI polish request
(phases 10–21), with the decisions and risks of the time. The current plan is [../README.md](../README.md).

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
   ([talking-to-herdr](../../docs/content/docs/talking-to-herdr.mdx)): `remote-api-bridge` per
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

## UI polish (phases 10–21)

The request (from the user, structured): give Oriel every interface feature that Superlogical's Rex
app has and that works with herdr, built now even where the design put it in a later step, in the
window layout the user agreed in [ui-layout.md](../ui-layout.md) (mock-ups: `resources/mockups/layout.html`,
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
9. A few basic settings, in the menu bar for now; the Settings window comes after its mock-ups.
10. No explanatory text in the UI beyond what ui-layout.md lists.
11. Rex as a multiplexer is **not** built: it is future work (`docs/content/docs/rex-backend.mdx`).
    No tab tear-off.

The full list of what is built and what is left out, feature by feature, is
[ui-polish.md](ui-polish.md). Each phase updates the design pages it changes.

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
