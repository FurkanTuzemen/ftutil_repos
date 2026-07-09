#!/usr/bin/env bash
# Print the SSH keys currently authorized on THIS Linux server (read-only).
# Reads ~/.ssh/authorized_keys of the target account (default: the invoking user;
# SUDO_USER when run via sudo). Shows index, key type, SHA256 fingerprint, comment.
# Changes nothing.
#
# To read a DIFFERENT user's file, pass --user <name> (may need sudo to read it).
set -euo pipefail

target_user="${SUDO_USER:-$(id -un)}"

usage() { echo "Usage: ./list-authorized-keys.sh [--user <name>]"; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)    target_user="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

home_dir="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6 || true)"
[[ -z "$home_dir" ]] && home_dir="$HOME"
akfile="$home_dir/.ssh/authorized_keys"

echo ""
echo "Authorized keys for '$target_user'"
echo "  file: $akfile"

if [[ ! -f "$akfile" ]]; then
    echo "  (file does not exist - no keys authorized)"
    echo ""
    exit 0
fi

if [[ ! -r "$akfile" ]]; then
    echo "  (cannot read $akfile - try: sudo ./list-authorized-keys.sh --user $target_user)"
    echo ""
    exit 1
fi

fingerprint() {
    command -v ssh-keygen >/dev/null 2>&1 || { echo "(ssh-keygen not found)"; return; }
    local tmp; tmp="$(mktemp)"
    printf '%s\n' "$1" > "$tmp"
    local out; out="$(ssh-keygen -l -f "$tmp" 2>/dev/null | awk '{print $2}')"
    rm -f "$tmp"
    echo "${out:-(unreadable)}"
}
key_comment() { echo "$1" | awk '{$1="";$2="";sub(/^[[:space:]]+/,"");print}'; }

# Collect key lines (non-empty, non-comment).
mapfile -t all < "$akfile"
keys=()
for line in "${all[@]}"; do
    t="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$t" || "$t" == \#* ]] && continue
    keys+=("$t")
done

if [[ ${#keys[@]} -eq 0 ]]; then
    echo "  (empty - no keys authorized)"
    echo ""
    exit 0
fi

echo ""
i=0
for k in "${keys[@]}"; do
    i=$((i + 1))
    typ="$(echo "$k" | awk '{print $1}')"
    cmt="$(key_comment "$k")"; [[ -z "$cmt" ]] && cmt="(no comment)"
    printf '  [%d] %-19s %s  %s\n' "$i" "$typ" "$(fingerprint "$k")" "$cmt"
done
echo ""
echo "  ${#keys[@]} key(s) authorized."
echo ""
