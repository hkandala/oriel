# Oriel

Oriel is a native macOS app for [herdr](https://github.com/herdrdev/herdr), the terminal multiplexer for AI
coding agents. herdr keeps the workspaces, tabs and panes; Oriel shows them as live terminal cards in a
Liquid Glass window and lets you drive them with the mouse, the trackpad and the keyboard.

## What it does

- Sessions of This Mac and of remote machines over SSH, each session a page in the sidebar; several windows.
- Workspaces with their git branch, tabs in the title row, panes laid out as herdr splits them.
- Split, zoom, resize, swap and drag panes; move them to another tab or workspace.
- The Agents view: every agent of a session and who needs you, with notifications and a Dock badge.
- The overview of every tab, and panes that float in windows of their own.
- Drop files on a pane to paste their paths (copied over first on a remote machine).
- Find in a pane, ⌘-click links, the command palette (⌘K), and keys for everything.

## Requirements

- macOS 26 or later.
- herdr 0.9.3 or later on each machine, found by `command -v herdr` in the login shell. The Mac needs it only
  for its own sessions.
- Perl on remote machines (the SSH relay is a small Perl script; nearly every Unix has it).
- Dependencies: libghostty-spm (a Swift package at an exact pin, which brings DisplayLink) and the system
  `ssh`; nothing else ships in the app.
- To build: Xcode 27 and Homebrew (`make setup` installs SwiftFormat, SwiftLint and xcbeautify from the
  `Brewfile`). The docs site needs Node 22 and pnpm 10.

## Build and install

```sh
make setup      # Homebrew tools and the git hooks
make install    # a Release build copied to ~/Applications
make app        # the Release app only
make dmg        # a disk image of it
make run        # build and open the app (SESSION=<name> for one session; agents: oriel-dev-* only)
make lint build test   # checks, the build, the unit checks
make e2e        # the UI tests against throwaway herdr sessions (ONLY=… for some)
```

Pass `DERIVED_DATA=/tmp/oriel-dd-<name>` when several checkouts build at once.

## Use it

Install herdr, open Oriel, and it shows This Mac's `default` session (starting it if needed). Open more
sessions with Open Session (⌥⌘T), add a remote machine from the machine button, and press ⌘/ for the
keyboard shortcuts ([all of them](https://oriel-docs.vercel.app/docs/ui/theme-and-accessibility#keyboard-shortcuts)).

## Future work

Bundling herdr in the app, an iPhone and iPad app, a chat view for agents, image paste, plugins and other
pane kinds, floating status pills, a Settings window. Their designs are in
[Future work](docs/content/docs/future-work/index.mdx).

## Links

- Design docs: [`docs/content/docs/`](docs/content/docs/), published at
  [oriel-docs.vercel.app](https://oriel-docs.vercel.app) (`cd docs && pnpm install && pnpm dev` to run it).
- How it is built, for agents: [`playbook/`](playbook/README.md).
- Code: `Oriel/` (the app), `Packages/HerdrKit/` (herdr calls, no UI), `OrielUITests/` (UI tests),
  `scripts/`, `resources/` (the app icon, program icons and research notes).
