# bitwarden / selfhosted (Vaultwarden) — PLANNED, not implemented

Status: **planned.** No scripts here yet — this document describes the intended design so it can be implemented later if needed.

## Intent

Host your **own** Bitwarden-compatible server so clients (desktop app, browser extension, mobile, `bw` CLI) sync against a vault you control instead of Bitwarden's cloud.

We will use **[Vaultwarden](https://github.com/dani-garcia/vaultwarden)** — an unofficial, lightweight Bitwarden-compatible server written in Rust. Reasons:

- **Docker-based**, so on Linux it fits this repo's "Linux via Docker" strategy.
- **ARM-friendly** — official multi-arch images run well on a **Raspberry Pi**, which is exactly the fleet this repo targets. (This is why the *server* can target Pis even though the *desktop client* can't.)
- Small footprint; implements the Bitwarden API that the standard clients already speak.

## Planned layout (when implemented)

```
selfhosted/
├── docker-compose.yml     # vaultwarden service: volume for data, port, env
├── .env.example           # DOMAIN, ADMIN_TOKEN, SIGNUPS_ALLOWED, etc. (no secrets committed)
├── bootstrap.sh           # ensure Docker (or defer to ../../docker), then `docker compose up -d`
└── RUNNING.md             # run steps + how to reach it, following repo conventions
```

## Planned behaviour / decisions (to settle at implementation)

- **Deployment:** `docker compose up -d` on a Linux host / Pi; reuse the [`docker`](../../docker) project to install the engine.
- **Data:** a named volume or bind mount so the vault persists across container restarts.
- **HTTPS:** Vaultwarden needs TLS for clients to connect. Options to decide: a reverse proxy (Caddy/Traefik/nginx) with automatic certs, or terminate TLS at Tailscale (`tailscale serve`) so it's reachable over the tailnet without exposing ports.
- **Access info:** per repo convention, the installer will **print the URL/admin details at the end** and ship a `connection-info.sh` to reprint them.
- **Secrets:** `ADMIN_TOKEN` and similar go in a local `.env` (git-ignored); only `.env.example` is committed.
- **No Windows server variant** — clients on Windows just point at the server's URL.

## Not doing yet

This is intentionally left unimplemented for now. When you want it, say so and it will be built following the layout above.
