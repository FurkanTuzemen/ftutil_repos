#!/usr/bin/env bash
# Bootstrap: Docker Engine (Linux, host-level)
# Usage: git clone <repo-url> && cd <repo>/docker/linux && sudo ./bootstrap.sh
# Idempotent: safe to re-run on an already-configured machine.
#
# Installs the Docker ENGINE on the host (not Docker Desktop). The container
# runtime can't install itself into a container, so this runs on the host and is
# meant to be cloned and run identically on every Raspberry Pi / PC.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/linux/common.sh"

require_root
log "Installing Docker Engine (distro: $(detect_distro))"

if command_exists docker; then
    log "docker already installed: $(docker --version)"
else
    # Docker's official convenience script supports Debian/Ubuntu/Raspberry Pi OS
    # and the common RPM distros, and picks the right repo for the architecture
    # (arm64/armhf on Pis, amd64 on PCs). This is Docker's recommended path for
    # Raspberry Pi OS, which is what makes the fleet reproducible.
    tmp="$(mktemp)"
    if command_exists curl; then
        curl -fsSL https://get.docker.com -o "$tmp"
    elif command_exists wget; then
        wget -qO "$tmp" https://get.docker.com
    else
        rm -f "$tmp"
        log "Neither curl nor wget is available; install one and re-run."
        exit 1
    fi
    sh "$tmp"
    rm -f "$tmp"
fi

# Enable + start the daemon.
if command_exists systemctl; then
    log "Enabling and starting the docker service"
    systemctl enable docker
    systemctl start docker
else
    log "systemctl not found; start the docker daemon with your init system manually."
fi

# Let the invoking (non-root) user run docker without sudo.
target_user="${SUDO_USER:-}"
if [[ -n "$target_user" && "$target_user" != "root" ]]; then
    if getent group docker >/dev/null 2>&1; then
        if id -nG "$target_user" | tr ' ' '\n' | grep -qx docker; then
            log "'$target_user' is already in the docker group."
        else
            usermod -aG docker "$target_user"
            log "Added '$target_user' to the docker group."
            group_hint=1
        fi
    fi
fi

log "Done."
echo ""
echo "==================== Docker ready ===================="
echo "  Engine:  $(docker --version 2>/dev/null || echo 'installed')"
echo "  Compose: $(docker compose version 2>/dev/null || echo 'plugin not detected')"
echo "  Verify:  docker run --rm hello-world"
if [[ "${group_hint:-0}" == "1" ]]; then
    echo ""
    echo "  NOTE: log out and back in (or run 'newgrp docker') so '$target_user'"
    echo "        can use docker without sudo. Until then, use 'sudo docker ...'."
fi
echo "====================================================="
echo ""
