#!/usr/bin/env bash
# Remove the passphrase from an existing SSH private key (client side).
# The KEY ITSELF is unchanged - the public key stays identical, so you do NOT
# need to re-authorize it on any server. Run as your normal user (NOT sudo).
#
# Interactive by default (prompts for the current passphrase). Pass
# --current-passphrase for unattended use (may be visible in process listings).
#
# SECURITY: a passphrase-less key means anyone who copies the private key file
# can use it. Fine on a machine you physically trust; risky on a laptop.
set -euo pipefail

type="ed25519"
path=""
current=""
have_current=0

usage() {
    cat <<EOF
Usage: ./remove-key-passphrase.sh [--type ed25519|rsa|ecdsa] [--path <keyfile>]
                                  [--current-passphrase <pass>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) type="$2"; shift 2 ;;
        --path) path="$2"; shift 2 ;;
        --current-passphrase) current="$2"; have_current=1; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

command -v ssh-keygen >/dev/null 2>&1 || { echo "ssh-keygen not found. Run bootstrap.sh first." >&2; exit 1; }

keyfile="${path:-$HOME/.ssh/id_$type}"
[[ -f "$keyfile" ]] || { echo "Private key not found: $keyfile" >&2; exit 1; }

echo "Removing passphrase from $keyfile"
if [[ $have_current -eq 1 ]]; then
    ssh-keygen -p -f "$keyfile" -P "$current" -N ""
else
    echo "Enter the key's CURRENT passphrase when prompted (the new passphrase will be empty)."
    ssh-keygen -p -f "$keyfile" -N ""
fi

echo "Done - the key now has NO passphrase."
echo "Its public key is unchanged, so no re-authorization on servers is needed."
echo "SECURITY: anyone who copies $keyfile can now use it. Consider 'ssh-add' + a passphrase instead."
