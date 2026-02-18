Set-StrictMode -Version Latest

function Get-EecCollectorCatalog {
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Name = "system"; Critical = $true; RequiresElevation = $false; Implemented = $true; Description = "System and OS details" }
        [pscustomobject]@{ Name = "processes"; Critical = $true; RequiresElevation = $false; Implemented = $true; Description = "Active process list" }
        [pscustomobject]@{ Name = "disk"; Critical = $true; RequiresElevation = $false; Implemented = $true; Description = "Disk usage and health basics" }
        [pscustomobject]@{ Name = "network"; Critical = $true; RequiresElevation = $false; Implemented = $true; Description = "Network diagnostics" }
        [pscustomobject]@{ Name = "apps"; Critical = $false; RequiresElevation = $false; Implemented = $true; Description = "Installed applications list" }
        [pscustomobject]@{ Name = "eventlogs"; Critical = $false; RequiresElevation = $true; Implemented = $true; Description = "Recent relevant event logs" }
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

function Set-EecOutputDirectoryPermissions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $isWindowsHost = $true
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        $isWindowsHost = [bool]$IsWindows
    }
    if (-not $isWindowsHost) {
        return
    }

    try {
        $userName = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
        & icacls $Path /inheritance:r /grant:r "${userName}:(OI)(CI)F" "Administrators:(OI)(CI)F" | Out-Null
    }
    catch {
        Write-Warning "Unable to harden output ACLs at '$Path': $($_.Exception.Message)"
    }
}

function New-EecRunOutputDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseOutputDir,
        [Parameter(Mandatory = $true)]
        [object]$RunMetadata
    )

    $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $caseToken = if (-not [string]::IsNullOrWhiteSpace($RunMetadata.CaseId)) { $RunMetadata.CaseId } elseif (-not [string]::IsNullOrWhiteSpace($RunMetadata.TicketId)) { $RunMetadata.TicketId } else { "no-case" }
    $safeCaseToken = ($caseToken -replace "[^A-Za-z0-9._-]", "_")
    $safeHost = (($RunMetadata.HostName | ForEach-Object { $_ }) -join "" -replace "[^A-Za-z0-9._-]", "_")

    $runDirName = "$safeHost-$stamp-$safeCaseToken"
    $runDir = Join-Path $BaseOutputDir $runDirName
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    Set-EecOutputDirectoryPermissions -Path $runDir
    $runDir
}

function Test-EecSafeIdentifier {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    $trimmed = $Value.Trim()
    if ($trimmed.Length -gt 128) {
        throw "$Name is too long. Maximum length is 128 characters."
    }

    if ($trimmed -match "[`n`r;&|]" -or $trimmed -match "\.\." -or $trimmed -match "[\\/]" -or $trimmed -match "^\s*[-]") {
        throw "$Name contains unsafe characters."
    }
}

function Invoke-EecRetentionCleanup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseOutputDir,
        [ValidateRange(1, 365)]
        [int]$RetentionDays = 7
    )

    if (-not (Test-Path -LiteralPath $BaseOutputDir)) {
        return [pscustomobject]@{
            base_output_dir = $BaseOutputDir
            retention_days = $RetentionDays
            cutoff_utc = [DateTime]::UtcNow.AddDays(-1 * $RetentionDays).ToString("o")
            removed_count = 0
            removed_directories = @()
            skipped_reason = "base output directory does not exist"
        }
    }

    $cutoff = [DateTime]::UtcNow.AddDays(-1 * $RetentionDays)
    $removed = @()

    $candidateDirs = Get-ChildItem -LiteralPath $BaseOutputDir -Directory -ErrorAction SilentlyContinue
    foreach ($dir in $candidateDirs) {
        try {
            if ($dir.LastWriteTimeUtc -lt $cutoff) {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                $removed += $dir.FullName
            }
        }
        catch {
            Write-Warning "Retention cleanup failed for '$($dir.FullName)': $($_.Exception.Message)"
        }
    }

    [pscustomobject]@{
        base_output_dir = $BaseOutputDir
        retention_days = $RetentionDays
        cutoff_utc = $cutoff.ToString("o")
        removed_count = $removed.Count
        removed_directories = $removed
        skipped_reason = $null
    }
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
                if ($_.Size -gt 0) { [math]::Round(($_.FreeSpace / $_.Size) * 100, 2) }
                else { 0 }
            } }
}

