#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Conan client setup (Windows): install the pinned Conan client and register
    the self-hosted remote served from the Pi (see ../linux).
.DESCRIPTION
    Must be idempotent: safe to run again on a machine that's already set up.
    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
    The Conan version comes from ..\versions.env so the client matches the
    server. An already-installed Conan with a different version is reported,
    not replaced.
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\conan-server\windows
    .\install.ps1 -RemoteUrl http://100.85.113.90:9300 -Login
#>
[CmdletBinding()]
param(
    # URL of the self-hosted server, printed by linux/connection-info.sh on
    # the Pi. Omit to only install the Conan client.
    [string]$RemoteUrl,
    [string]$RemoteName = 'ftpi',
    [string]$User = 'ci',
    # Prompt for the password and run `conan remote login` afterwards.
    [switch]$Login
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin
Write-Log "Starting Conan client setup"

$versionsFile = Join-Path $PSScriptRoot '..\versions.env'
$wanted = (Get-Content $versionsFile | Where-Object { $_ -match '^CONAN_SERVER_VERSION=' }) -replace '^CONAN_SERVER_VERSION=', ''
if (-not $wanted) { throw "CONAN_SERVER_VERSION not found in $versionsFile" }
Write-Log "Pinned Conan version: $wanted"

if (Test-CommandExists 'conan') {
    $have = ((conan --version) -replace '[^0-9.]', '').Trim()
    if ($have -eq $wanted) {
        Write-Log "Conan $have already installed"
    } else {
        Write-Log "WARNING: Conan $have installed, server runs $wanted. To match: python -m pip install `"conan==$wanted`""
    }
} else {
    $python = @('py', 'python') | Where-Object { Test-CommandExists $_ } | Select-Object -First 1
    if ($python) {
        Write-Log "Installing conan==$wanted with pip ($python)"
        & $python -m pip install --disable-pip-version-check "conan==$wanted"
    } else {
        Write-Log "No Python found - installing Conan $wanted via winget (JFrog.Conan)"
        winget install --id JFrog.Conan -e --version $wanted --silent --accept-source-agreements --accept-package-agreements
    }
    # Installers update PATH for future shells; make conan resolvable in this one.
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' +
                [Environment]::GetEnvironmentVariable('Path', 'User')
    if (-not (Test-CommandExists 'conan')) {
        Write-Log "conan is not on PATH in this session yet - open a NEW shell and re-run this script to register the remote."
        return
    }
}

if (-not $RemoteUrl) {
    Write-Log "No -RemoteUrl given, remote not registered. Re-run with -RemoteUrl http://<pi-address>:9300 to add it."
    return
}

$existing = conan remote list 2>$null
if ($existing -match "^$([regex]::Escape($RemoteName)):") {
    conan remote update $RemoteName --url $RemoteUrl
    Write-Log "Remote '$RemoteName' points to $RemoteUrl"
} else {
    conan remote add $RemoteName $RemoteUrl
    Write-Log "Added remote '$RemoteName' -> $RemoteUrl"
}

if ($Login) {
    conan remote login $RemoteName $User
} else {
    Write-Log "Log in with: conan remote login $RemoteName $User   (password: conan-server/linux/.env on the Pi)"
}
Write-Log "Done."
