BeforeAll {
    . (Join-Path $PSScriptRoot "_bootstrap.ps1")
}

Describe "Packaging and manifest" {
    InModuleScope EndpointEvidenceCollector {
        It "writes summary, manifest, zip, and checksum artifacts" {
            $meta = [pscustomobject]@{
                RunId = [guid]::NewGuid().Guid
                StartedAtUtc = [DateTime]::UtcNow.ToString("o")
                HostName = "testhost"
                CaseId = "INC-42"
                TicketId = ""
                RedactionLevel = "standard"
            }

            $runDir = Join-Path ([IO.Path]::GetTempPath()) ("eec-pack-" + [guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $runDir -Force | Out-Null

            $result = [pscustomobject]@{
                TotalCollectors = 1
                FailureCount = 0
                CriticalFailureCount = 0
                SkippedCount = 0
                ExitCode = 0
                TotalDurationMs = 100
                RedactionReport = [pscustomobject]@{
                    run_id = $meta.RunId
                    redaction_level = "standard"
                    redaction_error_count = 0
                    categories = [pscustomobject]@{ usernames = 0; tokens = 0; emails = 0; ip_addresses = 0 }
                }
                CollectorResults = @(
                    [pscustomobject]@{
                        Name = "system"
                        Status = "Success"
                        Critical = $true
                        RequiresElevation = $false
                        Message = "ok"
                        DurationMs = 10
                        Data = [pscustomobject]@{ OsCaption = "Windows" }
                    }
                )
            }

            $artifacts = Write-EecRunArtifacts -RunMetadata $meta -RunResult $result -RunOutputDir $runDir

            (Test-Path -LiteralPath $artifacts.SummaryPath) | Should -BeTrue
            (Test-Path -LiteralPath $artifacts.ManifestPath) | Should -BeTrue
            (Test-Path -LiteralPath $artifacts.BundlePath) | Should -BeTrue
            (Test-Path -LiteralPath $artifacts.ChecksumPath) | Should -BeTrue

            $manifest = Get-Content -LiteralPath $artifacts.ManifestPath -Raw | ConvertFrom-Json
            $manifest.run_id | Should -Be $meta.RunId
            @($manifest.files).Count | Should -BeGreaterThan 0
        }

        It "removes pre-redaction temporary artifacts after run" {
            $plan = @([pscustomobject]@{ Name = "system"; Critical = $true; RequiresElevation = $false; Implemented = $true })
            $meta = [pscustomobject]@{
                RunId = [guid]::NewGuid().Guid
                StartedAtUtc = [DateTime]::UtcNow.ToString("o")
                HostName = "testhost"
                CaseId = "INC-77"
                TicketId = ""
                RedactionLevel = "standard"
            }
            $base = Join-Path ([IO.Path]::GetTempPath()) ("eec-clean-" + [guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $base -Force | Out-Null

            Mock Invoke-EecCollector { [pscustomobject]@{ Message = "ok" } }
            Mock Test-EecIsElevated { $true }

            $run = Invoke-EecCollectionRun -CollectorPlan $plan -RunMetadata $meta -OutputDir $base
            $run.ArtifactPaths | Should -Not -BeNullOrEmpty

            $leftover = Get-ChildItem -LiteralPath $base -Force -Directory | Where-Object { $_.Name -like ".pre-redaction-*" }
            @($leftover).Count | Should -Be 0
        }
    }
}
