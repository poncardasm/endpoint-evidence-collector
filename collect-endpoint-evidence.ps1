[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CaseId,

    [Parameter(Mandatory = $false)]
    [string]$TicketId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = ".\\out",

    [Parameter(Mandatory = $false)]
    [ValidateSet("standard", "strict")]
    [string]$RedactionLevel = "standard",

    [Parameter(Mandatory = $false)]
    [string[]]$Include,

    [Parameter(Mandatory = $false)]
    [string[]]$Exclude,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 168)]
    [int]$EventLogLookbackHours = 24,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$CriticalFailureThreshold = 1
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Shared helper import pattern (temporary until full module wiring).
$modulePath = Join-Path $PSScriptRoot "src/EndpointEvidenceCollector/EndpointEvidenceCollector.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -ErrorAction Stop
}

if (-not (Get-Command -Name Get-EecCollectorCatalog -ErrorAction SilentlyContinue)) {
    throw "Module import failed. Required commands are unavailable."
}

try {
    $catalog = Get-EecCollectorCatalog
    $plan = Resolve-EecCollectorPlan -Catalog $catalog -Include $Include -Exclude $Exclude
    $resolvedOutputDir = Test-EecOutputPath -Path $OutputDir -CreateIfMissing:(-not $DryRun)
    $runMetadata = New-EecRunMetadata -CaseId $CaseId -TicketId $TicketId -RedactionLevel $RedactionLevel

    Write-Host "endpoint-evidence-collector"
    Write-Host "RunId: $($runMetadata.RunId)"
    Write-Host "Started (UTC): $($runMetadata.StartedAtUtc)"
    Write-Host "CaseId: $CaseId | TicketId: $TicketId | Redaction: $RedactionLevel"
    Write-Host "OutputDir: $resolvedOutputDir"
    Write-Host "EventLogLookbackHours: $EventLogLookbackHours"

    if ($DryRun) {
        Write-Host "Dry run enabled. Planned collectors:"
        foreach ($collector in $plan) {
            $elevation = if ($collector.RequiresElevation) { "requires-elevation" } else { "standard" }
            Write-Host ("- {0} ({1})" -f $collector.Name, $elevation)
        }
    }

    $runResult = Invoke-EecCollectionRun `
        -CollectorPlan $plan `
        -RunMetadata $runMetadata `
        -OutputDir $resolvedOutputDir `
        -CriticalFailureThreshold $CriticalFailureThreshold `
        -EventLogLookbackHours $EventLogLookbackHours `
        -DryRun:$DryRun

    Write-Host ("Completed in {0} ms | Collectors: {1} | Failures: {2} | Critical failures: {3}" -f `
            $runResult.TotalDurationMs, $runResult.TotalCollectors, $runResult.FailureCount, $runResult.CriticalFailureCount)

    if ($runResult.ExitCode -ne 0) {
        Write-Warning ("Run completed with exit code {0}." -f $runResult.ExitCode)
    }

    exit $runResult.ExitCode
}
catch {
    Write-Error $_.Exception.Message
    exit 99
}
