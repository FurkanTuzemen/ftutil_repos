# \<project-name\>

Status: template — copy this folder to `<project-name>/` at the repo root and fill in the TODOs.

One-line description of what this installs/configures.

## Linux

`linux/bootstrap.sh` — host-level install (or `linux/docker-compose.yml` if this tool runs containerized instead). Reproducible across a Raspberry Pi fleet via:

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/<project-name>/linux
sudo ./bootstrap.sh
```

## Windows

`windows/install.ps1` — native PowerShell install, no Docker. Run from an elevated PowerShell session:

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\<project-name>\windows
.\install.ps1
```

## Prerequisites

- TODO

## What it does

- TODO
