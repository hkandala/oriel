# Phase 7: rename Herdlight to Ovvi

Goal: no reference to "Herdlight", "herdlight" or the `hl` short form anywhere in the repo
(code, project, scripts, CI, docs, plan, research text), and everything still builds, lints
and passes e2e. Behavior does not change.

Already done by the orchestrator: GitHub repo renamed to `hkandala/ovvi` (old URLs redirect),
local checkout moved to `~/code/ovvi`.

## Decisions (from the user)

| What | Old | New |
|---|---|---|
| App name, display name | Herdlight | Ovvi |
| Xcode project, targets, folders | `Herdlight.xcodeproj`, `Herdlight`, `HerdlightUITests` | `Ovvi.xcodeproj`, `Ovvi`, `OvviUITests` |
| Bundle ids | `dev.hkandala.herdlight`, `….uitests` | `dev.ovvi.app`, `dev.ovvi.app.uitests` |
| Swift package | `HerdrKit` | unchanged (it is the herdr adapter, not the app) |
| Plugin label prefix | `hl:` | `ovvi:` |
| Floating-panes tab label | `hl:float` | `ovvi:float` |
| Change-signal metadata token | `hl_rev` | `ovvi_rev` |
| Metadata source | `user:herdlight` | `user:ovvi` |
| Throwaway herdr sessions | `hl-e2e-*`, `hl-dev-*` | `ovvi-e2e-*`, `ovvi-dev-*` |
| SSH sockets folder | `~/Library/Caches/hl/` | `~/Library/Caches/ovvi/` |
| State files | `~/.local/state/herdlight/` | `~/.local/state/ovvi/` |
| Logs | `~/Library/Logs/Herdlight/` | `~/Library/Logs/Ovvi/` |
| launchd labels | `dev.hkandala.herdlight.*` | `dev.ovvi.app.*` |
| Agent GUI lock, derived data | `/tmp/hl-gui.lock`, `/tmp/hl-dd-*` | `/tmp/ovvi-gui.lock`, `/tmp/ovvi-dd-*` |
| Other `hl-…` names (e.g. `hl-plugin`, `hl-git…`) | `hl-…` | `ovvi-…` |
| Docs site | `herdlight.vercel.app` | Vercel project renamed to `ovvi` (`ovvi.vercel.app` if free); repo homepage updated |
| CI herdr version | 0.9.3 | 0.9.5 (the minimum supported stays 0.9.3) |

- Git history stays as it is. Images stay as they are (text in screenshots is not edited);
  image file names that contain the old name are renamed.
- Research and inspiration text in `resources/` is renamed too.
- Design decisions that name the old app (e.g. D39 "privacy prompts would name Herdlight")
  just use the new name; numbering does not change.

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

- The two new reports come from `/tmp/hl-brainstorm/plugin-panes.md` and
  `/tmp/hl-brainstorm/remote-plugins.md`, with their text renamed too.
- Fix every link to moved files (docs `reference/sources.mdx`, other docs, plan, README).
