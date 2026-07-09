# Running `bootstrap.sh` (Linux)

Host-level installer, meant to be **cloned and run identically on every machine / Raspberry Pi**.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/openssh/linux
chmod +x bootstrap.sh    # only if the executable bit didn't survive the clone
sudo ./bootstrap.sh
```

## Reprint connection details

The install prints how to SSH in at the end. To show it again any time (no root needed):

```bash
./connection-info.sh
```

## Notes

- Must run as **root** — the script re-checks and exits otherwise. Use `sudo`.
- Idempotent: safe to re-run.
- Supported package managers: apt, dnf, yum, pacman, zypper (so it works on Raspberry Pi OS / Debian / Ubuntu / Fedora / RHEL / Arch / openSUSE).
- Enables and starts the SSH service (`ssh` on Debian/Raspberry Pi OS, `sshd` elsewhere).
