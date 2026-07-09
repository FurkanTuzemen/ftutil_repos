# Running `bootstrap.sh` (Linux)

Host-level installer, meant to be **cloned and run identically on every machine / Raspberry Pi**.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/<project>/linux
chmod +x bootstrap.sh    # only if the executable bit didn't survive the clone
sudo ./bootstrap.sh
```

## Notes

- Must run as **root** — the script re-checks and exits otherwise. Use `sudo`.
- Scripts must be idempotent: safe to re-run.
- If the tool runs containerized instead, this folder holds a `docker-compose.yml` — run it with `docker compose up -d`.
