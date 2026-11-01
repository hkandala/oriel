#!/bin/sh
# oriel-cli 1
# Written by Oriel: asks the Oriel that follows this herdr session. Oriel parses the arguments.
# https://github.com/hkandala/oriel/blob/main/docs/content/docs/future-work/agent-control/cli.mdx
herdr=${HERDR_BIN_PATH:-herdr} session=${HERDR_SESSION:-default} pane=${HERDR_PANE_ID:-} timeout=10
dir=$HOME/.cache/oriel/rpc
while :; do
    case ${1:-} in
    --pane) pane=$2 && shift 2 ;;
    --timeout) timeout=$2 && shift 2 ;;
    *) break ;;
    esac
done
[ -n "$pane" ] || { echo "oriel: run me in a herdr pane, or pass --pane" >&2 && exit 5; }
h() { "$herdr" --session "$session" "$@" 2>/dev/null; }

# status: herdr's tokens only, so it answers with no Oriel.
token() { printf %s "$1" | sed -n "s/.*\"$2\":\"\\([^\"]*\\)\".*/\\1/p"; }
status() {
    p=$(h pane get "$pane") || { echo "oriel: herdr has no pane $pane in session $session; pass --pane" >&2 && return 5; }
    w=$(h workspace get "$(token "$p" workspace_id)")
    shown=$(token "$p" oriel-shown) open=$(token "$w" oriel-open)
    printf '{"session":"%s","pane":"%s","open":%s,"shown":%s,"remote":%s,"protocol":%s}\n' "$session" "$pane" \
        "$([ -n "$open" ] && echo true || echo false)" "$([ -n "$shown" ] && echo true || echo false)" \
        "$([ "$shown" = remote ] && echo true || echo false)" "${open:-null}"
    [ -n "$open" ] || return 3
}
if [ "${1:-}" = status ]; then
    case ${2:-} in
    --json) status ;;
    --watch) last= && while s=$(status); c=$?; [ $c -le 3 ]; do
        [ "$s" = "$last" ] || echo "$s"; last=$s; sleep 2; done ;;
    *) s=$(status); c=$?; case $s in
        *'"shown":true'*) echo "Shown in Oriel" ;; *'"open":true'*) echo "Open in Oriel, not shown" ;;
        ?*) echo "Not in Oriel" ;; esac; exit $c ;;
    esac
    exit
fi

umask 077 && mkdir -p "$dir" || exit 5
id=$( (cat /proc/sys/kernel/random/uuid || uuidgen) 2>/dev/null | tr A-F a-f) f=$dir/$id
[ -n "$id" ] || { echo "oriel: no uuidgen" >&2 && exit 5; }
[ "${1:-}" = copy ] && cat >"$f.in"
printf '%s\000' oriel-req 1 "$PWD" "$@" >"$f.tmp" && mv "$f.tmp" "$f.req" || exit 5
h pane report-metadata "$pane" --source oriel-cli --token "oriel-req=$id" --ttl-ms 3000 >/dev/null ||
    { rm -f "$f".* && echo "oriel: herdr refused the request on pane $pane; pass --pane" >&2 && exit 5; }
# Waits until $1 holds, for $2 seconds by the clock (1 s less at worst).
until_() { end=$(($(date +%s) + $2)) && until eval "$1"; do [ "$(date +%s)" -lt $end ] || return 1; sleep 0.05; done; }
if ! until_ '[ ! -e "$f.req" ]' 3 && mv "$f.req" "$f.dead" 2>/dev/null; then
    rm -f "$f".* && echo "oriel: no Oriel shows herdr session $session" >&2 && exit 3
fi
until_ '[ -e "$f.exit" ]' "$timeout" ||
    { rm -f "$f".* && echo "oriel: Oriel did not answer within $timeout s" >&2 && exit 4; }
cat "$f.out" 2>/dev/null
code=$(head -n 1 "$f.exit") && tail -n +2 "$f.exit" >&2
rm -f "$f".*
exit "${code:-1}"
