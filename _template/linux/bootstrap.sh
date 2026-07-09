#!/usr/bin/env bash
# Bootstrap: <PROJECT_NAME> (Linux)
# Usage: git clone <repo-url> && cd <repo>/<project>/linux && sudo ./bootstrap.sh
# Must be idempotent: safe to run again on a machine that's already set up.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/../../lib/linux/common.sh"

require_root
log "Starting bootstrap for <PROJECT_NAME>"

# TODO: replace <BINARY> with the command this installs, then remove this check
# if command_exists <BINARY>; then
#     log "<PROJECT_NAME> already installed, skipping"
#     exit 0
# fi

# TODO: install steps here, e.g.:
# apt-get update
# apt-get install -y <package>

log "Done."
