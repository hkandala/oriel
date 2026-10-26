#!/usr/bin/env python3
"""Fills a throwaway herdr session with many workspaces, tabs and panes, some working like agents (phase 29).

Usage: scripts/stress.py <oriel-dev-*|oriel-e2e-*> [tabs=300] [workspaces=30] [--panes N] [--agents N]
Start the session first (scripts/herdr-session.sh up <name>); remove it after (… down <name>): hundreds of shells.
Makes `tabs` tabs (herdr's own labels, so their titles come from their programs, as most tabs' do) over `workspaces`
workspaces and `--panes` panes (default 400): the first tabs of each workspace split in two until the count is reached.
macOS gives at most `kern.tty.ptmx_max` (511) terminals to all its programs together (999 with `sudo sysctl`).
Every other pane prints a line a second. The first `--agents` panes (default 100, spread over the tabs) work like
agents instead: a line every 0.2 s, a new terminal title every second (its first word stays, as an agent's does), and a
new agent state (`pane report-agent`) every 5 s, mostly working, sometimes blocked or idle.
Then open Oriel on the session (`-session <name>`).
"""

import argparse
import concurrent.futures
import json
import os
import socket
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument("session")
parser.add_argument("tabs", nargs="?", type=int, default=300)
parser.add_argument("workspaces", nargs="?", type=int, default=30)
parser.add_argument("--panes", type=int, default=400)
parser.add_argument("--agents", type=int, default=100)
args = parser.parse_args()
if not args.session.startswith(("oriel-dev-", "oriel-e2e-")):
    parser.error(f"refusing '{args.session}': only oriel-e2e-* and oriel-dev-* sessions are throwaway")
# Inside a herdr pane these point at the user's own session.
env = {key: value for key, value in os.environ.items() if not key.startswith("HERDR_")}
listed = json.loads(subprocess.run(["herdr", "session", "list", "--json"], env=env, capture_output=True, text=True,
                                   check=True).stdout)["sessions"]
sock = next(s["socket_path"] for s in listed if s["name"] == args.session and s["running"])
# No rc files: 600 login shells start in moments, and nothing in them asks the user anything.
shell = {"cwd": "/tmp", "env": {"ZDOTDIR": "/var/empty"}}


def call(method, **params):
    """One request on the session's socket: a few ms, where a `herdr` run takes 20–140."""
    with socket.socket(socket.AF_UNIX) as conn:
        conn.connect(sock)
        conn.sendall((json.dumps({"id": "1", "method": method, "params": params}) + "\n").encode())
        reply = b""
        while not reply.endswith(b"\n") and (chunk := conn.recv(1 << 16)):
            reply += chunk
    reply = json.loads(reply)
    if "error" in reply:
        raise RuntimeError(f"{method}: {reply['error']}")
    return reply["result"]


def fill(w):
    """Workspace `w`'s tabs and panes, in order."""
    count = args.tabs // args.workspaces + (1 if w < args.tabs % args.workspaces else 0)
    created = call("workspace.create", label=f"stress {w + 1}", focus=False, **shell)
    workspace, panes = created["workspace"]["workspace_id"], []
    # This workspace's share of the second panes.
    splits = (args.panes - args.tabs) // args.workspaces + (1 if w < (args.panes - args.tabs) % args.workspaces else 0)
    for t in range(count):
        pane = created["root_pane"]["pane_id"] if t == 0 else call(
            "tab.create", workspace_id=workspace, focus=False, **shell
        )["root_pane"]["pane_id"]
        panes.append(pane)
        if t < splits:
            panes.append(call("pane.split", target_pane_id=pane, direction="right", focus=False, **shell)["pane"]
                         ["pane_id"])
    return panes


start = time.time()
with concurrent.futures.ThreadPoolExecutor(8) as pool:
    panes = [pane for panes in pool.map(fill, range(args.workspaces)) for pane in panes]
# Spread over the tabs: the first pane of every few tabs.
step = max(len(panes) // max(args.agents, 1), 1)
agents = set(panes[::step][:args.agents])
agent = ("i=$((RANDOM % 25)); s=working; while :; do i=$((i + 1)); echo \"$s $i $RANDOM $RANDOM $RANDOM\"; "
         "[ $((i % 5)) = 0 ] && printf '\\033]2;task %s %d\\007' $s $i; "
         "[ $((i % 25)) = 0 ] && s=$(echo working working blocked idle | cut -d' ' -f$((RANDOM % 4 + 1))) && "
         "herdr pane report-agent \"$HERDR_PANE_ID\" --source oriel-stress --agent claude --state $s --seq $i "
         ">/dev/null; sleep 0.2; done\r")
printing = "while :; do echo output $RANDOM $RANDOM $RANDOM; sleep 1; done\r"
for index, pane in enumerate(panes):
    if pane in agents or index % 2 == 0:
        call("pane.send_text", pane_id=pane, text=agent if pane in agents else printing)
print(f"{args.session}: {args.workspaces} workspaces, {args.tabs} tabs, {len(panes)} panes, "
      f"{len(agents)} agents, {len(set(panes[::2]) | agents)} printing, in {time.time() - start:.0f} s")
