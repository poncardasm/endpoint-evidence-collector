[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputRoot = ".\\out",

    [Parameter(Mandatory = $false)]
    [string]$ReportPath = ".\\pilot\\pilot-metrics-report.json"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $OutputRoot)) {
    throw "Output root not found: $OutputRoot"
}

$runDirs = Get-ChildItem -LiteralPath $OutputRoot -Directory -ErrorAction SilentlyContinue
$manifests = @()
$redactionReports = @()

foreach ($dir in $runDirs) {
    $manifestPath = Join-Path $dir.FullName "manifest.json"
    if (Test-Path -LiteralPath $manifestPath) {
        try {
            $manifests += @(Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json)
        }
        catch {
            Write-Warning "Failed to parse manifest: $manifestPath"
        }
    }

    $redactionPath = Join-Path $dir.FullName "redaction-report.json"
    if (Test-Path -LiteralPath $redactionPath) {
        try {
            $redactionReports += @(Get-Content -LiteralPath $redactionPath -Raw | ConvertFrom-Json)
        }
        catch {
            Write-Warning "Failed to parse redaction report: $redactionPath"
        }
    }
}

$durations = @($manifests | ForEach-Object { [double]$_.summary.total_duration_ms })
$durationsSorted = @($durations | Sort-Object)
$medianDuration = 0
if ($durationsSorted.Count -gt 0) {
    $mid = [math]::Floor($durationsSorted.Count / 2)
    if (($durationsSorted.Count % 2) -eq 0) {
        $medianDuration = ($durationsSorted[$mid - 1] + $durationsSorted[$mid]) / 2
    }
    else {
        $medianDuration = $durationsSorted[$mid]
    }
}

$withinFiveMinutes = @($durations | Where-Object { $_ -le 300000 }).Count
$runCount = $manifests.Count
$runtimeTargetPercent = if ($runCount -gt 0) { [math]::Round(($withinFiveMinutes / $runCount) * 100, 2) } else { 0 }

$totalFailureCount = @($manifests | ForEach-Object { [int]$_.summary.failure_count } | Measure-Object -Sum).Sum
$totalCriticalFailureCount = @($manifests | ForEach-Object { [int]$_.summary.critical_failure_count } | Measure-Object -Sum).Sum
$totalRedactionErrorCount = @($redactionReports | ForEach-Object { [int]$_.redaction_error_count } | Measure-Object -Sum).Sum

$report = [pscustomobject]@{
    generated_at_utc = [DateTime]::UtcNow.ToString("o")
    output_root = [System.IO.Path]::GetFullPath($OutputRoot)
    run_count = $runCount
    median_duration_ms = [int][math]::Round($medianDuration, 0)
    median_duration_minutes = [math]::Round($medianDuration / 60000, 2)
    runs_within_5min_percent = $runtimeTargetPercent
    total_failure_count = [int]$totalFailureCount
    total_critical_failure_count = [int]$totalCriticalFailureCount
    total_redaction_error_count = [int]$totalRedactionErrorCount
    notes = @(
        "Use this report to support pilot runtime and stability claims.",
        "Confirm redaction leakage with manual spot checks of sanitized artifacts."
    )
}

$reportDir = Split-Path -Parent $ReportPath
if (-not (Test-Path -LiteralPath $reportDir)) {
    New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $ReportPath -Encoding UTF8
Write-Host "Pilot metrics report written to: $ReportPath"
