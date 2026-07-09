# openssh

Status: planned

Installs and configures OpenSSH (server) consistently across machines.

- `linux/bootstrap.sh` — host-level install via the OS package manager + systemd service, intended to be cloned and run identically on every Raspberry Pi.
- `windows/install.ps1` — installs the Windows OpenSSH Server optional feature and starts/enables the service.

Scaffolded from [`_template`](../_template) — see that folder for the structure convention this project follows.
