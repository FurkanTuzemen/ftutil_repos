#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap: Bitwarden (Windows, via winget)
.DESCRIPTION
    Installs the Bitwarden CLI always, and the Bitwarden desktop app on graphical
    systems. On a headless Windows (Server Core, no Desktop Experience) only the
    CLI is installed. Idempotent: skips anything already present.
    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh).

    winget packages: Bitwarden.CLI (bw) and Bitwarden.Bitwarden (desktop app).
.PARAMETER Mode
    Auto (default) detects GUI vs headless; Cli forces CLI-only; Both forces
    CLI + desktop app.
.EXAMPLE
    .\install.ps1
.EXAMPLE
    .\install.ps1 -Mode Cli
#>
[CmdletBinding()]
param(
    [ValidateSet('Auto', 'Cli', 'Both')]
    [string]$Mode = 'Auto'
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin

if (-not (Test-CommandExists 'winget')) {
    Write-Log "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    exit 1
}

# Server Core (headless) has no explorer.exe; Desktop Experience does.
function Test-HasGui {
    return (Test-Path (Join-Path $env:WINDIR 'explorer.exe'))
}

if ($Mode -eq 'Auto') {
    if (Test-HasGui) {
        $Mode = 'Both'; Write-Log "Graphical Windows detected -> installing CLI + desktop app."
    } else {
        $Mode = 'Cli';  Write-Log "Headless Windows (Server Core) detected -> installing CLI only."
    }
}

function Install-WingetPackage {
    param([string]$Id, [string]$Friendly)
    $has = winget list --id $Id -e 2>$null | Select-String -SimpleMatch $Id
    if ($has) {
        Write-Log "$Friendly already installed, skipping."
    } else {
        Write-Log "Installing $Friendly ($Id) via winget"
        winget install --id $Id -e --source winget --silent `
            --accept-package-agreements --accept-source-agreements
        Write-Log "winget exit code: $LASTEXITCODE"
    }
}

Install-WingetPackage -Id 'Bitwarden.CLI' -Friendly 'Bitwarden CLI'
if ($Mode -eq 'Both') {
    Install-WingetPackage -Id 'Bitwarden.Bitwarden' -Friendly 'Bitwarden desktop app'
}

Write-Log "Done."
Write-Host ""
Write-Host "==================== Bitwarden ready ===================="
$bw = (Get-Command bw -ErrorAction SilentlyContinue).Source
if ($bw) {
    Write-Host "  CLI: $bw ($(bw --version 2>$null))"
} else {
    Write-Host "  CLI installed - open a new terminal so 'bw' is on PATH, then: bw --version"
}
if ($Mode -eq 'Both') {
    Write-Host "  Desktop app: launch 'Bitwarden' from the Start menu and log in."
}
Write-Host "  CLI login:  bw login   (then: bw unlock)"
Write-Host "========================================================"
Write-Host ""
