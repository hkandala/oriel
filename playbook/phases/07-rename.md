# Phase 7: the app's name and the research folder

Goal: one name, Ovvi, in the code, the project, the scripts, CI, the docs, the plan and the research text, and
everything still builds, lints and passes e2e. Behavior does not change.

## Names (from the user)

| What | Name |
|---|---|
| App name, display name | Ovvi |
| Xcode project, targets, folders | `Ovvi.xcodeproj`, `Ovvi`, `OvviUITests` |
| Bundle ids | `dev.ovvi.app`, `dev.ovvi.app.uitests` |
| Swift package | `HerdrKit` (it is the herdr adapter, not the app) |
| Plugin label prefix | `ovvi:` |
| Floating-panes tab label | `ovvi:float` |
| Change-signal metadata token | `ovvi_rev` |
| Metadata source | `user:ovvi` |
| Throwaway herdr sessions | `ovvi-e2e-*`, `ovvi-dev-*` |
| SSH sockets folder | `~/Library/Caches/ovvi/` |
| State files | `~/.local/state/ovvi/` |
| Logs | `~/Library/Logs/Ovvi/` |
| launchd labels | `dev.ovvi.app.*` |
| Agent GUI lock, derived data | `/tmp/ovvi-gui.lock`, `/tmp/ovvi-dd-*` |
| Other names of the app's own (e.g. `ovvi-plugin`, `ovvi-git…`) | `ovvi-…` |
| Docs site | the Vercel project `ovvi`; the repo's homepage points to it |
| CI herdr version | 0.9.5 (the minimum supported stays 0.9.3) |

- Git history stays as it is. Images stay as they are (text in screenshots is not edited).
- Research and inspiration text in `resources/` uses the name too.
- Design decisions keep their numbers.

## Research folder: group into sub folders

```text
resources/research/
  BRIEF.md                    shared brief for research agents
  herdr/                      herdr-core.md
  clients/                    macos-clients.md, mobile-clients.md, web-clients.md,
                              web-clients-notes/, primary-repos.md, repo-list.md, gorex.md
  plugins/                    plugin-architecture.md, plugin-system-v2.md,
                              plugin-system-v2-spike/, plugin-panes.md (new), remote-plugins.md (new)
  ui/                         floating-panels.md, floating-panes.md (+ floating-panels-smoke.png)
```

- The two new reports come from a brainstorm in `/tmp`: `plugin-panes.md` and `remote-plugins.md`.
- Fix every link to moved files (docs `reference/sources.mdx`, other docs, plan, README).
