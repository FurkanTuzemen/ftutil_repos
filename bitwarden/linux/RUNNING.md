# Running `bootstrap.sh` (Linux)

Installs Bitwarden. Meant to be cloned and run identically on every machine.

By default it **auto-detects** the machine: a graphical system gets the **CLI + desktop app**; a headless system (no display / boots to `multi-user.target`) gets the **CLI only**. Override with `--mode cli` or `--mode both`.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/bitwarden/linux
chmod +x bootstrap.sh    # only if the executable bit didn't survive the clone
sudo ./bootstrap.sh              # or:  sudo ./bootstrap.sh --mode cli
```

## Notes

- Must run as **root** — the script re-checks and exits otherwise. Use `sudo`.
- Idempotent: safe to re-run (skips anything already installed).
- **CLI** (`bw`): installed as the official native binary to `/usr/local/bin/bw` (needs `curl`/`wget` + `unzip`, auto-installed).
- **Desktop app**: installed via **flatpak** from Flathub (`com.bitwarden.desktop`); flatpak is installed first if missing.
- **x86_64 only.** Raspberry Pis / ARM are **not in scope yet** — the desktop app has no ARM build and the native `bw` binary is x86_64; on ARM the CLI comes from npm (`npm install -g @bitwarden/cli`). The script detects a non-x86_64 host and skips with a clear message. See [`../README.md`](../README.md).

## Verify

```bash
bw --version
# desktop: launch "Bitwarden" from your app menu, or: flatpak run com.bitwarden.desktop
```
