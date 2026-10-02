# Running conan-monitor (on a second Linux host)

Watches the Conan server from **another machine** (currently `ftbitpi`) and
emails when it breaks. Because it runs elsewhere, it also catches a server
that is completely dead, which a check on the server itself never could.

Every 5 minutes (`conan-monitor.timer`):

1. It runs `ssh furkan@<sshHost>`. The key is authorized with
   `restrict,command="…/doctor.sh"`, so it can only run the health check.
   It has no shell, pty or forwarding.
2. It requests `GET http://<target>:9300/v1/ping` from the monitor host,
   which is what clients and CI see.

Emails go to `mail.to`:

- **ALERT** after 2 bad runs in a row (about 5–10 min; short blips and reboots
  don't alert)
- a **REMINDER** every 24 h while it stays down
- **RECOVERED** when it's healthy again

Each email includes the full `doctor.sh` output and a link to the runbook.

## Install

On the monitor host:

```bash
cd ~/ftutil_repos/conan-server/monitor
sudo ./install.sh       # user conan-monitor, ssh key, /etc/conan-monitor/config.json, units
```

On the server, paste the key line that `install.sh` printed:

```bash
~/ftutil_repos/conan-server/linux/authorize-monitor.sh 'ssh-ed25519 AAAA… conan-monitor@ftBitPi'
```

Back on the monitor host, fill in `/etc/conan-monitor/config.json` (mode
`root:conan-monitor 0640`; see `config.json.example`), then:

```bash
sudo ./install.sh                                            # enables the timer once no CHANGE_ME is left
sudo -u conan-monitor python3 /usr/local/lib/conan-monitor/conan-monitor.py --dry-run
sudo -u conan-monitor python3 /usr/local/lib/conan-monitor/conan-monitor.py --test-email
```

## Config notes

- **`sshHost` must be the LAN name** (`ftbeepi.local`) because ftbeepi has
  **Tailscale SSH** enabled. Tailscale intercepts ssh on the tailnet address
  and asks for an interactive browser login, so a batch ssh just hangs.
  `target`, which is used for the HTTP check, stays the tailnet name
  because that is what clients use.
- **Mail** goes through Resend SMTP (`smtp.resend.com:465`, user `resend`,
  password = API key). The current key is the Görücü one, from
  `/etc/gorucu/domain-mail.json` on ftbitpi, and Resend only lets it send from
  **gorucusu.com**. A `from` on another domain fails with
  `550 This API key is not authorized to send emails from …`. To send from
  your own domain, create a separate Resend key with sending access for that
  domain and put it in `mail.password`.

## Day-2

```bash
systemctl list-timers conan-monitor.timer         # next/last run
journalctl -u conan-monitor -n 50                  # one "status=…" line per run, "mail sent: …"
sudo cat /var/lib/conan-monitor/state.json         # badStreak / alerted / lastAlert
sudo systemctl start conan-monitor.service         # run a check now
sudo systemctl disable --now conan-monitor.timer   # pause alerts (e.g. planned maintenance)
```

To update after a `git pull`, re-run `sudo ./install.sh`. It keeps the config and the key.
To remove the server's trust in the monitor, delete the `conan-monitor@…` line
from `~/.ssh/authorized_keys` on the server.
