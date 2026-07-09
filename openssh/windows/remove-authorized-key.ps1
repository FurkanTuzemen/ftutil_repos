#Requires -Version 5.1
<#
.SYNOPSIS
    List, or remove a single, authorized SSH key on THIS Windows server.
.DESCRIPTION
    Edits the authorized_keys file that sshd actually uses for an account:
      * admin account   -> C:\ProgramData\ssh\administrators_authorized_keys (needs elevation)
      * standard account -> %USERPROFILE%\.ssh\authorized_keys
    Run with NO selector to list the keys (index, fingerprint, comment).
    Pass -Index / -Comment / -Match / -PublicKey to remove one (or more that match).
    Rewrites the file in place so its locked ACL is preserved. Destructive removal
    prompts (ConfirmImpact High) unless -Confirm:$false. PS 5.1 and 7+.
.PARAMETER Index
    1-based index (from the listing) of the key to remove.
.PARAMETER Comment
    Remove key(s) whose comment equals this (e.g. furka@laptop).
.PARAMETER Match
    Remove key line(s) containing this substring.
.PARAMETER PublicKey
    Remove this exact public-key line.
.PARAMETER User
    Account whose authorized_keys to edit (default: current user).
.PARAMETER Scope
    Auto (detect admin) | Admin | User - force which file to use.
.EXAMPLE
    .\remove-authorized-key.ps1                        # list
.EXAMPLE
    .\remove-authorized-key.ps1 -Comment furka@laptop
.EXAMPLE
    .\remove-authorized-key.ps1 -Index 2 -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [int]$Index,
    [string]$Comment,
    [string]$Match,
    [string]$PublicKey,
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
            Write-Log "Could not confirm group membership for '$User'; assuming admin=$useAdminFile. Override with -Scope."
        }
    }
}

if ($useAdminFile) {
    $akFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    if (-not (Test-IsAdmin)) {
        Write-Log "'$User' uses the global admin keys file - re-run in an ELEVATED session."
        exit 1
    }
} else {
    if ($User -eq $env:USERNAME) { $profileDir = $env:USERPROFILE }
    else { $profileDir = Join-Path (Split-Path $env:USERPROFILE -Parent) $User }
    $akFile = Join-Path $profileDir '.ssh\authorized_keys'
}

if (-not (Test-Path $akFile)) {
    Write-Log "No authorized_keys file at $akFile - nothing is authorized."
    return
}

# --- Parse the key lines (skip blanks and comments), keeping a 1-based index ---
$allLines = @(Get-Content -Path $akFile)
$keys = foreach ($line in $allLines) {
    $t = $line.Trim()
    if ($t -and -not $t.StartsWith('#')) { $t }
}
$keys = @($keys)
if (-not $keys) { Write-Log "$akFile has no authorized keys."; return }

function Get-Fingerprint([string]$keyLine) {
    $kg = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source
    if (-not $kg) { return '' }
    $tmp = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $tmp -Value $keyLine -Encoding ascii
        $out = & $kg -l -f $tmp 2>$null
        if ($out) { return ($out -split '\s+')[1] }
    } catch { } finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
    return ''
}

function Get-Comment([string]$keyLine) {
    $p = $keyLine -split '\s+', 3
    if ($p.Count -ge 3 -and $p[2].Trim()) { $p[2] } else { '(no comment)' }
}

# --- No selector => just list ---
$hasSelector = $PSBoundParameters.ContainsKey('Index') -or $Comment -or $Match -or $PublicKey
if (-not $hasSelector) {
    Write-Log "Authorized keys in ${akFile}:"
    for ($i = 0; $i -lt $keys.Count; $i++) {
        $k = $keys[$i]
        Write-Host ("  [{0}] {1}  {2}  {3}" -f ($i + 1), (($k -split '\s+')[0]), (Get-Fingerprint $k), (Get-Comment $k))
    }
    Write-Host ""
    Write-Host "Remove one with:  -Index N   |   -Comment <text>   |   -Match <substr>   |   -PublicKey `"<line>`""
    return
}

# --- Find matching keys (1-based indices) ---
$removeIdx = for ($i = 0; $i -lt $keys.Count; $i++) {
    $k = $keys[$i]; $n = $i + 1
    if ($PSBoundParameters.ContainsKey('Index')) { if ($n -eq $Index) { $n } }
    elseif ($PublicKey) { if ($k -eq $PublicKey.Trim()) { $n } }
    elseif ($Comment)   { if ((Get-Comment $k) -eq $Comment) { $n } }
    elseif ($Match)     { if ($k -like "*$Match*") { $n } }
}
$removeIdx = @($removeIdx)

if (-not $removeIdx) {
    Write-Log "No authorized key matched. Run with no arguments to list them."
    return
}

Write-Log "Will remove:"
$removeIdx | ForEach-Object { Write-Host ("  [{0}] {1}" -f $_, $keys[$_ - 1]) }

if ($PSCmdlet.ShouldProcess($akFile, "Remove $($removeIdx.Count) authorized key(s)")) {
    # Rewrite keeping every original line except the matched key lines (by running index).
    $out = New-Object System.Collections.Generic.List[string]
    $running = 0
    foreach ($line in $allLines) {
        $t = $line.Trim()
        if ($t -and -not $t.StartsWith('#')) {
            $running++
            if ($removeIdx -contains $running) { continue }
        }
        $out.Add($line)
    }
    # Set-Content on the existing file preserves its ACL (no delete/recreate).
    Set-Content -Path $akFile -Value $out -Encoding ascii
    Write-Log "Removed $($removeIdx.Count) key(s); $((@($out | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })).Count) remain."
}
