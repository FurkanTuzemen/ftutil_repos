#!/usr/bin/env bash
# Install conan-monitor on the MONITOR host (not the server): a dedicated
# system user, an ssh key, the script, a systemd timer, and the config file.
#
#   cd ~/ftutil_repos/conan-server/monitor && sudo ./install.sh
#
# Then authorize the printed key on the server (linux/authorize-monitor.sh),
# fill in /etc/conan-monitor/config.json and run the self-test - see RUNNING.md.
# Idempotent: re-run to update the script/units; config and key are kept.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../lib/linux/common.sh
source "$SCRIPT_DIR/../../lib/linux/common.sh"

require_root
command_exists python3 || { log "python3 is required"; exit 1; }
command_exists ssh || { log "the ssh client is required"; exit 1; }

USER_NAME=conan-monitor
HOME_DIR=/var/lib/conan-monitor
CONF_DIR=/etc/conan-monitor
LIB_DIR=/usr/local/lib/conan-monitor

# ---- user + ssh key ---------------------------------------------------------
if ! id "$USER_NAME" >/dev/null 2>&1; then
    useradd --system --home-dir "$HOME_DIR" --create-home --shell /usr/sbin/nologin "$USER_NAME"
    log "Created system user $USER_NAME"
fi
install -d -m 700 -o "$USER_NAME" -g "$USER_NAME" "$HOME_DIR" "$HOME_DIR/.ssh"
if [[ ! -f "$HOME_DIR/.ssh/id_ed25519" ]]; then
    sudo -u "$USER_NAME" ssh-keygen -q -t ed25519 -N "" -C "conan-monitor@$(hostname)" -f "$HOME_DIR/.ssh/id_ed25519"
    log "Generated $HOME_DIR/.ssh/id_ed25519"
fi

# ---- script + config ----------------------------------------------------------
install -d -m 755 "$LIB_DIR"
install -m 755 "$SCRIPT_DIR/conan-monitor.py" "$LIB_DIR/conan-monitor.py"
install -d -m 750 -o root -g "$USER_NAME" "$CONF_DIR"
if [[ ! -f "$CONF_DIR/config.json" ]]; then
    install -m 640 -o root -g "$USER_NAME" "$SCRIPT_DIR/config.json.example" "$CONF_DIR/config.json"
    log "Wrote $CONF_DIR/config.json from the example - fill in the SMTP password"
fi

# ---- systemd ------------------------------------------------------------------
install -m 644 "$SCRIPT_DIR/conan-monitor.service" "$SCRIPT_DIR/conan-monitor.timer" /etc/systemd/system/
systemctl daemon-reload
if grep -q CHANGE_ME "$CONF_DIR/config.json"; then
    log "Timer NOT enabled yet: $CONF_DIR/config.json still has CHANGE_ME placeholders."
else
    systemctl enable --now conan-monitor.timer >/dev/null
    log "conan-monitor.timer enabled (every 5 min)"
fi

echo ""
echo "============================ conan-monitor ============================"
echo "  1. On the SERVER, authorize this key (it can only run doctor.sh):"
echo "       ~/ftutil_repos/conan-server/linux/authorize-monitor.sh '$(cat "$HOME_DIR/.ssh/id_ed25519.pub")'"
echo "  2. Fill in $CONF_DIR/config.json (target, mail.password), then re-run this script."
echo "  3. Self-test:"
echo "       sudo -u $USER_NAME python3 $LIB_DIR/conan-monitor.py --dry-run"
echo "       sudo -u $USER_NAME python3 $LIB_DIR/conan-monitor.py --test-email"
echo "  Logs: journalctl -u conan-monitor"
echo "======================================================================="
