# Phase 50: Agent control

Goal: build the recommended agent-control design: the `oriel` command and its protocol, so agents on This Mac and on
remote machines open and drive Oriel cards, ask whether they are shown, and manage plugins. Then replace today's
workarounds and the `oriel-panes` skill with one `oriel` skill.

Design: the recommended design, `~/Downloads/oriel-research/agent-control-design.html` (it wins), and the proposed
pages `docs/content/docs/future-work/agent-control/*.mdx`, which this phase moves out of future work and rewrites as
built. The user: "in parallel in a separate branch let's work on the agent control impl as well, go with your
recommended design, and once all the fixes i asked for above are done and agent control impl is also done, let's
merge the agent control impl on top of the main".

Branch `agent-control`, a Project: tracks from the report's build plan, a review per track, a docs pass, a final
review, then (after phase 49 is on main) a rebase onto main, two full CI runs green in a row plus the on-demand
suite on the exact head, and a fast-forward of main.

## The skill

"also update the oriel-panes skill, also call it just oriel skill and it should be fully based on the agent control
impl, keep it concise, simple, let it refer to herdr skill for any herdr related stuff, also use progressive
disclosure and have may be different md files where agent can load what only needed, keep the skill very clear and
simple and brief."

- `~/code/pi-hkandala/skills/oriel/`: a short `SKILL.md` (what Oriel is, how to tell it is there, the five commands
  an agent uses most, and links), plus one file per topic loaded only when needed (for example `cards.md`,
  `plugins.md`, `remote.md`). Every herdr detail points to the herdr skill (`herdr --skill`).
- The `oriel-panes` skill and its `placeholder.sh` go; pi-herd's `orielFloat` and `oriel-copy.ts` move onto the
  command (the report's migration table). Push pi-hkandala to master when the Oriel side is on main.

## Findings
