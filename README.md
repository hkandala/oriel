# Oriel

Oriel is a native SwiftUI app for macOS. It is a graphical client for
[herdr](https://github.com/herdrdev/herdr), the terminal multiplexer for AI coding agents. herdr keeps the
workspaces, tabs and panes. Oriel shows them: workspaces in a sidebar, tabs in the title row, each tab as a
page of live terminal cards laid out the way herdr splits them, and a sideways swipe to page between tabs.

It works with herdr on This Mac and on remote machines over SSH, in one or more windows. It can open, start,
stop and make sessions; make, rename, move and close workspaces, tabs and panes; split, zoom, resize and drag
panes; float a pane in its own window; show every tab at once in the overview; list the agents and their
states; find text in a pane; and jump anywhere with ⌘K. The
design is in [`docs/content/docs/`](docs/content/docs/).

## Requirements

- macOS 26 or later
- Xcode 27
- herdr 0.9.3 or later, found by `command -v herdr` in your login shell
- Homebrew, for SwiftFormat, SwiftLint and xcbeautify (`Brewfile`)

## Build, run and test

```
make setup      # brew bundle, and the git hooks (lint on every commit)
make run        # build and open the app on the default session
make run SESSION=oriel-dev-me   # open it on another session (agents: SESSION=oriel-dev-* only, see AGENTS.md)
make lint       # SwiftFormat and SwiftLint, as the hook and CI run them
make format     # fix what lint can fix
make build      # build the app
make test       # HerdrKit's unit and integration tests (swift test), and the three-finger check
make e2e        # the UI tests against throwaway herdr sessions (ONLY=… for some, ON_DEMAND_ONLY=1)
make strip-check   # after e2e: the empty strip check, with no accessibility client
make install    # a Release build copied to ~/Applications (make app, make dmg: the app or a disk image)
```

Pass `DERIVED_DATA=/tmp/oriel-dd-<name>` to keep separate build folders when several checkouts build at once.

## Code layout

```
Oriel/                     the app target (SwiftUI)
  App/                     @main, the windows, menu commands and the palette's command list
  Store/                   HostStore: the live @Observable model of one herdr session, and its writes;
                           a window's pages; machines
  Terminal/                libghostty glue: PaneTerminal (one pane's stream), PaneSurfaceView (keys,
                           mouse, scroll), PaneViewRegistry (which terminals stream)
  Views/                   title row, tab bar, sidebar, Agents view, strip and cards, overview, floating
                           panes, palette, Open Session, find bar, drag and drop, the Look tokens
OrielUITests/              XCUITest end-to-end suite (macOS)
Packages/HerdrKit/         Swift package, no UI: Exec (local, SSH, relay), HerdrClient (calls, events,
                           paced snapshots), models, split tree, TerminalStream, git status, starting a server
scripts/                   throwaway herdr sessions, the e2e helper and its swipe and drag tools, CI's sshd,
                           the shard split and the tests' measured times
plan/                      how we build it: the way of working, lessons, CI notes and the phase files
docs/                      the design site (MDX pages under docs/content/docs/)
resources/                 the app icon, the program icons and their sources, research notes
```

HerdrKit knows nothing about SwiftUI or libghostty; the app knows nothing about herdr's argv or JSON.

## How the tests work

- **Unit tests** (`make test`) cover logic with branches: decoding, the split tree, pacing, frame parsing, git
  status, SSH. A few integration tests start a throwaway herdr session and talk to it.
- **e2e tests** (`make e2e`) drive the real app with XCUITest. `scripts/e2e.sh` starts throwaway herdr sessions
  named `oriel-e2e-<id>-<letter>`, runs the suite and removes them all (and any launchd job the app made for
  them), even when tests fail. The UI test runner is sandboxed and cannot reach herdr, so
  `scripts/e2e-helper.py` serves herdr calls on localhost for the tests (API requests, `control` streams, stopping
  and starting a session, trackpad swipes and drags). It refuses any session it did not make. Tests assert
  through accessibility identifiers and through herdr itself, not through pixels.
- XCUITest moves the real mouse and types on the real keyboard: do not use the Mac while `make e2e` runs. The
  whole suite (about 170 tests) takes about 40 minutes on one Mac, so run the tests you change
  (`make e2e ONLY=OrielUITests/OrielUITests/testA`) and let CI run the rest.
- The stress, cost, frame-record and look-scene tests run only when asked (`make e2e ON_DEMAND_ONLY=1`).
- Never point the app or a test at a session you care about. Use `scripts/herdr-session.sh up oriel-dev-<name>` for
  hand testing, and `down` to remove it.

CI (GitHub Actions, `.github/workflows/ci.yml`) runs lint, the build, `make test` and the UI tests in 5
parallel jobs ([plan/ci.md](plan/ci.md)).

## Known limitations

- macOS only. What may come later (an iOS app, a chat view, plugins) is in
  [Future work](docs/content/docs/future-work.mdx).
- A window left in full screen opens as a normal window (macOS restored it with an empty title bar).
- IME composition (marked text, such as Japanese kana) is not tested yet. Committed text and dead keys work.
- Notifications and the Dock badge need a signed build: the ad-hoc dev build gets no notification permission.
- The UI tests share the app's defaults with your own Oriel (same bundle id): a run can change your settings.
- `Oriel.xcodeproj/.../Package.resolved`: if Xcode rewrites its `originHash` in your checkout, do not commit
  that change (`git checkout` the file). Command-line builds leave it unchanged.

## Design docs

Every design page is an MDX file under `docs/content/docs/`. Read them there, or run the site:

```
cd docs
pnpm install
pnpm dev
```

The site needs pnpm 10 or newer (`docs/package.json` pins it). With an older global pnpm, run
`npx pnpm@10 install` and `npx pnpm@10 dev` instead.

The workflow `.github/workflows/docs-deploy.yml` builds the docs site and deploys it to Vercel: a push to `main`
that changes `docs/` deploys production; a pull request only builds it. It needs the repository secrets
`VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` and `VERCEL_TOKEN` (Vercel project root directory: `docs`).
