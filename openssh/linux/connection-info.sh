#!/usr/bin/env bash
# Print how to SSH into this machine (OpenSSH server connection details).
# Standalone and reusable: run it any time to re-print the details.
# bootstrap.sh calls it at the end. Does NOT need root.
set -euo pipefail

# The login user we'd actually SSH in as (not root, when invoked via sudo).
ssh_user="${SUDO_USER:-$(id -un)}"
host_name="$(hostname)"

# SSH port: from sshd_config if explicitly set, else the default 22.
ssh_port=22
if [[ -r /etc/ssh/sshd_config ]]; then
    p="$(grep -E '^[[:space:]]*Port[[:space:]]+[0-9]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print $2}' | head -n1 || true)"
    [[ -n "${p:-}" ]] && ssh_port="$p"
fi

# SSH service status (unit name differs across distros).
ssh_status="unknown"
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet ssh 2>/dev/null; then ssh_status="running (ssh)"
    elif systemctl is-active --quiet sshd 2>/dev/null; then ssh_status="running (sshd)"
    else ssh_status="not running"
    fi
fi

# Usable IPv4 addresses, skipping loopback.
ips=()
if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
    mapfile -t ips < <(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.' | grep -v '^127\.' || true)
elif command -v ip >/dev/null 2>&1; then
    mapfile -t ips < <(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
fi

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

prefix=""
[[ "$ssh_port" != "22" ]] && prefix="-p $ssh_port "

echo ""
echo "==================== SSH into this machine ===================="
echo "  User:     $ssh_user"
echo "  Hostname: $host_name"
echo "  sshd:     $ssh_status (port $ssh_port)"
echo ""
echo "  From another machine:"
for ip in "${ips[@]}"; do
    tag="$(ip_tag "$ip")"
    if [[ -n "$tag" ]]; then
        printf '    ssh %s%s@%s   # %s\n' "$prefix" "$ssh_user" "$ip" "$tag"
    else
        printf '    ssh %s%s@%s\n' "$prefix" "$ssh_user" "$ip"
    fi
done
echo ""
echo "  Local test (on this machine):  ssh ${prefix}${ssh_user}@localhost"
echo "=============================================================="
echo ""
