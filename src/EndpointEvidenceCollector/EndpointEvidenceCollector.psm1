Set-StrictMode -Version Latest

function Get-EecCollectorCatalog {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{
            Name = "system"
            Critical = $true
            RequiresElevation = $false
            Implemented = $false
            Description = "System and OS details"
        }
        [pscustomobject]@{
            Name = "processes"
            Critical = $true
            RequiresElevation = $false
            Implemented = $false
            Description = "Active process list"
        }
        [pscustomobject]@{
            Name = "disk"
            Critical = $true
            RequiresElevation = $false
            Implemented = $false
            Description = "Disk usage and health basics"
        }
        [pscustomobject]@{
            Name = "network"
            Critical = $true
            RequiresElevation = $false
            Implemented = $false
            Description = "Network diagnostics"
        }
        [pscustomobject]@{
            Name = "apps"
            Critical = $false
            RequiresElevation = $false
            Implemented = $false
            Description = "Installed applications list"
        }
        [pscustomobject]@{
            Name = "eventlogs"
            Critical = $false
            RequiresElevation = $true
            Implemented = $false
            Description = "Recent relevant event logs"
        }
    )
}

function Resolve-EecCollectorPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Catalog,

        [string[]]$Include,
        [string[]]$Exclude
    )

    $availableNames = @($Catalog.Name)
    $includeNormalized = @()
    $excludeNormalized = @()

    if ($Include) {
        $includeNormalized = @($Include | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
        $invalidInclude = @($includeNormalized | Where-Object { $_ -notin $availableNames })
        if ($invalidInclude.Count -gt 0) {
            throw "Invalid include collector(s): $($invalidInclude -join ', '). Allowed values: $($availableNames -join ', ')."
        }
    }

    if ($Exclude) {
        $excludeNormalized = @($Exclude | ForEach-Object { $_.Trim().ToLowerInvariant() } | Sort-Object -Unique)
        $invalidExclude = @($excludeNormalized | Where-Object { $_ -notin $availableNames })
        if ($invalidExclude.Count -gt 0) {
            throw "Invalid exclude collector(s): $($invalidExclude -join ', '). Allowed values: $($availableNames -join ', ')."
        }
    }

    if ($includeNormalized.Count -gt 0 -and $excludeNormalized.Count -gt 0) {
        $conflicts = @($includeNormalized | Where-Object { $_ -in $excludeNormalized })
        if ($conflicts.Count -gt 0) {
            throw "Collector(s) cannot be in both include and exclude: $($conflicts -join ', ')."
        }
    }

    $filtered = @($Catalog)
    if ($includeNormalized.Count -gt 0) {
        $filtered = @($filtered | Where-Object { $_.Name -in $includeNormalized })
    }
    if ($excludeNormalized.Count -gt 0) {
        $filtered = @($filtered | Where-Object { $_.Name -notin $excludeNormalized })
    }

    if ($filtered.Count -eq 0) {
        throw "Collector plan is empty after include/exclude filters."
    }

    $filtered
}

function Test-EecOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [switch]$CreateIfMissing
    )

    $trimmedPath = $Path.Trim()
    if ([string]::IsNullOrWhiteSpace($trimmedPath)) {
        throw "OutputDir cannot be empty."
    }

    if ($trimmedPath -match "[`n`r;&|]") {
        throw "OutputDir contains unsupported characters."
    }

    $pathSegments = $trimmedPath -split "[\\/]"
    if ($pathSegments -contains "..") {
        throw "OutputDir cannot contain path traversal segments ('..')."
    }

    $resolvedPath = [System.IO.Path]::GetFullPath($trimmedPath)
    if ($CreateIfMissing -and -not (Test-Path -LiteralPath $resolvedPath)) {
        New-Item -ItemType Directory -Path $resolvedPath -Force | Out-Null
    }

    $resolvedPath
}

function New-EecRunMetadata {
    [CmdletBinding()]
    param(
        [string]$CaseId,
        [string]$TicketId,
        [string]$RedactionLevel
    )

    $startedAtUtc = [DateTime]::UtcNow
    [pscustomobject]@{
        RunId = [guid]::NewGuid().Guid
        StartedAtUtc = $startedAtUtc.ToString("o")
        HostName = $env:COMPUTERNAME
        CaseId = $CaseId
        TicketId = $TicketId
        RedactionLevel = $RedactionLevel
    }
}

function Invoke-EecCollectionRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$CollectorPlan,

        [Parameter(Mandatory = $true)]
        [object]$RunMetadata,

        [Parameter(Mandatory = $true)]
        [string]$OutputDir,

        [int]$CriticalFailureThreshold = 1,
        [switch]$DryRun
    )

    $results = @()
    $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    foreach ($collector in $CollectorPlan) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $status = "Success"
        $message = "Completed."

        try {
            if ($DryRun) {
                $status = "Planned"
                $message = "Dry run only. Collector execution skipped."
            }
            elseif (-not $collector.Implemented) {
                $status = "Skipped"
                $message = "Collector not yet implemented."
            }
            else {
                $status = "Success"
                $message = "Collector executed."
            }
        }
        catch {
            $status = "Failed"
            $message = $_.Exception.Message
        }
        finally {
            $stopwatch.Stop()
        }

        $result = [pscustomobject]@{
            Name = $collector.Name
            Critical = [bool]$collector.Critical
            RequiresElevation = [bool]$collector.RequiresElevation
            Status = $status
            Message = $message
            DurationMs = [int]$stopwatch.Elapsed.TotalMilliseconds
        }

        $results += $result
        Write-Host ("[{0}] {1} ({2} ms) - {3}" -f $result.Status, $result.Name, $result.DurationMs, $result.Message)
    }

    $runStopwatch.Stop()

    $failureCount = @($results | Where-Object { $_.Status -eq "Failed" }).Count
    $criticalFailureCount = @($results | Where-Object { $_.Status -eq "Failed" -and $_.Critical }).Count
    $skippedCount = @($results | Where-Object { $_.Status -eq "Skipped" }).Count

    $exitCode = 0
    if ($criticalFailureCount -ge $CriticalFailureThreshold) {
        $exitCode = 2
    }
    elseif ($failureCount -gt 0) {
        $exitCode = 1
    }

    [pscustomobject]@{
        RunId = $RunMetadata.RunId
        StartedAtUtc = $RunMetadata.StartedAtUtc
        OutputDir = $OutputDir
        DryRun = [bool]$DryRun
        TotalDurationMs = [int]$runStopwatch.Elapsed.TotalMilliseconds
        TotalCollectors = $CollectorPlan.Count
        FailureCount = $failureCount
        CriticalFailureCount = $criticalFailureCount
        SkippedCount = $skippedCount
        ExitCode = $exitCode
        CollectorResults = $results
    }
}

Export-ModuleMember -Function @(
    "Get-EecCollectorCatalog",
    "Resolve-EecCollectorPlan",
    "Test-EecOutputPath",
    "New-EecRunMetadata",
    "Invoke-EecCollectionRun"
)
