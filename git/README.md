# git

Installs Git. Both scripts are idempotent (safe to re-run).

## Linux (`linux/bootstrap.sh`)

Installs Git via the OS package manager, host-level — meant to be cloned and run identically on every Raspberry Pi / PC.

- Supports apt, dnf, yum, pacman, zypper.
- Exits early if `git` is already installed.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/git/linux
sudo ./bootstrap.sh
```

Full run steps: [`linux/RUNNING.md`](linux/RUNNING.md).

## Windows (`windows/install.ps1`)

Native install of **Git for Windows** via **winget** (`Git.Git`). No Docker.

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\git\windows
.\install.ps1
```

Run from an **elevated (Administrator)** session. Requires winget (`App Installer` from the Microsoft Store). Full run steps: [`windows/RUNNING.md`](windows/RUNNING.md).

## Prerequisites

- Linux: root/sudo, a supported package manager.
- Windows: Administrator PowerShell, winget available.

## Verify

```bash
git --version
```
