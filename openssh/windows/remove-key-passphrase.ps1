#Requires -Version 5.1
<#
.SYNOPSIS
    Remove the passphrase from an existing SSH private key (client side).
.DESCRIPTION
    Strips the passphrase so the key loads without prompting. The KEY ITSELF is
    unchanged - the public key stays identical, so you do NOT need to re-authorize
    it on any server. Does NOT require administrator. Runs on PS 5.1 and 7+.

    Interactive by default (prompts for the current passphrase). For unattended
    use pass -CurrentPassphrase, but note a command-line passphrase can show up in
    process listings / history - prefer the prompt. Unattended empty-passphrase
    handling is most reliable under PowerShell 7.

    SECURITY: a passphrase-less key means anyone who copies the private key file
    can use it. Fine on a machine you physically trust; risky on a laptop.
.PARAMETER Type
    Key type (default ed25519) -> ~\.ssh\id_<type>. Ignored if -Path is given.
.PARAMETER Path
    Explicit private key path.
.PARAMETER CurrentPassphrase
    The key's current passphrase (skips the prompt).
.EXAMPLE
    .\remove-key-passphrase.ps1
.EXAMPLE
    .\remove-key-passphrase.ps1 -Type rsa
#>
[CmdletBinding()]
param(
    [ValidateSet('ed25519', 'rsa', 'ecdsa')]
    [string]$Type = 'ed25519',
    [string]$Path,
    [string]$CurrentPassphrase
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

$keygen = (Get-Command ssh-keygen -ErrorAction SilentlyContinue).Source
if (-not $keygen) {
    foreach ($c in (Join-Path $env:ProgramFiles 'OpenSSH\ssh-keygen.exe'),
                   (Join-Path $env:WINDIR 'System32\OpenSSH\ssh-keygen.exe')) {
        if (Test-Path $c) { $keygen = $c; break }
    }
}
if (-not $keygen) { Write-Log "ssh-keygen not found. Run install.ps1 first."; exit 1 }

$keyPath = if ($Path) { $Path } else { Join-Path $env:USERPROFILE ".ssh\id_$Type" }
if (-not (Test-Path $keyPath)) { Write-Log "Private key not found: $keyPath"; exit 1 }

Write-Log "Removing passphrase from $keyPath"
if ($PSBoundParameters.ContainsKey('CurrentPassphrase')) {
    & $keygen -p -f $keyPath -P $CurrentPassphrase -N ''
} else {
    Write-Host "Enter the key's CURRENT passphrase when prompted (the new passphrase will be empty)."
    & $keygen -p -f $keyPath -N ''
}
if ($LASTEXITCODE -ne 0) {
    Write-Log "ssh-keygen failed (wrong current passphrase?). The key was NOT changed."
    exit 1
}

Write-Log "Done - the key now has NO passphrase."
Write-Log "Its public key is unchanged, so no re-authorization on servers is needed."
Write-Log "SECURITY: anyone who copies $keyPath can now use it. Consider 'ssh-add' + a passphrase instead."
