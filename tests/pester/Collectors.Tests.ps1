BeforeAll {
    . (Join-Path $PSScriptRoot "_bootstrap.ps1")
}

Describe "Collector units" {
    InModuleScope EndpointEvidenceCollector {
        BeforeEach {
            Mock Get-CimInstance {
                switch ($ClassName) {
                    "Win32_OperatingSystem" { [pscustomobject]@{ Caption = "Windows"; Version = "10.0"; BuildNumber = "19045"; LastBootUpTime = (Get-Date) } }
                    "Win32_ComputerSystem" { [pscustomobject]@{ Domain = "contoso.local"; Manufacturer = "Contoso"; Model = "ModelX"; TotalPhysicalMemory = 17179869184 } }
                    "Win32_BIOS" { [pscustomobject]@{ SMBIOSBIOSVersion = @("1.0.0"); SerialNumber = "ABC123" } }
                    "Win32_LogicalDisk" { @([pscustomobject]@{ DeviceID = "C:"; VolumeName = "OS"; FileSystem = "NTFS"; Size = 100GB; FreeSpace = 40GB }) }
                    default { @() }
                }
            }

            Mock Get-Process {
                @([pscustomobject]@{ Name = "proc"; Id = 1; CPU = 1.2; WS = 10; PM = 10; StartTime = (Get-Date) })
            }

            Mock Get-NetIPConfiguration { @([pscustomobject]@{ InterfaceAlias = "Ethernet"; InterfaceDescription = "Adapter"; IPv4Address = "10.0.0.10"; IPv6Address = $null; DNSServer = "10.0.0.2" }) }
            Mock Get-NetRoute { @([pscustomobject]@{ InterfaceAlias = "Ethernet"; DestinationPrefix = "0.0.0.0/0"; NextHop = "10.0.0.1"; RouteMetric = 25; State = "Alive" }) }
            Mock Get-DnsClientServerAddress { @([pscustomobject]@{ InterfaceAlias = "Ethernet"; AddressFamily = 2; ServerAddresses = @("10.0.0.2") }) }
            Mock Test-Connection { $true }
            Mock Get-ItemProperty { @([pscustomobject]@{ DisplayName = "AppA"; DisplayVersion = "1.0"; Publisher = "Contoso"; InstallDate = "20260101" }) }
            Mock Get-WinEvent { @([pscustomobject]@{ TimeCreated = (Get-Date); Id = 1000; LevelDisplayName = "Error"; ProviderName = "App"; Message = "failed for user bob@contoso.com" }) }
        }

        It "collects system data" {
            $data = Invoke-EecCollector -CollectorName "system"
            $data.OsCaption | Should -Be "Windows"
        }

        It "collects process list" {
            $data = Invoke-EecCollector -CollectorName "processes"
            @($data).Count | Should -BeGreaterThan 0
        }

        It "collects disk data" {
            $data = Invoke-EecCollector -CollectorName "disk"
            @($data).Count | Should -Be 1
        }

        It "collects network data" {
            $data = Invoke-EecCollector -CollectorName "network"
            @($data.Adapters).Count | Should -BeGreaterThan 0
            @($data.Routes).Count | Should -BeGreaterThan 0
            @($data.DnsServers).Count | Should -BeGreaterThan 0
        }

        It "collects installed apps" {
            $data = Invoke-EecCollector -CollectorName "apps"
            @($data).Count | Should -BeGreaterThan 0
        }

        It "collects event logs with lookback" {
            $data = Invoke-EecCollector -CollectorName "eventlogs" -EventLogLookbackHours 24
            $data.LookbackHours | Should -Be 24
        }
    }
}
