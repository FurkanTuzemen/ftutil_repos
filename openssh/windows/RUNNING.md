# Running `install.ps1` (Windows)

`install.ps1` requires an **elevated** session (it declares `#Requires -RunAsAdministrator`) and runs on **both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`)**.

## PowerShell 7 (pwsh)

1. Open PowerShell 7 **as Administrator**: Start menu → type "PowerShell 7" → right-click → **Run as administrator**. (Or from any terminal: `Start-Process pwsh -Verb RunAs`.)
2. Run:
   ```powershell
   cd C:\ftutil_repos\openssh\windows
   .\install.ps1
   ```
   Custom port: `.\install.ps1 -Port 2222`

Confirm you're actually on PS7: `$PSVersionTable.PSVersion` should show `7.x`.

## If scripts are blocked

If you see "running scripts is disabled on this system", allow scripts for the **current session only**, then re-run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

## One-liner (elevate + bypass + run)

```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-ExecutionPolicy','Bypass','-File','C:\ftutil_repos\openssh\windows\install.ps1'
```

## Windows PowerShell 5.1

Same steps — launch "Windows PowerShell" as Administrator instead of pwsh.

## Reprint connection details

The install prints how to SSH in at the end. To show it again any time (no admin needed):

```powershell
.\connection-info.ps1
```

## Notes

- Under PS7 the firewall step loads the `NetSecurity` module through the Windows compatibility layer and may print a one-time `WinPSCompatSession` warning — this is expected and harmless.
- The script is idempotent: safe to re-run.
