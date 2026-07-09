#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap: Git for Windows (via winget)
.DESCRIPTION
    Installs Git for Windows with winget (package 'Git.Git').
    Idempotent: skips the install if git is already present.
    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\git\windows
    .\install.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin

if (-not (Test-CommandExists 'winget')) {
    Write-Log "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    exit 1
}

$packageId = 'Git.Git'

$gitOnPath = Test-CommandExists 'git'
$wingetHas = winget list --id $packageId -e 2>$null | Select-String -SimpleMatch $packageId
if ($gitOnPath -or $wingetHas) {
    Write-Log "Git already installed, skipping winget install."
    if ($gitOnPath) { Write-Log (git --version) }
} else {
    Write-Log "Installing $packageId via winget"
    winget install --id $packageId -e --source winget --silent `
        --accept-package-agreements --accept-source-agreements
    Write-Log "winget exit code: $LASTEXITCODE"
}

Write-Log "Done."
$gitCli = (Get-Command git -ErrorAction SilentlyContinue).Source
if ($gitCli) {
    Write-Log "git: $gitCli ($(git --version 2>$null))"
} else {
    Write-Log "git is not on PATH in this session yet - open a new terminal, then run 'git --version'."
}
