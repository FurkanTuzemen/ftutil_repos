# Clients and CI

Remote URL: `http://100.85.113.90:9300` (or `http://ftbeepi.tailad1eae.ts.net:9300`).
The client machine must be on the tailnet, or on the same LAN and using
`http://192.168.1.7:9300`. **Use the same Conan version as the server**
(`conan-server/versions.env`, currently 2.7.1).

Logging in is required for both download and upload: anonymous clients get
401. The `ci` password is in `conan-server/linux/.env` on the Pi (`CONAN_SERVER_USERS`).

## Windows

```powershell
git clone https://github.com/FurkanTuzemen/ftutil_repos.git C:tutil_repos
cd C:tutil_repos\conan-server\windows
.\install.ps1 -RemoteUrl http://100.85.113.90:9300 -Login   # elevated session
```

The script installs `conan==<pinned>` with pip, or with winget if Python is
missing. If Conan is already installed at a different version, it warns
instead of replacing it. It then adds or updates the `ftpi` remote, and
`-Login` prompts for the password.

## Linux / macOS

```bash
pipx install conan==2.7.1
conan profile detect
conan remote add ftpi http://100.85.113.90:9300
conan remote login ftpi ci
```

## Day-to-day

```bash
conan install . --build=missing          # cache hits download, misses build locally
conan upload "*" -r ftpi --confirm       # share what you built (only 'ci' can upload)
conan list "*" -r ftpi                   # what's on the server
conan list "zlib/1.3@ft/rc1:*" -r ftpi   # binaries for one recipe
```

To check a remote without Conan installed (curl only):
`CONAN_PASSWORD=... conan-server/linux/smoke-test.sh http://100.85.113.90:9300 ci`.

## GitHub Actions

GitHub-hosted runners join the tailnet for the length of the job through
[`tailscale/github-action`](https://github.com/tailscale/github-action), so
the server is never exposed publicly. Full example:
[`examples/github-actions-conan.yml`](../examples/github-actions-conan.yml).
A live version is [`conan_server_test`](https://github.com/FurkanTuzemen/conan_server_test),
a zlib build → upload → wipe → download round trip.

Per consuming repo, under *Settings → Secrets and variables → Actions*:

| Kind | Name | Value |
|---|---|---|
| variable | `CONAN_REMOTE_URL` | `http://100.85.113.90:9300` |
| variable | `CONAN_REMOTE_USER` | `ci` |
| secret | `CONAN_REMOTE_PASSWORD` | the `ci` password from `conan-server/linux/.env` on the Pi |
| secret | `TS_OAUTH_CLIENT_ID` / `TS_OAUTH_SECRET` | Tailscale OAuth client that may create `tag:ci` nodes |

Tailscale side (admin console):

- Declare the tag: `"tagOwners": { "tag:ci": ["autogroup:admin"] }`.
- If the ACLs aren't allow-all, allow the runners to reach the Pi:
  `{"action": "accept", "src": ["tag:ci"], "dst": ["<pi-host-or-tag>:9300"]}`.
- Create the OAuth client with the `auth_keys` (write) scope and tag `tag:ci`.

The cache fails gracefully: if the Pi is unreachable,
`conan install --build=missing` still works and builds everything from
source, just slower.
