BeforeAll {
    . (Join-Path $PSScriptRoot "_bootstrap.ps1")
    $scriptPath = Join-Path $PSScriptRoot "../../collect-endpoint-evidence.ps1"
    $psExe = (Get-Process -Id $PID).Path
}

Describe "CLI validation" {
    It "fails when signature enabled without thumbprint" {
        $outputDir = Join-Path ([IO.Path]::GetTempPath()) ("eec-cli-" + [guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

        $output = & $psExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -DryRun -OutputDir $outputDir -EnableSignature 2>&1
        ($output | Out-String) | Should -Match "SigningCertThumbprint is required"
    }

    It "fails when encryption enabled without password" {
        $outputDir = Join-Path ([IO.Path]::GetTempPath()) ("eec-cli-" + [guid]::NewGuid().Guid)
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null

        $output = & $psExe -NoProfile -ExecutionPolicy Bypass -File $scriptPath -DryRun -OutputDir $outputDir -EnableBundleEncryption 2>&1
        ($output | Out-String) | Should -Match "BundlePassword is required"
    }
}
