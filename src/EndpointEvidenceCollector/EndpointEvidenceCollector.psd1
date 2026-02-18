@{
    RootModule = 'EndpointEvidenceCollector.psm1'
    ModuleVersion = '0.1.0'
    GUID = '63bbf019-f8b8-4af8-9756-052f2e9e58a3'
    Author = 'Mchael Poncardas'
    CompanyName = 'Arkibo'
    Copyright = '(c) Arkibo. All rights reserved.'
    Description = 'Core module for endpoint-evidence-collector orchestration and helpers.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Get-EecCollectorCatalog',
        'Resolve-EecCollectorPlan',
        'Test-EecOutputPath',
        'New-EecRunMetadata',
        'New-EecRunOutputDirectory',
        'Test-EecSafeIdentifier',
        'Invoke-EecRetentionCleanup',
        'Invoke-EecCollectionRun'
    )
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('service-desk', 'endpoint', 'evidence', 'diagnostics')
        }
    }
}
