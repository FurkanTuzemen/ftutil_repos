#!/usr/bin/env bash
# Bootstrap: OpenSSH server + client (Linux)
# Usage: git clone <repo-url> && cd <repo>/openssh/linux && sudo ./bootstrap.sh
# Idempotent: safe to re-run on an already-configured machine.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/linux/common.sh"

require_root

# Install the server + client packages using whichever package manager is present.
# Package names and the systemd unit name differ across distros:
#   Debian/Ubuntu/Raspberry Pi OS -> openssh-server / openssh-client, unit "ssh"
#   Fedora/RHEL/Arch/openSUSE      -> openssh-server / openssh(-clients), unit "sshd"
install_packages() {
    if command_exists apt-get; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update
        apt-get install -y openssh-server openssh-client
    elif command_exists dnf; then
        dnf install -y openssh-server openssh-clients
    elif command_exists yum; then
        yum install -y openssh-server openssh-clients
    elif command_exists pacman; then
        pacman -Sy --noconfirm --needed openssh
    elif command_exists zypper; then
        zypper install -y openssh
    else
        log "No supported package manager found (apt/dnf/yum/pacman/zypper)."
        exit 1
    fi
}

# Return the systemd unit name that actually exists on this system.
ssh_unit() {
    if systemctl list-unit-files 2>/dev/null | grep -q '^sshd\.service'; then
        echo "sshd"
    else
        echo "ssh"
    fi
}

log "Installing OpenSSH server and client (distro: $(detect_distro))"
install_packages

if command_exists systemctl; then
    unit="$(ssh_unit)"
    log "Enabling and starting the ${unit} service"
    systemctl enable "$unit"
    systemctl restart "$unit"
    systemctl --no-pager --lines=0 status "$unit" || true
else
    log "systemctl not found; start the SSH daemon with your init system manually."
fi

log "Done. Server: $(command -v sshd || echo 'sshd (see distro path)'); Client: $(command -v ssh)"
