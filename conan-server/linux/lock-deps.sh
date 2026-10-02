#!/usr/bin/env bash
# (Re)generate server/constraints/conan-server-<version>.txt - the exact
# transitive pip dependencies the image installs - for the version pinned in
# versions.env. Run after bumping CONAN_SERVER_VERSION, then commit the file.
#
#   ./lock-deps.sh            # needs docker, no root if in docker group
#   ./lock-deps.sh --force    # overwrite an existing lock
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

version="$(env_get CONAN_SERVER_VERSION "$VERSIONS_FILE")"
python="$(env_get CONAN_PYTHON_VERSION "$VERSIONS_FILE")"
lock="$LINUX_DIR/server/constraints/conan-server-$version.txt"

if [[ -f "$lock" && "${1:-}" != "--force" ]]; then
    die "$lock already exists (use --force to regenerate)"
fi

log "Resolving dependencies of conan-server $version on python:$python-slim ($(uname -m))"
deps="$(docker run --rm "python:$python-slim" sh -c "
    pip install -q --no-cache-dir --root-user-action=ignore 'conan-server==$version' >/dev/null &&
    pip freeze --exclude conan-server --exclude pip --exclude setuptools --exclude wheel")"

{
    echo "# Exact transitive dependencies of conan-server $version (python $python-slim, $(uname -m)),"
    echo "# resolved $(date '+%Y-%m-%d') by lock-deps.sh."
    echo "# Regenerate with lock-deps.sh when CONAN_SERVER_VERSION changes."
    echo "$deps"
} > "$lock"
log "Wrote $lock ($(echo "$deps" | wc -l) packages) - commit it, then: docker compose up -d --build"
