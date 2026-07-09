# Running `bootstrap.sh` (Linux)

Installs the **Docker Engine** host-level. Meant to be cloned and run identically on every machine / Raspberry Pi.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/docker/linux
chmod +x bootstrap.sh    # only if the executable bit didn't survive the clone
sudo ./bootstrap.sh
```

## Notes

- Must run as **root** — the script re-checks and exits otherwise. Use `sudo`.
- Idempotent: safe to re-run (skips the install if `docker` is already present).
- Needs network access; uses Docker's official install script from `get.docker.com`, which supports Debian / Ubuntu / Raspberry Pi OS and the common RPM distros, and auto-selects the right architecture (arm64/armhf on Pis).
- The script adds your user to the `docker` group. **Log out and back in** (or run `newgrp docker`) before you can use `docker` without `sudo`.

## Verify

```bash
docker run --rm hello-world
docker compose version
```
