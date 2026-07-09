#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Bootstrap: <PROJECT_NAME> (Windows)
.DESCRIPTION
    Must be idempotent: safe to run again on a machine that's already set up.
    Runs on both Windows PowerShell 5.1 and PowerShell 7+ (pwsh).
.EXAMPLE
    git clone <repo-url> C:\ftutil_repos
    cd C:\ftutil_repos\<project>\windows
    .\install.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Import-Module "$PSScriptRoot\..\..\lib\windows\Common.psm1" -Force

Assert-IsAdmin
Write-Log "Starting bootstrap for <PROJECT_NAME>"

# TODO: replace <BINARY> with the command this installs, then remove this check
# if (Test-CommandExists '<BINARY>') {
#     Write-Log "<PROJECT_NAME> already installed, skipping"
#     return
# }

# TODO: install steps here, e.g.:
# winget install --id <PackageId> -e --silent

Write-Log "Done."