function Get-EecNetworkEvidence {
    [CmdletBinding()]
    param()

    $adapters = Get-NetIPConfiguration | Select-Object -Property InterfaceAlias, InterfaceDescription, IPv4Address, IPv6Address, DNSServer
    $routes = Get-NetRoute -AddressFamily IPv4 | Select-Object -Property InterfaceAlias, DestinationPrefix, NextHop, RouteMetric, State
    $dnsServers = Get-DnsClientServerAddress | Select-Object -Property InterfaceAlias, AddressFamily, ServerAddresses

    $reachabilityTargets = @("1.1.1.1", "8.8.8.8", "microsoft.com")
    $reachability = foreach ($target in $reachabilityTargets) {
        [pscustomobject]@{
            Target = $target
            Reachable = (Test-Connection -ComputerName $target -Count 1 -Quiet -ErrorAction SilentlyContinue)
        }
    }

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

    if ($null -eq $Data) { return 0 }
    if ($Data -is [System.Array]) { return $Data.Count }
    if ($Data.PSObject.Properties.Name -contains "Count") { return [int]$Data.Count }

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

function New-EecTempArtifactPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputDir,
        [Parameter(Mandatory = $true)]
        [string]$RunId
    )

    $path = Join-Path $OutputDir (".pre-redaction-" + $RunId)
    if (Test-Path -LiteralPath $path) {
        Remove-Item -LiteralPath $path -Recurse -Force -ErrorAction Stop
    }
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    $path
}

function Remove-EecTempArtifactPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path) {
        Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
    }
}

function Write-EecPreRedactionSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TempDir,
        [Parameter(Mandatory = $true)]
        [string]$CollectorName,
        [Parameter(Mandatory = $true)]
        $Data
    )

    $filePath = Join-Path $TempDir ($CollectorName + ".raw.json")
    $Data | ConvertTo-Json -Depth 8 | Out-File -LiteralPath $filePath -Encoding UTF8
}

function New-EecRedactionCounters {
    [CmdletBinding()]
    param()

    @{ usernames = 0; tokens = 0; emails = 0; ip_addresses = 0 }
}

function Get-EecRedactionRules {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("standard", "strict")]
        [string]$RedactionLevel
    )

    $rules = @(
        [pscustomobject]@{
            Category = "usernames"
            Pattern = "(?i)(C:\\+Users\\+)([^\\\s]+)"
            Replace = { param($match) return $match.Groups[1].Value + "[REDACTED_USER]" }
        }
        [pscustomobject]@{
            Category = "usernames"
            Pattern = "(?i)(/Users/)([^/\s]+)"
            Replace = { param($match) return $match.Groups[1].Value + "[REDACTED_USER]" }
        }
        [pscustomobject]@{
            Category = "tokens"
            Pattern = "(?i)\b(?:api[_-]?key|access[_-]?token|refresh[_-]?token|secret|password)\b\s*[:=]\s*([^\s,;]+)"
            Replace = {
                param($match)
                $value = $match.Groups[0].Value
                $sepIndex = $value.IndexOf("=")
                if ($sepIndex -lt 0) { $sepIndex = $value.IndexOf(":") }
                if ($sepIndex -ge 0) { return $value.Substring(0, $sepIndex + 1) + " [REDACTED_SECRET]" }
                return "[REDACTED_SECRET]"
            }
        }
        [pscustomobject]@{
            Category = "tokens"
            Pattern = "\beyJ[a-zA-Z0-9_-]{10,}\.[a-zA-Z0-9._-]{10,}\.[a-zA-Z0-9._-]{10,}\b"
            Replace = { param($match) return "[REDACTED_JWT]" }
        }
        [pscustomobject]@{
            Category = "emails"
            Pattern = "\b([A-Za-z0-9._%+-])[A-Za-z0-9._%+-]*@([A-Za-z0-9.-]+\.[A-Za-z]{2,})\b"
            Replace = { param($match) return ($match.Groups[1].Value + "***@" + $match.Groups[2].Value) }
        }
    )

    if ($RedactionLevel -eq "strict") {
        $rules += [pscustomobject]@{
            Category = "ip_addresses"
            Pattern = "\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b"
            Replace = { param($match) return "[REDACTED_IPV4]" }
        }
        $rules += [pscustomobject]@{
            Category = "ip_addresses"
            Pattern = "(?i)\b(?:[A-F0-9]{0,4}:){2,7}[A-F0-9]{0,4}\b"
            Replace = { param($match) return "[REDACTED_IPV6]" }
        }
    }

    $rules
}

