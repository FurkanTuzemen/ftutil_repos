#!/usr/bin/env bash
# Build the test image and run the net-failover suite inside it.
# Usage: ./test/run-in-docker.sh      (from the net-failover/ project folder,
#                                      or from anywhere - paths are resolved)
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ="$(cd "$HERE/.." && pwd)"

cd "$PROJ"
docker build -f test/Dockerfile -t net-failover-test .
docker run --rm net-failover-test
