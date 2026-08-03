# Running `install.ps1` (Windows)

Client-side setup: installs the **Conan client** (winget, `JFrog.Conan`) and
registers the self-hosted remote. The server itself runs on the Pi — see
[`../linux/RUNNING.md`](../linux/RUNNING.md).

## Windows PowerShell 5.1

```powershell
git clone <repo-url> C:\ftutil_repos
cd C:\ftutil_repos\conan-server\windows
.\install.ps1 -RemoteUrl http://<pi-address>:9300
```

Run from an **elevated (Administrator)** session.

## PowerShell 7 (`pwsh`)

```powershell
# elevated pwsh; allow local scripts for this session if needed:
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
cd C:\ftutil_repos\conan-server\windows
.\install.ps1 -RemoteUrl http://<pi-address>:9300
```

One-liner from anywhere:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File C:\ftutil_repos\conan-server\windows\install.ps1 -RemoteUrl http://<pi-address>:9300
```

## Notes

- Get `<pi-address>` (and the login password location) from
  `./connection-info.sh` on the Pi. On a tailnet, prefer the Tailscale
  name/IP.
- If winget just installed Conan, the current shell may not see it on PATH —
  open a new shell and re-run the script (idempotent) to register the remote.
- After registering: `conan remote login ftpi <user>`, then the usual
  `conan install . --build=missing` / `conan upload "*" -r ftpi --confirm`.
