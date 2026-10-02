# Running the Conan server (Linux / Raspberry Pi)

Host-level bootstrap that mounts the storage disk, installs a systemd unit
and starts the Dockerized server. Meant to be **cloned and run identically**
on whichever Pi hosts the cache. Full walkthrough from a blank SD card:
[`../docs/setup-from-scratch.md`](../docs/setup-from-scratch.md).

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/conan-server/linux
chmod +x *.sh            # only if the bit didn't survive the clone
sudo ./bootstrap.sh
./doctor.sh              # every check should be [ OK ]
```

## Notes

- Must run as **root** — the script re-checks and exits otherwise. Use `sudo`.
- **Docker first**: run `docker/linux/bootstrap.sh` from this repo if Docker is missing.
- The **storage disk must be plugged in**. Default is the Seagate Expansion 4TB
  (NTFS, mounted at `/mnt/expansion` — existing data on it is left untouched).
  Other disk: `sudo CONAN_DISK_UUID=<uuid> CONAN_DISK_FSTYPE=ext4 ./bootstrap.sh`.
- First run generates `.env` here with a random password for the `ci` user.
  Reprint access details any time: `./connection-info.sh` (no root needed).
- Idempotent: safe to re-run; it keeps an existing `.env` and fstab entry.
  Re-running is also how you upgrade (version pin: `../versions.env`).

## Scripts in this directory

| Script | Root? | Purpose |
|---|---|---|
| `bootstrap.sh` | yes | install / upgrade / repair the whole server |
| `doctor.sh` | no | health check: disk → mount → unit → container → HTTP → login |
| `connection-info.sh` | no | print URLs, users, client commands |
| `smoke-test.sh <url> <user>` | no | curl-only check, runnable from any client |
| `backup.sh <dir>` | yes | package store + `.env` → backup dir |
| `lock-deps.sh` | no | lock pip deps after a version bump |

## Day-2

```bash
./doctor.sh                          # first stop when anything looks wrong
docker logs -f conan-server          # server logs
sudo systemctl restart conan-server  # restart (waits for the disk mount)
docker compose up -d                 # apply .env changes
```

If the Pi booted **without** the disk (or the NTFS volume is dirty), see
[`../docs/troubleshooting.md`](../docs/troubleshooting.md).
More: [`../docs/operations.md`](../docs/operations.md).
