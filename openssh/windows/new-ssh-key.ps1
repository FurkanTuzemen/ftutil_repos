#Requires -Version 5.1
<#
.SYNOPSIS
    Generate an SSH key pair for the current user (client side).
.DESCRIPTION
    Creates a key under %USERPROFILE%\.ssh (default: id_ed25519) and prints the
    public key. Idempotent: won't overwrite an existing key unless -Force.
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
New-Item -ItemType Directory -Force -Path $sshDir | Out-Null

if ((Test-Path $keyPath) -and -not $Force) {
    Write-Log "Key already exists: $keyPath (use -Force to regenerate). Printing existing public key:"
} else {
    if ((Test-Path $keyPath) -and $Force) { Remove-Item "$keyPath", "$keyPath.pub" -Force -ErrorAction SilentlyContinue }
    $kgArgs = @('-t', $Type, '-f', $keyPath, '-C', $Comment)
    if ($Type -eq 'rsa') { $kgArgs += @('-b', "$Bits") }
    # -N '' (empty passphrase) is reliable under PowerShell 7; on Windows PowerShell 5.1
    # the empty arg can be dropped and ssh-keygen will prompt. Default (no switch) prompts.
    if ($NoPassphrase)   { $kgArgs += @('-N', '') }
    Write-Log "Generating $Type key at $keyPath"
    & $keygen @kgArgs
}

$pub = Get-Content "$keyPath.pub" -Raw
Write-Host ""
Write-Host "==================== Public key ===================="
Write-Host $pub.Trim()
Write-Host "===================================================="
Write-Host "Private key: $keyPath  (never share or commit this)"
Write-Host "Authorize it on a server by running there:"
Write-Host "  Windows:  .\authorize-ssh-key.ps1 `"<paste the public key above>`""
Write-Host "  Linux:    ./authorize-ssh-key.sh `"<paste the public key above>`""
Write-Host ""
