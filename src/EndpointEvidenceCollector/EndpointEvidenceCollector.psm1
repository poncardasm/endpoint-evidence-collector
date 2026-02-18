Set-StrictMode -Version Latest

function Get-EecCollectorCatalog {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{
            Name = "system"
            Critical = $true
            RequiresElevation = $false
            Implemented = $true
            Description = "System and OS details"
        }
        [pscustomobject]@{
            Name = "processes"
            Critical = $true
            RequiresElevation = $false
            Implemented = $true
            Description = "Active process list"
        }
        [pscustomobject]@{
            Name = "disk"
            Critical = $true
            RequiresElevation = $false
            Implemented = $true
            Description = "Disk usage and health basics"
        }
        [pscustomobject]@{
            Name = "network"
            Critical = $true
            RequiresElevation = $false
            Implemented = $true
            Description = "Network diagnostics"
        }
        [pscustomobject]@{
            Name = "apps"
            Critical = $false
            RequiresElevation = $false
            Implemented = $true
            Description = "Installed applications list"
        }
        [pscustomobject]@{
            Name = "eventlogs"
            Critical = $false
            RequiresElevation = $true
            Implemented = $true
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

function Test-EecIsElevated {
    [CmdletBinding()]
    param()

    $isWindowsHost = $true
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $isWindowsHost = [bool]$IsWindows
    }

    if (-not $isWindowsHost) {
        return $false
    }

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-EecSystemEvidence {
    [CmdletBinding()]
    param()

    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $computer = Get-CimInstance -ClassName Win32_ComputerSystem
    $bios = Get-CimInstance -ClassName Win32_BIOS

    [pscustomobject]@{
        CollectedAtUtc = [DateTime]::UtcNow.ToString("o")
        ComputerName = $env:COMPUTERNAME
        Domain = $computer.Domain
        Manufacturer = $computer.Manufacturer
        Model = $computer.Model
        TotalPhysicalMemoryBytes = [int64]$computer.TotalPhysicalMemory
        OsCaption = $os.Caption
        OsVersion = $os.Version
        OsBuildNumber = $os.BuildNumber
        LastBootUpTime = $os.LastBootUpTime
        BiosVersion = ($bios.SMBIOSBIOSVersion -join ", ")
        SerialNumber = $bios.SerialNumber
    }
}

function Get-EecProcessEvidence {
    [CmdletBinding()]
    param()

    Get-Process |
        Sort-Object -Property CPU -Descending |
        Select-Object -Property Name, Id, CPU, WS, PM, StartTime -ErrorAction SilentlyContinue
}

function Get-EecDiskEvidence {
    [CmdletBinding()]
    param()

    Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType = 3" |
        Select-Object -Property DeviceID, VolumeName, FileSystem,
            @{Name = "SizeGB"; Expression = { [math]::Round(($_.Size / 1GB), 2) } },
            @{Name = "FreeGB"; Expression = { [math]::Round(($_.FreeSpace / 1GB), 2) } },
            @{Name = "FreePercent"; Expression = {
                if ($_.Size -gt 0) {
                    [math]::Round(($_.FreeSpace / $_.Size) * 100, 2)
                }
                else {
                    0
                }
            } }
}

function Get-EecNetworkEvidence {
    [CmdletBinding()]
    param()

    $adapters = Get-NetIPConfiguration | Select-Object -Property InterfaceAlias, InterfaceDescription, IPv4Address, IPv6Address, DNSServer, NetAdapter
    $routes = Get-NetRoute -AddressFamily IPv4 | Select-Object -Property InterfaceAlias, DestinationPrefix, NextHop, RouteMetric, State
    $dnsServers = Get-DnsClientServerAddress | Select-Object -Property InterfaceAlias, AddressFamily, ServerAddresses

    $reachability = @(
        [pscustomobject]@{ Target = "1.1.1.1"; Reachable = (Test-Connection -ComputerName "1.1.1.1" -Count 1 -Quiet -ErrorAction SilentlyContinue) }
        [pscustomobject]@{ Target = "8.8.8.8"; Reachable = (Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction SilentlyContinue) }
        [pscustomobject]@{ Target = "microsoft.com"; Reachable = (Test-Connection -ComputerName "microsoft.com" -Count 1 -Quiet -ErrorAction SilentlyContinue) }
    )

    [pscustomobject]@{
        Adapters = $adapters
        Routes = $routes
        DnsServers = $dnsServers
        Reachability = $reachability
    }
}

function Get-EecInstalledAppsEvidence {
    [CmdletBinding()]
    param()

    $paths = @(
        "HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $apps = foreach ($path in $paths) {
        Get-ItemProperty -Path $path -ErrorAction SilentlyContinue |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_.DisplayName) } |
            Select-Object -Property DisplayName, DisplayVersion, Publisher, InstallDate
    }

    $apps | Sort-Object -Property DisplayName -Unique
}

