#!/usr/bin/env bash
# Set or change the passphrase on an existing SSH private key (client side).
# Adds a passphrase to a key that has none, or changes an existing one. The KEY
# ITSELF is unchanged - the public key stays identical, so you do NOT need to
# re-authorize it on any server. Run as your normal user (NOT sudo).
#
# Interactive by default: ssh-keygen prompts for the current passphrase (leave
# blank if the key has none) and then the new one. For unattended use pass
# --new-passphrase (and --current-passphrase if it already has one); note a
# command-line passphrase may be visible in process listings.
set -euo pipefail

type="ed25519"
path=""
current=""
have_current=0
newpass=""
have_new=0

usage() {
    cat <<EOF
Usage: ./set-key-passphrase.sh [--type ed25519|rsa|ecdsa] [--path <keyfile>]
                               [--current-passphrase <pass>] [--new-passphrase <pass>]
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type) type="$2"; shift 2 ;;
        --path) path="$2"; shift 2 ;;
        --current-passphrase) current="$2"; have_current=1; shift 2 ;;
        --new-passphrase) newpass="$2"; have_new=1; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

command -v ssh-keygen >/dev/null 2>&1 || { echo "ssh-keygen not found. Run bootstrap.sh first." >&2; exit 1; }

keyfile="${path:-$HOME/.ssh/id_$type}"
[[ -f "$keyfile" ]] || { echo "Private key not found: $keyfile" >&2; exit 1; }

echo "Setting a new passphrase on $keyfile"
if [[ $have_new -eq 1 ]]; then
    args=(-p -f "$keyfile" -N "$newpass")
    [[ $have_current -eq 1 ]] && args+=(-P "$current")
    ssh-keygen "${args[@]}"
else
    echo "When prompted: enter the CURRENT passphrase (blank if the key has none), then the NEW passphrase twice."
    ssh-keygen -p -f "$keyfile"
fi

echo "Done - the key is now passphrase-protected."
echo "Its public key is unchanged, so no re-authorization on servers is needed."
echo "Tip: cache it once per session with 'ssh-add $keyfile' so you're not prompted every time."
