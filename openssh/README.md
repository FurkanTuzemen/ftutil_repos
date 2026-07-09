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

Full run steps: [`linux/RUNNING.md`](linux/RUNNING.md).

## Windows (`windows/install.ps1`)

Native install via **winget** (`Microsoft.OpenSSH.Preview` — Microsoft's Win32-OpenSSH MSI, which installs to `C:\Program Files\OpenSSH` and ships both `ssh.exe` client and `sshd.exe` server). No Docker.

> This is a *preview* build — currently the only Microsoft OpenSSH package in winget. The stable Windows OpenSSH ships as an optional feature (`Add-WindowsCapability`) instead; this repo standardises on winget for Windows installs.

- Installs the package with winget.
- Registers the `sshd` and `ssh-agent` services, sets them to start Automatically, and starts them.
- Adds an inbound firewall rule for TCP 22 (override with `-Port`).

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\openssh\windows
.\install.ps1            # or:  .\install.ps1 -Port 2222
```

Run from an **elevated (Administrator)** session. Works on both Windows PowerShell 5.1 and PowerShell 7+ — with pwsh:

```powershell
pwsh -File .\install.ps1
```

Requires winget (`App Installer` from the Microsoft Store). Under PowerShell 7 the firewall step loads the `NetSecurity` module through the Windows compatibility layer and may print a one-time WinPSCompatSession warning — this is expected and harmless.

Full run steps (elevation, execution policy, PowerShell 7 one-liner): [`windows/RUNNING.md`](windows/RUNNING.md).

## Connection details

Both installers **print how to SSH into the machine at the end** — user, hostname, the reachable IPv4 addresses (auto-labeled LAN vs Tailscale), the listening port, and ready-to-copy `ssh` commands.

To reprint them any time (no admin/root needed):

```powershell
# Windows
.\connection-info.ps1
```

```bash
# Linux
./connection-info.sh
```

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
