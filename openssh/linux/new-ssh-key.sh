#!/usr/bin/env bash
# Generate (or reuse) an SSH key pair for the current user (client side).
# Run as your normal user (NOT via sudo) so the key lands in your own ~/.ssh.
#
# Behaviour:
#   * If a private key already exists it is NOT regenerated (use --force to replace).
#   * If the private key exists but its .pub is missing, the public key is
#     re-derived from the private key and saved as <key>.pub.
#   * Otherwise a fresh key pair is generated.
# Prints the public key, then this machine's user@address for LAN and Tailscale.
#
# This is the CLIENT side (the machine you connect *from*). To let this key log
# IN to a server, copy the printed public key and run authorize-ssh-key.sh
# (Linux) or authorize-ssh-key.ps1 (Windows) on that server.
set -euo pipefail

type="ed25519"
comment="$(id -un)@$(hostname)"
bits=4096            # rsa only
nopass=0
force=0

usage() {
    cat <<EOF
Usage: ./new-ssh-key.sh [--type ed25519|rsa|ecdsa] [--comment "text"]
                        [--bits N] [--no-passphrase] [--force]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)          type="$2"; shift 2 ;;
        --comment)       comment="$2"; shift 2 ;;
        --bits)          bits="$2"; shift 2 ;;
        --no-passphrase) nopass=1; shift ;;
        --force)         force=1; shift ;;
        -h|--help)       usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo "ssh-keygen not found. Run bootstrap.sh first (installs openssh-client)." >&2
    exit 1
fi

sshdir="$HOME/.ssh"
keyfile="$sshdir/id_$type"
pubfile="$keyfile.pub"
mkdir -p "$sshdir"
chmod 700 "$sshdir"

if [[ $force -eq 1 && -f "$keyfile" ]]; then
    echo "Force: removing existing key at $keyfile"
    rm -f "$keyfile" "$pubfile"
fi

if [[ -f "$keyfile" ]]; then
    # Private key present: never regenerate it.
    echo "Private key already exists: $keyfile (use --force to regenerate)."
    if [[ -f "$pubfile" ]]; then
        echo "Public key present: $pubfile"
    else
        # Re-derive the public key from the private key. ssh-keygen -y prints it;
        # a passphrase-protected key will prompt to unlock. Modern OpenSSH keys
        # embed the comment, so -y may already include it (<type> <base64> <comment>);
        # only append our comment when the derived line doesn't already have one.
        echo "Public key missing; re-deriving it from the private key."
        if derived="$(ssh-keygen -y -f "$keyfile")"; then
            if [[ "$(echo "$derived" | awk '{print NF}')" -ge 3 ]]; then
                printf '%s\n' "$derived" > "$pubfile"
            else
                printf '%s %s\n' "$derived" "$comment" > "$pubfile"
            fi
            chmod 644 "$pubfile"
            echo "Saved $pubfile"
        else
            echo "Could not derive the public key from $keyfile." >&2
            exit 1
        fi
    fi
else
    # No private key: generate a fresh pair.
    args=(-t "$type" -f "$keyfile" -C "$comment")
    [[ "$type" == "rsa" ]] && args+=(-b "$bits")
    [[ $nopass -eq 1 ]] && args+=(-N "")   # else ssh-keygen prompts for a passphrase
    ssh-keygen "${args[@]}"
fi

# --- This machine's reachable IPv4 endpoints, labeled LAN vs Tailscale ---
me="$(id -un)"
ips=()
if command -v hostname >/dev/null 2>&1 && hostname -I >/dev/null 2>&1; then
    mapfile -t ips < <(hostname -I | tr ' ' '\n' | grep -E '^[0-9]+\.' | grep -v '^127\.' || true)
elif command -v ip >/dev/null 2>&1; then
    mapfile -t ips < <(ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 || true)
fi
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
echo "==================== Public key ===================="
cat "$pubfile"
echo "===================================================="
echo "Private key: $keyfile  (never share or commit this)"
echo ""
echo "This machine ($me@$(hostname)) - address for SSH in:"
for ip in "${ips[@]}"; do
    tag="$(ip_tag "$ip")"
    if [[ -n "$tag" ]]; then
        printf '    %s@%s   # %s\n' "$me" "$ip" "$tag"
    else
        printf '    %s@%s\n' "$me" "$ip"
    fi
done
echo ""
echo "Authorize the public key on a server by running there:"
echo "  Linux:    ./authorize-ssh-key.sh \"<paste the public key above>\""
echo "  Windows:  .\\authorize-ssh-key.ps1 \"<paste the public key above>\""
echo ""
