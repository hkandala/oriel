#!/usr/bin/env bash
# CI only (it writes ~/.ssh and adds a user): an sshd on 127.0.0.1:2222 for the remote-host tests, and two hosts in
# ~/.ssh/config, as a user would have them:
# - oriel-key: this user with a key and a known host key, so nothing asks; its herdr sessions are the e2e ones.
# - oriel-pw: a password user without herdr, behind a host key alias ssh does not know yet, so ssh asks both.
set -euo pipefail
[ "${CI:-}" = true ] || { echo "CI only: it writes ~/.ssh and adds a user" >&2 && exit 2; }
d=/tmp/oriel-sshd
mkdir -p "$d" ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -q -t ed25519 -N '' -f "$d/host_key"
ssh-keygen -q -t ed25519 -N '' -f ~/.ssh/oriel_e2e
cp ~/.ssh/oriel_e2e.pub "$d/authorized_keys"
cat >"$d/sshd_config" <<CONFIG
Port 2222
ListenAddress 127.0.0.1
HostKey $d/host_key
AuthorizedKeysFile $d/authorized_keys
PidFile $d/sshd.pid
PasswordAuthentication yes
KbdInteractiveAuthentication yes
UsePAM yes
StrictModes no
LogLevel VERBOSE
CONFIG
# The helper counts connections in the log: this user owns it, root's sshd appends.
touch "$d/sshd.log"
sudo /usr/sbin/sshd -f "$d/sshd_config" -E "$d/sshd.log"
sudo sysadminctl -addUser oriel-pw -password oriel-e2e-pw -home /Users/oriel-pw 2>&1
sudo createhomedir -c -u oriel-pw >/dev/null 2>&1 || true
cat >>~/.ssh/config <<CONFIG
Host oriel-key
  HostName 127.0.0.1
  Port 2222
  User $(id -un)
  IdentityFile ~/.ssh/oriel_e2e
  IdentitiesOnly yes
Host oriel-pw
  HostName 127.0.0.1
  Port 2222
  User oriel-pw
  PubkeyAuthentication no
  HostKeyAlias oriel-pw
CONFIG
for _ in $(seq 50); do
    ssh-keyscan -p 2222 127.0.0.1 2>/dev/null >>~/.ssh/known_hosts && grep -q 2222 ~/.ssh/known_hosts && break
    sleep 0.1
done
# Both hosts as the tests expect them: no prompt for one, a password for the other.
ssh -o BatchMode=yes oriel-key true
if ssh -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null oriel-pw true 2>/dev/null; then
    echo "oriel-pw got in without a password" >&2 && exit 1
fi
