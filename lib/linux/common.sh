#!/usr/bin/env bash
# Shared helpers for Linux bootstrap scripts. Meant to be sourced, not executed.

log() {
    printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_root() {
    if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
        log "This script must be run as root (use sudo)."
        exit 1
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        echo "$ID"
    else
        echo "unknown"
    fi
}
