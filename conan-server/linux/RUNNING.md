# Running the Conan server (Linux / Raspberry Pi)

Host-level bootstrap that mounts the storage disk and starts the Dockerized
server. Meant to be **cloned and run identically** on whichever Pi hosts the
cache.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/conan-server/linux
chmod +x bootstrap.sh connection-info.sh   # only if the bit didn't survive the clone
sudo ./bootstrap.sh
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

## Day-2

```bash
docker logs -f conan-server        # server logs
docker compose up -d               # apply .env changes / start after stop
docker compose down                # stop (packages stay on the disk)
```

If the Pi booted **without** the disk attached, plug it in and run
`sudo mount /mnt/expansion && docker compose up -d` (or just re-run
`sudo ./bootstrap.sh`).
