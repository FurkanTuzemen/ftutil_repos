# Running `install.ps1` (Windows)

Installs **Git for Windows** via winget. Requires an **elevated** session (it declares `#Requires -RunAsAdministrator`) and runs on **both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`)**.

## PowerShell 7 (pwsh)

1. Open PowerShell 7 **as Administrator**: Start menu → type "PowerShell 7" → right-click → **Run as administrator**.
2. Run:
   ```powershell
   cd C:\ftutil_repos\git\windows
   .\install.ps1
   ```

## If scripts are blocked

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

## One-liner (elevate + bypass + run)

```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-ExecutionPolicy','Bypass','-File','C:\ftutil_repos\git\windows\install.ps1'
```

## Notes

- Requires winget (`App Installer` from the Microsoft Store).
- Idempotent: safe to re-run (skips the install if `git` is already present).
- `git` may not be on PATH in the same session that installed it — open a new terminal to verify.

## Verify

```powershell
git --version
```
