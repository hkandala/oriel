#!/usr/bin/env bash
# The empty strip (a lazy strip that laid out no page), checked with no accessibility client: XCUITest is one, and any
# accessibility client hides the bug (SwiftUI then lays out the strip's pages anyway). So this drives the
# built app with key events and reads window captures. Fails on the old code, passes on the fix.
# Usage: scripts/strip-check.sh <Oriel.app>
set -euo pipefail
cd "$(dirname "$0")/.."
unset "${!HERDR_@}"
app=${1:?usage: $0 <Oriel.app>}
session=oriel-e2e-strip-$(openssl rand -hex 3)
scripts/herdr-session.sh up "$session"
# The app too, should the Swift part die before it ends it.
trap 'pkill -f "MacOS/Oriel -session $session" || true; scripts/herdr-session.sh down "$session"' EXIT
# w1: five tabs, the 4th (w1:t4) named; w2: one tab, named.
herdr --session "$session" workspace create --label five --cwd /tmp --no-focus >/dev/null
herdr --session "$session" workspace create --label one --cwd /tmp --no-focus >/dev/null
for label in "" "" strip-w1 ""; do
    herdr --session "$session" tab create --workspace w1 --cwd /tmp --no-focus ${label:+--label "$label"} >/dev/null
done
herdr --session "$session" tab rename w2:t1 strip-w2 >/dev/null
out=.build/strip-check
rm -rf "$out" && mkdir -p "$out"
swift scripts/strip-check.swift "$app/Contents/MacOS/Oriel" "$session" "$out"
