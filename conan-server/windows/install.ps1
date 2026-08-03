#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Conan client setup (Windows): install Conan and optionally register the
    self-hosted remote served from the Pi (see ../linux).
.DESCRIPTION
    Must be idempotent: safe to run again on a machine that's already set up.
    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\conan-server\windows
    .\install.ps1 -RemoteUrl http://<pi-address>:9300
#>
[CmdletBinding()]
param(
    # URL of the self-hosted server, printed by linux/connection-info.sh on
    # the Pi. Omit to only install the Conan client.
    [string]$RemoteUrl,
    [string]$RemoteName = 'ftpi'
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin
Write-Log "Starting Conan client setup"

if (Test-CommandExists 'conan') {
    Write-Log "Conan already installed, skipping install"
} else {
    Write-Log "Installing Conan via winget (JFrog.Conan)"
    winget install --id JFrog.Conan -e --silent --accept-source-agreements --accept-package-agreements
    # winget updates PATH for future shells; make conan resolvable in this one.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
}

if (-not (Test-CommandExists 'conan')) {
    Write-Log "conan is not on PATH in this session yet - open a NEW shell and re-run this script to register the remote."
    return
}

if ($RemoteUrl) {
    $existing = conan remote list 2>$null
    if ($existing -match [regex]::Escape($RemoteUrl)) {
        Write-Log "A remote with URL $RemoteUrl is already registered, skipping"
    } else {
        conan remote add $RemoteName $RemoteUrl
        Write-Log "Added remote '$RemoteName' -> $RemoteUrl"
    }
    Write-Log "Log in with: conan remote login $RemoteName <user>   (password: linux/.env on the Pi)"
} else {
    Write-Log "No -RemoteUrl given, remote not registered. Re-run with -RemoteUrl http://<pi-address>:9300 to add it."
}

Write-Log "Done."
