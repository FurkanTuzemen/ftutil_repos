#!/usr/bin/env bash
# Authorize a public key for inbound SSH login on THIS Linux machine.
# Adds the key to a user's ~/.ssh/authorized_keys with correct ownership/perms.
# Idempotent: skips a key that's already authorized.
#
# Target user defaults to the invoking login user (SUDO_USER when run via sudo).
# To authorize for a DIFFERENT user, pass --user <name> and run with sudo.
set -euo pipefail

target_user="${SUDO_USER:-$(id -un)}"
pubkey=""
pubkeyfile=""

usage() {
    cat <<EOF
Usage: ./authorize-ssh-key.sh "<public key line>" [--user <name>]
       ./authorize-ssh-key.sh --file <path-to.pub> [--user <name>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)    target_user="$2"; shift 2 ;;
        --file)    pubkeyfile="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        -*)        echo "Unknown option: $1" >&2; usage; exit 1 ;;
        *)         pubkey="$1"; shift ;;
    esac
done

if [[ -n "$pubkeyfile" ]]; then
    [[ -r "$pubkeyfile" ]] || { echo "Public key file not found: $pubkeyfile" >&2; exit 1; }
    pubkey="$(< "$pubkeyfile")"
fi
pubkey="$(echo "$pubkey" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

if [[ -z "$pubkey" ]]; then
    echo "No public key provided." >&2; usage; exit 1
fi
if ! echo "$pubkey" | grep -Eq '^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)[[:space:]]+AAAA[0-9A-Za-z+/]+=*'; then
    echo "That does not look like a valid SSH public key line:" >&2
    echo "  $pubkey" >&2
    echo "Expected something like: ssh-ed25519 AAAAC3Nza... comment" >&2
    exit 1
fi

# Resolve the target user's home directory.
home_dir="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6 || true)"
[[ -z "$home_dir" ]] && home_dir="$HOME"

# Writing another user's files (or chowning) requires root.
if [[ "$target_user" != "$(id -un)" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Authorizing for a different user ('$target_user') requires root - re-run with sudo." >&2
    exit 1
fi

sshdir="$home_dir/.ssh"
akfile="$sshdir/authorized_keys"
mkdir -p "$sshdir"

if [[ -f "$akfile" ]] && grep -qxF "$pubkey" "$akfile"; then
    echo "Key already authorized in $akfile - nothing to do."
else
    printf '%s\n' "$pubkey" >> "$akfile"
    echo "Key added to $akfile"
fi

# Ownership + strict perms (sshd StrictModes rejects group/other-writable files).
# Owner-only chown is enough: chmod 600 already blocks group/other access.
chown -R "$target_user" "$sshdir" 2>/dev/null || true
chmod 700 "$sshdir"
chmod 600 "$akfile"

echo ""
echo "Done. Test from the client that holds the matching private key:"
echo "  ssh $target_user@<this-host-ip>"
