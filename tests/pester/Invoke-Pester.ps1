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

    Invoke-Pester -Path $Path -Output Detailed -CI -PassThru `
        -Configuration @{
            TestResult = @{
                Enabled = $true
                OutputPath = $ResultsPath
                OutputFormat = "NUnitXml"
            }
        }
}
else {
    Invoke-Pester -Path $Path -Output Detailed
}
