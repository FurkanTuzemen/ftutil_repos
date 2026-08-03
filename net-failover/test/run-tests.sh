#!/usr/bin/env bash
# net-failover test harness.
#
# Drives the real daemon through scripted network scenarios using mock
# nmcli/curl/ping/ip, so the failover decision logic can be verified with no
# hardware, no root and no live network. Runs on any Linux host; the Dockerfile
# next to this file pins a reproducible environment for it.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"
DAEMON="$PROJ/linux/net-failover"

pass=0; fail=0; current=""
WORK=""

# ------------------------------------------------------------------ harness ---
scenario() {
    current="$1"
    WORK="$(mktemp -d)"
    export MOCK_DIR="$WORK/mock"
    mkdir -p "$MOCK_DIR" "$WORK/run" "$WORK/sys/eth0" "$WORK/sys/wlan0"

    # Sensible baseline: wired up and healthy, radio idle, nothing in range.
    printf 'eth0:ethernet:connected\nwlan0:wifi:disconnected\n' >"$MOCK_DIR/devices"
    printf 'netplan-eth0:802-3-ethernet:eth0:\n'                >"$MOCK_DIR/connections"
    : >"$MOCK_DIR/scan"
    : >"$MOCK_DIR/active_ssid"
    : >"$MOCK_DIR/nmcli.log"
    echo 1   >"$WORK/sys/eth0/carrier"
    echo 1   >"$WORK/sys/wlan0/carrier"
    echo 204 >"$MOCK_DIR/probe_eth0"
    echo 000 >"$MOCK_DIR/probe_wlan0"

    cat >"$WORK/config" <<'EOF'
ETH_IFACE=eth0
WIFI_IFACE=wlan0
CHECK_INTERVAL_HEALTHY=60
CHECK_INTERVAL_DEGRADED=10
FAIL_THRESHOLD=1
PROBE_TIMEOUT=1
WIFI_CONNECT_TIMEOUT=5
SSID_COOLDOWN=300
PROBE_URLS="http://probe.test/generate_204"
PING_TARGETS="1.1.1.1"
DISCONNECT_WIFI_ON_ETH=yes
ETH_METRIC_GOOD=100
ETH_METRIC_DEAD=1000
WIFI_METRIC=600
EOF
    : >"$WORK/networks.conf"
}

# Scenario setters, for readability at the call sites.
set_carrier()  { echo "$2" >"$WORK/sys/$1/carrier"; }
set_probe()    { echo "$2" >"$MOCK_DIR/probe_$1"; }
set_ping()     { echo "$2" >"$MOCK_DIR/ping_$1"; }
set_scan()     { printf '%s\n' "$@" >"$MOCK_DIR/scan"; }
set_networks() { printf '%s\n' "$@" >"$WORK/networks.conf"; }
set_connect()  { echo "$2" >"$MOCK_DIR/connect_$1"; }
set_config()   { echo "$1" >>"$WORK/config"; }
wifi_connected_to() {
    printf 'eth0:ethernet:connected\nwlan0:wifi:connected\n' >"$MOCK_DIR/devices"
    echo "$1" >"$MOCK_DIR/active_ssid"
    printf 'netplan-eth0:802-3-ethernet:eth0:\nnf-%s:802-11-wireless:wlan0:%s\n' "$1" "$1" \
        >"$MOCK_DIR/connections"
}

run_tick() {
    PATH="$HERE/bin:$PATH" \
    NET_FAILOVER_CONFIG="$WORK/config" \
    NET_FAILOVER_NETWORKS="$WORK/networks.conf" \
    NET_FAILOVER_STATE_DIR="$WORK/run" \
    NET_FAILOVER_SYSFS_NET="$WORK/sys" \
    MOCK_DIR="$MOCK_DIR" \
        bash "$DAEMON" --once >"$WORK/out" 2>"$WORK/err"
}