function Invoke-EecRedactionOnString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [Parameter(Mandatory = $true)]
        [object[]]$Rules,
        [Parameter(Mandatory = $true)]
        [hashtable]$Counters
    )

    $output = $Text
    foreach ($rule in $Rules) {
        $regex = [regex]::new($rule.Pattern)
        $output = $regex.Replace($output, [System.Text.RegularExpressions.MatchEvaluator]{
                param($match)
                $category = [string]$rule.Category
                if ($Counters.ContainsKey($category)) {
                    $Counters[$category] = [int]$Counters[$category] + 1
                }
                else {
                    $Counters[$category] = 1
                }
                & $rule.Replace $match
            })
    }
    $output
}

function Invoke-EecRedactValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Value,
        [Parameter(Mandatory = $true)]
        [object[]]$Rules,
        [Parameter(Mandatory = $true)]
        [hashtable]$Counters
    )

    if ($null -eq $Value) { return $null }
    if ($Value -is [string]) { return Invoke-EecRedactionOnString -Text $Value -Rules $Rules -Counters $Counters }
    if ($Value -is [ValueType]) { return $Value }

    if ($Value -is [System.Collections.IDictionary]) {
        $redactedMap = [ordered]@{}
        foreach ($key in $Value.Keys) {
            $redactedMap[$key] = Invoke-EecRedactValue -Value $Value[$key] -Rules $Rules -Counters $Counters
        }
        return [pscustomobject]$redactedMap
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $list = @()
        foreach ($item in $Value) {
            $list += @(Invoke-EecRedactValue -Value $item -Rules $Rules -Counters $Counters)
        }
        return $list
    }

    $properties = $Value.PSObject.Properties
    if (@($properties).Count -gt 0) {
        $redactedObject = [ordered]@{}
        foreach ($property in $properties) {
            if ($property.MemberType -eq "NoteProperty" -or $property.MemberType -eq "Property" -or $property.MemberType -eq "AliasProperty") {
                $redactedObject[$property.Name] = Invoke-EecRedactValue -Value $property.Value -Rules $Rules -Counters $Counters
            }
        }
        return [pscustomobject]$redactedObject
    }

    return $Value
}

function Invoke-EecRedaction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [ValidateSet("standard", "strict")]
        [string]$RedactionLevel,
        [Parameter(Mandatory = $true)]
        [hashtable]$Counters
    )

    $rules = Get-EecRedactionRules -RedactionLevel $RedactionLevel
    Invoke-EecRedactValue -Value $Data -Rules $rules -Counters $Counters
}

function Write-EecCollectorArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$CollectorResults,
        [Parameter(Mandatory = $true)]
        [string]$RunOutputDir
    )

    $jsonFiles = @()
    foreach ($result in $CollectorResults) {
        $payload = [pscustomobject]@{
            collector = $result.Name
            status = $result.Status
            critical = [bool]$result.Critical
            requires_elevation = [bool]$result.RequiresElevation
            message = $result.Message
            duration_ms = [int]$result.DurationMs
            data = $result.Data
        }
        $path = Join-Path $RunOutputDir ($result.Name + ".json")
        $payload | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $path -Encoding UTF8
        $jsonFiles += $path
    }
    $jsonFiles
}

