# AGENTS.md

Oriel: a native SwiftUI client for herdr on macOS.

## Read first, every time

- `playbook/workflow.md`: how we work. Follow it without being told.
- `playbook/lessons.md`: problems that came back.
- `playbook/phases/`: one file per phase; read the ones your change touches. A new phase is a new file there
  and a row in `playbook/README.md`.
- The design in `docs/content/docs/` wins on any conflict about what the app does.

## The rules that never bend

- Ponytail: the simplest code that works; no speculative abstractions or "for later" code.
- `make lint build test` on the rebased tree before you push, and the UI tests your change touches (local
  only when quick and the GUI lock is free, else a chosen-tests CI run: `playbook/ci.md`). A track or a
  feature pushes only after its review. Never `git commit --no-verify`, never `git stash`.
- herdr: the user's sessions are read only. Write only to throwaway sessions `oriel-e2e-*` / `oriel-dev-*`
  and delete them after. Every herdr argv carries `--session`; never call herdr focus methods.
- A rule a tool can check gets a lint rule or a script, not a line here.
