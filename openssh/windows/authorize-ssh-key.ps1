#Requires -Version 5.1
<#
.SYNOPSIS
    Authorize a public key for inbound SSH login on THIS Windows machine.
.DESCRIPTION
    Adds a public key to the correct authorized-keys file and locks its ACL so
    sshd (StrictModes) will accept it. Idempotent: skips a key that's already
    authorized. Runs on Windows PowerShell 5.1 and PS7+.

    Windows OpenSSH quirk this handles for you:
      * Accounts in the Administrators group are authorized via the GLOBAL file
        C:\ProgramData\ssh\administrators_authorized_keys (per sshd_config's
        "Match Group administrators" rule), NOT the user's ~\.ssh\authorized_keys.
        That file must be owned by Administrators/SYSTEM and writable only by
        them, or sshd silently ignores it.
      * Non-admin accounts use %USERPROFILE%\.ssh\authorized_keys.

    Writing the admin file needs an elevated session; a plain user key does not.
.PARAMETER PublicKey
    The public key line, e.g. "ssh-ed25519 AAAA... user@host". First positional.
.PARAMETER PublicKeyPath
    Path to a .pub file to read the key from instead of -PublicKey.
.PARAMETER User
    Account to authorize for (default: current user).
.PARAMETER Scope
    Auto (default, detects admin membership), Admin, or User - force the target file.
.EXAMPLE
    .\authorize-ssh-key.ps1 "ssh-ed25519 AAAAC3Nza... furka@laptop"
.EXAMPLE
    .\authorize-ssh-key.ps1 -PublicKeyPath C:\keys\laptop.pub -Scope User
#>
[CmdletBinding(DefaultParameterSetName = 'Key')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Key')]
    [string]$PublicKey,
    [Parameter(Mandatory, ParameterSetName = 'File')]
    [string]$PublicKeyPath,
    [string]$User = $env:USERNAME,
    [ValidateSet('Auto', 'Admin', 'User')]
    [string]$Scope = 'Auto'
)

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

# --- Resolve and validate the public key text ---
if ($PSCmdlet.ParameterSetName -eq 'File') {
    if (-not (Test-Path $PublicKeyPath)) { Write-Log "Public key file not found: $PublicKeyPath"; exit 1 }
    $PublicKey = (Get-Content -Path $PublicKeyPath -Raw)
}
$PublicKey = $PublicKey.Trim()
$keyPattern = '^(ssh-ed25519|ssh-rsa|ssh-dss|ecdsa-sha2-nistp(256|384|521)|sk-ssh-ed25519@openssh\.com|sk-ecdsa-sha2-nistp256@openssh\.com)\s+AAAA[0-9A-Za-z+/]+=*(\s+\S.*)?$'
if ($PublicKey -notmatch $keyPattern) {
    Write-Log "That does not look like a valid SSH public key line:"
    Write-Log "  $PublicKey"
    Write-Log "Expected something like: ssh-ed25519 AAAAC3Nza... comment"
    exit 1
}

function Resolve-Sid([string]$account) {
    foreach ($nt in @([System.Security.Principal.NTAccount]::new($account),
                      [System.Security.Principal.NTAccount]::new($env:COMPUTERNAME, $account))) {
        try { return $nt.Translate([System.Security.Principal.SecurityIdentifier]) } catch { }
    }
    return $null
}

$userSid = Resolve-Sid $User
if (-not $userSid) { Write-Log "Could not resolve account '$User'."; exit 1 }

# --- Decide which authorized-keys file to use ---
$useAdminFile = $false
switch ($Scope) {
    'Admin' { $useAdminFile = $true }
    'User'  { $useAdminFile = $false }
    'Auto'  {
        $inAdmins = $null
        try {
            $members = Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop
            $inAdmins = [bool]($members | Where-Object { $_.SID.Value -eq $userSid.Value })
        } catch { $inAdmins = $null }

        if ($null -ne $inAdmins) {
            $useAdminFile = $inAdmins
        } else {
            $useAdminFile = (Test-IsAdmin)   # detection failed; fall back to this session's elevation
            Write-Log "Could not confirm group membership for '$User'; assuming admin=$useAdminFile. Override with -Scope User|Admin."
        }
    }
}

if ($useAdminFile) {
    if (-not (Test-IsAdmin)) {
        Write-Log "'$User' is an administrator, so the key goes in the global"
        Write-Log "administrators_authorized_keys file - re-run this in an ELEVATED session."
        exit 1
    }
    $akFile = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'
    Write-Log "Authorizing admin account '$User' via $akFile"
} else {
    if ($User -eq $env:USERNAME) { $profileDir = $env:USERPROFILE }
    else { $profileDir = Join-Path (Split-Path $env:USERPROFILE -Parent) $User }
    $sshDir = Join-Path $profileDir '.ssh'
    $akFile = Join-Path $sshDir 'authorized_keys'
    Write-Log "Authorizing user account '$User' via $akFile"
}

# --- Write the key (idempotent) ---
New-Item -ItemType Directory -Force -Path (Split-Path $akFile -Parent) | Out-Null
$existing = if (Test-Path $akFile) { Get-Content -Path $akFile } else { @() }
if ($existing | Where-Object { $_.Trim() -eq $PublicKey }) {
    Write-Log "Key already authorized - nothing to do."
} else {
    Add-Content -Path $akFile -Value $PublicKey -Encoding ascii
    Write-Log "Key added."
}

# --- Lock down the ACL so sshd (StrictModes) accepts the file ---
# Use icacls: it changes only the DACL/owner (never the SACL), so unlike Set-Acl
# it needs no SeSecurityPrivilege and is safely repeatable. SIDs avoid locale
# issues: S-1-5-18 = SYSTEM, S-1-5-32-544 = Administrators.
$PSNativeCommandUseErrorActionPreference = $false   # handle icacls exit codes ourselves
$grants   = @('*S-1-5-18:(F)', '*S-1-5-32-544:(F)')
$ownerSid = 'S-1-5-32-544'
if (-not $useAdminFile) {
    $grants  += "*$($userSid.Value):(F)"
    $ownerSid = $userSid.Value
}
& icacls $akFile /inheritance:r /grant:r $grants > $null 2>&1
if ($LASTEXITCODE -ne 0) { Write-Log "Warning: could not set the DACL on $akFile (icacls exit $LASTEXITCODE)." }
& icacls $akFile /setowner "*$ownerSid" > $null 2>&1
if ($LASTEXITCODE -ne 0) { Write-Log "Warning: could not set the owner on $akFile (icacls exit $LASTEXITCODE)." }
Write-Log "Permissions locked (owner + SYSTEM/Administrators$(if (-not $useAdminFile) { ' + the user' }))."

Write-Host ""
Write-Log "Done. Test from the client that holds the matching private key:"
Write-Log "  ssh $User@<this-host-ip>"
