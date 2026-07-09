#Requires -Version 5.1
<#
.SYNOPSIS
    Print the SSH keys currently authorized on THIS Windows server (read-only).
.DESCRIPTION
    Lists the authorized_keys file sshd uses for an account:
      * admin account   -> C:\ProgramData\ssh\administrators_authorized_keys (needs elevation to READ)
      * standard account -> %USERPROFILE%\.ssh\authorized_keys
    Shows index, key type, SHA256 fingerprint, and comment. Read-only - changes
    nothing. Runs on Windows PowerShell 5.1 and PS7+.
.PARAMETER User
    Account whose authorized_keys to read (default: current user).
.PARAMETER Scope
    Auto (detect admin) | Admin | User - force which file to read.
.EXAMPLE
    .\list-authorized-keys.ps1
.EXAMPLE
    .\list-authorized-keys.ps1 -User bob -Scope User
#>
[CmdletBinding()]
param(
    [string]$User = $env:USERNAME,
    [ValidateSet('Auto', 'Admin', 'User')]
    [string]$Scope = 'Auto'
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

# --- Resolve which authorized_keys file sshd uses for this account ---
$useAdminFile = $false
switch ($Scope) {
    'Admin' { $useAdminFile = $true }
    'User'  { $useAdminFile = $false }
    'Auto'  {
        try {
            $sid = ([System.Security.Principal.NTAccount]::new($User)).Translate([System.Security.Principal.SecurityIdentifier])
            $members = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop
            $useAdminFile = [bool]($members | Where-Object { $_.SID.Value -eq $sid.Value })
        } catch {
            $useAdminFile = (Test-IsAdmin)
        }
    }
}

if ($useAdminFile) {
    $akFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    if (-not (Test-IsAdmin)) {
        Write-Log "'$User' uses the global admin keys file ($akFile);"
        Write-Log "reading it needs an ELEVATED session. Re-run as Administrator."
        exit 1
    }
} else {
    if ($User -eq $env:USERNAME) { $profileDir = $env:USERPROFILE }
    else { $profileDir = Join-Path (Split-Path $env:USERPROFILE -Parent) $User }
    $akFile = Join-Path $profileDir '.ssh\authorized_keys'
}

Write-Host ""
Write-Host "Authorized keys for '$User'"
Write-Host "  file: $akFile"

if (-not (Test-Path $akFile)) {
    Write-Host "  (file does not exist - no keys authorized)"
    Write-Host ""
    return
}

$keys = foreach ($line in (Get-Content -Path $akFile)) {
    $t = $line.Trim()
    if ($t -and -not $t.StartsWith('#')) { $t }
}
$keys = @($keys)

if (-not $keys) {
    Write-Host "  (empty - no keys authorized)"
    Write-Host ""
    return
}

function Get-Fingerprint([string]$keyLine) {
    $kg = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source
    if (-not $kg) { return '(ssh-keygen not found)' }
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmp -Value $keyLine -Encoding ascii
        $out = & $kg -l -f $tmp 2>$null
        if ($out) { return ($out -split '\s+')[1] }
    } catch { } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    return '(unreadable)'
}

Write-Host ""
for ($i = 0; $i -lt $keys.Count; $i++) {
    $k = $keys[$i]
    $parts = $k -split '\s+', 3
    $type = $parts[0]
    $cmt = if ($parts.Count -ge 3 -and $parts[2].Trim()) { $parts[2] } else { '(no comment)' }
    Write-Host ("  [{0}] {1,-19} {2}  {3}" -f ($i + 1), $type, (Get-Fingerprint $k), $cmt)
}
Write-Host ""
Write-Host ("  {0} key(s) authorized." -f $keys.Count)
Write-Host ""
