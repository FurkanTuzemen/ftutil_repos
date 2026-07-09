# docker

Installs Docker. Both scripts are idempotent (safe to re-run).

## Linux (`linux/bootstrap.sh`)

Host-level install of the **Docker Engine** — the container runtime can't install itself into a container, so this runs on the host and is meant to be cloned and run identically on every Raspberry Pi / PC.

- Uses Docker's official `get.docker.com` script (supports Debian / Ubuntu / Raspberry Pi OS and common RPM distros; auto-selects arm64/armhf/amd64).
- Enables and starts the `docker` service, and adds your user to the `docker` group (log out/in to use `docker` without `sudo`).
- Includes the Compose plugin (`docker compose`).

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/docker/linux
sudo ./bootstrap.sh
```

Full run steps: [`linux/RUNNING.md`](linux/RUNNING.md).

## Windows (`windows/install.ps1`)

Native install of **Docker Desktop** via **winget** (`Docker.DockerDesktop`). ("No Docker on Windows" in this repo refers to not using containers as the install *mechanism* — installing the Docker tool itself via winget is fine.)

- Installs Docker Desktop with winget.
- Prints next steps (reboot for the WSL2/Hyper-V backend, first-launch agreement, verify command).

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\docker\windows
.\install.ps1
```

Run from an **elevated (Administrator)** session. Needs the WSL2 backend (or Hyper-V) and usually a reboot; the first launch requires accepting Docker's service agreement in the GUI. Full run steps: [`windows/RUNNING.md`](windows/RUNNING.md).

## Prerequisites

- Linux: root/sudo, network access, `curl` or `wget`.
- Windows: Administrator PowerShell, winget, WSL2 or Hyper-V available.

## Verify

```bash
docker run --rm hello-world
```
