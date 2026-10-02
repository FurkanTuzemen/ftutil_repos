#!/usr/bin/env bash
# Health check for the whole chain the server depends on:
#   [dedicated disk: connected -> mounted rw -> not NTFS-dirty] -> data dir -> systemd unit
#   -> container running/healthy -> ping -> login -> search -> version match.
#
#   ./doctor.sh          # no root needed (uses sudo -n for dmesg if allowed)
#
# Exits non-zero if any check FAILs; WARN lines don't fail the run. Every FAIL
# prints the fix to try - see conan-server/docs/troubleshooting.md for details.
set -uo pipefail

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

failures=0
pass() { printf '  [ OK ] %s\n' "$*"; }
warn() { printf '  [WARN] %s\n' "$*"; }
fail() { printf '  [FAIL] %s\n' "$*"; failures=$((failures + 1)); }
hint() { printf '         -> %s\n' "$*"; }

[[ -r "$ENV_FILE" ]] || { echo "No readable $ENV_FILE - run: sudo ./bootstrap.sh"; exit 1; }

DISK_UUID="$(env_get CONAN_DISK_UUID)"
FSTYPE="$(env_get CONAN_DISK_FSTYPE)"
MOUNT_POINT="$(env_get CONAN_MOUNT_POINT)"
DATA_DIR="$(env_get CONAN_DATA_DIR)"
PORT="$(env_get CONAN_PUBLIC_PORT)"; PORT="${PORT:-9300}"
CONTAINER="$(env_get CONAN_CONTAINER_NAME)"; CONTAINER="${CONTAINER:-conan-server}"
WANT_VERSION="$(env_get CONAN_SERVER_VERSION "$VERSIONS_FILE")"

kmsg() { dmesg 2>/dev/null || sudo -n dmesg 2>/dev/null || true; }

echo "conan-server doctor - $(hostname), $(date '+%Y-%m-%d %H:%M:%S')"

# ---- Storage -------------------------------------------------------------------
echo "Storage"
if [[ -z "$DISK_UUID" || "$DISK_UUID" == none ]]; then
    pass "no dedicated disk - packages on $(findmnt -no SOURCE,FSTYPE -T "$DATA_DIR" 2>/dev/null | tr -s ' ' ' ' || echo '?')"
else
    if [[ -e "/dev/disk/by-uuid/$DISK_UUID" ]]; then
        pass "disk UUID=$DISK_UUID connected ($(readlink -f "/dev/disk/by-uuid/$DISK_UUID"))"
    else
        fail "disk UUID=$DISK_UUID not connected"
        hint "plug the disk in; if it's a different disk, set CONAN_DISK_UUID and re-run bootstrap"
    fi

    if mountpoint -q "$MOUNT_POINT" 2>/dev/null; then
        opts="$(findmnt -no OPTIONS "$MOUNT_POINT")"
        if [[ ",$opts," == *",rw,"* ]]; then
            pass "$MOUNT_POINT mounted read-write ($(findmnt -no FSTYPE "$MOUNT_POINT"))"
        else
            fail "$MOUNT_POINT is mounted READ-ONLY ($opts)"
            hint "usually filesystem errors - see conan-server/docs/troubleshooting.md"
        fi
    else
        fail "$MOUNT_POINT is not mounted"
        if [[ "$FSTYPE" == ntfs* ]] && kmsg | grep -q 'volume is dirty'; then
            hint "kernel says the NTFS volume is DIRTY (unclean unplug/power loss). Fix:"
            hint "sudo ntfsfix -d /dev/disk/by-uuid/$DISK_UUID && sudo mount $MOUNT_POINT && sudo systemctl restart conan-server"
        else
            hint "sudo mount $MOUNT_POINT   (then check: dmesg | tail)"
        fi
    fi

    if [[ "$FSTYPE" == ntfs* ]] && kmsg | grep -q 'It is recommened to use chkdsk'; then
        warn "kernel recommended chkdsk for the NTFS volume this boot - run 'chkdsk /f' on Windows when convenient"
    fi
fi

