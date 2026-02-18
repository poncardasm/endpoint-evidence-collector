param(
    [string]$Path = $PSScriptRoot
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command Invoke-Pester -ErrorAction SilentlyContinue)) {
    throw "Pester is not installed. Install-Module Pester -Scope CurrentUser -Force"
}

Invoke-Pester -Path $Path -Output Detailed
