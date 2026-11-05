#!/bin/sh
# ovvi-cli 1.2
# Written by Ovvi: asks the Ovvi that follows this herdr session. Ovvi parses the arguments.
# https://github.com/hkandala/ovvi/blob/main/docs/content/docs/agent-control/cli.mdx
herdr=${HERDR_BIN_PATH:-herdr} session=${HERDR_SESSION:-default} pane=${HERDR_PANE_ID:-} timeout=10 json= j=
dir=$HOME/.cache/ovvi/rpc
for a; do [ "$a" = --json ] && json=1; done
# Exits with $1, saying $3 on stderr and, with --json, {"error":…} with the code $2 on stdout.
fail() {
    echo "ovvi: $3" >&2
    [ -z "$json" ] || printf '{"error":{"code":"%s","message":"%s"}}\n' "$2" \
        "$(printf %s "$3" | tr -d '\000-\037' | sed 's/[\\"]/\\&/g')"
    exit "$1"
}
while :; do
    case ${1:-} in
    --pane) [ $# -ge 2 ] || fail 2 usage "--pane needs a pane"; pane=$2 && shift 2 ;;
    --timeout) [ $# -ge 2 ] || fail 2 usage "--timeout needs whole seconds"; timeout=$2 && shift 2 ;;
    --json) j=--json && shift ;;
    *) break ;;
    esac
done
case $timeout in '' | *[!0-9]*) fail 2 usage "--timeout takes whole seconds" ;; esac
# A --json before the command goes after it, so $1 is the command.
set -- "$@" $j
[ -n "$pane" ] || fail 5 no_herdr "run me in a herdr pane, or pass --pane"
h() { "$herdr" --session "$session" "$@" 2>/dev/null; }

# status: herdr's tokens only, so it answers with no Ovvi.
token() { printf %s "$1" | sed -n "s/.*\"$2\":\"\\([^\"]*\\)\".*/\\1/p"; }
status() {
    p=$(h pane get "$pane") || fail 5 no_herdr "herdr has no pane $pane in session $session; pass --pane"
    w=$(h workspace get "$(token "$p" workspace_id)")
    shown=$(token "$p" ovvi-shown) open=$(token "$w" ovvi-open)
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
        *'"shown":true'*) echo "Shown in Ovvi" ;; *'"open":true'*) echo "Open in Ovvi, not shown" ;;
        ?*) echo "Not in Ovvi" ;; esac; exit $c ;;
    esac
    exit
fi

umask 077 && mkdir -p "$dir" || fail 5 no_herdr "cannot write $dir"
id=$( (cat /proc/sys/kernel/random/uuid || uuidgen) 2>/dev/null | tr A-F a-f) f=$dir/$id
[ -n "$id" ] || fail 5 no_herdr "no uuidgen"
# One byte over the 1 MiB limit, so Ovvi sees standard input that is too large.
[ "${1:-}" = copy ] && head -c 1048577 >"$f.in"
printf '%s\000' ovvi-req 1 "$PWD" "$@" >"$f.tmp" && mv "$f.tmp" "$f.req" || fail 5 no_herdr "cannot write $dir"
h pane report-metadata "$pane" --source ovvi-cli --token "ovvi-req=$id" --ttl-ms 3000 >/dev/null ||
    { rm -f "$f".* && fail 5 no_herdr "herdr refused the request on pane $pane; pass --pane"; }
# Waits until $1 holds, for $2 seconds by the clock (1 s less at worst).
until_() { end=$(($(date +%s) + $2)) && until eval "$1"; do [ "$(date +%s)" -lt $end ] || return 1; sleep 0.05; done; }
if ! until_ '[ ! -e "$f.req" ]' 3 && mv "$f.req" "$f.dead" 2>/dev/null; then
    rm -f "$f".* && fail 3 no_ovvi "no Ovvi shows herdr session $session"
fi
until_ '[ -e "$f.exit" ]' "$timeout" ||
    { rm -f "$f".* && fail 4 timeout "Ovvi did not answer within $timeout s"; }
cat "$f.out" 2>/dev/null
code=$(head -n 1 "$f.exit") && tail -n +2 "$f.exit" >&2
rm -f "$f".*
exit "${code:-1}"
