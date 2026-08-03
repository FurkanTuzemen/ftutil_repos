#!/usr/bin/env bash
# Remove net-failover. Idempotent: safe to run when it is already gone.
# Keeps /etc/net-failover by default (it holds your WiFi passphrases);
# pass --purge to delete the config too.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/linux/common.sh"

PURGE=0
[[ "${1:-}" == "--purge" ]] && PURGE=1

require_root
log "Removing net-failover"

if systemctl list-unit-files net-failover.service >/dev/null 2>&1; then
    systemctl disable --now net-failover >/dev/null 2>&1 || true
fi
rm -f /etc/systemd/system/net-failover.service
systemctl daemon-reload

rm -f /usr/local/sbin/net-failover
rm -rf /run/net-failover

# Restore the ethernet route metric in case we exited while it was demoted.
if command_exists nmcli; then
    eth="${ETH_IFACE:-eth0}"
    [[ -r /etc/net-failover/config ]] && . /etc/net-failover/config 2>/dev/null || true
    eth="${ETH_IFACE:-eth0}"
    nmcli device modify "$eth" ipv4.route-metric 100 >/dev/null 2>&1 || true
    log "Reset $eth route metric to 100"

    # Drop only the profiles this daemon created (prefix nf-).
    while IFS= read -r name; do
        [[ -z "$name" ]] && continue
        log "Deleting NetworkManager profile '$name'"
        nmcli con delete "$name" >/dev/null 2>&1 || true
    done < <(nmcli -t -f NAME con show 2>/dev/null | grep '^nf-' || true)
fi

if [[ "$PURGE" -eq 1 ]]; then
    log "Purging /etc/net-failover (including your WiFi passphrases)"
    rm -rf /etc/net-failover
else
    log "Keeping /etc/net-failover - re-run with --purge to delete it"
fi

log "Done."
