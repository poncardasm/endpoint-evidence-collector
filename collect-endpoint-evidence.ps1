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
    [int]$CriticalFailureThreshold = 1,

    [Parameter(Mandatory = $false)]
    [switch]$EnableSignature,

    [Parameter(Mandatory = $false)]
    [string]$SigningCertThumbprint,

    [Parameter(Mandatory = $false)]
    [switch]$EnableBundleEncryption,

    [Parameter(Mandatory = $false)]
    [Security.SecureString]$BundlePassword,

    [Parameter(Mandatory = $false)]
    [switch]$KeepPlainBundle,

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$RetentionDays = 7,

    [Parameter(Mandatory = $false)]
    [switch]$RetentionCleanupOnly
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
    Test-EecSafeIdentifier -Name "CaseId" -Value $CaseId
    Test-EecSafeIdentifier -Name "TicketId" -Value $TicketId

    if ($EnableSignature) {
        if ([string]::IsNullOrWhiteSpace($SigningCertThumbprint)) {
            throw "SigningCertThumbprint is required when -EnableSignature is used."
        }
        if (($SigningCertThumbprint -replace "\s", "") -notmatch "^[A-Fa-f0-9]{40}$") {
            throw "SigningCertThumbprint must be a valid SHA-1 certificate thumbprint (40 hex characters)."
        }
    }

    if ($EnableBundleEncryption -and $null -eq $BundlePassword) {
        throw "BundlePassword is required when -EnableBundleEncryption is used."
    }

    $catalog = Get-EecCollectorCatalog
    $plan = Resolve-EecCollectorPlan -Catalog $catalog -Include $Include -Exclude $Exclude
    $resolvedBaseOutputDir = Test-EecOutputPath -Path $OutputDir -CreateIfMissing:(-not $DryRun)
    $runMetadata = New-EecRunMetadata -CaseId $CaseId -TicketId $TicketId -RedactionLevel $RedactionLevel
    $runOutputDir = $resolvedBaseOutputDir

    if ($RetentionCleanupOnly) {
        $cleanupOnly = Invoke-EecRetentionCleanup -BaseOutputDir $resolvedBaseOutputDir -RetentionDays $RetentionDays
        Write-Host ("Retention cleanup completed. Removed directories: {0}" -f $cleanupOnly.removed_count)
        exit 0
    }

    if (-not $DryRun) {
        $runOutputDir = New-EecRunOutputDirectory -BaseOutputDir $resolvedBaseOutputDir -RunMetadata $runMetadata
    }

    Write-Host "endpoint-evidence-collector"
    Write-Host "RunId: $($runMetadata.RunId)"
    Write-Host "Started (UTC): $($runMetadata.StartedAtUtc)"
    Write-Host "CaseId: $CaseId | TicketId: $TicketId | Redaction: $RedactionLevel"
    Write-Host "OutputDir: $runOutputDir"
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
        -OutputDir $runOutputDir `
        -CriticalFailureThreshold $CriticalFailureThreshold `
        -EventLogLookbackHours $EventLogLookbackHours `
        -EnableSignature:$EnableSignature `
        -SigningCertThumbprint $SigningCertThumbprint `
        -EnableBundleEncryption:$EnableBundleEncryption `
        -BundlePassword $BundlePassword `
        -KeepPlainBundle:$KeepPlainBundle `
        -DryRun:$DryRun

    Write-Host ("Completed in {0} ms | Collectors: {1} | Failures: {2} | Critical failures: {3}" -f `
            $runResult.TotalDurationMs, $runResult.TotalCollectors, $runResult.FailureCount, $runResult.CriticalFailureCount)

    if (-not $DryRun -and $runResult.ArtifactPaths) {
        Write-Host "Summary: $($runResult.ArtifactPaths.SummaryPath)"
        Write-Host "Manifest: $($runResult.ArtifactPaths.ManifestPath)"
        Write-Host "Bundle: $($runResult.ArtifactPaths.BundlePath)"
        Write-Host "Checksum: $($runResult.ArtifactPaths.ChecksumPath)"
        if ($runResult.ArtifactPaths.SignaturePath) {
            Write-Host "Signature: $($runResult.ArtifactPaths.SignaturePath)"
        }
    }

    if ($runResult.ExitCode -ne 0) {
        Write-Warning ("Run completed with exit code {0}." -f $runResult.ExitCode)
    }

    if (-not $DryRun) {
        $cleanupResult = Invoke-EecRetentionCleanup -BaseOutputDir $resolvedBaseOutputDir -RetentionDays $RetentionDays
        Write-Host ("Retention cleanup removed {0} old output director{1} (>{2} days)." -f `
                $cleanupResult.removed_count, $(if ($cleanupResult.removed_count -eq 1) { "y" } else { "ies" }), $RetentionDays)
    }

    exit $runResult.ExitCode
}
catch {
    Write-Error $_.Exception.Message
    exit 99
}
