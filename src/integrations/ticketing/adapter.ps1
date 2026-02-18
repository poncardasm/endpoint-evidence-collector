Set-StrictMode -Version Latest

function Export-EecEvidenceToServiceNow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BundlePath,
        [Parameter(Mandatory = $true)][string]$TicketId,
        [Parameter(Mandatory = $true)][string]$InstanceUrl,
        [Parameter(Mandatory = $true)][pscredential]$Credential
    )

    throw "Post-v1 adapter stub: implement ServiceNow attachment API integration."
}

function Export-EecEvidenceToJira {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BundlePath,
        [Parameter(Mandatory = $true)][string]$IssueKey,
        [Parameter(Mandatory = $true)][string]$BaseUrl,
        [Parameter(Mandatory = $true)][string]$ApiToken,
        [Parameter(Mandatory = $true)][string]$Email
    )

    throw "Post-v1 adapter stub: implement Jira attachment API integration."
}

function Export-EecEvidenceToZendesk {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BundlePath,
        [Parameter(Mandatory = $true)][string]$TicketId,
        [Parameter(Mandatory = $true)][string]$Subdomain,
        [Parameter(Mandatory = $true)][string]$ApiToken,
        [Parameter(Mandatory = $true)][string]$Email
    )

    throw "Post-v1 adapter stub: implement Zendesk upload + attachment flow."
}

Export-ModuleMember -Function @(
    "Export-EecEvidenceToServiceNow",
    "Export-EecEvidenceToJira",
    "Export-EecEvidenceToZendesk"
)
