$moduleManifest = Join-Path $PSScriptRoot "../../src/EndpointEvidenceCollector/EndpointEvidenceCollector.psd1"
$entryScript = Join-Path $PSScriptRoot "../../collect-endpoint-evidence.ps1"

if (-not (Test-Path -LiteralPath $moduleManifest)) {
    throw "Module manifest not found at $moduleManifest"
}

Import-Module $moduleManifest -Force
