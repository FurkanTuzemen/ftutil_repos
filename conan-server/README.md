# conan-server

Self-hosted **Conan 2 remote** — the official [`conan-server`](https://pypi.org/project/conan-server/) running in Docker on a Raspberry Pi, with package storage on an external USB disk. It acts as a binary cache: CI jobs and dev machines download prebuilt packages (recipes + the built `.dll`/`.lib`/`.so`/headers, stored per configuration) instead of rebuilding dependencies from source every time.

## Layout / how it works

- `linux/server/` — the Docker image: `python:<pinned>-slim` plus a **pinned** `conan-server`. At container start `entrypoint.py` renders `server.conf` from environment variables, then execs `conan_server`. All credentials/config live in the compose `.env`, so the image is generic.
- **Version policy: the server always matches [`ConanAutomation`](https://github.com/FurkanTuzemen/ConanAutomation).** Every `bootstrap.sh` run reads the toolchain pinned in that repo's `ftdeps/model.py` (`conan_version`, `python_version`) and writes it into `.env`; the compose build args pick it up. Bumping Conan in ConanAutomation + re-running `sudo ./bootstrap.sh` on the Pi is the whole upgrade procedure.
- `linux/docker-compose.yml` — runs the container (`restart: unless-stopped`, health-checked), publishes port 9300, and bind-mounts the package directory from the external disk to `/data`. `create_host_path` is disabled so a missing disk fails loudly instead of silently storing packages on the SD card.
- `linux/bootstrap.sh` — idempotent host setup: adds an `/etc/fstab` entry for the storage disk (by UUID, `nofail`, `ntfs3`), mounts it, creates the data directory **alongside the disk's existing data (nothing is erased)**, generates `linux/.env` with random secrets on first run, builds + starts the container, waits for health, prints connection info.
- `linux/connection-info.sh` — reprints the remote URL(s), users, and client commands any time.
- `windows/install.ps1` — client side: installs Conan via winget and registers the remote.
- `examples/github-actions-conan.yml` — GitHub Actions job using the server as a binary cache through Tailscale.

Secrets exist only in `linux/.env` on the server machine (gitignored, `chmod 600`).

## Server quickstart (Raspberry Pi)

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/conan-server/linux
sudo ./bootstrap.sh
```

Prerequisites: Docker (`docker/linux/bootstrap.sh` from this repo) and the storage disk plugged in. For a different disk than the default Seagate 4TB: `sudo CONAN_DISK_UUID=<uuid> CONAN_DISK_FSTYPE=ext4 ./bootstrap.sh` (find the UUID with `blkid`).

## Client usage (any machine)

```bash
conan remote add ftpi http://<pi-address>:9300
conan remote login ftpi ci        # password: linux/.env on the Pi
conan install . --build=missing   # download prebuilt deps, build only misses
conan upload "*" -r ftpi --confirm  # push what you built back to the cache
```

On Windows, `windows/install.ps1 -RemoteUrl http://<pi-address>:9300` installs Conan and adds the remote.

## GitHub Actions as a consumer

GitHub-hosted runners can't reach a home-LAN Pi directly. The example workflow joins the runner to a [Tailscale](https://tailscale.com) tailnet for the duration of the job (official `tailscale/github-action`), so nothing is exposed to the public internet — important because `conan_server` speaks plain HTTP. See [`examples/github-actions-conan.yml`](examples/github-actions-conan.yml) for the full job and the secrets/variables to configure. After installing Tailscale on the Pi, set `CONAN_PUBLIC_HOSTNAME` in `linux/.env` to the Pi's tailnet name/IP and restart (`docker compose up -d`) — that hostname is baked into the file-transfer URLs the server hands to clients.

## Operations

- Logs: `docker logs -f conan-server` · status: `docker ps`, `./connection-info.sh`
- Restart/apply `.env` changes: `cd linux && docker compose up -d`
- Upgrade: bump `conan_version` in ConanAutomation's `ftdeps/model.py`, then re-run `sudo ./bootstrap.sh` here — it re-syncs the pin and rebuilds. (Override for a one-off: `CONAN_SERVER_VERSION` in `.env` + `docker compose up -d --build`, until the next bootstrap re-syncs.)
- Add users: extend `CONAN_SERVER_USERS` (`name:pass;name2:pass2`) in `.env`, adjust `CONAN_WRITE_USERS`, re-run `docker compose up -d`
- Backup: the whole state is the data dir (`/mnt/expansion/conan-server-data`) + `linux/.env`
- Storage format: recipes and per-configuration binary tarballs (`conan_package.tgz`) under the data dir — platform-agnostic, so the Pi happily serves Windows/Linux/macOS binaries

## Notes

- A CI cache degrades gracefully: if the Pi is unreachable, `conan install --build=missing` just builds from source (slow but not broken).
- The default permission model requires authentication for both read and write (`CONAN_READ_USERS=?`); write is limited to the `ci` user.
- Cache downloads ride your home uplink — fine for tens-of-MB packages, worth remembering for huge dependency trees.
