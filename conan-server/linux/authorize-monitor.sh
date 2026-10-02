#!/usr/bin/env bash
# Authorize the conan-monitor ssh key (printed by monitor/install.sh on the
# monitor host) for the current user on THIS server, locked down so it can do
# exactly one thing: run doctor.sh. No shell, pty, or forwarding.
#
#   ./authorize-monitor.sh 'ssh-ed25519 AAAA... conan-monitor@ftbitpi'
#
# Idempotent: re-running with the same key replaces its line. No root needed.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

pubkey="${1:-}"
[[ "$pubkey" =~ ^ssh-(ed25519|rsa)\ [A-Za-z0-9+/=]+ ]] || die "usage: $0 '<ssh public key line>'"
blob="$(awk '{print $2}' <<<"$pubkey")"

auth="$HOME/.ssh/authorized_keys"
install -d -m 700 "$HOME/.ssh"
touch "$auth" && chmod 600 "$auth"
cp "$auth" "$auth.bak.conan-monitor"

line="restrict,command=\"$LINUX_DIR/doctor.sh\" $pubkey"
grep -vF "$blob" "$auth.bak.conan-monitor" > "$auth" || true
echo "$line" >> "$auth"
log "Authorized monitor key for $(id -un): forced command $LINUX_DIR/doctor.sh (backup: $auth.bak.conan-monitor)"
