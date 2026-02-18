[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue)) {
    Write-Error "PSScriptAnalyzer is required for pre-push checks. Install-Module PSScriptAnalyzer -Scope CurrentUser -Force"
    exit 1
}

$lintTargets = @("collect-endpoint-evidence.ps1", "src", "tests/pester")
$lintResults = @()
foreach ($target in $lintTargets) {
    if (Test-Path -LiteralPath $target) {
        $lintResults += @(Invoke-ScriptAnalyzer -Path $target -Recurse -Severity Error,Warning)
    }
}

if ($lintResults.Count -gt 0) {
    $lintResults | Format-Table -AutoSize | Out-String | Write-Host
}

$lintErrors = @($lintResults | Where-Object { $_.Severity -eq "Error" })
if ($lintErrors.Count -gt 0) {
    Write-Error "Pre-push failed: PSScriptAnalyzer reported error severity issues."
    exit 1
}

if (-not (Get-Command Invoke-Pester -ErrorAction SilentlyContinue)) {
    Write-Error "Pester is required for pre-push checks. Install-Module Pester -Scope CurrentUser -Force"
    exit 1
}

$runner = Join-Path $PSScriptRoot "../..//tests/pester/Invoke-Pester.ps1"
& $runner -CI
if ($LASTEXITCODE -ne 0) {
    Write-Error "Pre-push failed: Pester test suite failed."
    exit $LASTEXITCODE
}

Write-Host "Pre-push checks passed."
exit 0
