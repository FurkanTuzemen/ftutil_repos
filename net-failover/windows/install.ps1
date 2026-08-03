#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap: net-failover (Windows)
.DESCRIPTION
    Installs the net-failover daemon to C:\Program Files\net-failover, its
    config to C:\ProgramData\net-failover, and registers a SYSTEM scheduled
    task ('net-failover') that runs the failover loop from boot.

    Idempotent: re-running upgrades the daemon and task and never overwrites
    C:\ProgramData\net-failover\networks.conf (it holds your WiFi passphrases)
    or config.ps1.

    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh). Under PS7 the
    ScheduledTasks/NetAdapter modules may emit a one-time WinPSCompatSession
    warning; that is benign.
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\net-failover\windows
    .\install.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin
Write-Log 'Starting bootstrap for net-failover (Windows)'

$InstallDir = Join-Path $env:ProgramFiles 'net-failover'
$ConfDir    = Join-Path $env:ProgramData 'net-failover'
$TaskName   = 'net-failover'

# Language-neutral SIDs -- group NAMES like 'Administrators' do not exist on
# non-English Windows. 544 = Administrators, 545 = Users, S-1-5-18 = SYSTEM.
$SidAdmins = '*S-1-5-32-544'
$SidUsers  = '*S-1-5-32-545'
$SidSystem = '*S-1-5-18'

# ---------------------------------------------------------------- prereqs ---
# System32 curl.exe (Windows 10 1803+) does the interface-bound HTTP probes.
# Hard requirement, like on Linux: without it a captive portal would be
# misjudged as a working uplink.
$curlOk = Test-Path (Join-Path $env:SystemRoot 'System32\curl.exe')
if (-not $curlOk -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) { $curlOk = $true }
if (-not $curlOk) {
    Write-Log 'ERROR: curl.exe not found. It ships with Windows 10 1803+;'
    Write-Log '       on older builds install it first: winget install cURL.cURL'
    exit 1
}

# Not fatal: the daemon is still useful on a wired-only box, it just has
# nothing to fail over to.
$wifiAdapters = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.InterfaceType -eq 71 })
if ($wifiAdapters.Count -eq 0) {
    Write-Log 'WARNING: no WiFi adapter found - failover will have no target until one is present.'
} else {
    # netsh wlan is driven through the WLAN AutoConfig service.
    $svc = Get-Service -Name wlansvc -ErrorAction SilentlyContinue
    if ($svc) {
        if ($svc.StartType -ne 'Automatic') { Set-Service -Name wlansvc -StartupType Automatic }
        if ($svc.Status -ne 'Running') { Start-Service -Name wlansvc }
        Write-Log 'WLAN AutoConfig service (wlansvc): running, startup Automatic'
    }
}

# ------------------------------------------------------------------- code ---
# Always refreshed: these are code, not user data.
Write-Log "Installing daemon -> $InstallDir"
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
Copy-Item "$PSScriptRoot\net-failover.ps1" (Join-Path $InstallDir 'net-failover.ps1') -Force
Copy-Item "$PSScriptRoot\net-failover.cmd" (Join-Path $InstallDir 'net-failover.cmd') -Force

# On the machine PATH, so 'net-failover -Status' works from any NEW shell
# (the Windows twin of /usr/local/sbin).
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if (($machinePath -split ';') -notcontains $InstallDir) {
    Write-Log "Adding $InstallDir to the machine PATH (open a new shell to pick it up)"
    [Environment]::SetEnvironmentVariable('Path', ($machinePath.TrimEnd(';') + ';' + $InstallDir), 'Machine')
}

# ----------------------------------------------------------------- config ---
New-Item -ItemType Directory -Path $ConfDir -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $ConfDir 'state') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $ConfDir 'log') -Force | Out-Null

