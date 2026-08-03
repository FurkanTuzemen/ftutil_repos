# Running `install.ps1` (Windows)

Host-level installer, meant to be **cloned and run identically on every Windows
machine**. `install.ps1` requires an **elevated** session (it declares
`#Requires -RunAsAdministrator`) and runs on **both Windows PowerShell 5.1 and
PowerShell 7+ (`pwsh`)**.

## PowerShell 7 (pwsh)

1. Open PowerShell 7 **as Administrator**: Start menu → type "PowerShell 7" →
   right-click → **Run as administrator**. (Or from any terminal:
   `Start-Process pwsh -Verb RunAs`.)
2. Run:
   ```powershell
   cd C:\ftutil_repos\net-failover\windows
   .\install.ps1
   ```

Confirm you're actually on PS7: `$PSVersionTable.PSVersion` should show `7.x`.

## If scripts are blocked

If you see "running scripts is disabled on this system", allow scripts for the
**current session only**, then re-run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\install.ps1
```

## One-liner (elevate + bypass + run)

```powershell
Start-Process pwsh -Verb RunAs -ArgumentList '-ExecutionPolicy','Bypass','-File','C:\ftutil_repos\net-failover\windows\install.ps1'
```

## Windows PowerShell 5.1

Same steps — launch "Windows PowerShell" as Administrator instead of pwsh.

The installer prints the current uplink status when it finishes, and tells you
what to do next if no WiFi networks are configured yet.

## Then add your WiFi networks

The install ships a placeholder list with no real credentials, so failover has
nowhere to go until you fill it in. In an elevated shell:

```powershell
net-failover -Scan                                    # what is in range
notepad C:\ProgramData\net-failover\networks.conf     # SSID|PASSPHRASE, best first
Stop-ScheduledTask -TaskName net-failover; Start-ScheduledTask -TaskName net-failover
```

`net-failover` lands on the machine PATH at install time; the shell you
installed from won't see it yet, so open a new terminal or use the full path
(`& 'C:\Program Files\net-failover\net-failover.ps1' -Scan`).

Put the network you most want first. See the ordering advice in
[`networks.conf.example`](networks.conf.example) — WiFi from the same router
that feeds your ethernet port does not survive an ISP outage, so a phone / 4G
hotspot belongs last as an independent uplink.

## Verify

```powershell
net-failover -Status     # state, adapters, routes, priority list (no admin)
net-failover -Check      # probe each interface, changes nothing (no admin)
.\connection-info.ps1    # reprint uplink status, no admin needed
Get-Content C:\ProgramData\net-failover\log\net-failover.log -Tail 20 -Wait
```

Healthy output reports `state: ethernet` and an ethernet interface metric of
`10`.

### Testing real failover

Simulate a dead WAN without unplugging anything — block the wired interface's
probe traffic (outbound HTTP/HTTPS and ICMP), leaving LAN, RDP and SSH intact.
Elevated, with `Ethernet` replaced by your adapter's alias from
`Get-NetAdapter`:

```powershell
New-NetFirewallRule -Name nftest-http -DisplayName 'nf test: block web out on ethernet' `
    -Direction Outbound -Protocol TCP -RemotePort 80,443 -InterfaceAlias Ethernet -Action Block
New-NetFirewallRule -Name nftest-icmp -DisplayName 'nf test: block icmp out on ethernet' `
    -Direction Outbound -Protocol ICMPv4 -InterfaceAlias Ethernet -Action Block

# watch the state and routes flip
while ($true) {
    Clear-Host
    Get-Content C:\ProgramData\net-failover\state\state -ErrorAction SilentlyContinue
    Get-NetRoute -DestinationPrefix 0.0.0.0/0 -PolicyStore ActiveStore |
        Format-Table InterfaceAlias, NextHop, RouteMetric
    Start-Sleep 2
}

Remove-NetFirewallRule -Name nftest-http, nftest-icmp     # restore
```

Expect the state to move to `wifi:<SSID>` and the ethernet interface metric to
rise to `5000`, then return to `ethernet` at metric `10` after the rules are
removed.

**If you are connected over RDP or SSH via the wired interface**, this test is
safe: the rules only block *outbound* web and ICMP on that adapter, and your
inbound session is unaffected. The rules do persist until removed, though —
don't forget the `Remove-NetFirewallRule` line.

## Notes

- Install, uninstall and `-Once` need an **elevated** shell; `-Status`,
  `-Check` and `connection-info.ps1` do not.
- Idempotent: safe to re-run. It upgrades the daemon and task and **never
  overwrites** `C:\ProgramData\net-failover\networks.conf` or `config.ps1`.
- `networks.conf` is readable by Administrators/SYSTEM only (the `0600` of
  Windows) and holds plain-text passphrases. It is never committed to this
  repo.
- The daemon runs as the SYSTEM scheduled task **`net-failover`** from boot;
  its log is `C:\ProgramData\net-failover\log\net-failover.log` (the
  `journalctl -f` equivalent is `Get-Content <log> -Wait`).
- Windows 11 gates WiFi scan *results* behind **Location services** — with
  Location off, even elevated shells (and the SYSTEM daemon) get an empty
  list. Failover still works: an empty scan makes the daemon try your
  configured networks blind. Turn Location on (Settings → Privacy & security →
  Location) if you want `-Scan` output and in-range filtering, which avoids
  pointless connect attempts on out-of-range entries.

## Uninstall

```powershell
cd C:\ftutil_repos\net-failover\windows
.\uninstall.ps1              # keeps C:\ProgramData\net-failover
.\uninstall.ps1 -Purge       # also deletes the config and passphrases
```

Removes the task and daemon, restores automatic interface metrics, and deletes
only the WLAN profiles this daemon created (the `nf-` prefixed ones).
