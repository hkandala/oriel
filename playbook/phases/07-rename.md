# Phase 7: rename Herdlight to Oriel

Goal: no reference to "Herdlight", "herdlight" or the `hl` short form anywhere in the repo
(code, project, scripts, CI, docs, plan, research text), and everything still builds, lints
and passes e2e. Behavior does not change.

Already done by the orchestrator: GitHub repo renamed to `hkandala/oriel` (old URLs redirect),
local checkout moved to `~/code/oriel`.

## Decisions (from the user)

| What | Old | New |
|---|---|---|
| App name, display name | Herdlight | Oriel |
| Xcode project, targets, folders | `Herdlight.xcodeproj`, `Herdlight`, `HerdlightUITests` | `Oriel.xcodeproj`, `Oriel`, `OrielUITests` |
| Bundle ids | `dev.hkandala.herdlight`, `….uitests` | `dev.hkandala.oriel`, `dev.hkandala.oriel.uitests` |
| Swift package | `HerdrKit` | unchanged (it is the herdr adapter, not the app) |
| Plugin label prefix | `hl:` | `oriel:` |
| Floating-panes tab label | `hl:float` | `oriel:float` |
| Change-signal metadata token | `hl_rev` | `oriel_rev` |
| Metadata source | `user:herdlight` | `user:oriel` |
| Throwaway herdr sessions | `hl-e2e-*`, `hl-dev-*` | `oriel-e2e-*`, `oriel-dev-*` |
| SSH sockets folder | `~/Library/Caches/hl/` | `~/Library/Caches/oriel/` |
| State files | `~/.local/state/herdlight/` | `~/.local/state/oriel/` |
| Logs | `~/Library/Logs/Herdlight/` | `~/Library/Logs/Oriel/` |
| launchd labels | `dev.hkandala.herdlight.*` | `dev.hkandala.oriel.*` |
| Agent GUI lock, derived data | `/tmp/hl-gui.lock`, `/tmp/hl-dd-*` | `/tmp/oriel-gui.lock`, `/tmp/oriel-dd-*` |
| Other `hl-…` names (e.g. `hl-plugin`, `hl-git…`) | `hl-…` | `oriel-…` |
| Docs site | `herdlight.vercel.app` | Vercel project renamed to `oriel` (`oriel.vercel.app` if free); repo homepage updated |
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