function New-EecSummaryReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunMetadata,
        [Parameter(Mandatory = $true)]
        [object]$RunResult,
        [Parameter(Mandatory = $true)]
        [string]$RunOutputDir
    )

    $summaryPath = Join-Path $RunOutputDir "summary.md"
    $lines = @()
    $lines += "# Endpoint Evidence Collection Summary"
    $lines += ""
    $lines += "- Run ID: ``$($RunMetadata.RunId)``"
    $lines += "- Started (UTC): ``$($RunMetadata.StartedAtUtc)``"
    $lines += "- Host: ``$($RunMetadata.HostName)``"
    $lines += "- Case ID: ``$($RunMetadata.CaseId)``"
    $lines += "- Ticket ID: ``$($RunMetadata.TicketId)``"
    $lines += "- Redaction Level: ``$($RunMetadata.RedactionLevel)``"
    $lines += "- Total Duration (ms): ``$($RunResult.TotalDurationMs)``"
    $lines += "- Failures: ``$($RunResult.FailureCount)``"
    $lines += "- Critical Failures: ``$($RunResult.CriticalFailureCount)``"
    $lines += "- Skipped: ``$($RunResult.SkippedCount)``"
    $lines += ""
    $lines += "## Collector Status"
    $lines += ""
    $lines += "| Collector | Status | Critical | Duration (ms) | Message |"
    $lines += "|---|---|---|---:|---|"

    foreach ($result in $RunResult.CollectorResults) {
        $criticalLabel = if ($result.Critical) { "yes" } else { "no" }
        $lines += "| $($result.Name) | $($result.Status) | $criticalLabel | $($result.DurationMs) | $($result.Message) |"
    }

    if ($RunResult.FailureCount -gt 0) {
        $lines += ""
        $lines += "## Warnings"
        $lines += ""
        $lines += "- One or more collectors failed. Review per-collector JSON and messages before escalation handoff."
    }

    $lines | Out-File -LiteralPath $summaryPath -Encoding UTF8
    $summaryPath
}

function Get-EecModuleVersion {
    [CmdletBinding()]
    param()

    try {
        $manifestPath = Join-Path $PSScriptRoot "EndpointEvidenceCollector.psd1"
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Import-PowerShellDataFile -Path $manifestPath
            return [string]$manifest.ModuleVersion
        }
    }
    catch {
        return "unknown"
    }
    "unknown"
}

function New-EecManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunMetadata,
        [Parameter(Mandatory = $true)]
        [object]$RunResult,
        [Parameter(Mandatory = $true)]
        [string]$RunOutputDir
    )

    $manifestPath = Join-Path $RunOutputDir "manifest.json"
    $files = @()

    $artifactFiles = Get-ChildItem -LiteralPath $RunOutputDir -File | Where-Object { $_.Name -ne "manifest.json" }
    foreach ($file in $artifactFiles) {
        $hash = Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256
        $files += [pscustomobject]@{
            file_name = $file.Name
            relative_path = ".\$($file.Name)"
            size_bytes = [int64]$file.Length
            sha256 = $hash.Hash.ToLowerInvariant()
        }
    }

    $manifest = [pscustomobject]@{
        run_id = $RunMetadata.RunId
        generator_version = Get-EecModuleVersion
        host = $RunMetadata.HostName
        started_at_utc = $RunMetadata.StartedAtUtc
        finished_at_utc = [DateTime]::UtcNow.ToString("o")
        case_id = $RunMetadata.CaseId
        ticket_id = $RunMetadata.TicketId
        redaction_level = $RunMetadata.RedactionLevel
        summary = [pscustomobject]@{
            total_collectors = $RunResult.TotalCollectors
            failure_count = $RunResult.FailureCount
            critical_failure_count = $RunResult.CriticalFailureCount
            skipped_count = $RunResult.SkippedCount
            exit_code = $RunResult.ExitCode
            total_duration_ms = $RunResult.TotalDurationMs
        }
        files = $files
    }

    $manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $manifestPath -Encoding UTF8
    $manifestPath
}

