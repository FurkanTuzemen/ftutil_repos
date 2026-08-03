#!/usr/bin/env bash
# Bootstrap: net-failover (Linux)
# Usage: git clone <repo-url> && cd <repo>/net-failover/linux && sudo ./bootstrap.sh
# Idempotent: re-running upgrades the daemon and unit, and never overwrites
# /etc/net-failover/networks.conf (it holds your WiFi passphrases).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/linux/common.sh"

SBIN=/usr/local/sbin/net-failover
CONF_DIR=/etc/net-failover
UNIT=/etc/systemd/system/net-failover.service

require_root
log "Starting bootstrap for net-failover (distro: $(detect_distro))"

# ---------------------------------------------------------------- prereqs ---
if ! command_exists systemctl; then
    log "ERROR: systemd is required (no systemctl found)."
    exit 1
fi

if ! command_exists nmcli; then
    log "ERROR: NetworkManager (nmcli) is required but not installed."
    log "       Debian/Ubuntu/Raspberry Pi OS: apt-get install -y network-manager"
    exit 1
fi

if ! systemctl is-active --quiet NetworkManager; then
    log "ERROR: NetworkManager is installed but not active."
    log "       Enable it first: systemctl enable --now NetworkManager"
    log "       Note: if this machine uses dhcpcd or systemd-networkd to manage"
    log "       wlan0, migrate to NetworkManager before installing this daemon."
    exit 1
fi

if ! command_exists curl; then
    log "ERROR: curl is required for the HTTP reachability probes."
    log "       Debian/Ubuntu/Raspberry Pi OS: apt-get install -y curl"
    exit 1
fi

# Not fatal: the daemon is still useful on a wired-only box, it just has
# nothing to fail over to.
if ! nmcli -t -f DEVICE,TYPE device status 2>/dev/null | grep -q ':wifi$'; then
    log "WARNING: no WiFi device found by NetworkManager - failover will have"
    log "         no target until one is present."
fi

# ------------------------------------------------------------- daemon/unit ---
# Always refreshed: these are code, not user data.
log "Installing daemon -> $SBIN"
install -D -m 0755 -o root -g root "$SCRIPT_DIR/net-failover" "$SBIN"

log "Installing systemd unit -> $UNIT"
install -m 0644 -o root -g root "$SCRIPT_DIR/net-failover.service" "$UNIT"

# ----------------------------------------------------------------- config ---
install -d -m 0755 -o root -g root "$CONF_DIR"

if [[ -f "$CONF_DIR/config" ]]; then
    log "Keeping existing $CONF_DIR/config (not overwriting your tunables)"
else
    log "Installing default tunables -> $CONF_DIR/config"
    install -m 0644 -o root -g root "$SCRIPT_DIR/net-failover.config" "$CONF_DIR/config"
fi

# 0600: this file holds plain-text WPA passphrases.
if [[ -f "$CONF_DIR/networks.conf" ]]; then
    log "Keeping existing $CONF_DIR/networks.conf (your WiFi list and passphrases)"
    chmod 0600 "$CONF_DIR/networks.conf"
    chown root:root "$CONF_DIR/networks.conf"
else
    log "Installing starter WiFi list -> $CONF_DIR/networks.conf"
    install -m 0600 -o root -g root "$SCRIPT_DIR/networks.conf.example" "$CONF_DIR/networks.conf"
fi

# ---------------------------------------------------------------- service ---
log "Reloading systemd and enabling the service"
systemctl daemon-reload
systemctl enable net-failover >/dev/null

if systemctl is-active --quiet net-failover; then
    log "Service already running - restarting to pick up changes"
    systemctl restart net-failover
else
    systemctl start net-failover
fi

# Give the first tick a moment so the status printout is meaningful.
sleep 3

if ! systemctl is-active --quiet net-failover; then
    log "ERROR: the service failed to start. Recent log:"
    journalctl -u net-failover -n 20 --no-pager || true
    exit 1
fi

log "Done."

# ------------------------------------------------------------ access info ---
# Repo convention: print how to use what we just set up.
if [[ -x "$SCRIPT_DIR/connection-info.sh" ]]; then
    "$SCRIPT_DIR/connection-info.sh" || true
else
    bash "$SCRIPT_DIR/connection-info.sh" || true
fi

# Nudge only if no network is actually configured yet.
if ! grep -qE '^[[:space:]]*[^#[:space:]]+\|' "$CONF_DIR/networks.conf" 2>/dev/null; then
    echo ""
    echo "  NEXT STEP: no WiFi networks are configured yet."
    echo "    sudo net-failover --scan                  # see what is in range"
    echo "    sudo nano $CONF_DIR/networks.conf         # add SSID|PASSPHRASE lines"
    echo "    sudo systemctl restart net-failover"
    echo ""
fi
