# Operations

Run all commands on the Pi from `~/ftutil_repos/conan-server/linux`.

## Status and logs

```bash
./doctor.sh                 # full chain check; non-zero exit on failure
./connection-info.sh        # URLs, users, client commands
docker logs -f conan-server         # request log (mostly healthcheck pings)
systemctl status conan-server       # boot unit
journalctl -u conan-server -b       # why the unit did or didn't start this boot
```

## Start, stop, restart

```bash
sudo systemctl restart conan-server   # preferred - respects the disk-mount dependency
sudo systemctl stop conan-server      # packages stay on the disk
docker compose up -d                  # apply .env changes (recreates the container)
```

## Upgrade Conan

The server version follows ConanAutomation's toolchain pin:

1. Bump `conan_version` in `ConanAutomation/ftdeps/model.py` and merge.
2. On the Pi: `git pull && sudo ./bootstrap.sh`. It notices the new
   pin, rewrites `versions.env`, and rebuilds. The build warns that
   no dependency lock exists yet for the new version.
3. `./lock-deps.sh` writes `server/constraints/conan-server-<new>.txt`.
4. `docker compose up -d --build` rebuilds with the lock, then run `./doctor.sh`.
5. Commit `../versions.env` and the new constraints file. Also update
   `pipx install conan==...` in `examples/github-actions-conan.yml` and in
   consumer workflows.

Before upgrading, check the [conan-server changelog](https://docs.conan.io/2/changelog.html).
A downgrade is the same procedure with the old version; the on-disk format
has been stable across 2.x.

For a one-off test of another version without touching the pin:
`sudo CONAN_AUTOMATION_SYNC=0 ./bootstrap.sh` after hand-editing
`../versions.env`, and revert afterwards.

## Users and permissions

Users live in `.env`:

```bash
CONAN_SERVER_USERS=ci:<pw>;alice:<pw2>   # name:password pairs, ";"-separated
CONAN_WRITE_USERS=ci                      # who may upload (empty = all users)
CONAN_READ_USERS=?                        # "?" = any logged-in user, "*" = anonymous too
```

Apply with `docker compose up -d`. Generate passwords with
`python3 -c "import secrets; print(secrets.token_urlsafe(18))"`. After changing
the `ci` password, update the `CONAN_REMOTE_PASSWORD` secret in every
consumer repo.

## Rotate secrets

Replace `CONAN_JWT_SECRET` and/or `CONAN_UPDOWN_SECRET` in `.env` with new
`secrets.token_hex(32)` values, then run `docker compose up -d`. Existing login
tokens become invalid, and clients just log in again (`conan remote login`).

## Backup

```bash
sudo ./backup.sh /path/outside/the/data/dir
```

This produces two files:

- `conan-server-data-<stamp>.tgz`: the package store.
- `conan-server-env-<stamp>`: a copy of `.env`, chmod 600. It holds secrets,
  so keep it private.

The server is stopped for the few seconds the archive takes. The image is
not backed up because it rebuilds from the repo. Since this is a *cache*,
losing the packages costs only rebuild time. Losing `.env` means creating
new credentials and updating every consumer.

## Restore

On a fresh or replacement host, after steps 1–5 of
[setup-from-scratch.md](setup-from-scratch.md):

```bash
cd ~/ftutil_repos/conan-server/linux
cp /backup/conan-server-env-<stamp> .env && chmod 600 .env
# check CONAN_DISK_UUID / CONAN_MOUNT_POINT / CONAN_DATA_DIR / CONAN_PUBLIC_HOSTNAME in .env for the new host
sudo mkdir -p /mnt/expansion && sudo mount /dev/disk/by-uuid/<uuid> /mnt/expansion
mkdir -p /mnt/expansion/conan-server-data
tar -xzf /backup/conan-server-data-<stamp>.tgz -C /mnt/expansion/conan-server-data
sudo ./bootstrap.sh       # keeps the restored .env, adds fstab + unit, starts
./doctor.sh
```

## Move to a different disk

1. `sudo ./backup.sh /some/other/place`, or copy the data directory
   directly.
2. `sudo systemctl stop conan-server`.
3. Remove the old disk's line from `/etc/fstab`, plug in the new disk, and
   copy the data onto it.
4. In `.env`, delete the `CONAN_DISK_*`, `CONAN_MOUNT_POINT` and
   `CONAN_DATA_DIR` lines.
5. Run `sudo CONAN_DISK_UUID=<new> CONAN_DISK_FSTYPE=<fs> ./bootstrap.sh`.

## Updating the first (2026-08) deployment

The first deployment of this directory ran under the default compose project
name `linux`. `docker-compose.yml` now sets `name: conan-server`, so the first
`sudo ./bootstrap.sh` after `git pull` notices the old container (same name,
different project) and replaces it. Users, secrets and packages are kept,
because `.env` and the data directory don't change. It also adds the
`CONAN_DISK_*` keys to `.env` and installs the systemd unit. Afterwards you can
remove the leftovers: `docker network rm linux_default` and
`docker image rm ftutil/conan-server:2.31.1` (an unused test build).

## Housekeeping

- **Disk usage:** `./doctor.sh` prints used and free space. To prune
  old packages, use a client: `conan remove "<ref>#!latest" -r ftpi -c`
  removes all but the latest recipe revision.
- **Images:** `docker image prune` after upgrades.
- **NTFS:** after any unclean shutdown, `chkdsk /f` on Windows when
  convenient. `doctor.sh` warns when the kernel asked for one.
