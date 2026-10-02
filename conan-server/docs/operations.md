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
sudo systemctl restart conan-server   # preferred - respects the storage-mount dependency
sudo systemctl stop conan-server      # packages stay in CONAN_DATA_DIR
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
# check CONAN_PUBLIC_HOSTNAME, CONAN_DATA_DIR (and CONAN_DISK_* if using a dedicated disk) in .env
sudo mkdir -p /srv/conan-server-data
sudo tar -xzf /backup/conan-server-data-<stamp>.tgz -C /srv/conan-server-data
sudo ./bootstrap.sh       # keeps the restored .env, adds fstab + unit, starts
./doctor.sh
```

## Move to a different disk (or back to the SD card)

```bash
sudo systemctl stop conan-server
# copy the store to the new location, e.g. a dedicated ext4 disk mounted at /mnt/conan:
sudo mkdir -p /mnt/conan && sudo mount /dev/disk/by-uuid/<uuid> /mnt/conan
sudo cp -a /srv/conan-server-data /mnt/conan/
sudo umount /mnt/conan
# in .env: delete the CONAN_DATA_DIR line (and any old CONAN_DISK_* / CONAN_MOUNT_POINT lines)
sudo CONAN_DISK_UUID=<uuid> CONAN_DISK_FSTYPE=ext4 CONAN_MOUNT_POINT=/mnt/conan ./bootstrap.sh
./doctor.sh
```

To go back to the SD card, copy the store to `/srv/conan-server-data` and
run `sudo CONAN_DISK_UUID=none CONAN_DATA_DIR=/srv/conan-server-data ./bootstrap.sh`.
Bootstrap never removes old fstab entries, so delete the old disk's line from
`/etc/fstab` yourself if the disk goes away for good.

## Updating the first (2026-08) deployment

The first deployment of this directory ran under the default compose project
name `linux`. `docker-compose.yml` now sets `name: conan-server`, so the first
`sudo ./bootstrap.sh` after `git pull` notices the old container (same name,
different project) and replaces it. Users, secrets and packages are kept,
because `.env` and the data directory don't change. It also adds the
`CONAN_DISK_*` keys to `.env` and installs the systemd unit. Afterwards you can
remove the leftovers: `docker network rm linux_default` and
`docker image rm ftutil/conan-server:2.31.1` (an unused test build).

On 2026-10-02 the packages were also moved off the NTFS Seagate disk
(`/mnt/expansion/conan-server-data`) to `/srv/conan-server-data`, following
the procedure above. Later that day they moved to a dedicated ext4 disk
(Samsung M3 Portable 1 TB, formatted from Windows through WSL:
`wsl --mount \.\PHYSICALDRIVE<n> --bare`, then `parted` + `mkfs.ext4 -L
conan_server -m 1`) mounted at `/mnt/conan`. The copies on the Seagate and in
`/srv/conan-server-data` were left in place as fallbacks and can be deleted.

## Housekeeping

- **Disk usage:** `./doctor.sh` prints used and free space. To prune
  old packages, use a client: `conan remove "<ref>#!latest" -r ftpi -c`
  removes all but the latest recipe revision.
- **Images:** `docker image prune` after upgrades.
- **SD card space:** the cache shares the card with the OS. `doctor.sh` warns
  at 90% full; prune, or move the cache to a dedicated ext4 disk.
