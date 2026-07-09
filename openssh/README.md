# openssh

Installs and configures the OpenSSH **server + client** consistently across machines. Both scripts are idempotent (safe to re-run).

## Linux (`linux/bootstrap.sh`)

Host-level install via the OS package manager — the SSH daemon can't be containerized, so this runs on the host and is meant to be cloned and run identically on every Raspberry Pi / PC.

- Installs `openssh-server` + `openssh-client` (supports apt, dnf, yum, pacman, zypper).
- Enables and starts the SSH service (`ssh` on Debian/Raspberry Pi OS, `sshd` elsewhere).

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/openssh/linux
sudo ./bootstrap.sh
```

## Windows (`windows/install.ps1`)

Native install via **winget** (`Microsoft.OpenSSH.Beta` — the Win32-OpenSSH build, which ships both `ssh.exe` client and `sshd.exe` server). No Docker.

- Installs the package with winget.
- Registers the `sshd` and `ssh-agent` services, sets them to start Automatically, and starts them.
- Adds an inbound firewall rule for TCP 22 (override with `-Port`).

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\openssh\windows
.\install.ps1            # or:  .\install.ps1 -Port 2222
```

Run from an elevated (Administrator) PowerShell session. Requires winget (`App Installer` from the Microsoft Store).

## Prerequisites

- Linux: root/sudo, a supported package manager.
- Windows: Administrator PowerShell, winget available.

## Verify

```bash
# on the machine running the server
ssh localhost
# from another machine
ssh <user>@<host-ip>
```
