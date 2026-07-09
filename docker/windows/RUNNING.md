# Running `install.ps1` (Windows)

Installs **Docker Desktop** via winget. Requires an **elevated** session (it declares `#Requires -RunAsAdministrator`) and runs on **both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`)**.

## PowerShell 7 (pwsh)

1. Open PowerShell 7 **as Administrator**: Start menu → type "PowerShell 7" → right-click → **Run as administrator**.
2. Run:
   ```powershell
   cd C:\ftutil_repos\docker\windows
   .\install.ps1
   ```

## If scripts are blocked

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

## One-liner (elevate + bypass + run)

```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-ExecutionPolicy','Bypass','-File','C:\ftutil_repos\docker\windows\install.ps1'
```

## Notes

- Requires winget (`App Installer` from the Microsoft Store).
- Docker Desktop needs the **WSL2** backend (or Hyper-V) and usually a **reboot** after install.
- **First launch is manual:** open Docker Desktop once and accept the Docker Subscription Service Agreement — this step can't be automated.
- Idempotent: safe to re-run (skips the install if Docker is already present).

## Verify

```powershell
docker --version
docker run --rm hello-world
```
