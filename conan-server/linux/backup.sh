#!/usr/bin/env bash
# Back up everything needed to rebuild this server elsewhere:
#   * the package store (CONAN_DATA_DIR)  -> conan-server-data-<stamp>.tgz
#   * .env (users + secrets)              -> conan-server-env-<stamp>  (chmod 600)
# The image is NOT backed up - it rebuilds from this repo + versions.env.
#
#   sudo ./backup.sh /path/to/backup/dir
#
# The server is briefly stopped so no upload is half-written into the archive.
# Restore: see conan-server/docs/operations.md#restore.
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_root
dest="${1:-}"
[[ -n "$dest" ]] || die "usage: sudo $0 <backup-dir>"
dest="$(realpath -m "$dest")"
cd "$LINUX_DIR"
[[ -r "$ENV_FILE" ]] || die "no $ENV_FILE - nothing to back up"
DATA_DIR="$(env_get CONAN_DATA_DIR)"
[[ -d "$DATA_DIR" ]] || die "data dir $DATA_DIR not found (disk mounted?)"
case "$(readlink -f "$dest")/" in
    "$(readlink -f "$DATA_DIR")"/*) die "backup dir must not be inside the data dir" ;;
esac

mkdir -p "$dest"
stamp="$(date '+%Y%m%d-%H%M%S')"
archive="$dest/conan-server-data-$stamp.tgz"

was_running=0
if docker compose ps --status running -q 2>/dev/null | grep -q .; then
    was_running=1
    log "Stopping the server for a consistent snapshot"
    docker compose stop
fi
trap '[[ $was_running == 1 ]] && { log "Starting the server again"; docker compose start; }' EXIT

log "Archiving $DATA_DIR -> $archive"
tar -czf "$archive" -C "$DATA_DIR" .
install -m 600 "$ENV_FILE" "$dest/conan-server-env-$stamp"
[[ -n "${SUDO_UID:-}" ]] && chown "$SUDO_UID:${SUDO_GID:-$SUDO_UID}" "$archive" "$dest/conan-server-env-$stamp"

log "Done: $(du -h "$archive" | cut -f1) archive + env file in $dest"
log "The env file holds passwords and signing secrets - keep it somewhere private."
