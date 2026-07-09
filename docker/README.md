# docker

Status: planned

Installs the Docker engine itself.

- `linux/bootstrap.sh` — host-level install of Docker Engine (can't containerize the container runtime itself), intended to be cloned and run identically on every Raspberry Pi/PC.
- `windows/install.ps1` — native Windows install, no nested Docker dependency.

Scaffolded from [`_template`](../_template) — see that folder for the structure convention this project follows.
