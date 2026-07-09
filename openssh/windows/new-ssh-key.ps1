#Requires -Version 5.1
<#
.SYNOPSIS
    Generate (or reuse) an SSH key pair for the current user (client side).
.DESCRIPTION
    Ensures a key under %USERPROFILE%\.ssh (default: id_ed25519):
      * If a private key already exists, it is NOT regenerated (use -Force to replace).
      * If the private key exists but its .pub is missing, the public key is
        re-derived from the private key and saved as <key>.pub.
      * Otherwise a fresh key pair is generated.
    Prints the public key, then this machine's user@address for LAN and Tailscale.
    Does NOT require administrator. Runs on Windows PowerShell 5.1 and PS7+.

    This is the CLIENT side (the machine you connect *from*). To let this key log
    IN to a server, copy the printed public key and run authorize-ssh-key.ps1
    (Windows) or authorize-ssh-key.sh (Linux) on that server.
.EXAMPLE
    .\new-ssh-key.ps1
.EXAMPLE
    .\new-ssh-key.ps1 -Type ed25519 -NoPassphrase -Comment "furka@laptop"
#>
[CmdletBinding()]
param(
    [ValidateSet('ed25519', 'rsa', 'ecdsa')]
    [string]$Type = 'ed25519',
    [string]$Comment = "$env:USERNAME@$env:COMPUTERNAME",
    [int]$Bits = 4096,          # rsa only
    [switch]$NoPassphrase,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

# Locate ssh-keygen (on PATH, or the winget/MSI + capability install dirs).
$keygen = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source
if (-not $keygen) {
    foreach ($c in (Join-Path $env:ProgramFiles 'OpenSSH\ssh-keygen.exe'),
                   (Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe')) {
        if (Test-Path $c) { $keygen = $c; break }
    }
}
if (-not $keygen) {
    Write-Log "ssh-keygen not found. Run install.ps1 first (installs the OpenSSH client)."
    exit 1
}

$sshDir  = Join-Path $env:USERPROFILE '.ssh'
$keyPath = Join-Path $sshDir "id_$Type"
$pubPath = "$keyPath.pub"
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

if ($Force -and (Test-Path $keyPath)) {
    Write-Log "Force: removing existing key at $keyPath"
    Remove-Item $keyPath, $pubPath -Force -ErrorAction SilentlyContinue
}

if (Test-Path $keyPath) {
    # Private key present: never regenerate it.
    Write-Log "Private key already exists: $keyPath (use -Force to regenerate)."
    if (Test-Path $pubPath) {
        Write-Log "Public key present: $pubPath"
    } else {
        # Re-derive the public key from the private key. ssh-keygen -y prints it;
        # a passphrase-protected key will prompt to unlock. The -y output has no
        # comment, so append one for identification.
        Write-Log "Public key missing; re-deriving it from the private key."
        # Capture the full output first (do NOT pipe the native command straight into
        # Select-Object -First 1: that stops the pipeline early and can kill ssh-keygen
        # and corrupt its exit code). Then take the first non-empty line in memory.
        $derivedAll = & $keygen -y -f $keyPath
        $rc = $LASTEXITCODE
        $derived = @($derivedAll) | Where-Object { $_ -match '\S' } | Select-Object -First 1
        if ($rc -ne 0 -or [string]::IsNullOrWhiteSpace($derived)) {
            Write-Log "Could not derive the public key from $keyPath."
            exit 1
        }
        # Modern OpenSSH keys embed the comment, so -y may already include it
        # (<type> <base64> <comment>). Only append our comment if there isn't one.
        $derived = $derived.Trim()
        $pubLine = if (($derived -split '\s+').Count -ge 3) { $derived } else { "$derived $Comment" }
        $pubLine | Set-Content -Path $pubPath -Encoding ascii
        Write-Log "Saved $pubPath"
    }
} else {
    # No private key: generate a fresh pair.
    $kgArgs = @('-t', $Type, '-f', $keyPath, '-C', $Comment)
    if ($Type -eq 'rsa') { $kgArgs += @('-b', "$Bits") }
    # -N '' (empty passphrase) is reliable under PowerShell 7; on Windows PowerShell 5.1
    # the empty arg can be dropped and ssh-keygen will prompt. Default (no switch) prompts.
    if ($NoPassphrase)   { $kgArgs += @('-N', '') }
    Write-Log "Generating $Type key at $keyPath"
    & $keygen @kgArgs
}

# --- This machine's reachable IPv4 endpoints, labeled LAN vs Tailscale ---
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
$endpoints = Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object {
        $_.IPAddress -ne '127.0.0.1' -and
        $_.IPAddress -notlike '169.254.*' -and
        $_.InterfaceAlias -notmatch 'Loopback|vEthernet|WSL|Hyper-V|Default Switch'
    } | Sort-Object InterfaceAlias

$pub = (Get-Content $pubPath -Raw).Trim()
Write-Host ""
Write-Host "==================== Public key ===================="
Write-Host $pub
Write-Host "===================================================="
Write-Host "Private key: $keyPath  (never share or commit this)"
Write-Host ""
Write-Host "This machine ($($env:USERNAME)@$($env:COMPUTERNAME)) - address for SSH in:"
foreach ($e in $endpoints) {
    Write-Host ("    {0}@{1}   # {2}" -f $env:USERNAME, $e.IPAddress, (Get-IpTag -Ip $e.IPAddress -Alias $e.InterfaceAlias))
}
Write-Host ""
Write-Host "Authorize the public key on a server by running there:"
Write-Host "  Windows:  .\authorize-ssh-key.ps1 `"<paste the public key above>`""
Write-Host "  Linux:    ./authorize-ssh-key.sh `"<paste the public key above>`""
Write-Host ""
