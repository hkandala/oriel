# Phase 31: The user's seventh round of feedback

The user tested on 2026-10-26 (about 01:00). Capture E:
`/Users/hkandala/Library/Application Support/scrawl/captures/scrawl-1793001818197-6f5d-10.scrawl` (read it
with the scrawl skill, `/Users/hkandala/.agents/skills/scrawl/SKILL.md`). Each lane writes `## Findings` at
the end. `/tmp/oriel-gui.lock` is held for "user"; UI tests run on CI until the orchestrator says otherwise.

## Lane S: selection stays in view (items 1, 2)

1. **The sidebar scrolls to the selected workspace.** In a session with many workspaces, when the
   selected workspace changes (from the overview, ⌃⌘[ ], ⌃⌘1–9, a three-finger swipe, the palette, a
   notification), the sidebar's list scrolls just enough to show its row. The Agents view does the same for
   its selected agent row.
2. **The tab bar's selection capsule gets stuck** (capture E #2 0:19–#6 0:32): after zooming from the
   overview into a middle tab of a workspace with many tabs, the capsule sits between two tabs ("long
   horizon" half covered) until the next click. It happens every time. Find why (the capsule reads the
   strip's offset, and phase 29 lane T's `.defaultScrollAnchor` may set the first offset without the change
   the capsule listens to) and fix it for every way a tab is shown.

## Lane G: gestures (items 3–6)

3. **Remove ⌥ + swipe** (phase 30 lane G's SwipeRouter path, its test and docs); keep three-finger swipes.
4. **Three-finger vertical direction is reversed:** fingers up should go to the workspace above (the
   previous one), fingers down to the one below, like scrolling the sidebar's list. Horizontal stays.
5. **Faster two-finger paging between tabs**, and the overview's horizontal swipe between sessions at the
   same speed: the page should follow the fingers one to one and a flick should land on the next page
   sooner. Measure finger distance vs page movement and the time to land (CI recordings, local runs when the
   GUI is free) before and after.
6. **In the Agents view,** a three-finger vertical swipe moves the selection to the previous / next agent
   row (and shows that agent's pane, as a click does), instead of switching workspaces. In the workspaces
   view it switches workspaces. A vertical three-finger swipe always moves what the sidebar shows.

## Checks

- `make lint build test`; a UI test for each item a test can see (three-finger swipes: the recognizer's
  check script); the full CI suite green on each lane's last code commit; one review round per lane (spec
  and ponytail, read only).

## Findings