# Admins/SYSTEM own the tree; standard users only read (state, logs). The
# daemon dot-sources config.ps1 as SYSTEM, so it must not be user-writable.
icacls $ConfDir /inheritance:r /grant "${SidAdmins}:(OI)(CI)F" "${SidSystem}:(OI)(CI)F" "${SidUsers}:(OI)(CI)RX" | Out-Null

if (Test-Path (Join-Path $ConfDir 'config.ps1')) {
    Write-Log "Keeping existing $ConfDir\config.ps1 (not overwriting your tunables)"
} else {
    Write-Log "Installing default tunables -> $ConfDir\config.ps1"
    Copy-Item "$PSScriptRoot\net-failover.config.ps1" (Join-Path $ConfDir 'config.ps1')
}

# Administrators/SYSTEM only (the 0600 of Windows): this file holds plain-text
# WPA passphrases.
$networksConf = Join-Path $ConfDir 'networks.conf'
if (Test-Path $networksConf) {
    Write-Log "Keeping existing $networksConf (your WiFi list and passphrases)"
} else {
    Write-Log "Installing starter WiFi list -> $networksConf"
    Copy-Item "$PSScriptRoot\networks.conf.example" $networksConf
}
icacls $networksConf /inheritance:r /grant "${SidAdmins}:F" "${SidSystem}:F" | Out-Null

# ---------------------------------------------------------------- service ---
# A SYSTEM scheduled task is the native, dependency-free way to run a boot-time
# daemon on Windows (a real service would need a wrapper binary like NSSM).
# powershell.exe (5.1) is used because it exists on every box.
Write-Log "Registering scheduled task '$TaskName'"

$action = New-ScheduledTaskAction `
    -Execute (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') `
    -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Daemon' -f (Join-Path $InstallDir 'net-failover.ps1'))
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
# ExecutionTimeLimit zero = never stop it; restart-on-failure is the crash
# backstop (the loop itself catches per-tick errors).
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -StartWhenAvailable -MultipleInstances IgnoreNew `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1)

$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing -and $existing.State -eq 'Running') {
    Write-Log 'Task already running - restarting it to pick up changes'
    Stop-ScheduledTask -TaskName $TaskName
}
Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Principal $principal `
    -Settings $settings -Description 'Internet failover: ethernet first, WiFi fallback (ftutil)' -Force | Out-Null
Start-ScheduledTask -TaskName $TaskName

# Give the first tick a moment so the status printout is meaningful.
Start-Sleep -Seconds 3

$task = Get-ScheduledTask -TaskName $TaskName
if ($task.State -ne 'Running') {
    Write-Log "ERROR: the '$TaskName' task is not running (state: $($task.State)). Recent log:"
    Get-Content (Join-Path $ConfDir 'log\net-failover.log') -Tail 20 -ErrorAction SilentlyContinue
    exit 1
}
Write-Log "Task '$TaskName': running, starts at boot as SYSTEM"

Write-Log 'Done.'

# ------------------------------------------------------------ access info ---
# Repo convention: print how to use what we just set up. Failure here must not
# fail the install.
try {
    & (Join-Path $PSScriptRoot 'connection-info.ps1')
} catch {
    Write-Log "Could not print connection info: $($_.Exception.Message)"
    Write-Log 'Run .\connection-info.ps1 manually to see it.'
}

# Nudge only if no network is actually configured yet.
$hasEntries = $false
foreach ($line in @(Get-Content $networksConf -Encoding UTF8 -ErrorAction SilentlyContinue)) {
    if ($line -match '^\s*[^#\s|]+\|') { $hasEntries = $true; break }
}
if (-not $hasEntries) {
    Write-Host ''
    Write-Host '  NEXT STEP: no WiFi networks are configured yet. In this (elevated) shell:'
    Write-Host "    & '$InstallDir\net-failover.ps1' -Scan     # see what is in range"
    Write-Host "    notepad $networksConf                      # add SSID|PASSPHRASE lines, best first"
    Write-Host '    Stop-ScheduledTask -TaskName net-failover; Start-ScheduledTask -TaskName net-failover'
    Write-Host ''
}
