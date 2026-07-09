# Running `install.ps1` (Windows)

Installs Bitwarden via winget. Requires an **elevated** session (it declares `#Requires -RunAsAdministrator`) and runs on **both Windows PowerShell 5.1 and PowerShell 7+ (`pwsh`)**.

By default it **auto-detects** the machine: a normal (graphical) Windows gets the **CLI + desktop app**; a headless Windows (Server Core, no Desktop Experience) gets the **CLI only**. Override with `-Mode Cli` or `-Mode Both`.

## PowerShell 7 (pwsh)

1. Open PowerShell 7 **as Administrator**: Start menu → type "PowerShell 7" → right-click → **Run as administrator**.
2. Run:
   ```powershell
   cd C:\ftutil_repos\bitwarden\windows
   .\install.ps1              # or:  .\install.ps1 -Mode Cli
   ```

## If scripts are blocked

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

## One-liner (elevate + bypass + run)

```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-ExecutionPolicy','Bypass','-File','C:\ftutil_repos\bitwarden\windows\install.ps1'
```

## Notes

- Requires winget (`App Installer` from the Microsoft Store).
- Packages: `Bitwarden.CLI` (the `bw` command) and `Bitwarden.Bitwarden` (desktop app).
- Idempotent: safe to re-run (skips anything already installed).
- `bw` may not be on PATH in the same session that installed it — open a new terminal to verify.

## Verify

```powershell
bw --version
# desktop: launch "Bitwarden" from the Start menu
```
