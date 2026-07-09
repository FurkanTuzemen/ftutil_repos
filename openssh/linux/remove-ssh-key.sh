#!/usr/bin/env bash
# Delete an existing SSH key pair (private + public) for the current user.
# Destructive and irreversible: prints what it will remove and asks for
# confirmation unless --yes. Run as your normal user (NOT sudo) so it targets
# your own ~/.ssh.
#
# WARNING: deleting a private key is permanent. Any server that only trusts this
# key will refuse you until you generate a new key and re-authorize it there.
set -euo pipefail

type="ed25519"
path=""
all=0
assume_yes=0

usage() {
    cat <<EOF
Usage: ./remove-ssh-key.sh [--type ed25519|rsa|ecdsa] [--path <keyfile>] [--all] [--yes]
  --type   key type to remove (default ed25519) -> ~/.ssh/id_<type>
  --path   explicit private key path to remove
  --all    remove all standard ~/.ssh/id_* key pairs
  --yes    skip the confirmation prompt (for unattended use)
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --type)   type="$2"; shift 2 ;;
        --path)   path="$2"; shift 2 ;;
        --all)    all=1; shift ;;
        --yes|-y) assume_yes=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

sshdir="$HOME/.ssh"

# Build the list of private-key paths to target.
keypaths=()
if [[ $all -eq 1 ]]; then
    for kp in "$sshdir"/id_ed25519 "$sshdir"/id_rsa "$sshdir"/id_ecdsa "$sshdir"/id_dsa; do
        [[ -f "$kp" ]] && keypaths+=("$kp")
    done
elif [[ -n "$path" ]]; then
    keypaths+=("$path")
else
    keypaths+=("$sshdir/id_$type")
fi

# Gather the files that actually exist (private + public + cert).
targets=()
if [[ ${#keypaths[@]} -gt 0 ]]; then
    for kp in "${keypaths[@]}"; do
        for f in "$kp" "$kp.pub" "$kp-cert.pub"; do
            [[ -f "$f" ]] && targets+=("$f")
        done
    done
fi

if [[ ${#targets[@]} -eq 0 ]]; then
    echo "Nothing to delete (no matching key files found in $sshdir)."
    exit 0
fi

echo "These files will be permanently deleted:"
for f in "${targets[@]}"; do echo "    $f"; done

if [[ $assume_yes -ne 1 ]]; then
    read -r -p "Delete these files? [y/N] " reply
    case "$reply" in
        y|Y|yes|YES) ;;
        *) echo "Aborted."; exit 0 ;;
    esac
fi

for kp in "${keypaths[@]}"; do
    # Best-effort: drop the identity from the running agent first (needs the .pub).
    if command -v ssh-add >/dev/null 2>&1 && [[ -f "$kp.pub" ]]; then
        ssh-add -d "$kp" >/dev/null 2>&1 || true
    fi
    for f in "$kp" "$kp.pub" "$kp-cert.pub"; do
        if [[ -f "$f" ]]; then
            rm -f "$f"
            echo "Deleted $f"
        fi
    done
done
echo "Done."
