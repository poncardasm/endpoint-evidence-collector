BeforeAll {
    . (Join-Path $PSScriptRoot "_bootstrap.ps1")
}

Describe "Integration e2e flow" {
    InModuleScope EndpointEvidenceCollector {
        It "completes a one-collector run and produces expected artifacts" {
            $plan = @([pscustomobject]@{ Name = "system"; Critical = $true; RequiresElevation = $false; Implemented = $true })
            $meta = [pscustomobject]@{
                RunId = [guid]::NewGuid().Guid
                StartedAtUtc = [DateTime]::UtcNow.ToString("o")
                HostName = "testhost"
                CaseId = "INC-E2E"
                TicketId = ""
                RedactionLevel = "standard"
            }

            $runDir = Join-Path ([IO.Path]::GetTempPath()) ("eec-e2e-" + [guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null

            Mock Invoke-EecCollector { [pscustomobject]@{ Message = "ok user bob@contoso.com" } }
            Mock Test-EecIsElevated { $true }

            $result = Invoke-EecCollectionRun -CollectorPlan $plan -RunMetadata $meta -OutputDir $runDir
            $result.ExitCode | Should -Be 0
            (Test-Path -LiteralPath $result.ArtifactPaths.SummaryPath) | Should -BeTrue
            (Test-Path -LiteralPath $result.ArtifactPaths.ManifestPath) | Should -BeTrue
            (Test-Path -LiteralPath $result.ArtifactPaths.BundlePath) | Should -BeTrue
        }
    }
}
