# Running `bootstrap.sh` (Linux)

Host-level installer, meant to be **cloned and run identically on every machine / Raspberry Pi**.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/net-failover/linux
chmod +x bootstrap.sh    # only if the executable bit didn't survive the clone
sudo ./bootstrap.sh
```

The installer prints the current uplink status when it finishes, and tells you
what to do next if no WiFi networks are configured yet.

## Then add your WiFi networks

The install ships a placeholder list with no real credentials, so failover has
nowhere to go until you fill it in:

```bash
sudo net-failover --scan                      # what is in range
sudo nano /etc/net-failover/networks.conf     # SSID|PASSPHRASE, best first
sudo systemctl restart net-failover
```

Put the network you most want first. See the ordering advice in
[`networks.conf.example`](networks.conf.example) — WiFi from the same router
that feeds your ethernet port does not survive an ISP outage, so a phone / 4G
hotspot belongs last as an independent uplink.

## Verify

```bash
sudo net-failover --status     # state, devices, routes, priority list
sudo net-failover --check      # probe each interface, changes nothing
./connection-info.sh           # reprint uplink status, no root needed
sudo journalctl -u net-failover -f
```

Healthy output reports `state: ethernet` and an `eth0` metric of `100`.

### Testing real failover

Simulate a dead WAN without unplugging anything — drop IPv4 egress on the wired
interface to everything outside your LAN, leaving LAN/SSH intact:

```bash
sudo nft add table inet nftest
sudo nft add chain inet nftest out '{ type filter hook output priority 0; policy accept; }'
sudo nft add rule inet nftest out oifname eth0 ip daddr != 192.168.1.0/24 drop

watch -n2 'cat /run/net-failover/state; ip route show default'

sudo nft delete table inet nftest     # restore
```

Expect the state to move to `wifi:<SSID>` and `eth0`'s metric to rise to
`1000`, then return to `ethernet` at metric `100` after the rule is removed.
Adjust `192.168.1.0/24` to your LAN subnet.

**If you are connected over SSH via the wired interface**, this is safe only
when your session is on that LAN subnet (or link-local IPv6, or another
interface such as Tailscale) — the rule only blocks off-LAN IPv4. Confirm with
`echo $SSH_CONNECTION` first, and consider a watchdog that removes the rule
regardless:

```bash
sudo setsid bash -c 'sleep 300; nft delete table inet nftest' &
```

## Notes

- Must run as **root** — the script re-checks and exits otherwise. Use `sudo`.
- Idempotent: safe to re-run. It upgrades the daemon and unit and **never
  overwrites** `/etc/net-failover/networks.conf` or `/etc/net-failover/config`.
- Requires NetworkManager to manage both interfaces; `bootstrap.sh` refuses to
  install otherwise rather than fighting `dhcpcd` / `systemd-networkd`.
- `networks.conf` is mode `0600` and holds plain-text passphrases. It is never
  committed to this repo.

## Uninstall

```bash
cd ~/ftutil_repos/net-failover/linux
sudo ./uninstall.sh              # keeps /etc/net-failover
sudo ./uninstall.sh --purge      # also deletes the config and passphrases
```

Removes the service and daemon, restores the ethernet route metric, and deletes
only the NetworkManager profiles this daemon created (the `nf-` prefixed ones).
