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

    It also sets the SSH DEFAULT SHELL. Windows OpenSSH otherwise drops you into
    cmd.exe; -DefaultShell pwsh (the default) makes new SSH sessions land in
    PowerShell 7 instead, if pwsh is installed.
.PARAMETER Port
    Inbound TCP port to open for sshd (default 22).
.PARAMETER DefaultShell
    Which shell sshd hands out: pwsh (PowerShell 7, default), powershell (Windows
    PowerShell 5.1), cmd (revert to the built-in default), or keep (don't touch).
    'pwsh' falls back to leaving the default if PowerShell 7 isn't installed.
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\openssh\windows
    .\install.ps1
.EXAMPLE
    .\install.ps1 -DefaultShell keep      # leave the SSH shell as-is
#>
[CmdletBinding()]
param(
    [int]$Port = 22,
    [ValidateSet('pwsh', 'powershell', 'cmd', 'keep')]
    [string]$DefaultShell = 'pwsh'
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin

if (-not (Test-CommandExists 'winget')) {
    Write-Log "winget not found. Install 'App Installer' from the Microsoft Store, then re-run."
    exit 1
}

# Set which shell sshd launches. By default Windows OpenSSH uses cmd.exe; this
# points it at PowerShell 7 (or Windows PowerShell). DefaultShellCommandOption
# '-c' makes remote one-liners (ssh host "cmd") work with a PowerShell shell.
# Read fresh per connection, so no sshd restart is needed. Idempotent.
function Set-SshDefaultShell {
    param([ValidateSet('pwsh', 'powershell', 'cmd', 'keep')][string]$Choice)

    $regPath = 'HKLM:\SOFTWARE\OpenSSH'
    if (-not (Test-Path $regPath)) { New-Item -Path $regPath -Force | Out-Null }

    if ($Choice -eq 'keep') { Write-Log "Leaving the SSH default shell unchanged."; return }

    if ($Choice -eq 'cmd') {
        Remove-ItemProperty -Path $regPath -Name DefaultShell, DefaultShellCommandOption -ErrorAction SilentlyContinue
        Write-Log "SSH default shell reset to cmd.exe (registry override removed)."
        return
    }

    $shellExe = $null
    if ($Choice -eq 'pwsh') {
        $shellExe = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if (-not $shellExe -and (Test-Path 'C:\Program Files\PowerShell\7\pwsh.exe')) {
            $shellExe = 'C:\Program Files\PowerShell\7\pwsh.exe'
        }
        if (-not $shellExe) {
            Write-Log "PowerShell 7 (pwsh) not installed - leaving the SSH shell as the default (cmd)."
            Write-Log "Install pwsh (e.g. the git/bitwarden pattern, or winget Microsoft.PowerShell) and re-run, or use -DefaultShell powershell."
            return
        }
    } else {
        $shellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
        if (-not (Test-Path $shellExe)) { Write-Log "Windows PowerShell not found; leaving the SSH shell as default."; return }
    }

    $curShell = (Get-ItemProperty -Path $regPath -Name DefaultShell -ErrorAction SilentlyContinue).DefaultShell
    $curOpt   = (Get-ItemProperty -Path $regPath -Name DefaultShellCommandOption -ErrorAction SilentlyContinue).DefaultShellCommandOption
    if ($curShell -eq $shellExe -and $curOpt -eq '-c') {
        Write-Log "SSH default shell already set to $shellExe."
    } else {
        New-ItemProperty -Path $regPath -Name DefaultShell -Value $shellExe -PropertyType String -Force | Out-Null
        New-ItemProperty -Path $regPath -Name DefaultShellCommandOption -Value '-c' -PropertyType String -Force | Out-Null
        Write-Log "SSH default shell set to $shellExe (new SSH sessions land here; no sshd restart needed)."
    }
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

# --- SSH default shell (cmd.exe otherwise) ---
Set-SshDefaultShell -Choice $DefaultShell

Write-Log "Done."

# Print how to connect. Failure here must not fail the install.
try {
    & (Join-Path $PSScriptRoot 'connection-info.ps1')
} catch {
    Write-Log "Could not print connection info: $($_.Exception.Message)"
    Write-Log "Run .\connection-info.ps1 manually to see how to connect."
}
