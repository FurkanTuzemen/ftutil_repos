#!/usr/bin/env bash
# Bootstrap the Conan server on a Linux host (Raspberry Pi 5 / Debian 13).
#
#   git clone <repo-url> ~/ftutil_repos
#   cd ~/ftutil_repos/conan-server/linux && sudo ./bootstrap.sh
#
# Steps: sync the version pin with ConanAutomation -> mount the package disk
# (existing data untouched) -> generate .env secrets on first run -> install the
# systemd unit -> build + start the container -> wait for health.
#
# Idempotent: safe to re-run on a machine that's already set up. Re-running is
# also the upgrade procedure (see conan-server/docs/operations.md).
#
# Tunables (export before running, or keep them in .env after the first run):
#   CONAN_DISK_UUID      "none" = store packages on the root filesystem (default),
#                        or the partition UUID of a dedicated package disk (sudo blkid)
#   CONAN_DISK_FSTYPE    ext4 | ntfs3 | ...   (default: ext4; only with a disk)
#   CONAN_MOUNT_POINT    where to mount it    (default: /mnt/conan; only with a disk)
#   CONAN_DATA_DIR       package directory    (default: /srv/conan-server-data,
#                                              or <mount>/conan-server-data with a disk)
#   CONAN_PUBLIC_PORT    host port                            (default: 9300)
#   CONAN_AUTOMATION_SYNC=0   skip reading the pin from ConanAutomation
#   CONAN_INSTALL_SYSTEMD=0   don't install the systemd unit (remembered in .env)
#   CONAN_CONTAINER_NAME, COMPOSE_PROJECT_NAME   only for a throwaway test
#                             instance next to the real one (see CLAUDE.md)
set -euo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

require_root
log "Bootstrapping conan-server from $LINUX_DIR"

# The user who ran sudo owns the repo, .env and the package directory.
RUN_USER="${SUDO_USER:-$(id -un)}"
RUN_UID="${SUDO_UID:-$(id -u)}"
RUN_GID="${SUDO_GID:-$(id -g)}"

# Precedence: exported variable > existing .env > default.
pick() { local v="${!1:-}"; [[ -z "$v" ]] && v="$(env_get "$1")"; echo "${v:-$2}"; }
# Default: packages on the root filesystem (ext4 on the SD card). A dedicated
# disk is opt-in - the first deployment kept them on an NTFS USB disk, and a
# dirty NTFS volume took the server down for 8 weeks (docs/troubleshooting.md).
DISK_UUID="$(pick CONAN_DISK_UUID none)"
if [[ "$DISK_UUID" == none ]]; then
    DISK_FSTYPE="" MOUNT_POINT=""
    DATA_DIR="$(pick CONAN_DATA_DIR /srv/conan-server-data)"
else
    DISK_FSTYPE="$(pick CONAN_DISK_FSTYPE ext4)"
    MOUNT_POINT="$(pick CONAN_MOUNT_POINT /mnt/conan)"
    DATA_DIR="$(pick CONAN_DATA_DIR "$MOUNT_POINT/conan-server-data")"
fi
PORT="$(pick CONAN_PUBLIC_PORT 9300)"
INSTALL_SYSTEMD="$(pick CONAN_INSTALL_SYSTEMD 1)"

command_exists docker || die "Docker is required - run docker/linux/bootstrap.sh from this repo first."
docker compose version >/dev/null 2>&1 || die "The Docker Compose plugin is required - run docker/linux/bootstrap.sh from this repo first."
command_exists curl || die "curl is required (apt install curl)"

