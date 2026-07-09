#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap: OpenSSH server + client (Windows, via winget)
.DESCRIPTION
    Installs the Win32-OpenSSH build (client + server) with winget, registers
    and starts the sshd service, and opens the firewall for inbound SSH.
    Idempotent: safe to re-run on an already-configured machine.

    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh). Under PS7 the
    NetSecurity firewall cmdlets load via the Windows compatibility layer, which
    may emit a one-time "loaded in Windows PowerShell using WinPSCompatSession"
    warning; that is benign and does not stop the script.
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\openssh\windows
    .\install.ps1
#>
[CmdletBinding()]
param(
    [int]$Port = 22
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin

if (-not (Test-CommandExists 'winget')) {
    Write-Log "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    exit 1
}

# --- Install (client + server ship in the same package) ---
$packageId = 'Microsoft.OpenSSH.Beta'
$installed = winget list --id $packageId -e --accept-source-agreements 2>$null | Select-String -SimpleMatch $packageId
if ($installed) {
    Write-Log "$packageId already installed, skipping winget install"
} else {
    Write-Log "Installing $packageId via winget"
    winget install --id $packageId -e --silent `
        --accept-package-agreements --accept-source-agreements
    # winget returns non-zero for benign cases (e.g. already up to date); verify by result instead.
}

# --- Locate the OpenSSH install directory ---
$sshDir = Join-Path $env:ProgramFiles 'OpenSSH'
if (-not (Test-Path (Join-Path $sshDir 'sshd.exe'))) {
    $found = Get-ChildItem -Path $env:ProgramFiles -Filter 'sshd.exe' -Recurse -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($found) {
        $sshDir = $found.DirectoryName
    } else {
        Write-Log "Could not locate sshd.exe after install. Check the winget output above."
        exit 1
    }
}
Write-Log "OpenSSH installed at $sshDir"

# --- Register the sshd + ssh-agent services (only if not already present) ---
if (-not (Get-Service -Name 'sshd' -ErrorAction SilentlyContinue)) {
    Write-Log "Registering the sshd service"
    & (Join-Path $sshDir 'install-sshd.ps1')
} else {
    Write-Log "sshd service already registered"
}

# --- Enable + start services ---
foreach ($svc in 'sshd', 'ssh-agent') {
    if (Get-Service -Name $svc -ErrorAction SilentlyContinue) {
        Set-Service -Name $svc -StartupType Automatic
        Start-Service -Name $svc
        Write-Log "$svc service: $((Get-Service -Name $svc).Status), startup Automatic"
    }
}

# --- Firewall: allow inbound SSH ---
$ruleName = 'ftutil-OpenSSH-Server-In-TCP'
if (-not (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)) {
    Write-Log "Adding firewall rule '$ruleName' for inbound TCP $Port"
    New-NetFirewallRule -Name $ruleName -DisplayName 'OpenSSH Server (sshd, ftutil)' `
        -Enabled True -Direction Inbound -Protocol TCP -Action Allow -LocalPort $Port | Out-Null
} else {
    Write-Log "Firewall rule '$ruleName' already exists"
}

Write-Log "Done. Client: $(Join-Path $sshDir 'ssh.exe'); Server listening on TCP $Port"
