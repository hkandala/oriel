#!/usr/bin/env bash
# The empty strip of phase 25 (item 25), checked with no accessibility client: XCUITest is one, and any
# accessibility client hides the bug (SwiftUI then lays out the strip's pages anyway). So this drives the
# built app with key events and reads window captures. Fails on the old code, passes on the fix.
# Usage: scripts/strip-check.sh <Oriel.app>
set -euo pipefail
cd "$(dirname "$0")/.."
unset "${!HERDR_@}"
app=${1:?usage: $0 <Oriel.app>}
session=oriel-e2e-strip-$(openssl rand -hex 3)
scripts/herdr-session.sh up "$session"
trap 'scripts/herdr-session.sh down "$session"' EXIT
# w1: five tabs, the last named; w2: one tab, named.
herdr --session "$session" workspace create --label five --cwd /tmp --no-focus >/dev/null
herdr --session "$session" workspace create --label one --cwd /tmp --no-focus >/dev/null
for _ in 1 2 3 4; do
    herdr --session "$session" tab create --workspace w1 --cwd /tmp --no-focus >/dev/null
done
tabs=$(herdr --session "$session" tab list)
for workspace in w1 w2; do
    tab=$(python3 -c 'import json, sys
tabs = [t["tab_id"] for t in json.loads(sys.argv[1])["result"]["tabs"] if t["workspace_id"] == sys.argv[2]]
print(tabs[3] if sys.argv[2] == "w1" else tabs[0])' "$tabs" "$workspace")
    herdr --session "$session" tab rename "$tab" "strip-$workspace" >/dev/null
done
out=.build/strip-check
rm -rf "$out" && mkdir -p "$out"
swift scripts/strip-check.swift "$app/Contents/MacOS/Oriel" "$session" "$out"
