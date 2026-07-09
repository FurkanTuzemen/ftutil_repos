# ftutil_repos

Reproducible bootstrap/automation scripts for setting up tools (OpenSSH, Docker, Git, etc.) consistently across my machines: several Windows/Linux PCs and a fleet of Raspberry Pis.

## Goal

One source of truth for "how do I set this machine up" that:

- produces the **same result on every machine**, every time (idempotent — safe to re-run)
- works by **cloning this repo onto a Raspberry Pi and running one script** — no per-Pi customization needed, so it scales to N Pis
- uses the **right mechanism per platform** instead of forcing one tool everywhere

## Platform strategy

**Linux** (PCs and Raspberry Pis) — two allowed approaches, pick whichever fits the tool:

1. **Docker** — for anything that can run containerized (services, apps). Preferred when it applies.
2. **`bootstrap.sh` on the host** — for anything Docker can't install into itself: the SSH daemon, the Docker engine itself, Git, kernel/system packages, etc. Reproducibility here comes from `git clone` + running the script, not from a container — this is what makes it clonable across many Raspberry Pis identically.

**Windows** — native PowerShell scripts only (`install.ps1`). **No Docker on Windows** in this repo.

## Layout

```
ftutil_repos/
├── <project>/                  # one folder per tool, e.g. openssh, docker, git
│   ├── linux/
│   │   ├── bootstrap.sh        # host-level install, idempotent, run via git clone + ./bootstrap.sh
│   │   ├── RUNNING.md          # exact run steps for this platform, next to the script
│   │   └── docker-compose.yml  # optional — only if the tool runs containerized instead
│   ├── windows/
│   │   ├── install.ps1         # PowerShell install/config, no Docker
│   │   └── RUNNING.md          # exact run steps, incl. PowerShell 7 instructions
│   └── README.md                # what it installs, prerequisites, usage
├── lib/
│   ├── linux/common.sh         # shared bash helpers (logging, root check, command_exists, distro detect)
│   └── windows/Common.psm1     # shared PowerShell helpers (logging, admin check, command exists)
├── _template/                   # copy this folder to scaffold a new project
│   ├── linux/{bootstrap.sh, RUNNING.md}
│   ├── windows/{install.ps1, RUNNING.md}
│   └── README.md
├── CLAUDE.md                    # repo conventions/decisions for automated sessions
└── README.md                    # this file
```

Each project ships a **`RUNNING.md` right next to its scripts** with the exact commands to run them — the Windows one covers running under **PowerShell 7 (`pwsh`)** as well as Windows PowerShell 5.1.

## Usage

### Raspberry Pi / Linux fleet

```bash
git clone <repo-url> ~/ftutil_repos
cd ~/ftutil_repos/<project>/linux
chmod +x bootstrap.sh   # only if the executable bit didn't survive clone
sudo ./bootstrap.sh
```

Run the identical command on every Pi — that's the whole point.

### Windows

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\<project>\windows
.\install.ps1
```

Run PowerShell as Administrator. Works on both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`) — see each project's `windows/RUNNING.md` for the full PowerShell 7 walkthrough (elevation, execution policy, one-liner).

## Conventions for adding a new project

1. Copy `_template/` to `<project>/` and fill in the TODOs.
2. Scripts must be **idempotent**: check whether the tool is already installed/configured before acting, and exit cleanly if so.
3. Bash: start with `set -euo pipefail`, source `lib/linux/common.sh` for logging/helpers.
4. PowerShell: `$ErrorActionPreference = 'Stop'`, import `lib/windows/Common.psm1` for logging/helpers. Scripts must run on both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`) — start with `#Requires -Version 5.1`.
5. No secrets/credentials committed — scripts should be safe to run unattended.
6. Document what the project installs, prerequisites, and exact usage in its own `README.md`.
7. Ship a `RUNNING.md` next to the scripts in both `linux/` and `windows/` with the exact run steps (the `_template` already includes them) — the Windows one must cover PowerShell 7.
8. If a project sets up something you connect to or use (a server, a service), **print the access details at the end of the install** and ship a standalone `connection-info.ps1` / `connection-info.sh` next to the scripts so those details can be reprinted any time without re-running the installer. See `openssh/` for the pattern.

## Projects

- [x] `openssh` — install/configure OpenSSH server + client (Linux packages; Windows via winget), plus key-auth helpers and connection info.
- [x] `docker` — install Docker (Docker Engine host-level on Linux via `get.docker.com`; Docker Desktop on Windows via winget).
- [x] `git` — install Git (Linux packages; Windows via winget).

More will be added following the same convention above.
