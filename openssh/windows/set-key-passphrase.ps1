#Requires -Version 5.1
<#
.SYNOPSIS
    Set or change the passphrase on an existing SSH private key (client side).
.DESCRIPTION
    Adds a passphrase to a key that has none, or changes an existing one. The KEY
    ITSELF is unchanged - the public key stays identical, so you do NOT need to
    re-authorize it on any server. Does NOT require administrator. PS 5.1 and 7+.

    Interactive by default: ssh-keygen prompts for the current passphrase (leave
    blank if the key has none) and then the new one. For unattended use pass
    -NewPassphrase (and -CurrentPassphrase if the key already has one); note a
    command-line passphrase can show up in process listings / history.
.PARAMETER Type
    Key type (default ed25519) -> ~\.ssh\id_<type>. Ignored if -Path is given.
.PARAMETER Path
    Explicit private key path.
.PARAMETER CurrentPassphrase
    The key's current passphrase (empty if it has none). Skips that prompt.
.PARAMETER NewPassphrase
    The new passphrase to set. Skips the prompt.
.EXAMPLE
    .\set-key-passphrase.ps1
.EXAMPLE
    .\set-key-passphrase.ps1 -Type rsa
#>
[CmdletBinding()]
param(
    [ValidateSet('ed25519', 'rsa', 'ecdsa')]
    [string]$Type = 'ed25519',
    [string]$Path,
    [string]$CurrentPassphrase,
    [string]$NewPassphrase
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

Write-Log "Setting a new passphrase on $keyPath"
if ($PSBoundParameters.ContainsKey('NewPassphrase')) {
    $kgArgs = @('-p', '-f', $keyPath, '-N', $NewPassphrase)
    if ($PSBoundParameters.ContainsKey('CurrentPassphrase')) { $kgArgs += @('-P', $CurrentPassphrase) }
    & $keygen @kgArgs
} else {
    Write-Host "When prompted: enter the CURRENT passphrase (blank if the key has none), then the NEW passphrase twice."
    & $keygen -p -f $keyPath
}
if ($LASTEXITCODE -ne 0) {
    Write-Log "ssh-keygen failed (wrong current passphrase?). The key was NOT changed."
    exit 1
}

Write-Log "Done - the key is now passphrase-protected."
Write-Log "Its public key is unchanged, so no re-authorization on servers is needed."
Write-Log "Tip: cache it once per session with 'ssh-add $keyPath' so you're not prompted every time."
