#Requires -Version 5.1
<#
.SYNOPSIS
    Remove ALL authorized SSH keys on THIS Windows server (revoke everyone).
.DESCRIPTION
    Empties the authorized_keys file sshd uses for an account:
      * admin account   -> C:\ProgramData\ssh\administrators_authorized_keys (needs elevation)
      * standard account -> %USERPROFILE%\.ssh\authorized_keys
    Clears the file in place so its locked ACL is preserved (does not delete it).
    Prompts (ConfirmImpact High) unless -Confirm:$false. PS 5.1 and 7+.

    WARNING: after this, NO key can log in via this file. Keep a password login or
    an open session available so you don't lock yourself out.
.PARAMETER User
    Account whose authorized_keys to clear (default: current user).
.PARAMETER Scope
    Auto (detect admin) | Admin | User - force which file to use.
.EXAMPLE
    .\remove-all-authorized-keys.ps1
.EXAMPLE
    .\remove-all-authorized-keys.ps1 -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
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
    Write-Log "No authorized_keys file at $akFile - nothing to remove."
    return
}

$count = (@(Get-Content $akFile | Where-Object { $_.Trim() -and -not $_.Trim().StartsWith('#') })).Count
if ($count -eq 0) {
    Write-Log "$akFile is already empty - nothing to remove."
    return
}

Write-Log "This will remove ALL $count authorized key(s) from $akFile."
if ($PSCmdlet.ShouldProcess($akFile, "Remove all $count authorized keys")) {
    # Clear-Content empties the existing file, preserving its ACL.
    Clear-Content -Path $akFile
    Write-Log "Cleared. No keys are authorized via this file now."
}
