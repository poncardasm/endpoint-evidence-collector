BeforeAll {
    . (Join-Path $PSScriptRoot "_bootstrap.ps1")
}

Describe "Core module behaviors" {
    It "returns known collector catalog entries" {
        $catalog = Get-EecCollectorCatalog
        $catalog.Name | Should -Contain "system"
        $catalog.Name | Should -Contain "eventlogs"
        ($catalog | Where-Object Name -eq "eventlogs").RequiresElevation | Should -BeTrue
    }

    It "resolves include/exclude plans" {
        $catalog = Get-EecCollectorCatalog
        $plan = Resolve-EecCollectorPlan -Catalog $catalog -Include @("system", "disk")
        $plan.Count | Should -Be 2
        $plan.Name | Should -Contain "system"
        $plan.Name | Should -Contain "disk"
    }

    It "rejects conflicting include/exclude" {
        $catalog = Get-EecCollectorCatalog
        { Resolve-EecCollectorPlan -Catalog $catalog -Include @("system") -Exclude @("system") } | Should -Throw
    }

    It "validates unsafe output paths" {
        { Test-EecOutputPath -Path "..\\bad" } | Should -Throw
    }

    It "creates run metadata with run id and UTC timestamp" {
        $meta = New-EecRunMetadata -CaseId "INC-1" -TicketId "" -RedactionLevel "standard"
        $meta.RunId | Should -Not -BeNullOrEmpty
        $meta.StartedAtUtc | Should -Match "Z$"
    }
}
