# bitwarden

Installs the Bitwarden password manager **client** (desktop app and/or CLI). Both scripts are idempotent (safe to re-run).

## What gets installed

The installers **auto-detect** the machine:

| Machine | Installs |
|---|---|
| Graphical (desktop) | Desktop app **+** CLI (`bw`) |
| Headless (server / no display) | CLI (`bw`) only |

Override the detection with `-Mode Cli\|Both` (Windows) or `--mode cli\|both` (Linux).

## Linux (`linux/bootstrap.sh`)

- **CLI** (`bw`): official native binary → `/usr/local/bin/bw`.
- **Desktop app**: via **flatpak** from Flathub (`com.bitwarden.desktop`), on graphical systems.

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/bitwarden/linux
sudo ./bootstrap.sh              # or:  sudo ./bootstrap.sh --mode cli
```

Full run steps: [`linux/RUNNING.md`](linux/RUNNING.md).

## Windows (`windows/install.ps1`)

Native install via **winget**: `Bitwarden.CLI` (the `bw` command) and `Bitwarden.Bitwarden` (desktop app). No Docker.

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\bitwarden\windows
.\install.ps1                    # or:  .\install.ps1 -Mode Cli
```

Run from an **elevated (Administrator)** session. Full run steps: [`windows/RUNNING.md`](windows/RUNNING.md).

## Scope: Raspberry Pi / ARM (not yet)

Pis are **not in scope for this project yet**, deliberately:

- The Bitwarden **desktop app has no official ARM build**, so it can't run on a Pi.
- The native **`bw` CLI binary is x86_64 only**; on ARM the CLI is installed from npm instead (`npm install -g @bitwarden/cli`).

The Linux script detects a non-x86_64 host and **skips with a clear message** rather than failing. ARM support (npm-based CLI) will be added later if needed.

## Self-hosting (Vaultwarden) — planned, not implemented

If you later want to host your **own** Bitwarden server, that will live in [`selfhosted/`](selfhosted/) using **Vaultwarden** (a lightweight, ARM-friendly, Docker-based Bitwarden-compatible server that runs well on a Raspberry Pi). It is **documented but not implemented yet** — see [`selfhosted/README.md`](selfhosted/README.md).

## Prerequisites

- Linux: root/sudo, network access; `curl`/`wget` + `unzip` (auto-installed); flatpak for the desktop app (auto-installed).
- Windows: Administrator PowerShell, winget available.

## Verify

```bash
bw --version
```
