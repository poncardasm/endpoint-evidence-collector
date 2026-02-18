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
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Shared helper import pattern (temporary until full module wiring).
$modulePath = Join-Path $PSScriptRoot "src/EndpointEvidenceCollector/EndpointEvidenceCollector.psd1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -ErrorAction Stop
}

Write-Host "endpoint-evidence-collector bootstrap"
Write-Host "CaseId: $CaseId | TicketId: $TicketId | Redaction: $RedactionLevel"
Write-Host "OutputDir: $OutputDir"

if ($DryRun) {
    Write-Host "Dry run enabled. No evidence will be collected."
    exit 0
}

Write-Host "Collector implementation pending (see TASKS.md Sections 2+)."
exit 0
