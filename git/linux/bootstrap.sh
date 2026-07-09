#!/usr/bin/env bash
# Bootstrap: Git (Linux, host-level)
# Usage: git clone <repo-url> && cd <repo>/git/linux && sudo ./bootstrap.sh
# Idempotent: safe to re-run on an already-configured machine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/linux/common.sh"

require_root
log "Installing Git (distro: $(detect_distro))"

if command_exists git; then
    log "git already installed: $(git --version)"
    exit 0
fi

install_git() {
    if command_exists apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y git
    elif command_exists dnf; then
        dnf install -y git
    elif command_exists yum; then
        yum install -y git
    elif command_exists pacman; then
        pacman -Sy --noconfirm --needed git
    elif command_exists zypper; then
        zypper install -y git
    else
        log "No supported package manager found (apt/dnf/yum/pacman/zypper)."
        exit 1
    fi
}

install_git

log "Done. $(git --version)"
