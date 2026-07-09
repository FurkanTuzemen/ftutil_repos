# Shared helpers for Windows bootstrap scripts. Meant to be imported, not executed.

function Write-Log {
    param([Parameter(Mandatory)][string]$Message)
    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    Write-Host "[$timestamp] $Message"
}

function Test-CommandExists {
    param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command -Name $Name -ErrorAction SilentlyContinue)
}

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-IsAdmin {
    if (-not (Test-IsAdmin)) {
        Write-Log "This script must be run from an elevated (Administrator) PowerShell session."
        exit 1
    }
}

Export-ModuleMember -Function Write-Log, Test-CommandExists, Test-IsAdmin, Assert-IsAdmin
