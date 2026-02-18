Set-StrictMode -Version Latest

function Get-EecMacOSSystemEvidence {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        CollectedAtUtc = [DateTime]::UtcNow.ToString("o")
        SwVers = (sw_vers | Out-String).Trim()
        Hostname = (hostname)
        Uname = (uname -a)
    }
}

function Get-EecMacOSProcessEvidence {
    [CmdletBinding()]
    param()

    ps -axo pid,ppid,user,%cpu,%mem,comm
}

function Get-EecMacOSDiskEvidence {
    [CmdletBinding()]
    param()

    df -h
}

function Get-EecMacOSNetworkEvidence {
    [CmdletBinding()]
    param()

    [pscustomobject]@{
        Ifconfig = (ifconfig | Out-String)
        Routes = (netstat -rn | Out-String)
        Dns = (scutil --dns | Out-String)
    }
}

Export-ModuleMember -Function @(
    "Get-EecMacOSSystemEvidence",
    "Get-EecMacOSProcessEvidence",
    "Get-EecMacOSDiskEvidence",
    "Get-EecMacOSNetworkEvidence"
)