function New-EecZipBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunOutputDir,
        [Parameter(Mandatory = $true)]
        [object]$RunMetadata
    )

    $stamp = [DateTime]::UtcNow.ToString("yyyyMMddTHHmmssZ")
    $caseToken = if (-not [string]::IsNullOrWhiteSpace($RunMetadata.CaseId)) { $RunMetadata.CaseId } elseif (-not [string]::IsNullOrWhiteSpace($RunMetadata.TicketId)) { $RunMetadata.TicketId } else { "no-case" }
    $safeCaseToken = ($caseToken -replace "[^A-Za-z0-9._-]", "_")
    $safeHost = ($RunMetadata.HostName -replace "[^A-Za-z0-9._-]", "_")
    $zipPath = Join-Path $RunOutputDir ("$safeHost-$stamp-$safeCaseToken.zip")

    $itemsToArchive = Get-ChildItem -LiteralPath $RunOutputDir -File | Where-Object { $_.Extension -ne ".zip" -and $_.Name -ne "bundle.sha256" -and $_.Name -notlike "*.sig.json" -and $_.Name -notlike "*.enc" -and $_.Name -notlike "checksum-verify.txt" }
    if ($itemsToArchive.Count -eq 0) {
        throw "No files available to archive in '$RunOutputDir'."
    }

    Compress-Archive -Path ($itemsToArchive.FullName) -DestinationPath $zipPath -Force
    $zipPath
}

function ConvertTo-EecPlainText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$SecureValue
    )

    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureValue)
    try {
        [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
    }
    finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Convert-EecHexToBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hex
    )

    $clean = $Hex.Trim()
    if (($clean.Length % 2) -ne 0) {
        throw "Invalid hex string length."
    }

    $bytes = New-Object byte[] ($clean.Length / 2)
    for ($i = 0; $i -lt $clean.Length; $i += 2) {
        $bytes[$i / 2] = [Convert]::ToByte($clean.Substring($i, 2), 16)
    }
    $bytes
}

function Protect-EecBundleWithPassword {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BundlePath,
        [Parameter(Mandatory = $true)]
        [Security.SecureString]$BundlePassword,
        [switch]$KeepPlainBundle
    )

    $plainPassword = ConvertTo-EecPlainText -SecureValue $BundlePassword
    if ([string]::IsNullOrWhiteSpace($plainPassword)) {
        throw "Bundle password cannot be empty when encryption mode is enabled."
    }

    $salt = New-Object byte[] 16
    $iv = New-Object byte[] 16
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt)
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($iv)

    $kdf = $null
    try {
        $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($plainPassword, $salt, 100000, [Security.Cryptography.HashAlgorithmName]::SHA256)
    }
    catch {
        $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($plainPassword, $salt, 100000)
    }
    $key = $kdf.GetBytes(32)

    $aes = [Security.Cryptography.Aes]::Create()
    $aes.KeySize = 256
    $aes.Key = $key
    $aes.IV = $iv
    $aes.Mode = [Security.Cryptography.CipherMode]::CBC
    $aes.Padding = [Security.Cryptography.PaddingMode]::PKCS7

    $encryptedPath = $BundlePath + ".enc"

    $inputBytes = [IO.File]::ReadAllBytes($BundlePath)
    $encryptor = $aes.CreateEncryptor()
    $cipherBytes = $encryptor.TransformFinalBlock($inputBytes, 0, $inputBytes.Length)

    $combined = New-Object byte[] (4 + $salt.Length + $iv.Length + $cipherBytes.Length)
    [BitConverter]::GetBytes([int]$salt.Length).CopyTo($combined, 0)
    $salt.CopyTo($combined, 4)
    $iv.CopyTo($combined, 4 + $salt.Length)
    $cipherBytes.CopyTo($combined, 4 + $salt.Length + $iv.Length)

    [IO.File]::WriteAllBytes($encryptedPath, $combined)

    if (-not $KeepPlainBundle) {
        Remove-Item -LiteralPath $BundlePath -Force
    }

    $encryptedPath
}

function New-EecBundleChecksum {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BundlePath,
        [Parameter(Mandatory = $true)]
        [string]$RunOutputDir
    )

    $hash = Get-FileHash -LiteralPath $BundlePath -Algorithm SHA256
    $checksumPath = Join-Path $RunOutputDir "bundle.sha256"
    "$($hash.Hash.ToLowerInvariant())  $([IO.Path]::GetFileName($BundlePath))" | Out-File -LiteralPath $checksumPath -Encoding ASCII

    $verifyPath = Join-Path $RunOutputDir "checksum-verify.txt"
    @(
        "# Verify bundle checksum (PowerShell)",
        "$`$expected = (Get-Content .\\bundle.sha256).Split('  ')[0]",
        "$`$actual = (Get-FileHash -Algorithm SHA256 .\\$([IO.Path]::GetFileName($BundlePath))).Hash.ToLower()",
        "if ($`$expected -eq $`$actual) { 'Checksum OK' } else { 'Checksum MISMATCH' }"
    ) | Out-File -LiteralPath $verifyPath -Encoding UTF8

    [pscustomobject]@{ ChecksumPath = $checksumPath; VerifyInstructionsPath = $verifyPath }
}

