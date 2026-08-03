#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Remove net-failover (Windows). Idempotent: safe to run when it is already gone.
.DESCRIPTION
    Keeps C:\ProgramData\net-failover by default (it holds your WiFi
    passphrases); pass -Purge to delete the config too. Restores automatic
    interface metrics and deletes only the WLAN profiles this daemon created
    (the nf- prefixed ones).
.EXAMPLE
    .\uninstall.ps1
.EXAMPLE
    .\uninstall.ps1 -Purge
#>
[CmdletBinding()]
param([switch]$Purge)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin
Write-Log 'Removing net-failover'

$InstallDir = Join-Path $env:ProgramFiles 'net-failover'
$ConfDir    = Join-Path $env:ProgramData 'net-failover'
$TaskName   = 'net-failover'

# --- scheduled task ---
if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Write-Log "Removing scheduled task '$TaskName'"
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

# --- restore automatic metrics (we may exit while ethernet is demoted) ---
foreach ($a in @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { ($_.InterfaceType -eq 6 -and $_.InterfaceDescription -notmatch 'Bluetooth') -or $_.InterfaceType -eq 71 })) {
    try {
        Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv4 -AutomaticMetric Enabled -ErrorAction SilentlyContinue
        Set-NetIPInterface -InterfaceIndex $a.ifIndex -AddressFamily IPv6 -AutomaticMetric Enabled -ErrorAction SilentlyContinue
        Write-Log "Restored automatic interface metric on $($a.Name)"
    } catch { }
}

# --- drop only the WLAN profiles this daemon created (prefix nf-) ---
# Profile names come from wlansvc's XML store: locale-independent, unlike
# parsing 'netsh wlan show profiles' output.
$profDir = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces'
foreach ($f in @(Get-ChildItem -Path $profDir -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue)) {
    try {
        $name = ([xml](Get-Content -LiteralPath $f.FullName -Raw)).WLANProfile.name
        if ($name -and $name.StartsWith('nf-')) {
            Write-Log "Deleting WLAN profile '$name'"
            netsh wlan delete profile name="$name" | Out-Null
        }
    } catch { }
}

# --- files and PATH ---
if (Test-Path $InstallDir) {
    Write-Log "Removing $InstallDir"
    Remove-Item -Recurse -Force $InstallDir
}
$machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
if (($machinePath -split ';') -contains $InstallDir) {
    Write-Log 'Removing the install dir from the machine PATH'
    $parts = @($machinePath -split ';' | Where-Object { $_ -and $_ -ne $InstallDir })
    [Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), 'Machine')
}

Remove-Item -Recurse -Force (Join-Path $ConfDir 'state') -ErrorAction SilentlyContinue
Remove-Item -Recurse -Force (Join-Path $ConfDir 'log') -ErrorAction SilentlyContinue

if ($Purge) {
    Write-Log "Purging $ConfDir (including your WiFi passphrases)"
    Remove-Item -Recurse -Force $ConfDir -ErrorAction SilentlyContinue
} else {
    Write-Log "Keeping $ConfDir - re-run with -Purge to delete it"
}

Write-Log 'Done.'
