#!/usr/bin/env bash
# Print the current uplink status managed by net-failover.
# Standalone and reusable: run it any time. bootstrap.sh calls it at the end.
# Does NOT need root (a few details are richer with sudo).
set -uo pipefail

CONF_DIR=/etc/net-failover
STATE_DIR=/run/net-failover

state="$(cat "$STATE_DIR/state" 2>/dev/null || echo 'unknown')"
metric="$(cat "$STATE_DIR/eth_metric" 2>/dev/null || echo '-')"

svc="not installed"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet net-failover 2>/dev/null; then
        svc="running"
        systemctl is-enabled --quiet net-failover 2>/dev/null && svc="running, enabled at boot"
    else
        svc="stopped"
    fi
fi

eth_iface=eth0
wifi_iface=wlan0
if [[ -r "$CONF_DIR/config" ]]; then
    # shellcheck source=/dev/null
    . "$CONF_DIR/config" 2>/dev/null || true
    eth_iface="${ETH_IFACE:-eth0}"
    wifi_iface="${WIFI_IFACE:-wlan0}"
fi

# Human-readable form of the daemon's state file.
case "$state" in
    ethernet) pretty="online via ethernet ($eth_iface)" ;;
    wifi:*)   pretty="online via WiFi '${state#wifi:}' ($wifi_iface)" ;;
    offline)  pretty="OFFLINE - no ethernet and no configured WiFi worked" ;;
    unknown)  pretty="unknown (service has not reported yet)" ;;
    *)        pretty="$state" ;;
esac

echo ""
echo "==================== net-failover status ===================="
echo "  Service:      $svc"
echo "  Current link: $pretty"
echo "  $eth_iface metric:  $metric   (${ETH_METRIC_GOOD:-100} = preferred, ${ETH_METRIC_DEAD:-1000} = demoted, no internet)"
echo ""

echo "  Interfaces:"
if command -v nmcli >/dev/null 2>&1; then
    nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null \
        | awk -F: '$2=="ethernet"||$2=="wifi"{printf "    %-8s %-9s %s\n",$1,$2,$3}'
fi
echo ""

echo "  Default route(s), lowest metric wins:"
ip route show default 2>/dev/null | sed 's/^/    /'
echo ""

echo "  WiFi fallback order:"
if [[ -r "$CONF_DIR/networks.conf" ]]; then
    n=0
    while IFS='|' read -r ssid _rest; do
        case "$ssid" in ''|'#'*) continue ;; esac
        n=$((n+1))
        printf '    %d. %s\n' "$n" "$ssid"
    done < "$CONF_DIR/networks.conf"
    [[ "$n" -eq 0 ]] && echo "    (none configured yet - edit $CONF_DIR/networks.conf)"
else
    echo "    (unreadable - run with sudo to see it)"
fi
echo ""

echo "  Commands:"
echo "    sudo net-failover --status     # state, devices, routes, priority list"
echo "    sudo net-failover --check      # probe each interface, changes nothing"
echo "    sudo net-failover --scan       # what is in range right now"
echo "    sudo journalctl -u net-failover -f"
echo "============================================================="
echo ""
