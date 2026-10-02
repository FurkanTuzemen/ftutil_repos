# Architecture

```
 GitHub Actions runner ──(tailscale/github-action, tag:ci)──┐
 Dev PC (Windows/Linux) ──────────(tailnet or LAN)──────────┤
                                                            ▼
┌──────────────────────── ftbeepi (Raspberry Pi 5) ───────────────────────────┐
│  tailscaled 100.85.113.90                                                   │
│        │ :9300                                                              │
│  ┌─────▼────────────────────────────┐   systemd: conan-server.service       │
│  │ container "conan-server"         │   (RequiresMountsFor=/mnt/expansion)  │
│  │  entrypoint.py → server.conf     │                                       │
│  │  conan_server (Bottle, HTTP)     │                                       │
│  │  /data ──────────────────────────┼──bind──┐                              │
│  └──────────────────────────────────┘        │                              │
│                                    /mnt/expansion/conan-server-data         │
│                                    (USB Seagate 4 TB, NTFS via ntfs3)       │
│  SD card: OS, Docker, ~/ftutil_repos, conan-server/linux/.env (chmod 600)   │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Components

| Piece | What it is | Where it's defined |
|---|---|---|
| Image `ftutil/conan-server:<ver>` | `python:<ver>-slim` + `conan-server==<ver>` with locked transitive deps. It contains no credentials. | `linux/server/Dockerfile`, `linux/server/constraints/` |
| Entrypoint | Renders `~/.conan_server/server.conf` from env vars at every start, then `exec conan_server` | `linux/server/entrypoint.py`, `linux/server/server.conf.template` |
| Container | `restart: unless-stopped`, `init: true`, health check on `/v1/ping` every 30 s, json-file logs capped at 3×10 MB | `linux/docker-compose.yml` |
| Config + secrets | `linux/.env`, generated once by bootstrap; gitignored, chmod 600 | `linux/.env.example` documents every key |
| Version pin | `conan-server/versions.env`, committed; bootstrap keeps it equal to ConanAutomation's toolchain | `versions.env` |
| Package store | Plain files on the USB disk, bind-mounted to `/data` | `CONAN_DATA_DIR` |
| Boot ordering | systemd oneshot unit that runs `docker compose up -d` after the disk is mounted and `docker compose stop` before it is unmounted | `linux/systemd/conan-server.service` |
| Network | Tailscale on the host. The server speaks plain HTTP and is never exposed to the internet. | (host setup; see setup doc) |

## Request flow

1. The client calls `GET /v1/ping` (no auth), then `GET /v2/users/authenticate`
   with HTTP basic auth and gets a JWT (valid 120 min, `jwt_expire_minutes`).
2. Recipe and package metadata calls carry `Authorization: Bearer <jwt>`.
   Permissions come from `server.conf`:
   - `[read_permissions] */*@*/*: ?`: any **authenticated** user can read.
     Anonymous users get 401 once the store holds packages. (`*` would allow
     anonymous access too.)
   - `[write_permissions] */*@*/*: ci`: only `ci` can upload.
3. File transfers go to URLs that the server generates and signs with
   `updown_secret`. Those URLs contain `CONAN_PUBLIC_HOSTNAME:CONAN_PUBLIC_PORT`,
   so that address must be reachable from every client. That's why it's
   the Tailscale IP and not `localhost` or the LAN IP.

## On-disk format

```
conan-server-data/
  <name>/<version>/<user>/<channel>/
    revisions.txt                         recipe revisions (+ .lock)
    <rrev>/export/                        conanfile.py, conanmanifest.txt, conan_export.tgz, conan_sources.tgz
    <rrev>/package/<package_id>/
      revisions.txt                       package revisions
      <prev>/conan_package.tgz            the binary, plus conaninfo.txt, conanmanifest.txt
```

The format doesn't depend on the platform. The Pi (arm64) stores and serves
Windows, Linux and macOS binaries, because it never runs them.

## Design decisions

- **Official `conan_server`, not Artifactory CE.** It's small, has no JVM,
  fits comfortably on a Pi, and is enough for one person's CI cache. Downsides:
  it runs a single-threaded Bottle/WSGIRef server, it has no web UI, and
  managing users means editing `.env`.
- **Plain HTTP + Tailscale instead of TLS.** The tailnet already encrypts and
  authenticates traffic, and GitHub runners join it for the length of a job
  (`tag:ci`). Nothing is port-forwarded.
- **The server version follows ConanAutomation.** The Conan client used by
  automation/CI (`ftdeps/model.py: conan_version`) and the server are kept
  identical, which avoids protocol and revision-format surprises.
  `bootstrap.sh` checks the pin on every run.
- **Locked dependencies.** Without the constraint file, a rebuild resolves
  whatever is newest on PyPI. On 2026-10-02 a fresh resolve already gave
  different PyJWT, idna and charset-normalizer versions than production.
  `linux/server/constraints/conan-server-<ver>.txt` keeps rebuilds identical.
  The base image tag (`3.11-slim`) still floats, on purpose, so OS security
  patches arrive on rebuild.
- **`create_host_path: false` on the data bind mount.** If the disk isn't
  mounted, the container fails to start. Without this, Docker would silently
  create an empty directory on the SD card and accept uploads into it.
- **A systemd unit on top of the restart policy.** Docker's restart-on-boot
  can run before the USB disk is mounted. The unit's `RequiresMountsFor=`
  orders the start after the mount, and on shutdown it stops the container
  before the NTFS volume is unmounted.
- **The disk stays NTFS** because it also holds personal data and gets
  plugged into Windows. This is the weakest part of the setup: an unclean
  unplug or power loss leaves the volume dirty, and Linux then refuses to
  mount it (see troubleshooting). A dedicated ext4 partition or disk would
  remove that failure mode: `CONAN_DISK_FSTYPE=ext4`.
