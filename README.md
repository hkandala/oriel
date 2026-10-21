# Oriel

Oriel is a native SwiftUI app for macOS. It is a graphical client for
[herdr](https://github.com/herdrdev/herdr), the terminal multiplexer for AI coding agents. herdr keeps the
workspaces, tabs and panes; Oriel shows them in one window: workspaces and tabs in a sidebar, each tab as a
page of live terminal cards laid out the way herdr splits them, and a sideways swipe to page between tabs.

v0 talks to herdr on this Mac only. It can switch sessions, start a stopped one, make tabs, workspaces and
sessions, split, zoom and close panes, and jump anywhere with ⌘K. The iOS target builds and shows an empty state.
The full design, including what comes later, is in [`docs/content/docs/`](docs/content/docs/).

## Requirements

- macOS 26 or later
- Xcode 27
- herdr 0.9.3 or later on your `PATH` (the app reads your login shell's `PATH`)
- Homebrew, for SwiftFormat, SwiftLint and xcbeautify (`Brewfile`)

## Build, run and test

```
make setup      # brew bundle, and the git hooks (lint on every commit)
make run        # build and open the app on the default session
make run SESSION=oriel-dev-me   # open it on another session (agents: SESSION=oriel-dev-* only, see AGENTS.md)
make lint       # SwiftFormat and SwiftLint, as the hook and CI run them
make format     # fix what lint can fix
make build      # the macOS and iOS builds
make test       # HerdrKit's unit and integration tests (swift test)
make e2e        # the UI tests against throwaway herdr sessions
```

Pass `DERIVED_DATA=/tmp/oriel-dd-<name>` to keep separate build folders when several checkouts build at once.

## Code layout

```
Oriel/                     the app target (SwiftUI, macOS + iOS)
  App/                     @main, the window, menu commands, the detail view
  Store/                   HostStore: the live @Observable model of one herdr session, and its writes
  Terminal/                libghostty glue: PaneTerminal (one pane's stream), PaneSurfaceView (keys,
                           mouse, scroll), PaneViewRegistry (which terminals stream)
  Views/                   Sidebar, TitleBar, Strip (pages, split layout, cards), SessionPicker, Palette, Style
OrielUITests/              XCUITest end-to-end suite (macOS)
Packages/HerdrKit/         Swift package, no UI: Exec/ProcessExec (child processes), HerdrClient (calls,
                           events, paced snapshots), models, split tree, TerminalStream, starting a server
scripts/                   herdr-session.sh (throwaway sessions), e2e.sh and e2e-helper.py (UI test setup)
plan/                      the v0 plan, phase files and their findings
docs/                      the design site (MDX pages under docs/content/docs/, the overview in docs/public/overview/)
resources/                 research notes and UI references
```

HerdrKit knows nothing about SwiftUI or libghostty; the app knows nothing about herdr's argv or JSON.

## How the tests work

- **Unit tests** (`make test`) cover logic with branches: decoding, the split tree, pacing, frame parsing. Two
  integration tests start a throwaway herdr session and talk to it.
- **e2e tests** (`make e2e`) drive the real app with XCUITest. `scripts/e2e.sh` starts throwaway herdr sessions
  `oriel-e2e-<id>-a`, `-b`, `-c` (stopped, for "Show stopped") and `-e` (stopped and started by a test); `-d` is
  the name the New Session test makes. It runs the suite and removes them all (and any launchd job the app made for them)
  even when tests fail. The UI test runner is sandboxed and cannot reach herdr, so `scripts/e2e-helper.py` serves
  herdr calls on localhost for the tests: API requests, a second `control` stream to tell a held pane from a free
  one, a list of the session's streams, and stopping or starting a session. It refuses any session it did not
  make. Tests assert through accessibility identifiers and through herdr itself, not through pixels.
- XCUITest moves the real mouse and types on the real keyboard: don't use the Mac while `make e2e` runs (32 tests,
  about 6.5 minutes locally).
- Never point the app or a test at a session you care about. Use `scripts/herdr-session.sh up oriel-dev-<name>` for
  hand testing, and `down` to remove it.

CI (GitHub Actions, `.github/workflows/ci.yml`) runs lint, both builds, and `make test e2e` with herdr 0.9.5.

## Known limitations

- This Mac only: no remote machines, no iOS app yet.
- No chat view, plugins, floating panes, notifications, status area, drag and drop, or divider drag.
- A window left in full screen opens as a normal window (macOS restored it with an empty title bar).
- IME composition (marked text, such as Japanese kana) is not tested yet. Committed text and dead keys work.
- Trackpad swipes between tabs are checked by hand; the e2e suite covers mouse-wheel paging.
- `Oriel.xcodeproj/.../Package.resolved`: if Xcode rewrites its `originHash` in your checkout, don't commit
  that change (`git checkout` the file). Command-line builds leave it unchanged.

## Design docs

Every design page is an MDX file under `docs/content/docs/`. Read them there, or run the site:

```
cd docs
pnpm install
pnpm dev
```

The site needs pnpm 10 or newer (`docs/package.json` pins it). With an older global pnpm, run
`npx pnpm@10 install` and `npx pnpm@10 dev` instead. `docs/public/overview/index.html` is a one-page overview with no
build step (`open docs/public/overview/index.html`).

The raw inspiration videos and frames are kept locally only; they are not in git.

The workflow `.github/workflows/docs-deploy.yml` builds the docs site and deploys it to Vercel: a push to `main`
that changes `docs/` deploys production; a pull request only builds it. It needs the repository secrets
`VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` and `VERCEL_TOKEN` (Vercel project root directory: `docs`).