function New-EecDetachedSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$BundlePath,
        [Parameter(Mandatory = $true)]
        [string]$SigningCertThumbprint,
        [Parameter(Mandatory = $true)]
        [string]$RunOutputDir
    )

    $thumb = ($SigningCertThumbprint -replace "\\s", "").ToUpperInvariant()
    $cert = Get-ChildItem -Path "Cert:\CurrentUser\My" -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
    if (-not $cert) {
        $cert = Get-ChildItem -Path "Cert:\LocalMachine\My" -ErrorAction SilentlyContinue | Where-Object { $_.Thumbprint -eq $thumb } | Select-Object -First 1
    }
    if (-not $cert) {
        throw "Signing certificate with thumbprint '$SigningCertThumbprint' not found."
    }

    $rsa = [Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($cert)
    if ($null -eq $rsa) {
        throw "Signing certificate does not provide an RSA private key."
    }

    $hash = Get-FileHash -LiteralPath $BundlePath -Algorithm SHA256
    $hashBytes = Convert-EecHexToBytes -Hex $hash.Hash
    $signatureBytes = $rsa.SignHash($hashBytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)

    $sigPayload = [pscustomobject]@{
        file_name = [IO.Path]::GetFileName($BundlePath)
        sha256 = $hash.Hash.ToLowerInvariant()
        algorithm = "RSA-SHA256"
        cert_thumbprint = $cert.Thumbprint
        signature_base64 = [Convert]::ToBase64String($signatureBytes)
        created_at_utc = [DateTime]::UtcNow.ToString("o")
    }

    $sigPath = Join-Path $RunOutputDir ([IO.Path]::GetFileName($BundlePath) + ".sig.json")
    $sigPayload | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $sigPath -Encoding UTF8
    $sigPath
}

