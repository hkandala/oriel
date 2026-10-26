# Working rules

Roles and the phase loop are in [workflow.md](workflow.md) and [execution.md](execution.md). Reviewers are
read only: they never edit files or commit, and report a numbered list with file:line, severity (blocker /
should / nit) and a concrete fix.

## Commits

- Small and atomic: one logical change per commit, with its tests. Commit as soon as a
  step builds and passes checks. Push after each green step that builds.
- Conventional subject line: `feat(herdrkit): …`, `fix(app): …`, `chore(ci): …`,
  `test(e2e): …`, `docs: …`. Imperative, ≤ 72 chars.
- The pre-commit hook (`.githooks/pre-commit`) must pass. Never `--no-verify`.
- Never commit build output, DerivedData, `.xcresult`, screenshots or secrets.

## Building and running

- Use the `Makefile` targets (`make lint`, `make format`, `make build`, `make test`,
  `make e2e`, `make run`). If you need a new command, add a target.
- Concurrent agents must not share DerivedData: pass `DERIVED_DATA=/tmp/oriel-dd-<agent-name>`
  (the Makefile honors it).
- Only one agent drives the GUI at a time (XCUITest and manual runs take over the real mouse and keyboard).
  Take the GUI lock before any GUI driving (running the app and clicking, screenshots that need the app
  frontmost, `make e2e`, `make strip-check`) and release it in the same command, also on failure:

  ```sh
  ( mkdir /tmp/oriel-gui.lock || exit 1; trap 'rm -rf /tmp/oriel-gui.lock' EXIT
    echo "$NAME $(date +%H:%M)" > /tmp/oriel-gui.lock/owner; make e2e ONLY=… )
  ```

  If the lock is there, do not wait in a loop: work on, and try again later. Hold it for one run, at most
  10 minutes. Never remove another agent's lock or the user's (owner "user"). The GUI budget in
  [execution.md](execution.md#gui-budget-the-user-works-on-this-mac) says who may run what, and how often.
  Never send keys with `osascript`.
- Screenshots: `screencapture -x -l <windowid> <file>` for the app window, or the
  attachments in the `.xcresult`. Put the ones you report in `/tmp/oriel-shots/`.

## herdr safety

- Existing sessions (`default` and any other listed by `herdr session list`): read only.
  No writes, no `control` streams, no `--takeover`. Use `observe` or `pane.read` to look.
- Writes, `control` streams and layout changes go only to throwaway sessions named
  `oriel-e2e-<id>` (tests) or `oriel-dev-<agent>` (manual work). Stop and delete them when done
  (`herdr session stop`, `herdr session delete`). `scripts/` has helpers.
- When running the app by hand against a real session, launch it with the throwaway session
  selected (`-session oriel-dev-<agent>` launch argument), never `default`.
- Remote machines: tests use CI's sshd on localhost (`scripts/ci-sshd.sh`). Never connect to the user's
  remote hosts.

## Docs site

- The docs deploy only through `.github/workflows/docs-deploy.yml` and the Vercel project `oriel`.
  Vercel's own git deploys are off (`docs/vercel.json`): with them on, every push to main deployed (81 a
  day) and hit the free plan's 100 deploys a day.
- Run the `vercel` CLI only from the repo root (linked to `oriel`). In another folder, `vercel pull --yes`
  creates and links a new project without asking.
