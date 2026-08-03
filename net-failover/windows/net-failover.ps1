#Requires -Version 5.1
<#
.SYNOPSIS
    net-failover -- keep this machine on the internet (Windows).
.DESCRIPTION
    Policy:
      1. Ethernet is always preferred, as long as it actually reaches the internet.
      2. If it does not, walk a priority-ordered list of WiFi networks and settle
         on the first one that does.
      3. As soon as ethernet recovers, go back to it and park the WiFi radio.

    Reachability is verified per interface by binding probes to the interface's
    IPv4 address (Windows' default strong-host model then forces egress out
    that NIC), so a link with carrier and a DHCP lease but a dead uplink is
    correctly treated as offline.

    install.ps1 copies this script to C:\Program Files\net-failover and runs it
    as the SYSTEM scheduled task 'net-failover' from boot. Runs on Windows
    PowerShell 5.1 and PowerShell 7+.
.EXAMPLE
    net-failover -Status      # state, adapters, routes, priority list (no admin)
.EXAMPLE
    net-failover -Check       # probe each interface, changes nothing (no admin)
.EXAMPLE
    net-failover -Once        # run a single decision tick, verbosely (elevated)
#>
[CmdletBinding(DefaultParameterSetName = 'Usage')]
param(
    [Parameter(ParameterSetName = 'Daemon')][switch]$Daemon,
    [Parameter(ParameterSetName = 'Once')][switch]$Once,
    [Parameter(ParameterSetName = 'Check')][switch]$Check,
    [Parameter(ParameterSetName = 'Scan')][switch]$Scan,
    [Parameter(ParameterSetName = 'Status')][switch]$Status
)

$ErrorActionPreference = 'Stop'

# Paths are overridable purely so a test harness can redirect them; in normal
# operation the defaults are what the scheduled task runs with.
$ConfDir      = Join-Path $env:ProgramData 'net-failover'
$ConfigPath   = $env:NET_FAILOVER_CONFIG
if (-not $ConfigPath)   { $ConfigPath   = Join-Path $ConfDir 'config.ps1' }
$NetworksPath = $env:NET_FAILOVER_NETWORKS
if (-not $NetworksPath) { $NetworksPath = Join-Path $ConfDir 'networks.conf' }
$StateDir     = $env:NET_FAILOVER_STATE_DIR
if (-not $StateDir)     { $StateDir     = Join-Path $ConfDir 'state' }
$LogFile      = $env:NET_FAILOVER_LOG
if (-not $LogFile)      { $LogFile      = Join-Path $ConfDir 'log\net-failover.log' }

# ---------------------------------------------------------------- defaults ---
# Every value here can be overridden in $ConfigPath (config.ps1).
$ETH_ALIAS  = ''                # empty = auto-detect the physical ethernet adapter
$WIFI_ALIAS = ''                # empty = auto-detect the physical WiFi adapter
$CHECK_INTERVAL_HEALTHY  = 60   # seconds between checks while online
$CHECK_INTERVAL_DEGRADED = 10   # seconds between checks while hunting for a link
$FAIL_THRESHOLD = 2             # consecutive failures before acting (rides out blips)
$PROBE_TIMEOUT  = 5
$PROBE_URLS   = @(
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://cp.cloudflare.com/generate_204',
    'http://www.gstatic.com/generate_204'
)
$PING_TARGETS = @('1.1.1.1', '8.8.8.8')
$DISCONNECT_WIFI_ON_ETH = $true
$ETH_METRIC_GOOD = 10           # ethernet wins the default route
$ETH_METRIC_DEAD = 5000         # ...unless it is dead, then WiFi (50) wins
$WIFI_METRIC     = 50
$WIFI_CONNECT_TIMEOUT = 30
$SSID_COOLDOWN = 300            # seconds to skip an SSID after it fails to deliver
$WIFI_PROFILE_PREFIX = 'nf-'    # prefix for WLAN profiles this daemon creates
$VERBOSE_LOG = $false

if (Test-Path -LiteralPath $ConfigPath) { . $ConfigPath }

