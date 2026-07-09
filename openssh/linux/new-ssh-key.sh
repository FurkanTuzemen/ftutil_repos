#!/usr/bin/env bash
# Generate an SSH key pair for the current user (client side).
# Run as your normal user (NOT via sudo) so the key lands in your own ~/.ssh.
# Idempotent: won't overwrite an existing key unless --force.
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
mkdir -p "$sshdir"
chmod 700 "$sshdir"

if [[ -f "$keyfile" && $force -ne 1 ]]; then
    echo "Key already exists: $keyfile (use --force to regenerate). Printing existing public key:"
else
    [[ $force -eq 1 ]] && rm -f "$keyfile" "$keyfile.pub"
    args=(-t "$type" -f "$keyfile" -C "$comment")
    [[ "$type" == "rsa" ]] && args+=(-b "$bits")
    [[ $nopass -eq 1 ]] && args+=(-N "")   # else ssh-keygen prompts for a passphrase
    ssh-keygen "${args[@]}"
fi

echo ""
echo "==================== Public key ===================="
cat "$keyfile.pub"
echo "===================================================="
echo "Private key: $keyfile  (never share or commit this)"
echo "Authorize it on a server by running there:"
echo "  Linux:    ./authorize-ssh-key.sh \"<paste the public key above>\""
echo "  Windows:  .\\authorize-ssh-key.ps1 \"<paste the public key above>\""
echo ""
