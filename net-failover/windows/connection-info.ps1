#Requires -Version 5.1
<#
.SYNOPSIS
    Print the current uplink status managed by net-failover.
.DESCRIPTION
    Standalone and reusable: run it any time. install.ps1 calls it at the end.
    Does NOT require administrator (a few details are richer when elevated).
    Runs on Windows PowerShell 5.1 and PowerShell 7+.
.EXAMPLE
    .\connection-info.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$ConfDir  = Join-Path $env:ProgramData 'net-failover'
$StateDir = Join-Path $ConfDir 'state'

$state = 'unknown'
$raw = Get-Content -LiteralPath (Join-Path $StateDir 'state') -ErrorAction SilentlyContinue | Select-Object -First 1
if ($raw) { $state = $raw }
$metric = '-'
$raw = Get-Content -LiteralPath (Join-Path $StateDir 'eth_metric') -ErrorAction SilentlyContinue | Select-Object -First 1
if ($raw) { $metric = $raw }

# Defaults, refined by the installed config when present (it is plain
# PowerShell and only ever admin-written, so dot-sourcing it is safe).
$ETH_ALIAS = ''; $WIFI_ALIAS = ''
$ETH_METRIC_GOOD = 10; $ETH_METRIC_DEAD = 5000
$cfg = Join-Path $ConfDir 'config.ps1'
if (Test-Path $cfg) { try { . $cfg } catch { } }

$svc = 'not installed'
try {
    $task = Get-ScheduledTask -TaskName 'net-failover' -ErrorAction Stop
    if ($task.State -eq 'Running') {
        $svc = 'running'
        if ($task.Settings.Enabled) { $svc = 'running, starts at boot' }
    } else {
        $svc = "$($task.State)".ToLower()
    }
} catch { }

$eth = $null
$wifi = $null
if ($ETH_ALIAS)  { $eth  = Get-NetAdapter -Name $ETH_ALIAS  -ErrorAction SilentlyContinue }
if ($WIFI_ALIAS) { $wifi = Get-NetAdapter -Name $WIFI_ALIAS -ErrorAction SilentlyContinue }
if (-not $eth) {
    $eth = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceType -eq 6 -and $_.InterfaceDescription -notmatch 'Bluetooth' } |
        Sort-Object ifIndex | Select-Object -First 1
}
if (-not $wifi) {
    $wifi = Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceType -eq 71 } |
        Sort-Object ifIndex | Select-Object -First 1
}
$ethName = 'ethernet'
if ($eth) { $ethName = $eth.Name }
$wifiName = 'wifi'
if ($wifi) { $wifiName = $wifi.Name }

# Human-readable form of the daemon's state file.
switch -Wildcard ($state) {
    'ethernet' { $pretty = "online via ethernet ($ethName)" }
    'wifi:*'   { $pretty = "online via WiFi '$($state.Substring(5))' ($wifiName)" }
    'offline'  { $pretty = 'OFFLINE - no ethernet and no configured WiFi worked' }
    'unknown'  { $pretty = 'unknown (task has not reported yet)' }
    default    { $pretty = $state }
}

Write-Host ''
Write-Host '==================== net-failover status ===================='
Write-Host "  Task:         $svc"
Write-Host "  Current link: $pretty"
Write-Host "  $ethName metric:  $metric   ($ETH_METRIC_GOOD = preferred, $ETH_METRIC_DEAD = demoted, no internet)"
Write-Host ''

Write-Host '  Interfaces:'
foreach ($a in @($eth, $wifi)) {
    if (-not $a) { continue }
    $type = 'wifi'
    if ($a.InterfaceType -eq 6) { $type = 'ethernet' }
    Write-Host ('    {0,-14} {1,-9} {2}' -f $a.Name, $type, "$($a.MediaConnectionState)".ToLower())
}
Write-Host ''

Write-Host '  Default route(s), lowest metric wins:'
foreach ($r in @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore -ErrorAction SilentlyContinue)) {
    $ifm = (Get-NetIPInterface -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric
    Write-Host ('    {0} via {1} (metric {2})' -f $r.InterfaceAlias, $r.NextHop, ($ifm + $r.RouteMetric))
}
Write-Host ''

Write-Host '  WiFi fallback order:'
$nets = Join-Path $ConfDir 'networks.conf'
if (Test-Path $nets) {
    $n = 0
    try {
        foreach ($line in @(Get-Content $nets -Encoding UTF8 -ErrorAction Stop)) {
            if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
            $n++
            Write-Host ('    {0}. {1}' -f $n, $line.Split('|')[0])
        }
        if ($n -eq 0) { Write-Host "    (none configured yet - edit $nets)" }
    } catch {
        Write-Host '    (unreadable - run elevated to see it)'
    }
} else {
    Write-Host '    (not installed yet)'
}
Write-Host ''

Write-Host '  Commands:'
Write-Host '    net-failover -Status     # state, adapters, routes, priority list'
Write-Host '    net-failover -Check      # probe each interface, changes nothing'
Write-Host '    net-failover -Scan       # what is in range (Win11: needs Location services on)'
Write-Host "    Get-Content '$ConfDir\log\net-failover.log' -Tail 20 -Wait"
Write-Host '============================================================='
Write-Host ''