$script:STATE = 'init'
$script:NEXT_INTERVAL = $CHECK_INTERVAL_DEGRADED
$script:eth_fails = 0
$script:wifi_fails = 0

# System32 curl.exe ships with Windows 10 1803+. It must be resolved to the
# .exe explicitly: bare 'curl' is an Invoke-WebRequest alias on PowerShell 5.1.
$CurlExe = Join-Path $env:SystemRoot 'System32\curl.exe'
if (-not (Test-Path -LiteralPath $CurlExe)) {
    $curlCmd = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($curlCmd) { $CurlExe = $curlCmd.Source } else { $CurlExe = $null }
}

# ----------------------------------------------------------------- logging ---
# To the log file always (best effort: non-admin modes cannot write it), and to
# the console, which the scheduled task discards but interactive runs display.
function Write-NfLog {
    param([string]$Level, [string]$Message)
    $line = '{0} [{1,-5}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    try {
        $f = Get-Item -LiteralPath $LogFile -ErrorAction SilentlyContinue
        if ($f -and $f.Length -gt 5MB) { Move-Item -LiteralPath $LogFile -Destination "$LogFile.1" -Force }
        Add-Content -LiteralPath $LogFile -Value $line -Encoding UTF8
    } catch { }
    Write-Host $line
}
function Log  { param([string]$m) Write-NfLog 'INFO'  $m }
function Warn { param([string]$m) Write-NfLog 'WARN'  $m }
function Err  { param([string]$m) Write-NfLog 'ERROR' $m }
function Dbg  { param([string]$m) if ($VERBOSE_LOG) { Write-NfLog 'DEBUG' $m } }

# ------------------------------------------------------------------- state ---
function Set-NfState {
    param([string]$New)
    if ($New -eq $script:STATE) { return }
    $script:STATE = $New
    try { Set-Content -LiteralPath (Join-Path $StateDir 'state') -Value $New -Encoding UTF8 } catch { }
    Log "state -> $New"
}

function Get-UnixNow { return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Get-SsidKey {
    param([string]$Ssid)
    $md5 = [System.Security.Cryptography.MD5]::Create()
    try { $hash = $md5.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Ssid)) }
    finally { $md5.Dispose() }
    return (($hash | ForEach-Object { $_.ToString('x2') }) -join '')
}

function Test-CooldownActive {
    param([string]$Ssid)
    $f = Join-Path $StateDir ('cooldown\' + (Get-SsidKey $Ssid))
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    $until = 0L
    $raw = Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not [long]::TryParse("$raw", [ref]$until)) { return $false }
    return ((Get-UnixNow) -lt $until)
}

