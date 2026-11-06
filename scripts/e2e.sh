#!/usr/bin/env bash
# Run a command (the UI tests) against two throwaway herdr sessions and the e2e helper, and remove
# the sessions after, even when the command fails.
# Usage: scripts/e2e.sh <command>...
set -euo pipefail
cd "$(dirname "$0")/.."
# Inside a herdr pane these point at the user's own session; keep them out of herdr and the helper.
unset "${!HERDR_@}"

id=$(openssl rand -hex 3)
one=ovvi-e2e-$id-a
two=ovvi-e2e-$id-b
# Listed but stopped, for "Show stopped".
three=ovvi-e2e-$id-c
# Made by the app's New Session.
four=ovvi-e2e-$id-d
# Stopped and started again by a test.
five=ovvi-e2e-$id-e
# Made by the app in a start that fails first (`-startTimeout 0`), then by Retry.
six=ovvi-e2e-$id-f
# Stopped and deleted from Open Session by a test.
seven=ovvi-e2e-$id-g
# Made and removed by the stress test (the helper's `stress`).
eight=ovvi-e2e-$id-h
# A session joins the cleanup only once it is up: a failed `up` must not remove a session it did not make.
made=("$four" "$six" "$eight")
# Browser panes' state files (plugins/api#state) go with their sessions, and so do the app's agent times
# (`agentMarks.‹machine› ‹session›`, in the defaults the tests share with the user's Ovvi).
cleanup() {
    for s in "${made[@]}"; do scripts/herdr-session.sh down "$s" || true; rm -rf "$HOME/.local/state/ovvi/$s"; done
    defaults read dev.ovvi.app 2>/dev/null | grep -o "\"agentMarks\.[^\"]* ovvi-e2e-$id-[a-z]\"" | tr -d '"' |
        while read -r key; do defaults delete dev.ovvi.app "$key" || true; done
}
trap cleanup EXIT
for s in "$one" "$two" "$three" "$five" "$seven"; do
    scripts/herdr-session.sh up "$s"
    made+=("$s")
done
herdr session stop "$three" >/dev/null

# The tests' config folder (OvviUITests.noConfig): this build's default plugins install there afresh.
rm -rf /tmp/ovvi-e2e-no-config

# The sandboxed test runner cannot reach herdr; the helper serves it on localhost while the tests run.
python3 scripts/e2e-helper.py "$one" "$two" "$three" "$four" "$five" "$six" "$seven" "$eight" -- "$@"
