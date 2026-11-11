function Test-ResourceGroupName {
    <#
    .SYNOPSIS
        Validates a resource group name against the standard naming convention.
    .EXAMPLE
        Test-ResourceGroupName -Name 'prod-billing-eastus-rg'
        # True
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $Name -cmatch (Get-ResourceGroupNamePattern)
}
