# net-failover tests

Verification of the failover **decision logic** with no hardware, no root, no
live network and no risk to the machine running it.

## Why Docker here

net-failover itself is **not** containerized — it drives the host's
NetworkManager and real radios, so it installs on the host via
`linux/bootstrap.sh`. Docker is used only to pin a reproducible environment for
the test suite, so the same command gives the same result on any machine in the
fleet.

```bash
cd net-failover
./test/run-in-docker.sh
```

Or run directly on any Linux host with bash (shellcheck optional):

```bash
./test/run-tests.sh
```

## How it works

`test/bin/` holds mock `nmcli`, `curl`, `ping` and `ip` binaries that are put
ahead of the real ones on `PATH`. The **real daemon** then runs unmodified
against scripted network conditions.

Scenario state lives in a temp dir per test (`$MOCK_DIR`):

| File | Meaning |
|---|---|
| `devices` | `name:type:state` per interface |
| `connections` | `name:type:device:ssid` per NM profile |
| `scan` | SSIDs currently in range |
| `active_ssid` | which SSID is associated |
| `probe_<iface>` | HTTP status the mock `curl` returns for that interface |
| `ping_<iface>` | `ok` / `fail` for the mock `ping` |
| `connect_<ssid>` | `fail` to make association fail |
| `metric_<iface>` | route metric the daemon set |
| `nmcli.log` | every nmcli invocation, for ordering assertions |

The daemon's file paths are redirected with `NET_FAILOVER_CONFIG`,
`NET_FAILOVER_NETWORKS`, `NET_FAILOVER_STATE_DIR` and `NET_FAILOVER_SYSFS_NET`
(the last one fakes `/sys/class/net/<if>/carrier`). These exist purely for
testing; systemd runs with the defaults.

Each test calls `net-failover --once`, which runs exactly one decision tick.

## What is covered

| Scenario | Asserts |
|---|---|
| ethernet healthy | stays put, metric 100, WiFi untouched |
| ethernet healthy while radio associated | radio is parked |
| single probe failure, threshold 2 | does **not** fail over |
| carrier up but no internet | metric demoted to 1000, WiFi attempted |
| several networks in range | first listed wins |
| first choice out of range | skipped without an attempt |
| associates but no internet | falls through to the next network, in order |
| captive portal (non-204) | treated as offline, ICMP not consulted |
| HTTP blocked, ICMP fine | stays on ethernet via the ping fallback |
| no carrier | goes straight to WiFi |
| nothing configured in range | reports `offline` |
| hidden network | attempted despite being absent from the scan |
| ethernet recovers | returns to it, metric restored, radio parked |

Plus `shellcheck` and `bash -n` over the daemon, the installer scripts and the
mocks.

## Limitations

These tests cover decision logic, not the NetworkManager interaction itself —
the mocks assume `nmcli` behaves as documented. Real-hardware behaviour
(association, DHCP, actual route installation) still needs the live check in
[`../linux/RUNNING.md`](../linux/RUNNING.md).
