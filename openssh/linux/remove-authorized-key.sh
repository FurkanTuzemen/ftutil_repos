#!/usr/bin/env bash
# List, or remove a single, authorized SSH key on THIS Linux server.
# Edits ~/.ssh/authorized_keys of the target account (default: the invoking user;
# SUDO_USER when run via sudo). Run with NO selector to list; pass a selector to
# remove. Rewrites the file in place, preserving ownership and 600 perms.
#
# To edit a DIFFERENT user's file, pass --user <name> and run with sudo.
set -euo pipefail

target_user="${SUDO_USER:-$(id -un)}"
index=""
comment=""
match=""
pubkey=""
assume_yes=0

usage() {
    cat <<EOF
Usage: ./remove-authorized-key.sh [--user <name>] [selector] [--yes]
  (no selector)        list authorized keys with index, fingerprint, comment
  --index N            remove the key at index N (from the listing)
  --comment <text>     remove key(s) whose comment equals <text>
  --match <substr>     remove key line(s) containing <substr>
  --key "<line>"       remove this exact public-key line
  --yes                skip the confirmation prompt
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --user)    target_user="$2"; shift 2 ;;
        --index)   index="$2"; shift 2 ;;
        --comment) comment="$2"; shift 2 ;;
        --match)   match="$2"; shift 2 ;;
        --key)     pubkey="$2"; shift 2 ;;
        --yes|-y)  assume_yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

home_dir="$(getent passwd "$target_user" 2>/dev/null | cut -d: -f6 || true)"
[[ -z "$home_dir" ]] && home_dir="$HOME"
akfile="$home_dir/.ssh/authorized_keys"

if [[ "$target_user" != "$(id -un)" && "${EUID:-$(id -u)}" -ne 0 ]]; then
    echo "Editing another user's authorized_keys ('$target_user') requires root - re-run with sudo." >&2
    exit 1
fi

if [[ ! -f "$akfile" ]]; then
    echo "No authorized_keys file at $akfile - nothing is authorized."
    exit 0
fi

fingerprint() {
    command -v ssh-keygen >/dev/null 2>&1 || { echo ""; return; }
    local tmp; tmp="$(mktemp)"
    printf '%s\n' "$1" > "$tmp"
    ssh-keygen -l -f "$tmp" 2>/dev/null | awk '{print $2}'
    rm -f "$tmp"
}
key_comment() { echo "$1" | awk '{$1="";$2="";sub(/^[[:space:]]+/,"");print}'; }

# Collect the key lines (non-empty, non-comment) in order.
mapfile -t all < "$akfile"
keys=()
for line in "${all[@]}"; do
    t="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -z "$t" || "$t" == \#* ]] && continue
    keys+=("$t")
done

if [[ ${#keys[@]} -eq 0 ]]; then
    echo "$akfile has no authorized keys."
    exit 0
fi

# No selector -> list.
if [[ -z "$index$comment$match$pubkey" ]]; then
    echo "Authorized keys in $akfile:"
    i=0
    for k in "${keys[@]}"; do
        i=$((i + 1))
        typ="$(echo "$k" | awk '{print $1}')"
        cmt="$(key_comment "$k")"; [[ -z "$cmt" ]] && cmt="(no comment)"
        printf '  [%d] %s  %s  %s\n' "$i" "$typ" "$(fingerprint "$k")" "$cmt"
    done
    echo ""
    echo "Remove one with:  --index N | --comment <text> | --match <substr> | --key \"<line>\""
    exit 0
fi

# Find matching indices (1-based).
remove_idx=()
i=0
for k in "${keys[@]}"; do
    i=$((i + 1))
    if   [[ -n "$index"  ]]; then [[ "$i" -eq "$index" ]] && remove_idx+=("$i")
    elif [[ -n "$pubkey" ]]; then [[ "$k" == "$pubkey" ]] && remove_idx+=("$i")
    elif [[ -n "$comment" ]]; then [[ "$(key_comment "$k")" == "$comment" ]] && remove_idx+=("$i")
    elif [[ -n "$match"  ]]; then [[ "$k" == *"$match"* ]] && remove_idx+=("$i")
    fi
done

if [[ ${#remove_idx[@]} -eq 0 ]]; then
    echo "No authorized key matched. Run with no arguments to list them."
    exit 0
fi

echo "Will remove:"
for idx in "${remove_idx[@]}"; do echo "  [$idx] ${keys[$((idx - 1))]}"; done

if [[ $assume_yes -ne 1 ]]; then
    read -r -p "Remove ${#remove_idx[@]} key(s)? [y/N] " reply
    case "$reply" in y|Y|yes|YES) ;; *) echo "Aborted."; exit 0 ;; esac
fi

# Rewrite, dropping the matched key lines by running index. Preserve perms.
tmp="$(mktemp)"
running=0
for line in "${all[@]}"; do
    t="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    if [[ -n "$t" && "$t" != \#* ]]; then
        running=$((running + 1))
        skip=0
        for idx in "${remove_idx[@]}"; do [[ "$running" -eq "$idx" ]] && { skip=1; break; }; done
        [[ $skip -eq 1 ]] && continue
    fi
    printf '%s\n' "$line" >> "$tmp"
done
cat "$tmp" > "$akfile"
rm -f "$tmp"
chmod 600 "$akfile"
echo "Removed ${#remove_idx[@]} key(s)."
