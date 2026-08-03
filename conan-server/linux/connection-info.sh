#!/usr/bin/env bash
# Print how to use this machine's Conan remote (server URL, users, client and
# CI commands). Standalone and reusable: run it any time to re-print the
# details. bootstrap.sh calls it at the end. Does NOT need root.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

env_get() {
    grep -E "^$1=" "$ENV_FILE" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

port=9300
users="(no .env found - run bootstrap.sh first)"
if [[ -r "$ENV_FILE" ]]; then
    p="$(env_get CONAN_PUBLIC_PORT)"
    [[ -n "$p" ]] && port="$p"
    users="$(env_get CONAN_SERVER_USERS | tr ';' '\n' | cut -d: -f1 | paste -sd ',' - | tr ',' ' ')"
fi

status="unknown (is Docker installed?)"
if command -v docker >/dev/null 2>&1; then
    s="$(docker ps --filter name='^conan-server$' --format '{{.Status}}' 2>/dev/null || true)"
    if [[ -n "$s" ]]; then status="$s"; else status="not running"; fi
fi

# Usable IPv4 addresses, skipping loopback.
mapfile -t ips < <(hostname -I 2>/dev/null | tr ' ' '\n' | grep -E '^[0-9]+\.' | grep -v '^127\.' || true)

# Label an IPv4 address: Tailscale (100.64.0.0/10), LAN (RFC1918), or blank.
ip_tag() {
    case "$1" in
        100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*)
            echo "Tailscale - reachable from anywhere on your tailnet" ;;
        192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)
            echo "LAN" ;;
        *) echo "" ;;
    esac
}

echo ""
echo "================= Conan remote on this machine ================="
echo "  Container: $status"
echo "  Users:     $users  (passwords: $ENV_FILE on this machine)"
echo ""
echo "  Add the remote from another machine:"
for ip in "${ips[@]}"; do
    tag="$(ip_tag "$ip")"
    printf '    conan remote add ftpi http://%s:%s%s\n' "$ip" "$port" "${tag:+   # $tag}"
done
echo ""
echo "  Then log in (required for download and upload):"
echo "    conan remote login ftpi <user>"
echo ""
echo "  GitHub Actions: store the URL as the CONAN_REMOTE_URL variable and the"
echo "  password as the CONAN_REMOTE_PASSWORD secret - see conan-server/examples/."
echo "================================================================"
echo ""
