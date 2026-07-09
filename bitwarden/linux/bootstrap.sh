#!/usr/bin/env bash
# Bootstrap: Bitwarden (Linux)
# Usage: git clone <repo-url> && cd <repo>/bitwarden/linux && sudo ./bootstrap.sh
# Idempotent: safe to re-run on an already-configured machine.
#
# Installs the Bitwarden CLI ('bw') always, and the Bitwarden DESKTOP APP on
# graphical systems. On a headless machine (no display / multi-user.target) only
# the CLI is installed.
#
#   --mode auto  (default) detect GUI vs headless
#   --mode cli   force CLI only
#   --mode both  force CLI + desktop app
#
# SCOPE NOTE: Raspberry Pis (ARM) are not in scope yet. The desktop app has no
# official ARM build, and the native 'bw' binary is x86_64 only; on ARM the CLI
# would come from npm instead. See README.md. This will be added later if needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/linux/common.sh"

mode="auto"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)     mode="$2"; shift 2 ;;
        --cli-only) mode="cli"; shift ;;
        --both)     mode="both"; shift ;;
        -h|--help)  echo "Usage: sudo ./bootstrap.sh [--mode auto|cli|both]"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

require_root

# GUI if a display is attached or the system boots to a graphical target.
has_gui() {
    [[ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]] && return 0
    if command_exists systemctl && systemctl get-default 2>/dev/null | grep -q graphical; then
        return 0
    fi
    command_exists Xorg && return 0
    [[ -x /usr/bin/X ]] && return 0
    return 1
}

if [[ "$mode" == "auto" ]]; then
    if has_gui; then
        mode="both"; log "Graphical system detected -> installing CLI + desktop app."
    else
        mode="cli";  log "Headless system detected -> installing CLI only."
    fi
fi

# Install a single package with whichever package manager is present.
install_pkg() {
    local pkg="$1"
    if command_exists apt-get; then
        DEBIAN_FRONTEND=noninteractive apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg"
    elif command_exists dnf;    then dnf install -y "$pkg"
    elif command_exists yum;    then yum install -y "$pkg"
    elif command_exists pacman; then pacman -Sy --noconfirm --needed "$pkg"
    elif command_exists zypper; then zypper install -y "$pkg"
    else log "No supported package manager to install '$pkg'."; return 1; fi
}

install_cli() {
    if command_exists bw; then
        log "Bitwarden CLI already installed: $(bw --version 2>/dev/null || echo present)"
        return 0
    fi
    local arch; arch="$(uname -m)"
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        log "Bitwarden ships the native 'bw' binary for x86_64 only (this host is $arch)."
        log "On ARM (e.g. Raspberry Pi) install via npm: 'npm install -g @bitwarden/cli'. Skipping CLI."
        return 1
    fi
    command_exists unzip || install_pkg unzip
    local tmp zip; tmp="$(mktemp -d)"; zip="$tmp/bw.zip"
    log "Downloading the Bitwarden CLI (native x86_64 binary)"
    if command_exists curl; then
        curl -fsSL "https://vault.bitwarden.com/download/?app=cli&platform=linux" -o "$zip"
    elif command_exists wget; then
        wget -qO "$zip" "https://vault.bitwarden.com/download/?app=cli&platform=linux"
    else
        rm -rf "$tmp"; log "Need curl or wget to download the Bitwarden CLI."; return 1
    fi
    unzip -o "$zip" -d "$tmp" >/dev/null
    install -m 0755 "$tmp/bw" /usr/local/bin/bw
    rm -rf "$tmp"
    log "Installed Bitwarden CLI: $(bw --version 2>/dev/null)"
}

install_app() {
    local arch; arch="$(uname -m)"
    if [[ "$arch" != "x86_64" && "$arch" != "amd64" ]]; then
        log "The Bitwarden desktop app has no official ARM build (this host is $arch). Skipping desktop app."
        return 1
    fi
    command_exists flatpak || { log "Installing flatpak"; install_pkg flatpak; }
    flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
    if flatpak info com.bitwarden.desktop >/dev/null 2>&1; then
        log "Bitwarden desktop app already installed (flatpak)."
    else
        log "Installing Bitwarden desktop app via flatpak (flathub com.bitwarden.desktop)"
        flatpak install -y flathub com.bitwarden.desktop
    fi
}

case "$mode" in
    cli)  install_cli ;;
    both) install_cli; install_app ;;
    *) log "Unknown mode: '$mode' (use auto|cli|both)."; exit 1 ;;
esac

log "Done."
echo ""
echo "==================== Bitwarden ready ===================="
echo "  CLI:     $(command -v bw >/dev/null 2>&1 && bw --version 2>/dev/null || echo 'see notes above')"
if [[ "$mode" == "both" ]]; then
    echo "  Desktop: launch 'Bitwarden' from your app menu (or 'flatpak run com.bitwarden.desktop')"
fi
echo "  Login:   bw login   (then: bw unlock)"
echo "========================================================"
echo ""
