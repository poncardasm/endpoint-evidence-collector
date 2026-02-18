[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$staged = @(git diff --cached --name-only)
if ($staged.Count -eq 0) {
    exit 0
}

$docsPaths = @($staged | Where-Object { $_ -match '^docs/' })
if ($docsPaths.Count -gt 0) {
    Write-Error "docs/ is local-only and cannot be committed. Unstage: git restore --staged <path>"
    exit 1
}

$psTargets = @($staged | Where-Object { $_ -match '\.(ps1|psm1|psd1)$' })
if ($psTargets.Count -eq 0) {
    exit 0
}

if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
    Write-Error "PSScriptAnalyzer is required for pre-commit checks. Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
    exit 1
}

$results = @()
foreach ($target in $psTargets) {
    if (Test-Path -LiteralPath $target) {
        $results += @(Invoke-ScriptAnalyzer -Path $target -Severity Error,Warning)
    }
}

if ($results.Count -gt 0) {
    $results | Format-Table -AutoSize | Out-String | Write-Host
    Write-Error "Pre-commit failed: PSScriptAnalyzer reported issues."
    exit 1
}

Write-Host "Pre-commit checks passed."
exit 0