function Write-EecRunArtifacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$RunMetadata,
        [Parameter(Mandatory = $true)]
        [object]$RunResult,
        [Parameter(Mandatory = $true)]
        [string]$RunOutputDir,
        [switch]$EnableSignature,
        [string]$SigningCertThumbprint,
        [switch]$EnableBundleEncryption,
        [Security.SecureString]$BundlePassword,
        [switch]$KeepPlainBundle
    )

    $collectorJsonPaths = Write-EecCollectorArtifacts -CollectorResults $RunResult.CollectorResults -RunOutputDir $RunOutputDir
    $summaryPath = New-EecSummaryReport -RunMetadata $RunMetadata -RunResult $RunResult -RunOutputDir $RunOutputDir

    $redactionReportPath = Join-Path $RunOutputDir "redaction-report.json"
    $RunResult.RedactionReport | ConvertTo-Json -Depth 6 | Out-File -LiteralPath $redactionReportPath -Encoding UTF8

    $manifestPath = New-EecManifest -RunMetadata $RunMetadata -RunResult $RunResult -RunOutputDir $RunOutputDir
    $bundlePath = New-EecZipBundle -RunOutputDir $RunOutputDir -RunMetadata $RunMetadata

    if ($EnableBundleEncryption) {
        if ($null -eq $BundlePassword) {
            throw "Bundle encryption is enabled, but BundlePassword was not supplied."
        }
        $bundlePath = Protect-EecBundleWithPassword -BundlePath $bundlePath -BundlePassword $BundlePassword -KeepPlainBundle:$KeepPlainBundle
    }

    $checksum = New-EecBundleChecksum -BundlePath $bundlePath -RunOutputDir $RunOutputDir

    $signaturePath = $null
    if ($EnableSignature) {
        if ([string]::IsNullOrWhiteSpace($SigningCertThumbprint)) {
            throw "Signature mode enabled, but SigningCertThumbprint is empty."
        }
        $signaturePath = New-EecDetachedSignature -BundlePath $bundlePath -SigningCertThumbprint $SigningCertThumbprint -RunOutputDir $RunOutputDir
    }

    [pscustomobject]@{
        RunOutputDir = $RunOutputDir
        CollectorJsonPaths = $collectorJsonPaths
        SummaryPath = $summaryPath
        RedactionReportPath = $redactionReportPath
        ManifestPath = $manifestPath
        BundlePath = $bundlePath
        ChecksumPath = $checksum.ChecksumPath
        VerifyInstructionsPath = $checksum.VerifyInstructionsPath
        SignaturePath = $signaturePath
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
        [ValidateRange(1, 10)]
        [int]$CriticalFailureThreshold = 1,
        [ValidateRange(1, 168)]
        [int]$EventLogLookbackHours = 24,
        [switch]$EnableSignature,
        [string]$SigningCertThumbprint,
        [switch]$EnableBundleEncryption,
        [Security.SecureString]$BundlePassword,
        [switch]$KeepPlainBundle,
        [switch]$DryRun
    )

    $results = @()
    $runStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $isElevated = Test-EecIsElevated
    $redactionLevel = [string]$RunMetadata.RedactionLevel
    $redactionCounters = New-EecRedactionCounters
    $redactionErrorCount = 0
    $tempArtifactPath = $null

    if (-not $DryRun) {
        try {
            $tempArtifactPath = New-EecTempArtifactPath -OutputDir $OutputDir -RunId $RunMetadata.RunId
        }
        catch {
            throw "Failed to initialize pre-redaction temporary workspace: $($_.Exception.Message)"
        }
    }

    try {
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
                    Write-EecPreRedactionSnapshot -TempDir $tempArtifactPath -CollectorName $collector.Name -Data $data

                    try {
                        $data = Invoke-EecRedaction -Data $data -RedactionLevel $redactionLevel -Counters $redactionCounters
                    }
                    catch {
                        $redactionErrorCount++
                        throw "Redaction failed for collector '$($collector.Name)'."
                    }

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
    }
    finally {
        if (-not $DryRun -and $tempArtifactPath) {
            try {
                Remove-EecTempArtifactPath -Path $tempArtifactPath
            }
            catch {
                throw "Failed to remove pre-redaction temporary artifacts at '$tempArtifactPath'."
            }
        }
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

    $redactionReport = [pscustomobject]@{
        run_id = $RunMetadata.RunId
        redaction_level = $redactionLevel
        redaction_error_count = $redactionErrorCount
        categories = [pscustomobject]@{
            usernames = [int]$redactionCounters["usernames"]
            tokens = [int]$redactionCounters["tokens"]
            emails = [int]$redactionCounters["emails"]
            ip_addresses = [int]$redactionCounters["ip_addresses"]
        }
    }

    $runResult = [pscustomobject]@{
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
        RedactionReport = $redactionReport
        CollectorResults = $results
        ArtifactPaths = $null
    }

    if (-not $DryRun) {
        if ($redactionErrorCount -gt 0) {
            throw "Redaction errors were detected. Export artifacts are blocked (fail-closed)."
        }

        $artifacts = Write-EecRunArtifacts `
            -RunMetadata $RunMetadata `
            -RunResult $runResult `
            -RunOutputDir $OutputDir `
            -EnableSignature:$EnableSignature `
            -SigningCertThumbprint $SigningCertThumbprint `
            -EnableBundleEncryption:$EnableBundleEncryption `
            -BundlePassword $BundlePassword `
            -KeepPlainBundle:$KeepPlainBundle
        $runResult.ArtifactPaths = $artifacts
    }

    $runResult
}

Export-ModuleMember -Function @(
    "Get-EecCollectorCatalog",
    "Resolve-EecCollectorPlan",
    "Test-EecOutputPath",
    "New-EecRunMetadata",
    "New-EecRunOutputDirectory",
    "Test-EecSafeIdentifier",
    "Invoke-EecRetentionCleanup",
    "Invoke-EecCollectionRun"
)
