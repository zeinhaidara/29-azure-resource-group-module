function New-StandardResourceGroup {
    <#
    .SYNOPSIS
        Idempotently creates a resource group that matches the naming convention.
    .DESCRIPTION
        Checks for an existing resource group with the given name first. If it already
        exists in the same location it is left untouched (its tags are merged in, not
        replaced). If it exists in a different location this is treated as a conflict
        and an error is thrown rather than silently reusing the wrong resource group.
    .EXAMPLE
        New-StandardResourceGroup -Name 'prod-billing-eastus-rg' -Location 'eastus' -Tag @{ owner = 'platform-team' }
    #>
    [CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Medium')]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$Location,

        [hashtable]$Tag = @{}
    )

    if (-not (Test-ResourceGroupName -Name $Name)) {
        throw "Resource group name '$Name' does not satisfy the naming convention."
    }

    $existing = Get-AzResourceGroup -Name $Name -ErrorAction SilentlyContinue

    if ($existing) {
        if ($existing.Location -ne $Location) {
            throw "Resource group '$Name' already exists in '$($existing.Location)', not '$Location'. Refusing to proceed."
        }

        Write-Verbose "Resource group '$Name' already exists in '$Location'; treating as up to date."

        $mergedTags = @{}
        if ($existing.Tags) {
            foreach ($key in $existing.Tags.Keys) { $mergedTags[$key] = $existing.Tags[$key] }
        }
        foreach ($key in $Tag.Keys) { $mergedTags[$key] = $Tag[$key] }

        if ($PSCmdlet.ShouldProcess($Name, 'Update resource group tags')) {
            return Set-AzResourceGroup -Name $Name -Tag $mergedTags
        }
        return $existing
    }

    if ($PSCmdlet.ShouldProcess($Name, "Create resource group in $Location")) {
        return New-AzResourceGroup -Name $Name -Location $Location -Tag $Tag
    }
}
