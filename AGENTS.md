# AGENTS.md

Oriel: a native SwiftUI client for herdr on macOS.

## Read first, every time

- `plan/workflow.md`: how we work. When a task needs phases and when not, worktrees and pushing, the GUI
  lock, herdr safety, how to start and brief agents, the phase loop, reviews and the coding rules. Follow
  it without being told.
- `plan/lessons.md`: problems that came back, and the rule for each.
- `plan/phases/`: one file per phase, with its Findings. Read the ones your change touches; a new phase is
  a new file there.
- The design in `docs/content/docs/` wins on any conflict about what the app does.

## The rules that never bend

- Ponytail: the simplest code that works; no speculative abstractions or "for later" code.
- `make lint build test` on the rebased tree before you push, and the UI tests your change touches (one
  local run under the GUI lock, or a chosen-tests CI run: `plan/ci.md`). Never `git commit --no-verify`,
  never `git stash`.
- herdr: the user's sessions are read only. Write only to throwaway sessions `oriel-e2e-*` / `oriel-dev-*`
  and delete them after. Every herdr argv carries `--session`; never call herdr focus methods.
- A rule a tool can check gets a lint rule or a script, not a line here.
