function New-ResourceGroupName {
    <#
    .SYNOPSIS
        Builds a resource group name from the standard naming convention.
    .DESCRIPTION
        Produces names of the form <env>-<app>-<region>-rg, e.g. prod-billing-eastus-rg.
        Environment is lower-cased and must be one of dev, test, stage, prod. Application
        and region are lower-cased; application may contain hyphens, region may not.
        This is a pure string builder with no side effects, despite the New- verb.
    .EXAMPLE
        New-ResourceGroupName -Environment prod -Application billing -Region eastus
        # prod-billing-eastus-rg
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '', Justification = 'Pure name builder, no side effects')]
    [CmdletBinding()]
    [OutputType([string])]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('dev', 'test', 'stage', 'prod')]
        [string]$Environment,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9-]{1,29}$')]
        [string]$Application,

        [Parameter(Mandatory)]
        [ValidatePattern('^[A-Za-z][A-Za-z0-9]{2,20}$')]
        [string]$Region
    )

    $name = '{0}-{1}-{2}-rg' -f $Environment.ToLowerInvariant(), $Application.ToLowerInvariant(), $Region.ToLowerInvariant()

    if (-not (Test-ResourceGroupName -Name $name)) {
        throw "Generated name '$name' does not satisfy the naming convention."
    }

    $name
}
