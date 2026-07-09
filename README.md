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
│   │   └── docker-compose.yml  # optional — only if the tool runs containerized instead
│   ├── windows/
│   │   └── install.ps1         # PowerShell install/config, no Docker
│   └── README.md                # what it installs, prerequisites, usage
├── lib/
│   ├── linux/common.sh         # shared bash helpers (logging, root check, command_exists, distro detect)
│   └── windows/Common.psm1     # shared PowerShell helpers (logging, admin check, command exists)
├── _template/                   # copy this folder to scaffold a new project
│   ├── linux/bootstrap.sh
│   ├── windows/install.ps1
│   └── README.md
└── README.md                    # this file
```

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

Run PowerShell as Administrator.

## Conventions for adding a new project

1. Copy `_template/` to `<project>/` and fill in the TODOs.
2. Scripts must be **idempotent**: check whether the tool is already installed/configured before acting, and exit cleanly if so.
3. Bash: start with `set -euo pipefail`, source `lib/linux/common.sh` for logging/helpers.
4. PowerShell: `$ErrorActionPreference = 'Stop'`, import `lib/windows/Common.psm1` for logging/helpers.
5. No secrets/credentials committed — scripts should be safe to run unattended.
6. Document what the project installs, prerequisites, and exact usage in its own `README.md`.

## Planned projects

- [ ] `openssh` — install/configure OpenSSH (server)
- [ ] `docker` — install the Docker engine (host-level on Linux; no nested Docker)
- [ ] `git` — install Git

More will be added following the same convention above.
