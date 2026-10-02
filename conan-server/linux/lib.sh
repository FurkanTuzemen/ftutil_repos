#!/usr/bin/env bash
# conan-server helpers on top of the repo-wide lib/linux/common.sh.
# Meant to be sourced by the scripts in this directory, not executed.

# This directory: holds docker-compose.yml and the (gitignored) .env.
LINUX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/linux/common.sh
source "$LINUX_DIR/../../lib/linux/common.sh"

# shellcheck disable=SC2034  # used by the scripts that source this file
ENV_FILE="$LINUX_DIR/.env"
# shellcheck disable=SC2034
VERSIONS_FILE="$LINUX_DIR/../versions.env"

die() {
    log "ERROR: $*"
    exit 1
}

# Read KEY from a KEY=value file (no shell evaluation of the file).
env_get() {
    local key="$1" file="${2:-$ENV_FILE}"
    grep -E "^$key=" "$file" 2>/dev/null | head -n1 | cut -d= -f2- || true
}

# Set KEY=value in a KEY=value file, appending if missing.
env_set() {
    local key="$1" value="$2" file="${3:-$ENV_FILE}"
    if grep -qE "^$key=" "$file"; then
        sed -i "s|^$key=.*|$key=$value|" "$file"
    else
        echo "$key=$value" >> "$file"
    fi
}
