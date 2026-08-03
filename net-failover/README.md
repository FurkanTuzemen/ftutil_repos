# net-failover

Keeps a machine on the internet: **ethernet first**, falling back through a
**priority-ordered list of WiFi networks** when the wire can't actually reach
the internet — and switching back automatically when it can.

Built for the Raspberry Pi fleet, where a Pi may be wired most of the time but
must not drop off the network when a cable, switch, router or ISP fails.

Run steps live next to the scripts: [`linux/RUNNING.md`](linux/RUNNING.md).

## Why not just let NetworkManager do it

NetworkManager already prefers ethernet over WiFi by route metric and can
autoconnect saved WiFi profiles. What it does not do is notice that a link is
**up but useless** — carrier present, DHCP lease valid, default route
installed, and no path to the internet. That is the common real-world failure
(ISP outage, dead router WAN port, captive portal), and in that state
NetworkManager happily keeps ethernet as the default route forever.

This daemon closes that gap.

## How it decides

- **Per-interface reachability.** Probes are bound to a specific interface with
  `SO_BINDTODEVICE` (`curl --interface`, `ping -I`), so each link is judged on
  its own merits regardless of which one currently owns the default route.
- **HTTP 204 is authoritative.** A non-204 answer means a captive portal or
  walled garden and counts as offline. ICMP is only consulted when no probe URL
  responded at all, which keeps a port-80-filtering uplink from being
  misjudged.
- **Ethernet is demoted, not downed.** When the wire fails its probe, its
  default-route metric is raised above WiFi's (100 → 1000) via
  `nmcli device modify`, which is a runtime-only change that does not touch the
  saved profile. The interface keeps its IP, so **LAN and SSH stay reachable**
  on it the whole time.
- **A threshold rides out blips.** `FAIL_THRESHOLD` consecutive failures are
  required before anything changes.
- **Failed networks cool down.** An SSID that won't associate, or associates
  without internet, is skipped for `SSID_COOLDOWN` seconds instead of being
  hammered.
- **Recovery is automatic.** As soon as ethernet probes clean again, its metric
  is restored and the radio is parked with `nmcli dev disconnect` (which also
  stops NetworkManager from autoconnecting it back).

## Linux

`linux/bootstrap.sh` — host-level install. The daemon drives the host's
NetworkManager and real radios, so per this repo's platform strategy it is a
host script, not a container.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/net-failover/linux
sudo ./bootstrap.sh
```

Idempotent: re-running upgrades the daemon and unit and **never overwrites**
`/etc/net-failover/networks.conf`, which holds your WiFi passphrases.

Then add your networks:

```bash
sudo net-failover --scan                     # what is in range
sudo nano /etc/net-failover/networks.conf    # SSID|PASSPHRASE, best first
sudo systemctl restart net-failover
```

To remove: `sudo ./uninstall.sh` (add `--purge` to delete the config too).

## Windows

Not applicable. This targets NetworkManager on Linux; Windows has its own
adapter-priority mechanism and is out of scope for this project.

## Prerequisites

- systemd, and **NetworkManager managing both interfaces** (`nmcli` present and
  `NetworkManager.service` active). If `wlan0` is managed by `dhcpcd` or
  `systemd-networkd`, migrate it to NetworkManager first — `bootstrap.sh`
  checks and refuses rather than fighting another manager.
- `curl`, root/sudo.
- A WiFi device, for failover to have anywhere to go.

## Files it installs

| Path | What |
|---|---|
| `/usr/local/sbin/net-failover` | the daemon |
| `/etc/net-failover/config` | tunables (intervals, probes, metrics) |
| `/etc/net-failover/networks.conf` | your WiFi priority list, mode `0600` |
| `/etc/systemd/system/net-failover.service` | unit, enabled at boot |
| `/run/net-failover/state` | current state, for scripts to read |

## Usage

```bash
sudo net-failover --status     # state, devices, routes, priority list
sudo net-failover --check      # probe each interface, changes nothing
sudo net-failover --scan       # what is in range right now
sudo net-failover --once       # run a single decision tick, verbosely
./linux/connection-info.sh     # reprint current uplink status (no root needed)
sudo journalctl -u net-failover -f
```

## Configuring networks

`/etc/net-failover/networks.conf`, one per line, **best first**:

```
SSID|PASSWORD|FLAGS
```

`PASSWORD` may be a plain-text passphrase, `@saved` to reuse what
NetworkManager already stores, or empty for an open network. `FLAGS` currently
supports `hidden` (tried even though it never appears in a scan). An explicit
password here is authoritative — it is synced into the NetworkManager profile,
so correcting a wrong passphrase in this file actually takes effect.

See [`linux/networks.conf.example`](linux/networks.conf.example) for the full
annotated version.

### Choosing the order

WiFi from the **same router** that feeds your ethernet port covers a dead
cable, switch or NIC — but not an ISP outage, since that router's WiFi is
equally offline then. A phone or 4G hotspot is the only entry that survives
that case, so it belongs last as a true independent uplink. Confirm
independence by comparing public IPs:

```bash
curl --interface eth0  https://api.ipify.org
curl --interface wlan0 https://api.ipify.org
```

Different answers mean genuinely separate uplinks, even when both hand out
addresses on the same private subnet.

## Gotchas worth knowing

- **A stored WPA key is hashed with the SSID.** A key saved under a misspelled
  SSID can never authenticate against the correct one — the plain-text
  passphrase is required. The symptom in `journalctl -u NetworkManager` is
  `4way_handshake -> disconnected` followed by "asking for new key".
- **`nmcli con modify` silently rejects `key-mgmt` and `psk` in one call**,
  leaving a profile that looks correct but has no secret and fails at the
  handshake. They must be set in separate invocations; the daemon does this.
- **Two uplinks on the same private subnet** (common when a hotspot also uses
  `192.168.1.0/24`) work, but mean two unrelated devices answer to the same
  gateway IP while both links are up. `DISCONNECT_WIFI_ON_ETH=yes` keeps that
  window small; changing the hotspot's LAN subnet removes it entirely.

## Tests

Mocked, hardware-free verification of the decision logic:

```bash
cd net-failover
./test/run-in-docker.sh        # reproducible, pinned image
# or, on any Linux host:
./test/run-tests.sh
```

See [`test/README.md`](test/README.md).
