#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap: Docker Desktop (Windows, via winget)
.DESCRIPTION
    Installs Docker Desktop with winget (package 'Docker.DockerDesktop').
    Idempotent: skips the install if Docker is already present.

    "No Docker on Windows" in this repo means we don't use containers as the
    install *mechanism* on Windows - installing the Docker tool itself via winget
    is fine. On Linux we install the Docker Engine host-level instead.

    Docker Desktop needs the WSL2 backend (or Hyper-V) and usually a reboot after
    install, and its first launch requires accepting the Docker Subscription
    Service Agreement in the GUI - so this step is not fully unattended.

    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\docker\windows
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

$packageId = 'Docker.DockerDesktop'

# Already present? (either the docker CLI is on PATH, or winget lists the package)
$dockerOnPath = Test-CommandExists 'docker'
$wingetHas    = winget list --id $packageId -e 2>$null | Select-String -SimpleMatch $packageId
if ($dockerOnPath -or $wingetHas) {
    Write-Log "Docker already installed, skipping winget install."
} else {
    Write-Log "Installing $packageId via winget (this is a large download)"
    winget install --id $packageId -e --source winget --silent `
        --accept-package-agreements --accept-source-agreements
    Write-Log "winget exit code: $LASTEXITCODE"
}

Write-Log "Done."
$dockerCli = (Get-Command docker -ErrorAction SilentlyContinue).Source
Write-Host ""
Write-Host "==================== Docker Desktop ===================="
if ($dockerCli) {
    Write-Host "  CLI: $dockerCli"
    Write-Host "  Version: $(docker --version 2>$null)"
} else {
    Write-Host "  CLI not on PATH yet - a sign-out/reboot is usually needed."
}
Write-Host ""
Write-Host "  Next steps:"
Write-Host "    1. Reboot if prompted (enables the WSL2 / Hyper-V backend)."
Write-Host "    2. Launch Docker Desktop once and accept the service agreement."
Write-Host "    3. Verify:  docker run --rm hello-world"
Write-Host "======================================================="
Write-Host ""
