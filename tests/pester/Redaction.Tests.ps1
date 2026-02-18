BeforeAll {
    . (Join-Path $PSScriptRoot "_bootstrap.ps1")
}

Describe "Redaction engine" {
    InModuleScope EndpointEvidenceCollector {
        It "redacts token and email in standard mode" {
            $counters = New-EecRedactionCounters
            $input = [pscustomobject]@{
                Message = "api_key=abcdef123456 user bob@contoso.com path C:\\Users\\bob\\Desktop"
            }

            $out = Invoke-EecRedaction -Data $input -RedactionLevel "standard" -Counters $counters
            $out.Message | Should -Match "REDACTED_SECRET"
            $out.Message | Should -Match "\*\*\*@contoso.com"
            $out.Message | Should -Match "C:\\Users\\\[REDACTED_USER\]"
            $counters.tokens | Should -BeGreaterThan 0
            $counters.emails | Should -BeGreaterThan 0
            $counters.usernames | Should -BeGreaterThan 0
        }

        It "redacts IP addresses in strict mode" {
            $counters = New-EecRedactionCounters
            $input = [pscustomobject]@{ Note = "source 10.1.2.3 destination 2001:db8::1" }
            $out = Invoke-EecRedaction -Data $input -RedactionLevel "strict" -Counters $counters
            $out.Note | Should -Match "REDACTED_IPV4"
            $out.Note | Should -Match "REDACTED_IPV6"
            $counters.ip_addresses | Should -BeGreaterThan 0
        }

        It "fails closed by blocking export when redaction errors occur" {
            $plan = @([pscustomobject]@{ Name = "system"; Critical = $true; RequiresElevation = $false; Implemented = $true })
            $meta = [pscustomobject]@{
                RunId = [guid]::NewGuid().Guid
                StartedAtUtc = [DateTime]::UtcNow.ToString("o")
                HostName = "testhost"
                CaseId = "INC-9"
                TicketId = ""
                RedactionLevel = "standard"
            }

            $temp = Join-Path ([IO.Path]::GetTempPath()) ("eec-test-" + [guid]::NewGuid().Guid)
            New-Item -ItemType Directory -Path $temp -Force | Out-Null

            Mock Invoke-EecCollector { [pscustomobject]@{ Message = "secret=abc" } }
            Mock Invoke-EecRedaction { throw "forced redaction failure" }

            { Invoke-EecCollectionRun -CollectorPlan $plan -RunMetadata $meta -OutputDir $temp } | Should -Throw
        }
    }
}
