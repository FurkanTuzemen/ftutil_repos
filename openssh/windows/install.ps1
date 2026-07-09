#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap: OpenSSH server + client (Windows, via winget)
.DESCRIPTION
    Installs the Win32-OpenSSH build (client + server) with winget, ensures the
    sshd service is registered/enabled/started, and opens the firewall for
    inbound SSH. Idempotent: safe to re-run on an already-configured machine.

    Uses the winget package 'Microsoft.OpenSSH.Preview' (Microsoft's Win32-OpenSSH
    MSI, which installs to C:\Program Files\OpenSSH and ships both ssh.exe and
    sshd.exe). This is a preview build; the stable OpenSSH on Windows ships as an
    optional feature (Add-WindowsCapability) instead, but this repo standardises
    on winget for Windows installs.

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

# Win32-OpenSSH MSI always installs here (64-bit). We look ONLY here on purpose:
# a broad search of Program Files can match unrelated sshd.exe binaries shipped
# by Git for Windows, WSL, etc.
$packageId = 'Microsoft.OpenSSH.Preview'
$sshDir    = Join-Path $env:ProgramFiles 'OpenSSH'
$sshdExe   = Join-Path $sshDir 'sshd.exe'

# --- Install (client + server ship in the same package) ---
$installed = winget list --id $packageId -e 2>$null | Select-String -SimpleMatch $packageId
if ($installed) {
    Write-Log "$packageId already installed, skipping winget install"
} else {
    Write-Log "Installing $packageId via winget"
    winget install --id $packageId -e --source winget --silent `
        --accept-package-agreements --accept-source-agreements
    Write-Log "winget exit code: $LASTEXITCODE"
}

# --- Verify the install landed where we expect (this is the real success signal) ---
if (-not (Test-Path $sshdExe)) {
    Write-Log "sshd.exe not found at $sshdExe after winget install."
    Write-Log "The winget install did not complete as expected (see its output above). Aborting."
    exit 1
}
Write-Log "OpenSSH installed at $sshDir"

# --- Register the sshd service if the MSI didn't already do it ---
if (-not (Get-Service -Name 'sshd' -ErrorAction SilentlyContinue)) {
    $installSshd = Join-Path $sshDir 'install-sshd.ps1'
    if (Test-Path $installSshd) {
        Write-Log "Registering the sshd service via install-sshd.ps1"
        & $installSshd
    } else {
        Write-Log "sshd service is not registered and $installSshd was not found."
        Write-Log "The MSI normally registers it; reopen the shell or reboot and re-run. Aborting."
        exit 1
    }
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