function Set-Cooldown {
    param([string]$Ssid)
    try {
        $d = Join-Path $StateDir 'cooldown'
        New-Item -ItemType Directory -Path $d -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $d (Get-SsidKey $Ssid)) `
            -Value ((Get-UnixNow) + $SSID_COOLDOWN) -Encoding UTF8
    } catch { }
}

# -------------------------------------------------------------- interfaces ---
# InterfaceType 6 = 802.3 ethernet, 71 = IEEE 802.11. -Physical excludes
# Hyper-V/WSL vEthernet switches; Bluetooth PAN also reports type 6, hence the
# description filter.
function Get-EthAdapter {
    if ($ETH_ALIAS) { return Get-NetAdapter -Name $ETH_ALIAS -ErrorAction SilentlyContinue }
    $cands = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceType -eq 6 -and $_.InterfaceDescription -notmatch 'Bluetooth' } |
        Sort-Object ifIndex)
    $up = @($cands | Where-Object { $_.MediaConnectionState -eq 'Connected' })
    if ($up.Count -gt 0) { return $up[0] }
    if ($cands.Count -gt 0) { return $cands[0] }
    return $null
}

function Get-WifiAdapter {
    if ($WIFI_ALIAS) { return Get-NetAdapter -Name $WIFI_ALIAS -ErrorAction SilentlyContinue }
    $cands = @(Get-NetAdapter -Physical -ErrorAction SilentlyContinue |
        Where-Object { $_.InterfaceType -eq 71 } | Sort-Object ifIndex)
    if ($cands.Count -gt 0) { return $cands[0] }
    return $null
}

function Test-Carrier {
    param($Adapter)
    return [bool]($Adapter -and $Adapter.MediaConnectionState -eq 'Connected')
}

function Get-IfIpv4 {
    param($Adapter)
    if (-not $Adapter) { return $null }
    $a = @(Get-NetIPAddress -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -and $_.IPAddress -notlike '169.254.*' -and $_.IPAddress -ne '127.0.0.1' })
    if ($a.Count -gt 0) { return $a[0].IPAddress }
    return $null
}

# ------------------------------------------------------------------ probes ---
# True if $Adapter has genuine internet access. HTTP 204 is authoritative (it
# also unmasks captive portals); ICMP is only consulted when no probe URL was
# reachable at all.
function Test-IfaceInternet {
    param($Adapter)
    $ip = Get-IfIpv4 $Adapter
    if (-not $ip) { Dbg "probe $($Adapter.Name): no IPv4 address"; return $false }

    if ($CurlExe) {
        $portal = $false
        foreach ($url in $PROBE_URLS) {
            # -s keeps stderr quiet; on any failure -w still prints 000.
            $code = & $CurlExe -s -o NUL -w '%{http_code}' --interface $ip `
                --max-time $PROBE_TIMEOUT -H 'Cache-Control: no-cache' $url
            if ($code -eq '204') { Dbg "probe $($Adapter.Name): 204 from $url"; return $true }
            if (-not $code -or $code -eq '000') {
                Dbg "probe $($Adapter.Name): no response from $url"
            } else {
                Dbg "probe $($Adapter.Name): HTTP $code from $url (captive portal?)"
                $portal = $true
            }
        }
        if ($portal) {
            Warn "$($Adapter.Name): probes intercepted (captive portal / walled garden)"
            return $false
        }
    }

    # No HTTP probe got a response -- the uplink may just be filtering port 80.
    # ping.exe exits 0 even for 'Destination host unreachable' replies, so a
    # reply only proves life when it carries a TTL.
    foreach ($t in $PING_TARGETS) {
        $out = & (Join-Path $env:SystemRoot 'System32\ping.exe') -4 -n 1 -w ($PROBE_TIMEOUT * 1000) -S $ip $t
        if ($LASTEXITCODE -eq 0 -and ($out -match 'TTL=')) {
            Dbg "probe $($Adapter.Name): ICMP fallback reached $t"
            return $true
        }
    }
    return $false
}

