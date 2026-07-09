#Requires -Version 5.1
<#
.SYNOPSIS
    Print how to SSH into this machine (OpenSSH server connection details).
.DESCRIPTION
    Standalone and reusable: run it any time to re-print the details.
    install.ps1 calls it at the end of a successful install.
    Does NOT require administrator. Runs on Windows PowerShell 5.1 and PS7+.
.EXAMPLE
    .\connection-info.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# Actual port the running sshd is listening on (falls back to 22).
function Get-SshPort {
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -eq 'Running') {
        $procIds = (Get-Process -Name sshd -ErrorAction SilentlyContinue).Id
        if ($procIds) {
            $ports = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                Where-Object { $_.OwningProcess -in $procIds } |
                Select-Object -ExpandProperty LocalPort -Unique
            if ($ports) { return ($ports | Sort-Object | Select-Object -First 1) }
        }
    }
    return 22
}

# Label an IPv4 address: Tailscale (100.64.0.0/10 CGNAT), LAN (RFC1918), or the adapter name.
function Get-IpTag {
    param([string]$Ip, [string]$Alias)
    if ($Alias -match 'Tailscale') { return 'Tailscale - reachable from anywhere on your tailnet' }
    $o = $Ip.Split('.')
    if ($o[0] -eq '100' -and [int]$o[1] -ge 64 -and [int]$o[1] -le 127) {
        return 'Tailscale - reachable from anywhere on your tailnet'
    }
    if ($Ip -like '192.168.*' -or $Ip -like '10.*' -or
        ($o[0] -eq '172' -and [int]$o[1] -ge 16 -and [int]$o[1] -le 31)) {
        return "LAN: $Alias"
    }
    return $Alias
}

$user     = $env:USERNAME
$computer = $env:COMPUTERNAME
$port     = Get-SshPort
$svc      = Get-Service -Name sshd -ErrorAction SilentlyContinue
$status   = if ($svc) { "$($svc.Status), startup $($svc.StartType)" } else { 'not installed' }

$addrs = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and
        $_.IPAddress -notlike '169.254.*' -and
        $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL|Hyper-V|Default Switch'
    } |
    Sort-Object InterfaceAlias

$prefix   = if ($port -eq 22) { '' } else { "-p $port " }
$localCmd = "ssh ${prefix}$user@localhost"

Write-Host ""
Write-Host "==================== SSH into this PC ===================="
Write-Host ("  User:     {0}" -f $user)
Write-Host ("  Hostname: {0}" -f $computer)
Write-Host ("  sshd:     {0} (listening on port {1})" -f $status, $port)
Write-Host ""
Write-Host "  From another machine:"
foreach ($a in $addrs) {
    $tag = Get-IpTag -Ip $a.IPAddress -Alias $a.InterfaceAlias
    Write-Host ("    ssh {0}{1}@{2}   # {3}" -f $prefix, $user, $a.IPAddress, $tag)
}
Write-Host ""
Write-Host "  Local test (on this PC):  $localCmd"
Write-Host "  Auth: your Windows password for '$user' (a Windows Hello PIN will NOT work over SSH)."
Write-Host "========================================================="
Write-Host ""