ok()   { pass=$((pass+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
bad()  { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"
         printf '        %s\n' "$2"
         printf '        --- daemon log ---\n'; sed 's/^/        /' "$WORK/err" | head -20
         printf '        --- nmcli calls ---\n'; sed 's/^/        /' "$MOCK_DIR/nmcli.log" | head -25; }

assert_state() {
    local got; got="$(cat "$WORK/run/state" 2>/dev/null)"
    [ "$got" = "$1" ] && ok "$current: state=$1" || bad "$current" "expected state '$1', got '$got'"
}
assert_metric() {
    local got; got="$(cat "$MOCK_DIR/metric_$1" 2>/dev/null || echo unset)"
    [ "$got" = "$2" ] && ok "$current: $1 metric=$2" || bad "$current" "expected $1 metric '$2', got '$got'"
}
assert_called() {
    grep -qF -- "$1" "$MOCK_DIR/nmcli.log" && ok "$current: called '$1'" \
        || bad "$current" "expected an nmcli call containing: $1"
}
assert_not_called() {
    grep -qF -- "$1" "$MOCK_DIR/nmcli.log" && bad "$current" "did NOT expect an nmcli call containing: $1" \
        || ok "$current: did not call '$1'"
}
assert_order() {
    local a b
    a=$(grep -nF -- "$1" "$MOCK_DIR/nmcli.log" | head -1 | cut -d: -f1)
    b=$(grep -nF -- "$2" "$MOCK_DIR/nmcli.log" | head -1 | cut -d: -f1)
    if [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]; then
        ok "$current: '$1' tried before '$2'"
    else
        bad "$current" "expected '$1' (line ${a:-none}) before '$2' (line ${b:-none})"
    fi
}

echo "=============================================================="
echo " net-failover test suite"
echo "=============================================================="

# ------------------------------------------------------------------- lint ---
echo ""
echo "-- lint --"
if command -v shellcheck >/dev/null 2>&1; then
    lint_failed=0
    for f in "$DAEMON" "$PROJ"/linux/*.sh "$HERE"/run-tests.sh "$HERE"/bin/*; do
        shellcheck -S warning -e SC1090,SC1091 "$f" || lint_failed=1
    done
    [ "$lint_failed" -eq 0 ] && { pass=$((pass+1)); printf '  \033[32mPASS\033[0m shellcheck clean\n'; } \
                             || { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m shellcheck reported issues\n'; }
else
    printf '  \033[33mSKIP\033[0m shellcheck not installed\n'
fi

# bash -n on everything, always.
synerr=0
for f in "$DAEMON" "$PROJ"/linux/*.sh "$HERE"/run-tests.sh "$HERE"/bin/*; do
    bash -n "$f" 2>/dev/null || { echo "    syntax error in $f"; synerr=1; }
done
[ "$synerr" -eq 0 ] && { pass=$((pass+1)); printf '  \033[32mPASS\033[0m bash -n clean\n'; } \
                    || { fail=$((fail+1)); printf '  \033[31mFAIL\033[0m syntax errors\n'; }

echo ""
echo "-- behaviour --"

# 1. Wired link healthy: stay put, keep the preferred metric, never touch WiFi.
scenario "ethernet healthy"
set_networks "HomeAP|secret"
run_tick
assert_state "ethernet"
assert_metric eth0 100
assert_not_called "con up"

# 2. Wired healthy while the radio is associated: park the radio.
scenario "ethernet healthy parks wifi"
set_networks "HomeAP|secret"
wifi_connected_to "HomeAP"
run_tick
assert_state "ethernet"
assert_called "dev disconnect wlan0"

# 3. A single probe failure must NOT trigger failover when threshold is 2.
scenario "one blip does not fail over"
set_config "FAIL_THRESHOLD=2"
set_probe eth0 000
set_ping  eth0 fail
set_networks "HomeAP|secret"
set_scan "HomeAP"
run_tick
assert_metric eth0 unset
assert_not_called "con up"

# 4. Wired carrier up but no internet: demote the route and move to WiFi.
scenario "dead wan fails over to wifi"
set_probe eth0 000
set_ping  eth0 fail
set_probe wlan0 204
set_networks "HomeAP|secret"
set_scan "HomeAP"
run_tick
assert_state "wifi:HomeAP"
assert_metric eth0 1000
assert_called "con up nf-HomeAP"

# 5. Priority order is honoured: first listed network that is in range wins.
scenario "priority order respected"
set_probe eth0 000
set_ping  eth0 fail
set_probe wlan0 204
set_networks "FirstChoice|a" "SecondChoice|b"
set_scan "SecondChoice" "FirstChoice"
run_tick
assert_state "wifi:FirstChoice"
assert_not_called "con up nf-SecondChoice"

# 6. Out-of-range entries are skipped, not attempted.
scenario "skips network not in range"
set_probe eth0 000
set_ping  eth0 fail
set_probe wlan0 204
set_networks "FarAway|a" "NearBy|b"
set_scan "NearBy"
run_tick
assert_state "wifi:NearBy"
assert_not_called "con up nf-FarAway"

# 7. Associates but has no internet: fall through to the next network.
scenario "falls through a wifi with no internet"
set_probe eth0 000
set_ping  eth0 fail
set_probe wlan0 204
set_networks "DeadAP|a" "GoodAP|b"
set_scan "DeadAP" "GoodAP"
set_connect "DeadAP" fail
run_tick
assert_state "wifi:GoodAP"
assert_order "con up nf-DeadAP" "con up nf-GoodAP"

# 8. Captive portal (a non-204 answer) counts as offline, not online.
scenario "captive portal treated as offline"
set_probe eth0 302
set_ping  eth0 ok
set_probe wlan0 204
set_networks "GoodAP|b"
set_scan "GoodAP"
run_tick
assert_state "wifi:GoodAP"
assert_metric eth0 1000

# 9. HTTP blocked but ICMP works: the ping fallback keeps us on ethernet.
scenario "icmp fallback keeps ethernet"
set_probe eth0 000
set_ping  eth0 ok
set_networks "GoodAP|b"
set_scan "GoodAP"
run_tick
assert_state "ethernet"
assert_metric eth0 100

# 10. No cable at all: go straight to WiFi without probing ethernet.
scenario "no carrier goes straight to wifi"
set_carrier eth0 0
set_probe wlan0 204
set_networks "GoodAP|b"
set_scan "GoodAP"
run_tick
assert_state "wifi:GoodAP"

# 11. Nothing usable in range: report offline rather than pretending.
scenario "nothing in range is offline"
set_probe eth0 000
set_ping  eth0 fail
set_networks "HomeAP|secret"
set_scan "SomeoneElsesAP"
run_tick
assert_state "offline"
assert_not_called "con up"

# 12. Hidden networks never appear in a scan, so they must be tried anyway.
scenario "hidden network is attempted"
set_probe eth0 000
set_ping  eth0 fail
set_probe wlan0 204
set_networks "StealthAP|pw|hidden"
set_scan "SomethingElse"
run_tick
assert_state "wifi:StealthAP"
assert_called "con up nf-StealthAP"

# 13. Recovery: wired comes back while on WiFi -> return to it and park radio.
scenario "recovers to ethernet"
set_probe eth0 204
set_networks "HomeAP|secret"
wifi_connected_to "HomeAP"
echo 1000 >"$MOCK_DIR/metric_eth0"
run_tick
assert_state "ethernet"
assert_metric eth0 100
assert_called "dev disconnect wlan0"

echo ""
echo "=============================================================="
printf ' passed: %d   failed: %d\n' "$pass" "$fail"
echo "=============================================================="
[ "$fail" -eq 0 ]