# ------------------------------------------------------------ route metric ---
# Ethernet keeps its IP (so LAN/RDP/SSH stays reachable) but its default route
# is demoted below WiFi's by raising the INTERFACE metric (Windows' effective
# route metric = interface metric + route metric).
function Set-EthMetric {
    param($Adapter, [int]$Metric)
    if (-not $Adapter) { return }
    $f = Join-Path $StateDir 'eth_metric'
    $cur = ''
    if (Test-Path -LiteralPath $f) {
        $cur = Get-Content -LiteralPath $f -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if ("$cur" -eq "$Metric") { return }
    try {
        Set-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -InterfaceMetric $Metric
        Set-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv6 -InterfaceMetric $Metric -ErrorAction SilentlyContinue
        Set-Content -LiteralPath $f -Value $Metric -Encoding UTF8
        Log "$($Adapter.Name): interface metric -> $Metric"
    } catch {
        Warn "$($Adapter.Name): could not set interface metric to $Metric ($($_.Exception.Message))"
    }
}

function Set-WifiMetric {
    param($Adapter)
    if (-not $Adapter) { return }
    try {
        $cur = (Get-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric
        if ($cur -ne $WIFI_METRIC) {
            Set-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv4 -InterfaceMetric $WIFI_METRIC
            Set-NetIPInterface -InterfaceIndex $Adapter.ifIndex -AddressFamily IPv6 -InterfaceMetric $WIFI_METRIC -ErrorAction SilentlyContinue
            Log "$($Adapter.Name): interface metric -> $WIFI_METRIC"
        }
    } catch {
        Warn "$($Adapter.Name): could not set interface metric ($($_.Exception.Message))"
    }
}

# -------------------------------------------------------------------- wifi ---
# netsh wlan localises its labels, so parsing sticks to the tokens that survive
# every display language: 'SSID <n> :' in a scan, '    SSID :' in 'show
# interfaces'. Everything stateful comes from Get-NetAdapter/Get-NetIPAddress,
# and SSID -> profile-name mapping reads wlansvc's XML store directly.

function Test-WifiConnected {
    param($Adapter)
    return [bool]((Test-Carrier $Adapter) -and (Get-IfIpv4 $Adapter))
}

function Get-CurrentSsid {
    foreach ($line in @(netsh wlan show interfaces)) {
        if ($line -match '^\s+SSID\s*:\s*(.+?)\s*$') { return $Matches[1] }
    }
    return ''
}

function Get-VisibleSsids {
    $found = foreach ($line in @(netsh wlan show networks)) {
        if ($line -match '^\s*SSID\s+\d+\s*:\s*(.*)$') { $Matches[1].Trim() }
    }
    return @($found | Where-Object { $_ } | Sort-Object -Unique)
}

# Existing WLAN profile for an SSID, if any (so saved passwords keep working).
function Get-SavedProfileForSsid {
    param([string]$Ssid)
    $dir = Join-Path $env:ProgramData 'Microsoft\Wlansvc\Profiles\Interfaces'
    foreach ($f in @(Get-ChildItem -Path $dir -Filter *.xml -Recurse -File -ErrorAction SilentlyContinue)) {
        try {
            $x = [xml](Get-Content -LiteralPath $f.FullName -Raw)
            if ($x.WLANProfile.SSIDConfig.SSID.name -eq $Ssid) { return [string]$x.WLANProfile.name }
        } catch { }
    }
    return $null
}

function New-WifiProfileXml {
    param([string]$Name, [string]$Ssid, [string]$Psk, [bool]$Hidden)
    $xName = [System.Security.SecurityElement]::Escape($Name)
    $xSsid = [System.Security.SecurityElement]::Escape($Ssid)
    $nonBroadcast = 'false'
    if ($Hidden) { $nonBroadcast = 'true' }
    if ($Psk) {
        $xPsk = [System.Security.SecurityElement]::Escape($Psk)
        $security = @"
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$xPsk</keyMaterial>
            </sharedKey>
"@
    } else {
        $security = @"
            <authEncryption>
                <authentication>open</authentication>
                <encryption>none</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
"@
    }
    return @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$xName</name>
    <SSIDConfig>
        <SSID><name>$xSsid</name></SSID>
        <nonBroadcast>$nonBroadcast</nonBroadcast>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>manual</connectionMode>
    <MSM>
        <security>
$security
        </security>
    </MSM>
</WLANProfile>
"@
}

# connectionMode=manual mirrors autoconnect=no on Linux: only this daemon
# decides when the profile is used. Re-adding an existing profile overwrites
# it, which is exactly the 'explicit password is authoritative' sync behaviour.
function Install-WifiProfile {
    param([string]$Name, [string]$Ssid, [string]$Psk, [bool]$Hidden)
    $tmp = Join-Path $env:TEMP ('nf-profile-' + [guid]::NewGuid().ToString('n') + '.xml')
    Set-Content -LiteralPath $tmp -Value (New-WifiProfileXml $Name $Ssid $Psk $Hidden) -Encoding UTF8
    try {
        $out = netsh wlan add profile filename="$tmp" user=all
        if ($LASTEXITCODE -ne 0) {
            Err "could not store WLAN profile '$Name': $($out -join ' ')"
            return $false
        }
        return $true
    } finally {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
    }
}

function Connect-Wifi {
    param($Adapter, [string]$ProfileName)
    $out = netsh wlan connect name="$ProfileName" interface="$($Adapter.Name)"
    if ($LASTEXITCODE -ne 0) { Dbg "netsh wlan connect: $($out -join ' ')"; return $false }
    $deadline = (Get-UnixNow) + $WIFI_CONNECT_TIMEOUT
    while ((Get-UnixNow) -lt $deadline) {
        Start-Sleep -Seconds 2
        $a = Get-NetAdapter -Name $Adapter.Name -ErrorAction SilentlyContinue
        if (Test-WifiConnected $a) { return $true }
    }
    return $false
}

# Try to bring up one SSID and verify it actually reaches the internet.
function Invoke-WifiTry {
    param($Adapter, [string]$Ssid, [string]$Psk, [bool]$Hidden)

    if ($Psk) {
        # An explicit password in networks.conf is authoritative: rewriting the
        # nf- profile syncs it, so correcting a typo there actually takes effect.
        $prof = "$WIFI_PROFILE_PREFIX$Ssid"
        if (-not (Install-WifiProfile -Name $prof -Ssid $Ssid -Psk $Psk -Hidden $Hidden)) { return $false }
    } else {
        # @saved or open network: reuse whatever profile Windows already has.
        $prof = Get-SavedProfileForSsid $Ssid
        if (-not $prof) {
            $prof = "$WIFI_PROFILE_PREFIX$Ssid"
            if (-not (Install-WifiProfile -Name $prof -Ssid $Ssid -Psk '' -Hidden $Hidden)) { return $false }
        }
    }

    Log "trying WiFi '$Ssid' (profile '$prof')"
    if (-not (Connect-Wifi $Adapter $prof)) {
        Warn "'$Ssid': association/DHCP failed"
        Set-Cooldown $Ssid
        return $false
    }

    Set-WifiMetric $Adapter
    $a = Get-NetAdapter -Name $Adapter.Name -ErrorAction SilentlyContinue
    if (Test-IfaceInternet $a) {
        Log "'$Ssid': online"
        return $true
    }

    Warn "'$Ssid': associated but no internet"
    Set-Cooldown $Ssid
    netsh wlan disconnect interface="$($Adapter.Name)" | Out-Null
    return $false
}

function Get-NfNetworkNames {
    $names = @()
    foreach ($line in @(Get-Content -LiteralPath $NetworksPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }
        $n = $line.Split('|')[0]
        if ($n) { $names += $n }
    }
    return $names
}

# Walk networks.conf top to bottom; first working network wins.
function Invoke-WifiList {
    param($Adapter)

    if (-not (Test-Path -LiteralPath $NetworksPath)) {
        Err "$NetworksPath is missing -- no WiFi networks configured"
        return $false
    }
    if (-not $Adapter) {
        Err 'no WiFi adapter present'
        return $false
    }

    # Give the radio a chance: WLAN service up, adapter enabled.
    try { Start-Service -Name wlansvc -ErrorAction SilentlyContinue } catch { }
    if ($Adapter.Status -eq 'Disabled') {
        Log "$($Adapter.Name): enabling adapter"
        try { Enable-NetAdapter -Name $Adapter.Name -Confirm:$false } catch { Warn "could not enable $($Adapter.Name)" }
    }

    $visible = Get-VisibleSsids
    $blind = ($visible.Count -eq 0)
    if ($blind) {
        # Windows cannot be forced to rescan, and Win11 gates scan results
        # behind location permission -- an empty scan is not proof that nothing
        # is in range, so fall back to trying every configured network.
        Warn 'WiFi scan returned nothing -- trying configured networks blind'
    }

    $found = $false
    foreach ($line in @(Get-Content -LiteralPath $NetworksPath -Encoding UTF8 -ErrorAction SilentlyContinue)) {
        if ($line -match '^\s*$' -or $line -match '^\s*#') { continue }

        $parts = $line.Split('|')
        $ssid = $parts[0]
        $psk = ''
        if ($parts.Count -ge 2) { $psk = $parts[1] }
        $flags = ''
        if ($parts.Count -ge 3) { $flags = $parts[2] }
        if ($psk -eq '@saved') { $psk = '' }
        $hidden = [bool]($flags -match 'hidden')
        if (-not $ssid) { continue }

        if (Test-CooldownActive $ssid) {
            Dbg "skipping '$ssid' (cooling down after a recent failure)"
            continue
        }
        if (-not $hidden -and -not $blind -and ($visible -notcontains $ssid)) {
            Dbg "skipping '$ssid' (not in range)"
            continue
        }

        if (Invoke-WifiTry -Adapter $Adapter -Ssid $ssid -Psk $psk -Hidden $hidden) {
            Set-NfState "wifi:$ssid"
            $script:NEXT_INTERVAL = $CHECK_INTERVAL_HEALTHY
            $found = $true
            break
        }
    }

    if (-not $found) {
        # Only spell out the details on the transition, not every 10s.
        if ($script:STATE -ne 'offline') {
            Warn 'no configured WiFi network could get online'
            Warn "  configured: $((Get-NfNetworkNames) -join ' ')"
            Warn "  in range:   $($visible -join ' ')"
        }
        Set-NfState 'offline'
        return $false
    }
    return $true
}

# -------------------------------------------------------------------- tick ---
function Invoke-Tick {
    $script:NEXT_INTERVAL = $CHECK_INTERVAL_DEGRADED
    $eth = Get-EthAdapter
    $wifi = Get-WifiAdapter

    # ---- 1. Ethernet, always preferred ----
    if (Test-Carrier $eth) {
        if ((Get-IfIpv4 $eth) -and (Test-IfaceInternet $eth)) {
            $script:eth_fails = 0
            Set-EthMetric $eth $ETH_METRIC_GOOD
            if ($DISCONNECT_WIFI_ON_ETH -and (Test-WifiConnected $wifi)) {
                Log 'ethernet is healthy -- parking WiFi'
                netsh wlan disconnect interface="$($wifi.Name)" | Out-Null
            }
            Set-NfState 'ethernet'
            $script:NEXT_INTERVAL = $CHECK_INTERVAL_HEALTHY
            return
        }
        $script:eth_fails++
        Warn "$($eth.Name): no internet ($($script:eth_fails)/$FAIL_THRESHOLD)"
        if ($script:eth_fails -lt $FAIL_THRESHOLD) { return }
    } else {
        if ($script:eth_fails -lt $FAIL_THRESHOLD) {
            Warn "$(if ($eth) { $eth.Name } else { 'ethernet' }): no carrier"
        }
        $script:eth_fails = $FAIL_THRESHOLD
    }

    # ---- 2. Ethernet is out: let WiFi own the default route ----
    Set-EthMetric $eth $ETH_METRIC_DEAD

    # ---- 3. Is the WiFi we are already on still good? ----
    if (Test-WifiConnected $wifi) {
        if (Test-IfaceInternet $wifi) {
            $script:wifi_fails = 0
            Set-NfState "wifi:$(Get-CurrentSsid)"
            $script:NEXT_INTERVAL = $CHECK_INTERVAL_HEALTHY
            return
        }
        $script:wifi_fails++
        Warn "$($wifi.Name): no internet ($($script:wifi_fails)/$FAIL_THRESHOLD)"
        if ($script:wifi_fails -lt $FAIL_THRESHOLD) { return }
        $s = Get-CurrentSsid
        if ($s) { Set-Cooldown $s }
        Log "dropping WiFi '$s' and re-scanning"
        netsh wlan disconnect interface="$($wifi.Name)" | Out-Null
    }
    $script:wifi_fails = 0

    # ---- 4. Walk the priority list ----
    Invoke-WifiList $wifi | Out-Null
}

# ------------------------------------------------------------------ status ---
function Show-Status {
    $state = 'not running'
    $raw = Get-Content -LiteralPath (Join-Path $StateDir 'state') -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($raw) { $state = $raw }
    $metric = '-'
    $raw = Get-Content -LiteralPath (Join-Path $StateDir 'eth_metric') -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($raw) { $metric = $raw }
    Write-Host "state:      $state"
    Write-Host "eth metric: $metric"
    Write-Host ''
    Write-Host '--- adapters ---'
    foreach ($a in @((Get-EthAdapter), (Get-WifiAdapter))) {
        if (-not $a) { continue }
        $type = 'wifi'
        if ($a.InterfaceType -eq 6) { $type = 'ethernet' }
        $extra = ''
        if ($type -eq 'wifi' -and (Test-Carrier $a)) { $extra = "  ssid: $(Get-CurrentSsid)" }
        Write-Host ('  {0,-14} {1,-9} {2,-13} ip: {3}{4}' -f $a.Name, $type, $a.MediaConnectionState, (Get-IfIpv4 $a), $extra)
    }
    Write-Host ''
    Write-Host '--- default routes (lowest metric wins) ---'
    foreach ($r in @(Get-NetRoute -DestinationPrefix '0.0.0.0/0' -PolicyStore ActiveStore -ErrorAction SilentlyContinue)) {
        $ifm = (Get-NetIPInterface -InterfaceIndex $r.ifIndex -AddressFamily IPv4 -ErrorAction SilentlyContinue).InterfaceMetric
        Write-Host ('  {0,-14} via {1,-15} metric {2} (interface {3} + route {4})' -f $r.InterfaceAlias, $r.NextHop, ($ifm + $r.RouteMetric), $ifm, $r.RouteMetric)
    }
    Write-Host ''
    Write-Host '--- configured networks (priority order) ---'
    $i = 0
    foreach ($n in @(Get-NfNetworkNames)) {
        $i++
        Write-Host ('  {0}. {1}' -f $i, $n)
    }
    if ($i -eq 0) { Write-Host "  (none, or $NetworksPath is not readable without elevation)" }
}

function Test-NfAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# -------------------------------------------------------------------- main ---
switch ($PSCmdlet.ParameterSetName) {
    'Status' { Show-Status; exit 0 }
    'Scan'   { netsh wlan show networks mode=bssid; exit 0 }
    'Check'  {
        $script:VERBOSE_LOG = $true
        foreach ($a in @((Get-EthAdapter), (Get-WifiAdapter))) {
            if (-not $a) { continue }
            if (Test-IfaceInternet $a) { Write-Host "$($a.Name): ONLINE" } else { Write-Host "$($a.Name): offline" }
        }
        exit 0
    }
    'Once'   {
        if (-not (Test-NfAdmin)) { Write-Host 'net-failover -Once must run elevated.'; exit 1 }
        New-Item -ItemType Directory -Path (Join-Path $StateDir 'cooldown') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $LogFile) -Force | Out-Null
        $script:VERBOSE_LOG = $true
        Invoke-Tick
        Write-Host "state: $($script:STATE)"
        exit 0
    }
    'Daemon' {
        if (-not (Test-NfAdmin)) {
            Write-Host 'net-failover -Daemon must run elevated (normally as the SYSTEM scheduled task).'
            exit 1
        }
        New-Item -ItemType Directory -Path (Join-Path $StateDir 'cooldown') -Force | Out-Null
        New-Item -ItemType Directory -Path (Split-Path -Parent $LogFile) -Force | Out-Null
        if (-not $CurlExe) {
            Warn 'curl.exe not found -- HTTP probes disabled, ICMP only (captive portals will be misjudged as online)'
        }
        $ethShown = 'auto'
        if ($ETH_ALIAS) { $ethShown = $ETH_ALIAS }
        $wifiShown = 'auto'
        if ($WIFI_ALIAS) { $wifiShown = $WIFI_ALIAS }
        Log "net-failover started (eth=$ethShown wifi=$wifiShown interval=$($CHECK_INTERVAL_HEALTHY)s/$($CHECK_INTERVAL_DEGRADED)s)"
        while ($true) {
            try { Invoke-Tick } catch { Err "tick failed: $($_.Exception.Message)" }
            Start-Sleep -Seconds $script:NEXT_INTERVAL
        }
    }
    default {
        Write-Host 'usage: net-failover [-Daemon|-Once|-Check|-Scan|-Status]'
        Write-Host ''
        Write-Host '  -Status   current state, adapters, routes, priority list (no admin needed)'
        Write-Host '  -Check    probe each interface, changes nothing (no admin needed)'
        Write-Host '  -Scan     list WiFi networks in range (Win11: needs Location services on)'
        Write-Host '  -Once     run a single decision tick, verbosely (elevated)'
        Write-Host '  -Daemon   run the failover loop (the scheduled task does this)'
        exit 2
    }
}