# ---- 1. Version pin: versions.env, synced with ConanAutomation ---------------
# The server must ALWAYS run the Conan version pinned in
# FurkanTuzemen/ConanAutomation (ftdeps/model.py). If the pin moved, rewrite
# versions.env so the drift shows up in `git diff` and gets committed.
if [[ "${CONAN_AUTOMATION_SYNC:-1}" != "0" ]]; then
    repo_url="${CONAN_AUTOMATION_REPO:-git@github.com:FurkanTuzemen/ConanAutomation.git}"
    tmp_dir="$(sudo -u "$RUN_USER" mktemp -d)"
    if sudo --preserve-env=SSH_AUTH_SOCK -u "$RUN_USER" \
            git clone --quiet --depth 1 "$repo_url" "$tmp_dir/ca" 2>/dev/null; then
        model_py="$tmp_dir/ca/ftdeps/model.py"
        pin_conan="$(grep -Eo 'conan_version: str = "[^"]+"' "$model_py" | head -n1 | grep -Eo '[0-9][0-9.]*' || true)"
        pin_python="$(grep -Eo 'python_version: str = "[^"]+"' "$model_py" | head -n1 | grep -Eo '[0-9][0-9.]*' || true)"
        if [[ -n "$pin_conan" ]]; then
            log "ConanAutomation pin: conan $pin_conan, python ${pin_python:-?}"
            if [[ "$pin_conan" != "$(env_get CONAN_SERVER_VERSION "$VERSIONS_FILE")" ]] ||
               [[ -n "$pin_python" && "$pin_python" != "$(env_get CONAN_PYTHON_VERSION "$VERSIONS_FILE")" ]]; then
                env_set CONAN_SERVER_VERSION "$pin_conan" "$VERSIONS_FILE"
                [[ -n "$pin_python" ]] && env_set CONAN_PYTHON_VERSION "$pin_python" "$VERSIONS_FILE"
                log "versions.env updated to match ConanAutomation - COMMIT this change."
            fi
        fi
    else
        log "WARNING: could not read ConanAutomation ($repo_url) - using versions.env as is"
    fi
    rm -rf "$tmp_dir"
fi
SERVER_VERSION="$(env_get CONAN_SERVER_VERSION "$VERSIONS_FILE")"
PYTHON_VERSION="$(env_get CONAN_PYTHON_VERSION "$VERSIONS_FILE")"
[[ -n "$SERVER_VERSION" && -n "$PYTHON_VERSION" ]] || die "versions.env is missing CONAN_SERVER_VERSION / CONAN_PYTHON_VERSION"
[[ -f "$LINUX_DIR/server/constraints/conan-server-$SERVER_VERSION.txt" ]] ||
    log "WARNING: no dependency lock for conan-server $SERVER_VERSION - run ./lock-deps.sh after this and commit it"
log "Server version: conan-server $SERVER_VERSION on python $PYTHON_VERSION"

# ---- 2. Package storage (+ persistent mount if on a dedicated disk) ----------
if [[ "$DISK_UUID" == none ]]; then
    log "No dedicated disk (CONAN_DISK_UUID=none) - packages on the root filesystem"
elif [[ ! -e "/dev/disk/by-uuid/$DISK_UUID" ]]; then
    die "Disk with UUID $DISK_UUID is not connected - plug it in and re-run (or set CONAN_DISK_UUID; see: sudo blkid)."
elif ! grep -q "UUID=$DISK_UUID" /etc/fstab; then
    cp /etc/fstab /etc/fstab.bak.conan-server
    if [[ "$DISK_FSTYPE" == ntfs* ]]; then
        opts="defaults,nofail,uid=$RUN_UID,gid=$RUN_GID,umask=022"
    else
        opts="defaults,nofail"
    fi
    echo "UUID=$DISK_UUID $MOUNT_POINT $DISK_FSTYPE $opts 0 0" >> /etc/fstab
    systemctl daemon-reload
    log "Added $MOUNT_POINT to /etc/fstab (backup: /etc/fstab.bak.conan-server)"
else
    log "fstab entry for UUID=$DISK_UUID already present"
fi
if [[ "$DISK_UUID" != none ]]; then
    mkdir -p "$MOUNT_POINT"
fi
if [[ "$DISK_UUID" != none ]] && ! mountpoint -q "$MOUNT_POINT"; then
    if ! mount "$MOUNT_POINT"; then
        if dmesg 2>/dev/null | tail -n 50 | grep -q 'volume is dirty'; then
            log "The NTFS volume is marked dirty (unclean unplug/shutdown). See conan-server/docs/troubleshooting.md:"
            log "  sudo ntfsfix -d /dev/disk/by-uuid/$DISK_UUID && sudo ./bootstrap.sh"
        fi
        die "Could not mount $MOUNT_POINT"
    fi
fi
if [[ ! -d "$DATA_DIR" ]]; then
    mkdir -p "$DATA_DIR"
    [[ "$DISK_FSTYPE" == ntfs* ]] || chown "$RUN_UID:$RUN_GID" "$DATA_DIR"
fi
log "Package storage: $DATA_DIR ($(df -h --output=avail "$DATA_DIR" | tail -1 | tr -d ' ') free)"

# ---- 3. Secrets / server config (.env) ---------------------------------------
if [[ ! -f "$ENV_FILE" ]]; then
    ci_password="$(python3 -c 'import secrets; print(secrets.token_urlsafe(18))')"
    # Prefer the Tailscale address: CI runners reach the Pi over the tailnet.
    public_host="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
    [[ -n "$public_host" ]] || public_host="$(hostname -I | awk '{print $1}')"
    cat > "$ENV_FILE" <<EOF
# Generated by bootstrap.sh on $(date '+%Y-%m-%d'). NOT committed to git.
# See .env.example for what each variable means.
CONAN_SERVER_USERS=ci:$ci_password
CONAN_WRITE_USERS=ci
CONAN_READ_USERS=?
CONAN_JWT_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
CONAN_UPDOWN_SECRET=$(python3 -c 'import secrets; print(secrets.token_hex(32))')
CONAN_PUBLIC_HOSTNAME=$public_host
CONAN_PUBLIC_PORT=$PORT
EOF
    log "Generated $ENV_FILE (user 'ci' with a random password - see the file)"
else
    log ".env already exists, keeping its users and secrets"
fi
# Host settings + version pin are (re)written on every run.
env_set CONAN_DISK_UUID "$DISK_UUID"
if [[ "$DISK_UUID" == none ]]; then
    sed -i '/^CONAN_DISK_FSTYPE=/d; /^CONAN_MOUNT_POINT=/d' "$ENV_FILE"
else
    env_set CONAN_DISK_FSTYPE "$DISK_FSTYPE"
    env_set CONAN_MOUNT_POINT "$MOUNT_POINT"
fi
env_set CONAN_DATA_DIR "$DATA_DIR"
env_set CONAN_SERVER_VERSION "$SERVER_VERSION"
env_set CONAN_PYTHON_VERSION "$PYTHON_VERSION"
# Side-by-side test instances need their own container AND compose project
# name, or `up --remove-orphans` / `down` would act on the real server.
[[ -n "${CONAN_CONTAINER_NAME:-}" ]] && env_set CONAN_CONTAINER_NAME "$CONAN_CONTAINER_NAME"
[[ -n "${COMPOSE_PROJECT_NAME:-}" ]] && env_set COMPOSE_PROJECT_NAME "$COMPOSE_PROJECT_NAME"
# Remembered so a later re-run of a test instance can't install the unit.
[[ "$INSTALL_SYSTEMD" == "0" ]] && env_set CONAN_INSTALL_SYSTEMD 0
chown "$RUN_UID:$RUN_GID" "$ENV_FILE" "$VERSIONS_FILE"
chmod 600 "$ENV_FILE"

# ---- 4. systemd unit: start after the storage mounts, stop before unmount ----
if [[ "$INSTALL_SYSTEMD" != "0" ]] && command_exists systemctl; then
    unit=/etc/systemd/system/conan-server.service
    sed -e "s|@LINUX_DIR@|$LINUX_DIR|g" -e "s|@DATA_DIR@|$DATA_DIR|g" \
        "$LINUX_DIR/systemd/conan-server.service" > "$unit.new"
    if ! cmp -s "$unit.new" "$unit" 2>/dev/null; then
        mv "$unit.new" "$unit"
        systemctl daemon-reload
        log "Installed $unit"
    else
        rm -f "$unit.new"
    fi
    systemctl enable conan-server.service >/dev/null 2>&1
fi

# ---- 5. Build and start --------------------------------------------------------
# A container with our name from another compose project would block `up` -
# e.g. the first deployment (2026-08), which ran under the default project
# name "linux" before docker-compose.yml set `name: conan-server`. Containers
# are stateless here - packages live on the disk - so replacing it is safe.
container="$(env_get CONAN_CONTAINER_NAME)"; container="${container:-conan-server}"
project="$(env_get COMPOSE_PROJECT_NAME)"; project="${project:-conan-server}"
owner="$(docker inspect -f '{{index .Config.Labels "com.docker.compose.project"}}' "$container" 2>/dev/null || true)"
if [[ -n "$owner" && "$owner" != "$project" ]]; then
    log "Replacing container '$container' from compose project '$owner'"
    docker rm -f "$container" >/dev/null
fi
(cd "$LINUX_DIR" && docker compose up -d --build --remove-orphans)
if [[ "$INSTALL_SYSTEMD" != "0" ]] && command_exists systemctl; then
    # Mark the oneshot unit active so the shutdown ordering applies this boot.
    systemctl start conan-server.service
fi

# ---- 6. Wait until it answers ------------------------------------------------
log "Waiting for the server to answer on port $PORT ..."
for _ in $(seq 1 30); do
    if curl -fsS "http://127.0.0.1:$PORT/v1/ping" >/dev/null 2>&1; then
        log "Conan server is up."
        sudo -u "$RUN_USER" "$LINUX_DIR/connection-info.sh"
        exit 0
    fi
    sleep 2
done
die "Server did not answer after 60s - check: docker logs conan-server"
