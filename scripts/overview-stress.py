#!/usr/bin/env python3
"""Fills a throwaway herdr session with many tabs for the overview's stress test (phase 28).

Usage: scripts/overview-stress.py <oriel-dev-*|oriel-e2e-*> [tabs] [workspaces]
Start the session first (scripts/herdr-session.sh up <name>); remove it after (… down <name>).
Makes `tabs` tabs (default 200) over `workspaces` workspaces (default 8); every third tab is split in two, and
every other pane prints a line a second, as an agent does. Then open Oriel on the session (`-session <name>`),
⌃⌘O, and scroll: `footprint Oriel`, `top -pid`, or Instruments' Animation Hitches.
"""

import json
import os
import subprocess
import sys

name = sys.argv[1] if len(sys.argv) > 1 else ""
if not name.startswith(("oriel-dev-", "oriel-e2e-")):
    sys.exit(f"refusing '{name}': only oriel-e2e-* and oriel-dev-* sessions are throwaway")
tabs, workspaces = (int(sys.argv[2]) if len(sys.argv) > 2 else 200), (int(sys.argv[3]) if len(sys.argv) > 3 else 8)
# Inside a herdr pane these point at the user's own session.
env = {key: value for key, value in os.environ.items() if not key.startswith("HERDR_")}


def herdr(*args):
    out = subprocess.run(["herdr", "--session", name, *args], env=env, capture_output=True, text=True, check=True)
    return json.loads(out.stdout)["result"] if out.stdout.strip() else None


panes = []
for w in range(workspaces):
    created = herdr("workspace", "create", "--label", f"stress {w + 1}", "--cwd", "/tmp", "--no-focus")
    workspace, first = created["workspace"]["workspace_id"], created["root_pane"]["pane_id"]
    count = tabs // workspaces + (1 if w < tabs % workspaces else 0)
    for t in range(count):
        pane = first if t == 0 else herdr("tab", "create", "--workspace", workspace, "--cwd", "/tmp",
                                          "--label", f"agent {w + 1}.{t + 1}")["root_pane"]["pane_id"]
        panes.append(pane)
        if t % 3 == 0:
            panes.append(herdr("pane", "split", pane, "--direction", "right", "--no-focus")["pane"]["pane_id"])
for index, pane in enumerate(panes):
    if index % 2 == 0:
        herdr("pane", "run", pane, "while :; do echo working $RANDOM $RANDOM; sleep 1; done")
print(f"{name}: {tabs} tabs, {len(panes)} panes, {len(panes[::2])} printing")
