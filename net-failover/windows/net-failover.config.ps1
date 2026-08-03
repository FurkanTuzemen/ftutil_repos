# net-failover -- tunables. Dot-sourced by the daemon as PowerShell; restart
# the scheduled task after editing (elevated):
#   Stop-ScheduledTask -TaskName net-failover; Start-ScheduledTask -TaskName net-failover
# Installed to C:\ProgramData\net-failover\config.ps1

# --- interfaces ---
# Empty = auto-detect the physical adapters. Set to pin an exact adapter by its
# alias from Get-NetAdapter (e.g. 'Ethernet 2', 'Wi-Fi').
$ETH_ALIAS  = ''
$WIFI_ALIAS = ''

# --- timing (seconds) ---
$CHECK_INTERVAL_HEALTHY  = 60    # while a link is confirmed online
$CHECK_INTERVAL_DEGRADED = 10    # while hunting for a working link
$FAIL_THRESHOLD          = 2     # consecutive failures before failing over
$PROBE_TIMEOUT           = 5
$WIFI_CONNECT_TIMEOUT    = 30
$SSID_COOLDOWN           = 300   # skip an SSID for this long after it fails

# --- reachability probes ---
# HTTP 204 is authoritative and unmasks captive portals; ICMP is only used
# when no probe URL responded at all.
$PROBE_URLS = @(
    'http://connectivitycheck.gstatic.com/generate_204',
    'http://cp.cloudflare.com/generate_204',
    'http://www.gstatic.com/generate_204'
)
$PING_TARGETS = @('1.1.1.1', '8.8.8.8')

# --- behaviour ---
$DISCONNECT_WIFI_ON_ETH = $true  # park the radio once ethernet is confirmed healthy

# --- routing ---
# Ethernet keeps its IP while dead (so LAN/RDP/SSH stays reachable) but its
# default route is demoted below WiFi's via the INTERFACE metric (Windows'
# effective route metric = interface metric + route metric).
$ETH_METRIC_GOOD = 10
$ETH_METRIC_DEAD = 5000
$WIFI_METRIC     = 50

# $VERBOSE_LOG = $true           # log every individual probe result
