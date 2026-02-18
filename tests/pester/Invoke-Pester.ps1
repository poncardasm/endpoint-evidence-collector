param(
    [string]$Path = $PSScriptRoot,
    [switch]$CI,
    [string]$ResultsPath = (Join-Path $PSScriptRoot "results/pester-results.xml")
)

$ErrorActionPreference = "Stop"

if (-not (Get-Command Invoke-Pester -ErrorAction SilentlyContinue)) {
    throw "Pester is not installed. Install-Module Pester -Scope CurrentUser -Force"
}

if ($CI) {
    $resultsDir = Split-Path -Parent $ResultsPath
    if (-not (Test-Path -LiteralPath $resultsDir)) {
        New-Item -ItemType Directory -Path $resultsDir -Force | Out-Null
    }

    if (-not (Get-Command New-PesterConfiguration -ErrorAction SilentlyContinue)) {
        throw "Installed Pester version does not support New-PesterConfiguration."
    }

    $config = New-PesterConfiguration
    $config.Run.Path = $Path
    $config.Run.Exit = $true
    $config.Output.Verbosity = "Detailed"
    $config.TestResult.Enabled = $true
    $config.TestResult.OutputPath = $ResultsPath
    $config.TestResult.OutputFormat = "NUnitXml"

    Invoke-Pester -Configuration $config
}
else {
    Invoke-Pester -Path $Path -Output Detailed
}
