# Running `bootstrap.sh` (Linux)

Installs **Git** host-level via the OS package manager. Meant to be cloned and run identically on every machine / Raspberry Pi.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/git/linux
chmod +x bootstrap.sh    # only if the executable bit didn't survive the clone
sudo ./bootstrap.sh
```

## Notes

- Must run as **root** — the script re-checks and exits otherwise. Use `sudo`.
- Idempotent: safe to re-run (exits early if `git` is already installed).
- Supported package managers: apt, dnf, yum, pacman, zypper (Raspberry Pi OS / Debian / Ubuntu / Fedora / RHEL / Arch / openSUSE).

## Verify

```bash
git --version
```
