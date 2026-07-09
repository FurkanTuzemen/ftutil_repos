#!/usr/bin/env bash
# Remove ALL authorized SSH keys on THIS Linux server (revoke everyone).
# Empties ~/.ssh/authorized_keys of the target account (default: the invoking
# user; SUDO_USER when run via sudo), preserving ownership and 600 perms.
#
# To clear a DIFFERENT user's file, pass --user <name> and run with sudo.
#
# WARNING: after this, NO key can log in via this file. Keep a password login or
# an open session available so you don't lock yourself out.
set -euo pipefail

target_user="${SUDO_USER:-$(id -un)}"
assume_yes=0

usage() { echo "Usage: ./remove-all-authorized-keys.sh [--user <name>] [--yes]"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)    target_user="$2"; shift 2 ;;
        --yes|-y)  assume_yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

home_dir="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6 || true)"
[[ -z "$home_dir" ]] && home_dir="$HOME"
akfile="$home_dir/.ssh/authorized_keys"

if [[ "$target_user" != "$(id -un)" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Clearing another user's authorized_keys ('$target_user') requires root - re-run with sudo." >&2
    exit 1
fi

if [[ ! -f "$akfile" ]]; then
    echo "No authorized_keys file at $akfile - nothing to remove."
    exit 0
fi

count="$(grep -cvE '^[[:space:]]*($|#)' "$akfile" || true)"
if [[ "${count:-0}" -eq 0 ]]; then
    echo "$akfile is already empty - nothing to remove."
    exit 0
fi

echo "This will remove ALL $count authorized key(s) from $akfile."
if [[ $assume_yes -ne 1 ]]; then
    read -r -p "Continue? [y/N] " reply
    case "$reply" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# Empty the file in place (preserves ownership/perms).
: > "$akfile"
chmod 600 "$akfile"
echo "Cleared. No keys are authorized via this file now."
