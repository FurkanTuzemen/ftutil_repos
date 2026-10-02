# conan-server

Self-hosted **Conan 2 remote**. It runs the official
[`conan-server`](https://pypi.org/project/conan-server/) in Docker on a
Raspberry Pi, keeps packages on the Pi's SD card (ext4), and is reachable over
Tailscale. It serves as a binary cache: CI jobs and dev machines download
prebuilt dependencies (recipes plus the built `.dll`/`.lib`/`.so`/headers,
per configuration) instead of rebuilding them, and push back anything they
had to build.

Everything needed to rebuild the server from a blank SD card is in this
directory. The secrets (`linux/.env`) and the package store are
not, and `linux/backup.sh` backs both up.

## Current deployment

| | |
|---|---|
| Host | `ftbeepi`, Raspberry Pi 5 Model B (8 GB), Raspberry Pi OS / Debian 13 *trixie*, arm64 |
| URL (tailnet) | `http://100.85.113.90:9300`, `http://ftbeepi.tailad1eae.ts.net:9300` |
| Server | `conan-server` **2.7.1** on `python:3.11-slim` (pinned in [`versions.env`](versions.env)) |
| Storage | Root filesystem (64 GB SD card, ext4): `/srv/conan-server-data` (`CONAN_DISK_UUID=none`). A dedicated disk is optional. |
| Users | `ci` (read + write); anonymous access is refused |
| Consumers | GitHub Actions through Tailscale (e.g. [`conan_server_test`](https://github.com/FurkanTuzemen/conan_server_test)); dev PCs |

## Quickstart

Server (Pi, with Docker installed through `docker/linux/bootstrap.sh` and
Tailscale up):

```bash
cd ~/ftutil_repos/conan-server/linux
sudo ./bootstrap.sh     # generate .env, install systemd unit, build, start
./doctor.sh             # end-to-end health check
```

Client (any machine on the tailnet; Windows: `windows/install.ps1`):

```bash
conan remote add ftpi http://100.85.113.90:9300
conan remote login ftpi ci                 # password: linux/.env on the Pi
conan install . --build=missing            # download what exists, build the rest
conan upload "*" -r ftpi --confirm         # push new binaries back to the cache
```

Exact run steps: [`linux/RUNNING.md`](linux/RUNNING.md), [`windows/RUNNING.md`](windows/RUNNING.md).

## Documentation

- [Architecture](docs/architecture.md): components, the boot and request flow, design decisions.
- [Setup from scratch](docs/setup-from-scratch.md): from a blank SD card to a working server.
- [Operations](docs/operations.md): logs, upgrades, users, backup and restore, secret rotation, changing disks.
- [Clients and CI](docs/clients.md): Windows, Linux and GitHub Actions setup.
- [Troubleshooting](docs/troubleshooting.md): symptom-to-fix table, plus the 2026-10-02 dirty-NTFS outage write-up.

## Layout

```
versions.env                    pinned conan-server + python versions (source of truth, synced with ConanAutomation)
linux/
  bootstrap.sh                  idempotent install / upgrade / repair (root)
  doctor.sh                     health check: disk -> mount -> unit -> container -> HTTP -> login
  connection-info.sh            prints URLs, users and client commands
  smoke-test.sh                 curl-only check from any client machine
  backup.sh                     package store + .env -> backup dir
  lock-deps.sh                  regenerates server/constraints/ after a version bump
  lib.sh                        conan-server helpers on top of lib/linux/common.sh
  docker-compose.yml            the service: port 9300, disk bind mount, healthcheck, log rotation
  .env.example                  every config variable, documented (real .env is generated, gitignored)
  server/
    Dockerfile                  python:<ver>-slim + conan-server==<ver> with locked transitive deps
    constraints/                per-version pip lock files
    entrypoint.py               renders server.conf from env vars, then execs conan_server
    server.conf.template
  systemd/conan-server.service  starts after the storage mounts, stops before it unmounts
windows/install.ps1             installs the pinned Conan client, registers the remote
examples/github-actions-conan.yml
docs/
```

## History

- **2026-08-03:** first deployment. Smoke-tested with `zlib/1.3@ft/rc1`
  from `conan_server_test`.
- **2026-08-03 → 2026-10-02:** down for about 8 weeks, unnoticed. An unclean
  shutdown left the NTFS disk dirty, Linux refused to mount it, and the
  container couldn't start ([write-up](docs/troubleshooting.md#incident-2026-10-02-server-down-8-weeks-dirty-ntfs-volume)).
- **2026-10-02:** repaired and hardened:
  - single version pin with locked dependencies
  - a systemd unit tied to the storage mount
  - `doctor.sh` and `backup.sh`
  - log rotation
  - the docs in `docs/`
  - packages moved from the NTFS USB disk to the SD card (ext4), so a dirty
    NTFS volume can't take the server down again
