#!/usr/bin/env bash
# Print how to reach this machine's Conan remote: URLs, users, client and CI
# commands. Safe to run any time; bootstrap.sh calls it at the end. No root.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

port=9300
users="(no .env found - run sudo ./bootstrap.sh first)"
if [[ -r "$ENV_FILE" ]]; then
    p="$(env_get CONAN_PUBLIC_PORT)"; [[ -n "$p" ]] && port="$p"
    users="$(env_get CONAN_SERVER_USERS | tr ';' '\n' | cut -d: -f1 | paste -sd ' ' -)"
fi
container="$(env_get CONAN_CONTAINER_NAME)"; container="${container:-conan-server}"

status="unknown (docker not usable by $(id -un))"
if command_exists docker; then
    s="$(docker ps -a --filter "name=^${container}\$" --format '{{.Status}}' 2>/dev/null || true)"
    status="${s:-not created}"
fi

# Candidate addresses: Tailscale MagicDNS name first, then every IPv4.
addrs=()
if command_exists tailscale; then
    dns="$(tailscale status --self --json 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))' 2>/dev/null || true)"
    [[ -n "$dns" ]] && addrs+=("$dns|Tailscale MagicDNS")
fi
while read -r ip; do
    case "$ip" in
        100.6[4-9].*|100.[7-9][0-9].*|100.1[0-1][0-9].*|100.12[0-7].*) addrs+=("$ip|Tailscale - reachable from anywhere on the tailnet") ;;
        192.168.*|10.*|172.1[6-9].*|172.2[0-9].*|172.3[0-1].*)          addrs+=("$ip|LAN") ;;
        *)                                                               addrs+=("$ip|") ;;
    esac
done < <(ip -o -4 addr show scope global 2>/dev/null |
         grep -vE '^[0-9]+: (docker[0-9]*|br-[0-9a-f]+|veth[^ ]*) ' |   # skip Docker's internal bridges
         awk '{print $4}' | cut -d/ -f1 || true)

echo ""
echo "================= Conan remote on $(hostname) ================="
echo "  Container:  $status"
echo "  Advertised: $(env_get CONAN_PUBLIC_HOSTNAME):$port  (CONAN_PUBLIC_HOSTNAME - upload/download URLs use this)"
echo "  Users:      $users  (passwords: $ENV_FILE)"
echo ""
echo "  Add the remote from another machine:"
for a in "${addrs[@]}"; do
    host="${a%%|*}"; tag="${a#*|}"
    printf '    conan remote add ftpi http://%s:%s%s\n' "$host" "$port" "${tag:+   # $tag}"
done
echo ""
echo "  Then log in (required for download AND upload):"
echo "    conan remote login ftpi <user>"
echo ""
echo "  Health check:  ./doctor.sh"
echo "  GitHub Actions: see conan-server/examples/github-actions-conan.yml"
echo "================================================================"
echo ""