if [[ -d "$DATA_DIR" ]]; then
    use_pct="$(df --output=pcent "$DATA_DIR" | tail -1 | tr -dc '0-9')"
    msg="data dir $DATA_DIR ($(du -sh "$DATA_DIR" 2>/dev/null | cut -f1) used, $(df -h --output=avail "$DATA_DIR" | tail -1 | tr -d ' ') free)"
    if (( use_pct >= 90 )); then
        warn "$msg - filesystem ${use_pct}% full"
    else
        pass "$msg"
    fi
else
    fail "data dir $DATA_DIR missing"
    hint "sudo ./bootstrap.sh"
fi

# ---- Service -------------------------------------------------------------------
echo "Service"
if command_exists systemctl && systemctl cat conan-server.service >/dev/null 2>&1; then
    state="$(systemctl is-active conan-server.service)"
    enabled="$(systemctl is-enabled conan-server.service 2>/dev/null)"
    if [[ "$state" == active && "$enabled" == enabled ]]; then
        pass "systemd unit conan-server.service active + enabled"
    else
        fail "systemd unit conan-server.service is $state / $enabled"
        hint "sudo systemctl enable --now conan-server   (journalctl -u conan-server for why)"
    fi
else
    warn "systemd unit not installed - boot start may race the disk mount (re-run bootstrap)"
fi

if ! command_exists docker || ! docker info >/dev/null 2>&1; then
    fail "cannot talk to docker as $(id -un)"
    hint "add yourself to the docker group, or run with sudo"
else
    cstate="$(docker inspect -f '{{.State.Status}} {{if .State.Health}}{{.State.Health.Status}}{{end}}' "$CONTAINER" 2>/dev/null || true)"
    case "$cstate" in
        "running healthy") pass "container $CONTAINER running, healthy" ;;
        running*)          warn "container $CONTAINER $cstate" ;;
        "")                fail "container $CONTAINER does not exist"; hint "sudo ./bootstrap.sh" ;;
        *)                 fail "container $CONTAINER is $cstate"
                           err="$(docker inspect -f '{{.State.Error}}' "$CONTAINER" 2>/dev/null)"
                           [[ -n "$err" ]] && hint "last error: $err"
                           hint "fix storage above first, then: sudo systemctl restart conan-server" ;;
    esac
    running_version="$(docker exec "$CONTAINER" pip show conan-server 2>/dev/null | awk '/^Version:/ {print $2}')"
    if [[ -n "$running_version" ]]; then
        if [[ "$running_version" == "$WANT_VERSION" ]]; then
            pass "conan-server $running_version matches versions.env"
        else
            warn "running conan-server $running_version but versions.env pins $WANT_VERSION - re-run bootstrap"
        fi
    fi
fi

# ---- HTTP ----------------------------------------------------------------------
echo "HTTP (127.0.0.1:$PORT)"
if curl -fsS -m 5 "http://127.0.0.1:$PORT/v1/ping" >/dev/null 2>&1; then
    pass "ping"
    users="$(env_get CONAN_SERVER_USERS)"; first="${users%%;*}"
    user="${first%%:*}"; password="${first#*:}"
    token="$(curl -fsS -m 10 -u "$user:$password" "http://127.0.0.1:$PORT/v2/users/authenticate" 2>/dev/null || true)"
    if [[ -n "$token" ]]; then
        pass "login as '$user'"
        result="$(curl -fsS -m 10 -H "Authorization: Bearer $token" "http://127.0.0.1:$PORT/v2/conans/search?q=*" 2>/dev/null || true)"
        if [[ -n "$result" ]]; then
            count="$(python3 -c 'import json,sys; print(len(json.load(sys.stdin)["results"]))' <<<"$result" 2>/dev/null || echo '?')"
            pass "search: $count recipe reference(s) stored"
        else
            fail "search failed"
        fi
    else
        fail "login as '$user' failed"
        hint "check CONAN_SERVER_USERS in .env, then: docker compose up -d"
    fi
else
    fail "server does not answer /v1/ping on port $PORT"
fi

echo ""
if (( failures == 0 )); then
    echo "All checks passed."
else
    echo "$failures check(s) FAILED - see conan-server/docs/troubleshooting.md"
fi
exit $(( failures > 0 ))
