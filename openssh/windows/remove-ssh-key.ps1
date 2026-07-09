#Requires -Version 5.1
<#
.SYNOPSIS
    Delete an existing SSH key pair (private + public) for the current user.
.DESCRIPTION
    Removes the private key, its .pub, and any matching -cert.pub, and first drops
    the key from the running ssh-agent. Destructive and irreversible - prompts for
    confirmation (ConfirmImpact High) unless you pass -Confirm:$false; -WhatIf
    shows what would be deleted. Does NOT require administrator. Runs on Windows
    PowerShell 5.1 and PS7+.

    WARNING: deleting a private key is permanent. Any server that only trusts this
    key will refuse you until you generate a new key and re-authorize it there.
.PARAMETER Type
    Key type to remove (default ed25519) -> ~\.ssh\id_<type>. Ignored with -Path/-All.
.PARAMETER Path
    Explicit private key path to remove (its .pub and -cert.pub go too).
.PARAMETER All
    Remove all standard ~\.ssh\id_* key pairs.
.EXAMPLE
    .\remove-ssh-key.ps1
.EXAMPLE
    .\remove-ssh-key.ps1 -Type rsa
.EXAMPLE
    .\remove-ssh-key.ps1 -WhatIf
.EXAMPLE
    .\remove-ssh-key.ps1 -All -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High', DefaultParameterSetName = 'Type')]
param(
    [Parameter(ParameterSetName = 'Type')]
    [ValidateSet('ed25519', 'rsa', 'ecdsa')]
    [string]$Type = 'ed25519',
    [Parameter(ParameterSetName = 'Path')]
    [string]$Path,
    [Parameter(ParameterSetName = 'All')]
    [switch]$All
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

$sshDir = Join-Path $env:USERPROFILE '.ssh'

# Build the list of private-key paths to target.
if ($All) {
    $keyPaths = @()
    if (Test-Path $sshDir) {
        $keyPaths = Get-ChildItem -Path $sshDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^id_(ed25519|rsa|ecdsa|dsa)$' } |
            ForEach-Object { $_.FullName }
    }
} elseif ($Path) {
    $keyPaths = @($Path)
} else {
    $keyPaths = @(Join-Path $sshDir "id_$Type")
}

# Gather the files that actually exist (private + public + cert).
$targets = foreach ($kp in $keyPaths) {
    foreach ($f in $kp, "$kp.pub", "$kp-cert.pub") {
        if (Test-Path $f) { $f }
    }
}

if (-not $targets) {
    Write-Log "Nothing to delete (no matching key files found in $sshDir)."
    return
}

Write-Log "These files will be permanently deleted:"
$targets | ForEach-Object { Write-Host "    $_" }

foreach ($kp in $keyPaths) {
    if (-not (Test-Path $kp) -and -not (Test-Path "$kp.pub")) { continue }
    if ($PSCmdlet.ShouldProcess($kp, 'Delete SSH key pair (private + public)')) {
        # Best-effort: drop the identity from the running agent first (needs the .pub).
        if ((Test-CommandExists 'ssh-add') -and (Test-Path "$kp.pub")) {
            & ssh-add -d $kp 2>$null | Out-Null
        }
        foreach ($f in $kp, "$kp.pub", "$kp-cert.pub") {
            if (Test-Path $f) {
                Remove-Item -Path $f -Force
                Write-Log "Deleted $f"
            }
        }
    }
}
Write-Log "Done."