function Get-EecEventLogEvidence {
    [CmdletBinding()]
    param(
        [ValidateRange(1, 168)]
        [int]$LookbackHours = 24,

        [ValidateRange(50, 2000)]
        [int]$MaxEventsPerLog = 200
    )

    $startTime = (Get-Date).AddHours(-1 * $LookbackHours)
    $logs = @("Application", "System")

    $result = foreach ($log in $logs) {
        [pscustomobject]@{
            LogName = $log
            Events = @(Get-WinEvent -FilterHashtable @{ LogName = $log; StartTime = $startTime } -MaxEvents $MaxEventsPerLog -ErrorAction SilentlyContinue |
                    Select-Object -Property TimeCreated, Id, LevelDisplayName, ProviderName, Message)
        }
    }

    [pscustomobject]@{
        StartTime = $startTime
        LookbackHours = $LookbackHours
        Logs = $result
    }
}

function Invoke-EecCollector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CollectorName,

        [ValidateRange(1, 168)]
        [int]$EventLogLookbackHours = 24
    )

    switch ($CollectorName) {
        "system" { return Get-EecSystemEvidence }
        "processes" { return Get-EecProcessEvidence }
        "disk" { return Get-EecDiskEvidence }
        "network" { return Get-EecNetworkEvidence }
        "apps" { return Get-EecInstalledAppsEvidence }
        "eventlogs" { return Get-EecEventLogEvidence -LookbackHours $EventLogLookbackHours }
        default { throw "Unknown collector: $CollectorName" }
    }
}

function Get-EecCollectorDataCount {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Data
    )

    if ($null -eq $Data) {
        return 0
    }

    if ($Data -is [System.Array]) {
        return $Data.Count
    }

    if ($Data.PSObject.Properties.Name -contains "Count") {
        return [int]$Data.Count
    }

    if ($Data.PSObject.Properties.Name -contains "Logs") {
        $total = 0
        foreach ($logBlock in $Data.Logs) {
            if ($logBlock.PSObject.Properties.Name -contains "Events") {
                $total += @($logBlock.Events).Count
            }
        }
        return $total
    }

    return 1
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

        [ValidateRange(1, 10)]
        [int]$CriticalFailureThreshold = 1,

        [ValidateRange(1, 168)]
        [int]$EventLogLookbackHours = 24,

        [switch]$DryRun
    )

    $results = @()
    $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $isElevated = Test-EecIsElevated

    foreach ($collector in $CollectorPlan) {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        $status = "Success"
        $message = "Completed."
        $data = $null

        try {
            if ($DryRun) {
                $status = "Planned"
                $message = "Dry run only. Collector execution skipped."
            }
            elseif (-not $collector.Implemented) {
                $status = "Skipped"
                $message = "Collector not yet implemented."
            }
            elseif ($collector.RequiresElevation -and -not $isElevated) {
                $status = "Skipped"
                $message = "Collector requires elevation and current session is not elevated."
            }
            else {
                $data = Invoke-EecCollector -CollectorName $collector.Name -EventLogLookbackHours $EventLogLookbackHours
                $itemCount = Get-EecCollectorDataCount -Data $data
                $status = "Success"
                $message = "Collector executed. Items captured: $itemCount"
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
            Data = $data
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
        IsElevated = [bool]$isElevated
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
